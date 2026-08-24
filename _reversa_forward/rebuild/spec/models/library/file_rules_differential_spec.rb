# frozen_string_literal: true

require "rails_helper"
require_relative "support/fixtures"

# DIFFERENTIAL. The three naming/typing rules of the upload path — sanitize_file_name(),
# wp_unique_filename(), wp_check_filetype_and_ext() — plus wp_read_image_metadata(), each
# asked of the oracle and of the port on the same inputs. Every one of these has branches
# nobody would write from memory (the `-1` forced onto `image-150x150.png`, the `.php_`
# underscore, the rename of a PNG called `.jpg`), which is exactly why the oracle answers.
RSpec.describe "Library file rules vs the oracle" do
  before(:all) do
    skip "oracle not available" unless Library::SpecFixtures.oracle_available?
    @fixtures = Library::SpecFixtures.build
    # wp_unique_filename() scans the DIRECTORY; the corpus uploads dir is the one the
    # legacy would scan, and it is read here, never written.
    @uploads_dir = "/workspace/WordPress/_reversa_forward/oracle/wordpress/wp-content/uploads/2026/08"
    @names = ["My Photo (1).PNG", "image-150x150.png", "Ünïcødé façade.jpg", "weird%20name+x.php.png",
              "..hidden.png", "a.b.c.png", "png", "résumé.pdf", "name with  spaces.JPEG", "日本語.png",
              "photo.tar.gz", "shot.jpeg.exe", "  trim-me-.png", "x.PnG", "a/b\\c:d*e?.png"]
    @unique = %w[oracle-image.png image-150x150.png new-file.png oracle-image.PNG thumb-oracle-image.png
                 oracle-image-150x150.png oracle-image-scaled.png oracle-doc.pdf photo.heic]
    @oracle = Library::SpecFixtures.probe(
      "sanitize" => @names, "unique_dir" => @uploads_dir, "unique" => @unique,
      "files" => @fixtures.except("empty.png")
    )
  end

  it "sanitize_file_name() — formatting.php:2035" do
    @names.each do |name|
      expect(Library::FileName.sanitize(name)).to eq(@oracle["sanitize"][name]), name.inspect
    end
  end

  it "wp_unique_filename() — functions.php:2589, against the corpus directory listing" do
    existing = Dir.children(@uploads_dir)
    @unique.each do |name|
      expect(Library::FileName.unique(name, existing: existing)).to eq(@oracle["unique"][name]), name
    end
  end

  it "wp_check_filetype_and_ext() — functions.php:3124: ext, type and the corrected name" do
    @fixtures.except("empty.png").each do |name, path|
      verdict = Library::FileTypeCheck.call(File.binread(path), name)
      expected = @oracle["filetype"][name]
      expect([verdict.ext, verdict.type, verdict.proper_filename])
        .to eq([expected["ext"], expected["type"], expected["proper_filename"]]), name
    end
  end

  it "wp_read_image_metadata() — image.php:825: the image_meta shape, EXIF included" do
    @fixtures.except("empty.png").each do |name, path|
      verdict = Library::FileTypeCheck.call(File.binread(path), name)
      next unless verdict.type.to_s.start_with?("image/")

      expected = @oracle["image_meta"][name]
      expect(Library::ImageMetadata.read(File.binread(path), verdict.type)).to eq(expected), name
    end
  end

  it "fileinfo answers through libmagic, as PHP's does" do
    expect(Library::Fileinfo.libmagic?).to be(true),
                                          "libmagic is not installed: text/plain uploads would be refused"
  end
end
