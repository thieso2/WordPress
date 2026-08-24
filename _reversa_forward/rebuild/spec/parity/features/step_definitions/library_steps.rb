# frozen_string_literal: true

# PT-009 -- Assets and their derivatives (AGG-Asset). BR-MIGRATE-079..088, BR-MIGRATE-033.
#
# Inspector contract (paradigm_decision.md): derived state is asserted as BEHAVIOUR.
# Nothing below asks whether a callback ran, what a validation is called, or what a
# column defaults to. It asks what an outside observer of the system would see: which
# variant rows exist, what the recorded MIME type is, whether a write was refused.
#
# AD-02 is the reason this aggregate exists at all: in the legacy the whole model lived
# in four `_wp_attachment*` / `_thumbnail_id` postmeta keys because the wp_posts shape
# did not fit it. So these steps deliberately touch no post columns for asset facts.

require "zlib"
require "stringio"

# Real PNG bytes, built here rather than checked in, so that "the MIME type comes from
# the CONTENT" is a claim about actual magic bytes and the probed dimensions are read
# out of an actual IHDR chunk. A fixture named *.png would prove neither.
module ParityImageFixtures
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

  module_function

  def png(width, height)
    scanlines = ("\x00".b + ("\x80".b * width)) * height   # filter byte 0, 8-bit greyscale
    ihdr = [width, height].pack("N2") + [8, 0, 0, 0, 0].pack("C5")
    PNG_SIGNATURE + chunk("IHDR", ihdr) + chunk("IDAT", Zlib::Deflate.deflate(scanlines)) +
      chunk("IEND", "".b)
  end

  def chunk(type, data)
    body = type.b + data.b
    [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
  end
end

def parity_asset(slug: "parity-asset", **attributes)
  Library::Asset.create!(
    { title: "Parity asset", slug: slug, mime_type: "image/png", byte_size: 1_024,
      width: 2_000, height: 1_500 }.merge(attributes)
  )
end

# ── Variant generation (BR-MIGRATE-088, BR-MIGRATE-079) ───────────────────────

Given("the registered image sizes are thumbnail, medium and large") do
  @registered_sizes = Library::Asset::REGISTERED_SIZES.slice("thumbnail", "medium", "large")
  expect(@registered_sizes.keys).to eq(%w[thumbnail medium large])
end

Given("the registered size {string} is {int} pixels wide") do |size_name, pixels|
  @registered_sizes = Library::Asset::REGISTERED_SIZES
  expect(@registered_sizes.fetch(size_name)[:width]).to eq(pixels)
end

When("an editor uploads an image larger than every registered size") do
  bound = @registered_sizes.values.flat_map { |s| [s[:width], s[:height]] }.max
  @original_width = bound * 2
  @original_height = (bound * 1.5).to_i
  # The premise of the scenario, stated rather than assumed.
  @registered_sizes.each_value do |spec|
    expect(@original_width).to be > spec[:width]
    expect(@original_height).to be > spec[:height]
  end

  @asset = Library::Asset.upload!(
    io: StringIO.new(ParityImageFixtures.png(@original_width, @original_height)),
    filename: "wide-original.png", sizes: @registered_sizes
  )
end

When("an editor uploads an image {int} pixels wide") do |pixels|
  @original_width = pixels
  @original_height = 300
  @asset = Library::Asset.upload!(
    io: StringIO.new(ParityImageFixtures.png(@original_width, @original_height)),
    filename: "small-original.png", sizes: @registered_sizes
  )
end

Then("a variant exists for each registered size") do
  expect(@asset.reload.variants.pluck(:size_name)).to match_array(@registered_sizes.keys)
end

Then("each variant records its own width, height and MIME type") do
  rows = @asset.reload.variants.pluck(:size_name, :width, :height, :mime_type)

  rows.each do |size_name, width, height, mime_type|
    expect(width).to be_positive, "#{size_name} has no width"
    expect(height).to be_positive, "#{size_name} has no height"
    expect(mime_type).to eq(@asset.mime_type)
    # "its OWN" — a derivative, never a copy of the original's geometry.
    expect([width, height]).not_to eq([@original_width, @original_height])
    expect(width).to be <= @original_width
    expect(height).to be <= @original_height
  end

  # Distinct sizes really are distinct sizes, so the assertion above cannot be
  # satisfied by writing one geometry three times.
  expect(rows.map { |r| [r[1], r[2]] }.uniq.size).to eq(rows.size)
end

# BR-MIGRATE-079: WordPress never upscales — a requested size larger than the original
# yields no file at all, and the original is used instead.
Then("no {string} variant is generated") do |size_name|
  expect(@asset.reload.variants.where(size_name: size_name)).to be_empty

  # Not vacuous: the sizes the original IS large enough for were still generated.
  expect(@asset.variants).not_to be_empty
end

# ── Uniqueness, guaranteed by the database (AD-05) ────────────────────────────

Given("an asset with a {string} variant") do |size_name|
  @asset = parity_asset(slug: "asset-with-#{size_name}")
  @asset.variants.create!(size_name: size_name, width: 150, height: 150,
                          mime_type: @asset.mime_type)
end

# "written DIRECTLY to the database": the guarantee under test is the unique index, not
# a model validation. Going through the model would prove only that a validation exists.
When("a second {string} variant for that asset is written directly to the database") do |size_name|
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO asset_variants (asset_id, size_name, width, height, mime_type)
      VALUES (#{@asset.id}, '#{size_name}', 300, 300, 'image/png')
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

# BR-MIGRATE-033: attachment slugs are unique across ALL post types in the legacy, so
# the index here is global rather than scoped to a parent or a type.
Given("an asset with slug {string}") do |slug|
  @asset = parity_asset(slug: slug)
end

When("a second asset with slug {string} is written directly to the database") do |slug|
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO assets (title, slug, mime_type, byte_size)
      VALUES ('Duplicate', '#{slug}', 'image/png', 2048)
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

# ── Alt text is an attribute of the ASSET (was postmeta '_wp_attachment_image_alt') ──

Given("an asset with alt text") do
  @asset = parity_asset(slug: "asset-with-alt", alt_text: "A grey rectangle")
end

When("the asset is displayed within two different records") do
  @displaying_records = 2.times.map do |i|
    Publishing::Article.create!(
      title: "Display #{i}", content: "", excerpt: "", slug: "display-#{i}",
      status: "published", published_at: 1.day.ago, featured_asset: @asset
    )
  end
end

Then("both display the same alt text") do
  # Queried from the PUBLISHING side on purpose. Library::Asset declares no inverse
  # association back to Publishing; adding one to make this assertion convenient would
  # be exactly the back-edge target_architecture.md forbids.
  shown = @displaying_records.map { |record| record.reload.featured_asset.alt_text }

  expect(shown.uniq.size).to eq(1)
  expect(shown.first).to eq(@asset.reload.alt_text)
  expect(shown.first).to be_present
end

# ── MIME type comes from the content (AGG-Asset invariant) ────────────────────

Given("a file whose extension does not match its content") do
  @upload_bytes = ParityImageFixtures.png(120, 90)
  @upload_filename = "holiday-photo.jpg"
  # The extension really does imply something else — confirmed against the oracle,
  # whose name-only wp_check_filetype('parity_test.jpg') reports image/jpeg while the
  # content-aware wp_check_filetype_and_ext() on the same PNG bytes reports image/png.
  @extension_implied_mime = "image/jpeg"
end

When("the file is uploaded") do
  @asset = Library::Asset.upload!(io: StringIO.new(@upload_bytes), filename: @upload_filename)
end

Then("the recorded MIME type reflects the content") do
  expect(@asset.reload.mime_type).to eq("image/png")
  expect(@asset.mime_type).not_to eq(@extension_implied_mime)
end

# ── Deletion and detachment ───────────────────────────────────────────────────

Given("an asset with three variants") do
  sizes = Library::Asset::REGISTERED_SIZES.slice("thumbnail", "medium", "large")
  @asset = Library::Asset.upload!(io: StringIO.new(ParityImageFixtures.png(2_000, 1_500)),
                                  filename: "three-variants.png", sizes: sizes)
  expect(@asset.variants.count).to eq(3)
  @asset_id = @asset.id
end

When("the asset is deleted") do
  @asset.destroy!
end

Then("no variant rows reference that asset") do
  expect(Library::Variant.where(asset_id: @asset_id)).to be_empty
end

Given("an asset attached to a published record") do
  @record = Publishing::Article.create!(title: "Holds an asset", content: "", excerpt: "",
                                        slug: "holds-an-asset", status: "published",
                                        published_at: 1.day.ago)
  @asset = parity_asset(slug: "attached-asset")
  @asset.attach!(@record)
  expect(@asset.reload).to be_attached
  @asset_id = @asset.id
end

# NOTE: "When the record is deleted" is deliberately NOT defined here. It is a shared
# phrasing across features 02, 03, 08 and 09, and discussion_steps.rb defines it; a
# second definition makes every use of it ambiguous. The Given above therefore sets
# `@record`, which is the state that step operates on.

Then("the asset still exists") do
  expect(Library::Asset.exists?(@asset_id)).to be(true)
end

Then("the asset is no longer attached to any record") do
  # Detachment, not deletion: assets.attached_to_id is ON DELETE SET NULL precisely
  # because an asset outlives the record that displayed it.
  expect(Library::Asset.find(@asset_id)).not_to be_attached
  # Read straight off the row, so the surviving link is observed in the DATABASE and not
  # only through the model's own predicate. (The previous second assertion here queried
  # posts.featured_asset_id, which this scenario never sets and which the deletion of the
  # post empties regardless -- it was true before the When and could not fail.)
  expect(Library::Asset.where(id: @asset_id).pluck(:attached_to_id)).to eq([nil])
end
