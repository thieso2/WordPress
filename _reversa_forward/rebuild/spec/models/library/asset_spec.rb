# frozen_string_literal: true

require "rails_helper"
require_relative "support/fixtures"

# AGG-Asset behaviour that the oracle cannot be asked about because it is about THIS
# model's shape: one original blob, regenerable derivatives, synchronous deletion, the
# corpus rows that arrived without bytes, and the option-backed size registry.
RSpec.describe Library::Asset do
  include ActiveSupport::Testing::TimeHelpers

  before(:all) { @fixtures = Library::SpecFixtures.build }
  before do
    Library::SpecFixtures.seed_media_settings!
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
  end

  def upload(name, **opts)
    described_class.upload!(io: File.binread(@fixtures[name]), filename: name,
                            time: Time.new(2026, 3, 15, 10, 0, 0, "+01:00"), **opts)
  end

  it "stores exactly one original blob at the legacy relative path and serves it at the legacy URL" do
    asset = upload("oracle-image.png")
    expect(asset.original).to be_attached
    expect(asset.original.blob.key).to eq("2026/03/oracle-image.png")
    expect(asset.url).to eq("/wp-content/uploads/2026/03/oracle-image.png")
    expect(File).to exist(ActiveStorage::Blob.service.path_for("2026/03/oracle-image.png"))
    expect(asset.scaled).not_to be_attached
  end

  it "keeps the upload as the original and the -scaled copy as the full size above the threshold" do
    asset = upload("big-3000x2000.png")
    expect(asset.original.blob.key).to eq("2026/03/big-3000x2000-1.png")
    expect(asset.scaled.blob.key).to eq("2026/03/big-3000x2000-1-scaled.png")
    expect([asset.width, asset.height]).to eq([2560, 1707])
    expect(asset.metadata["original_image"]).to eq("big-3000x2000-1.png")
    # BR-MIGRATE-079 is judged against the ORIGINAL's geometry, so 2048x2048 exists.
    expect(asset.variants.pluck(:size_name)).to include("2048x2048")
  end

  it "refuses an empty file with the legacy's words (file.php:946)" do
    expect { upload("empty.png") }.to raise_error(Library::UploadError, Library::UploadError::EMPTY)
  end

  it "regenerates every derivative from the original without data loss" do
    asset = upload("oracle-photo.jpeg")
    before_keys = ActiveStorage::Blob.pluck(:key).sort
    old_variant_ids = asset.variants.pluck(:id)

    asset.regenerate_variants!

    expect(asset.variants.pluck(:id) & old_variant_ids).to be_empty
    expect(ActiveStorage::Blob.pluck(:key).sort).to eq(before_keys)
    # jsonb does not keep key order; the rows do (image.php:497's priority order).
    expect(asset.reload.metadata["sizes"].keys).to match_array(%w[medium large thumbnail medium_large 1536x1536 2048x2048])
    expect(asset.variants.order(:id).pluck(:size_name)).to eq(%w[medium large thumbnail medium_large 1536x1536 2048x2048])
    expect(Dir[File.join(ActiveStorage::Blob.service.root, "**", "*")].count { |f| File.file?(f) }).to eq(before_keys.size)
  end

  it "regenerates a subset of sizes when asked, from the same original" do
    asset = upload("oracle-image.png")
    asset.regenerate_variants!(described_class::REGISTERED_SIZES.slice("thumbnail", "medium"))
    expect(asset.variants.pluck(:size_name)).to match_array(%w[thumbnail medium])
    expect(asset.metadata["sizes"].keys).to match_array(%w[medium thumbnail])
    expect(asset.variants.order(:id).pluck(:size_name)).to eq(%w[medium thumbnail])
  end

  it "deletes its files with the row, synchronously (AGG-Asset command `delete`)" do
    asset = upload("big-3000x2000.png")
    keys = [asset.original.blob.key, asset.scaled.blob.key] + asset.variants.map { |v| v.file.blob.key }
    expect(keys.size).to eq(8)

    asset.destroy!

    expect(ActiveStorage::Blob.where(key: keys)).to be_empty
    keys.each { |k| expect(File).not_to exist(ActiveStorage::Blob.service.path_for(k)) }
    expect(Library::Variant.where(asset_id: asset.id)).to be_empty
  end

  it "reads the registered sizes from the media settings, with the registry as fallback" do
    Configuration::Setting.set("medium_size_w", "640")
    Configuration::Setting.set("thumbnail_crop", "0")
    sizes = described_class.registered_sizes
    expect(sizes["medium"]).to eq(width: 640, height: 300, crop: false)
    expect(sizes["thumbnail"][:crop]).to be(false)
    expect(sizes["2048x2048"]).to eq(width: 2048, height: 2048, crop: false)

    Configuration::Setting.unset("large_size_w")
    expect(described_class.registered_sizes["large"]).to eq(width: 1024, height: 1024, crop: false)
  end

  it "still regenerates geometry-only rows for a corpus asset that has no blob" do
    asset = described_class.create!(title: "Corpus", slug: "corpus", mime_type: "image/png", byte_size: 70,
                                    width: 1600, height: 1200, metadata: { "file" => "2026/08/x.png" })
    asset.regenerate_variants!
    expect(asset.variants.pluck(:size_name, :width, :height))
      .to match_array([["thumbnail", 150, 150], ["medium", 300, 225], ["medium_large", 768, 576],
                       ["large", 1024, 768], ["1536x1536", 1536, 1152]])
    expect(asset.reload.metadata["file"]).to eq("2026/08/x.png")
  end

  it "allocates -2, -3… for a taken slug and never a feed name (post.php:5597)" do
    upload("small.png")
    # Same directory: wp_unique_filename() renames the FILE first, and the title and
    # slug follow the stored name (media.php:491) — `small-1`, not `small-2`.
    second = upload("small.png")
    expect(second.original.blob.key).to eq("2026/03/small-1.png")
    expect(second.slug).to eq("small-1")
    # Another directory: the file name is free again, so only the slug collides.
    third = described_class.upload!(io: File.binread(@fixtures["small.png"]), filename: "small.png",
                                    time: Time.new(2026, 4, 1, 10, 0, 0, "+02:00"))
    expect(third.original.blob.key).to eq("2026/04/small.png")
    expect(third.slug).to eq("small-2")
    expect(described_class.allocate_slug("feed")).to eq("feed-2")
    expect(described_class.allocate_slug("embed")).to eq("embed-2")
  end

  it "lands in the site's current month when the upload has no parent date" do
    travel_to Time.utc(2026, 8, 31, 23, 30) do # 01:30 on September 1st in Europe/Madrid
      asset = described_class.upload!(io: File.binread(@fixtures["small.png"]), filename: "small.png")
      expect(asset.original.blob.key).to eq("2026/09/small.png")
    end
  end
end
