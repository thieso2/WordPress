# frozen_string_literal: true

require "open3"
require "json"
require "tmpdir"
require "vips"

module Library
  # Real image bytes, generated rather than checked in: the claims under test are about
  # what the BYTES say (magic numbers, IHDR/SOF dimensions, EXIF tags), so a fixture that
  # is actually a PNG/JPEG/PDF is the only kind that proves anything. Names are chosen to
  # exercise the legacy's naming rules: an uppercase extension, a dimension-like suffix,
  # a wrong extension, a threshold-crossing size, a non-image, a forbidden type.
  module SpecFixtures
    BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
    PROBE = File.expand_path("oracle_probe.php", __dir__)

    module_function

    def oracle_available? = File.exist?(BOOTSTRAP) && !`which php`.strip.empty?

    # name => absolute path, in a fresh temp dir.
    def build(dir = Dir.mktmpdir("library-fixtures"))
      png = ->(name, w, h) { Vips::Image.black(w, h, bands: 3).write_to_file(File.join(dir, name)) }
      png.call("oracle-image.png", 1600, 1200)
      png.call("small.png", 500, 300)
      png.call("square.png", 800, 800)
      png.call("wide-2049.png", 2049, 1000)
      png.call("big-3000x2000.png", 3000, 2000)
      png.call("image-150x150.png", 1600, 1200)
      Vips::Image.black(3000, 2000, bands: 3).write_to_file(File.join(dir, "oracle-photo.jpeg"), Q: 82)
      FileUtils.cp(File.join(dir, "oracle-image.png"), File.join(dir, "png-named.jpg"))
      FileUtils.cp(File.join(dir, "oracle-image.png"), File.join(dir, "My Photo (1).PNG"))
      exif = Vips::Image.black(1200, 900, bands: 3).copy
      { "exif-ifd0-ImageDescription" => "A lovely test image", "exif-ifd0-Model" => "OracleCam 3000",
        "exif-ifd0-Artist" => "O. Brien", "exif-ifd0-Copyright" => "(c) Oracle",
        "exif-ifd2-FNumber" => "2.8", "exif-ifd2-ExposureTime" => "1/125",
        "exif-ifd2-ISOSpeedRatings" => "400", "exif-ifd2-FocalLength" => "50",
        "exif-ifd2-DateTimeDigitized" => "2024:05:06 07:08:09" }.each do |field, value|
        exif.set_type(GObject::GSTR_TYPE, field, value)
      end
      exif.write_to_file(File.join(dir, "exif-photo.jpeg"))
      File.binwrite(File.join(dir, "oracle-doc.pdf"),
                    "%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")
      File.binwrite(File.join(dir, "evil.php"), "<?php echo 1;")
      File.binwrite(File.join(dir, "notes.txt"), "hello world\n")
      File.binwrite(File.join(dir, "empty.png"), "")
      # The corpus's own three "files" are 70-byte 1x1 PNGs under three different names.
      one_by_one = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
      %w[corpus-image.png corpus-photo.jpeg corpus-doc.pdf].each { |n| File.binwrite(File.join(dir, n), one_by_one) }
      Dir.children(dir).sort.to_h { |n| [n, File.join(dir, n)] }
    end

    # Asks the oracle. `request` is JSON for spec/models/library/support/oracle_probe.php.
    def probe(request)
      out, err, status = Open3.capture3("php", PROBE, stdin_data: JSON.generate(request))
      raise "oracle probe failed: #{err}\n#{out}" unless status.success?

      JSON.parse(out[out.index("{")..])
    end

    # The settings the oracle's defaults carry and the suites truncate away.
    def seed_media_settings!
      { "uploads_use_yearmonth_folders" => "1", "timezone_string" => "Europe/Madrid",
        "thumbnail_size_w" => "150", "thumbnail_size_h" => "150", "thumbnail_crop" => "1",
        "medium_size_w" => "300", "medium_size_h" => "300",
        "medium_large_size_w" => "768", "medium_large_size_h" => "0",
        "large_size_w" => "1024", "large_size_h" => "1024" }.each { |k, v| Configuration::Setting.set(k, v) }
    end
  end
end
