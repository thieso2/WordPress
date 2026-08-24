# frozen_string_literal: true

require "rails_helper"
require_relative "support/fixtures"

# DIFFERENTIAL, end to end: media_handle_sideload() in the oracle against
# Library::Asset.upload! here, on the same bytes under the same names, comparing what
# each RECORDS — slug, title, type, the stored path, the generated sizes (name, file,
# dimensions, type, and their order), the `-scaled` replacement and the image_meta.
#
# Not compared: the derivatives' byte sizes. GD and libvips are different encoders; no
# rule anywhere says the pixels match, and the metadata's `filesize` per size is the
# only field that reflects it.
#
# ⚠️ The oracle's writes are rolled back and its files removed (oracle_probe.php); the
# probe reports `clean` and this spec fails loudly if the corpus was not left as found.
RSpec.describe "Library::Asset.upload! vs media_handle_sideload()" do
  # Corpus post 4 (the published article) has post_date 2026-03-15 09:56:00 (site time),
  # so a file attached to it lands in /2026/03 — the oracle says so, and media.php:469 is
  # why. Not post 5: tools/seed.php makes it the zero-date draft (RISK-007), whose
  # post_date is whatever the clock said when the corpus was seeded.
  PARENT_POST = 4
  PARENT_DATE = Time.new(2026, 3, 15, 9, 56, 0, "+01:00")

  UPLOADS = [
    ["oracle-image.png", PARENT_POST], ["oracle-photo.jpeg", PARENT_POST], ["oracle-doc.pdf", PARENT_POST],
    ["png-named.jpg", PARENT_POST], ["My Photo (1).PNG", PARENT_POST], ["small.png", PARENT_POST],
    ["square.png", PARENT_POST], ["wide-2049.png", PARENT_POST], ["big-3000x2000.png", PARENT_POST],
    ["evil.php", PARENT_POST], ["notes.txt", PARENT_POST], ["image-150x150.png", PARENT_POST],
    ["oracle-image.png", PARENT_POST], ["exif-photo.jpeg", PARENT_POST], ["small.png", 0],
    ["corpus-image.png", PARENT_POST], ["corpus-photo.jpeg", PARENT_POST], ["corpus-doc.pdf", PARENT_POST]
  ].freeze

  before(:all) do
    skip "oracle not available" unless Library::SpecFixtures.oracle_available?
    @fixtures = Library::SpecFixtures.build
    @oracle = Library::SpecFixtures.probe(
      "sideload" => UPLOADS.map { |name, parent| { "name" => name, "path" => @fixtures[name], "parent" => parent } }
    )
  end

  before do
    Library::SpecFixtures.seed_media_settings!
    ActiveStorage::Blob.service.root.then { |root| FileUtils.rm_rf(root) }
  end

  it "left the oracle's corpus exactly as it found it" do
    expect(@oracle["clean"]).to be(true), "oracle probe was not clean: #{@oracle.slice('leftover', 'posts')}"
  end

  it "records the same asset for every upload, refusing the same ones" do
    @oracle["sideload"].zip(UPLOADS).each do |expected, (name, parent)|
      io = File.binread(@fixtures[name])
      time = parent.zero? ? nil : PARENT_DATE
      if expected["error"]
        expect { Library::Asset.upload!(io: io, filename: name, time: time) }
          .to raise_error(Library::UploadError, expected["error"]), name
        next
      end

      asset = Library::Asset.upload!(io: io, filename: name, time: time)
      aggregate_failures name do
        expect(asset.slug).to eq(expected["post_name"])
        expect(asset.title).to eq(expected["post_title"])
        expect(asset.mime_type).to eq(expected["post_mime_type"])
        expect(asset.file).to eq(expected["attached_file"])
        expect(asset.alt_text).to eq(expected["alt"])

        meta = asset.metadata
        theirs = expected["meta"]
        # _wp_attached_file rides in metadata['file'] here (no separate column); the
        # oracle's metadata for a non-image is `{"filesize"}` alone.
        expect(meta.keys).to match_array(theirs.keys | ["file"])
        expect(meta["width"]).to eq(theirs["width"])
        expect(meta["height"]).to eq(theirs["height"])
        expect(meta["original_image"]).to eq(theirs["original_image"])
        expect(meta["image_meta"]).to eq(theirs["image_meta"])
        expect(meta["filesize"]).to eq(theirs["filesize"]) unless theirs["original_image"] # same bytes unless re-encoded
        # An image with no generated size serialises as an empty PHP array (`[]` in JSON).
        theirs["sizes"] = {} if theirs["sizes"] == []
        if theirs["sizes"]
          # jsonb does not preserve key order; the promoted rows below carry the
          # priority ORDER (image.php:497), and are compared in order.
          expect(meta["sizes"].keys).to match_array(theirs["sizes"].keys)
          theirs["sizes"].each do |size_name, size|
            expect(meta["sizes"][size_name].except("filesize")).to eq(size.except("filesize")), size_name
          end
          # AD-03: the promoted rows carry the same facts as the nested array.
          rows = asset.variants.order(:id).map { |v| [v.size_name, v.width, v.height, v.mime_type, v.filename] }
          expect(rows).to eq(theirs["sizes"].map { |n, s| [n, s["width"], s["height"], s["mime-type"], s["file"]] })
          # ...and every variant is a real file at the legacy path.
          asset.variants.each do |v|
            expect(v.file).to be_attached
            expect(v.file.blob.key).to eq("#{File.dirname(asset.file)}/#{v.filename}")
          end
        end
      end
    end
  end
end
