# frozen_string_literal: true

require "vips"

module Library
  # wp_read_image_metadata(), wp-admin/includes/image.php:825 — the `image_meta` entry of
  # `_wp_attachment_metadata`: EXIF reduced to the handful of fields the product shows.
  #
  # Shape is the oracle's, observed: every scalar is a STRING ("aperture" => "0",
  # "orientation" => "1", "created_timestamp" => "1714979289"), keywords an array, alt a
  # string — wp_kses_post_deep() at the function's end (image.php:1067) stringifies. A
  # JPEG with no EXIF block still gets the defaults; a PNG gets the defaults too.
  #
  # Read here: EXIF (JPEG/TIFF, image.php:944 `wp_read_image_metadata_types`) via libvips,
  # and the XMP AltTextAccessibility alt (wp_get_image_alttext, image.php:1088). IPTC
  # (APP13, `iptcparse()`) is NOT read — libvips does not parse it — so an IPTC-only
  # title/caption/credit/keywords set is the known gap; reported, not hidden.
  module ImageMetadata
    DEFAULTS = {
      "aperture" => "0", "credit" => "", "camera" => "", "caption" => "",
      "created_timestamp" => "0", "copyright" => "", "focal_length" => "0", "iso" => "0",
      "shutter_speed" => "0", "title" => "", "orientation" => "0", "keywords" => [],
      "alt" => ""
    }.freeze

    EXIF_TYPES = %w[image/jpeg image/tiff].freeze

    module_function

    # nil when the bytes are not an image (wp_getimagesize() false, image.php:831).
    def read(bytes, mime_type)
      data = bytes.to_s.b
      return nil unless mime_type.to_s.start_with?("image/")

      meta = DEFAULTS.dup
      meta["keywords"] = []
      meta["alt"] = alt_text(data)

      exif = EXIF_TYPES.include?(mime_type) ? exif_fields(data) : {}

      description = exif["ImageDescription"].to_s.strip
      if !description.empty?
        meta["title"] = description if meta["title"].empty? && description.bytesize < 80
        meta["caption"] = description if meta["caption"].empty?
      elsif meta["caption"].empty? && exif["Comments"].to_s.strip != ""
        meta["caption"] = exif["Comments"].to_s.strip
      end

      if meta["credit"].empty?
        meta["credit"] = exif["Artist"].to_s.strip unless exif["Artist"].to_s.empty?
      end
      meta["copyright"] = exif["Copyright"].to_s.strip if meta["copyright"].empty? && !exif["Copyright"].to_s.empty?
      meta["aperture"] = php_string(frac2dec(exif["FNumber"]).round(2)) unless blank?(exif["FNumber"])
      meta["camera"] = exif["Model"].to_s.strip unless exif["Model"].to_s.empty?
      if meta["created_timestamp"] == "0" && !blank?(exif["DateTimeDigitized"])
        meta["created_timestamp"] = exif_date_to_ts(exif["DateTimeDigitized"]).to_s
      end
      meta["focal_length"] = php_string(frac2dec(exif["FocalLength"])) unless blank?(exif["FocalLength"])
      meta["iso"] = exif["ISOSpeedRatings"].to_s.strip unless blank?(exif["ISOSpeedRatings"])
      meta["shutter_speed"] = php_string(frac2dec(exif["ExposureTime"])) unless blank?(exif["ExposureTime"])
      meta["orientation"] = exif["Orientation"].to_s unless blank?(exif["Orientation"])

      meta
    end

    # libvips exposes EXIF as "exif-ifd0-Model" => "OracleCam 3000 (OracleCam 3000, ASCII,
    # 15 components, 15 bytes)". The raw value is the text before the parenthesised
    # rendering; rationals arrive as "2800/1000", which is what PHP's exif_read_data()
    # hands wp_exif_frac2dec() too.
    def exif_fields(data)
      image = Vips::Image.new_from_buffer(data, "")
      fields = {}
      image.get_fields.each do |field|
        next unless field.start_with?("exif-ifd")

        tag = field.split("-", 3).last
        fields[tag] = image.get(field).to_s.sub(/ \(.*\z/m, "")
      end
      fields
    rescue Vips::Error
      {}
    end

    # wp_exif_frac2dec(), image.php:761.
    def frac2dec(value)
      s = value.to_s
      return s.to_f if s.count("/") != 1 && numeric?(s)
      return 0 if s.count("/") != 1

      numerator, denominator = s.split("/", 2)
      return 0 unless numeric?(numerator) && numeric?(denominator)
      return 0 if denominator.to_f.zero?

      numerator.to_f / denominator.to_f
    end

    # wp_exif_date2ts(), image.php:801: "2024:05:06 07:08:09" → strtotime in UTC.
    def exif_date_to_ts(value)
      date, time = value.to_s.split(" ", 2)
      y, m, d = date.to_s.split(":")
      Time.utc(y.to_i, m.to_i, d.to_i, *time.to_s.split(":").map(&:to_i)).to_i
    rescue ArgumentError
      0
    end

    # wp_get_image_alttext(), image.php:1088: the Iptc4xmpCore:AltTextAccessibility alt
    # from an embedded XMP packet, preferring the site locale, then its language, then
    # x-default. The locale here is the default install's `en_US`.
    def alt_text(data, locale: "en_US")
      start = data.index("<x:xmpmeta".b)
      finish = data.index("</x:xmpmeta>".b)
      return "" if start.nil? || finish.nil?

      xmp = data[start, finish - start + 12].force_encoding("UTF-8")
      doc = Nokogiri::XML(xmp) { |c| c.strict.nonet }
      doc.remove_namespaces!
      node = doc.at_xpath("/xmpmeta/RDF/Description/AltTextAccessibility")
      return "" unless node

      [locale, locale[0, 2], "x-default"].each do |lang|
        li = node.xpath("Alt/li").find { |n| n["lang"] == lang }
        return li.text if li && !li.text.empty?
      end
      ""
    rescue Nokogiri::XML::SyntaxError
      ""
    end

    def numeric?(s) = s.to_s.match?(/\A\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*\z/)

    def blank?(v) = v.nil? || v.to_s.strip.empty? || v.to_s == "0"

    # PHP's (string) cast of a float: integral values print without a fraction and the
    # default `precision` of 14 significant digits applies.
    def php_string(value)
      return value.to_s unless value.is_a?(Float)
      return value.to_i.to_s if value.finite? && value == value.floor && value.abs < 1e15

      format("%.14g", value)
    end
  end
end
