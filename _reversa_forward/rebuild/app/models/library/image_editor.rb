# frozen_string_literal: true

require "vips"

module Library
  # WP_Image_Editor_GD (wp-includes/class-wp-image-editor-gd.php), on libvips.
  #
  # BR-MIGRATE-085 / 086: the legacy picks an editor per operation — Imagick if it can,
  # GD otherwise — and memoises the choice. AD-01 removes `wp_image_editors`, so the
  # choice is a constant: this class, always. What it reproduces of the GD editor is the
  # CONTRACT — the geometry comes from Library::Geometry (BR-MIGRATE-079..082), the output
  # is exactly the computed width x height, the JPEG quality is the legacy default, and a
  # file that GD could not open yields no sub-sizes rather than an error. The encoder's
  # bytes are libvips's, not GD's; pixel-level identity is not a rule anywhere and is not
  # claimed.
  class ImageEditor
    # file_is_displayable_image(), wp-admin/includes/image.php:1172 — the types for which
    # wp_generate_attachment_metadata() attempts sub-sizes at all. PHP names ICO
    # image/vnd.microsoft.icon; the upload table records it as image/x-icon.
    DISPLAYABLE = %w[image/gif image/jpeg image/png image/bmp image/x-icon
                     image/vnd.microsoft.icon image/webp image/avif image/heic].freeze

    # What libvips on this host can both read and write. BMP, ICO, AVIF and HEIC have no
    # encoder here, which is the same outcome as a GD built without their support: the
    # original is stored, the metadata carries its dimensions, and `sizes` stays empty.
    EDITABLE = %w[image/jpeg image/png image/gif image/webp].freeze

    # `big_image_size_threshold` filter default, image.php:282. Above this on either
    # axis the original is scaled down and the scaled copy becomes the "full" size.
    BIG_IMAGE_SIZE_THRESHOLD = 2560

    # WP_Image_Editor::get_default_quality(), class-wp-image-editor.php:317.
    DEFAULT_QUALITY = 82
    WEBP_QUALITY = 86

    SAVE_SUFFIX = { "image/jpeg" => ".jpg", "image/png" => ".png",
                    "image/gif" => ".gif", "image/webp" => ".webp" }.freeze

    Saved = Struct.new(:bytes, :width, :height, :mime_type, keyword_init: true)

    def self.displayable?(mime_type) = DISPLAYABLE.include?(mime_type.to_s)

    def self.supports?(mime_type) = EDITABLE.include?(mime_type.to_s)

    # Returns nil where the legacy returns a WP_Error from wp_get_image_editor().
    def self.open(bytes, mime_type)
      return nil unless supports?(mime_type)

      image = Vips::Image.new_from_buffer(bytes.to_s.b, "")
      new(image, mime_type)
    rescue Vips::Error
      nil
    end

    attr_reader :image, :mime_type

    def initialize(image, mime_type)
      @image = image
      @mime_type = mime_type
    end

    def width = image.width

    def height = image.height

    # The EXIF Orientation tag, or 0 when there is none. WP_Image_Editor::maybe_exif_rotate()
    # (class-wp-image-editor.php:486) reads it for JPEGs only.
    def exif_orientation
      return 0 unless mime_type == "image/jpeg"
      return 0 unless image.get_typeof("exif-ifd0-Orientation") != 0

      image.get("exif-ifd0-Orientation").to_s[/\A\d+/].to_i
    rescue Vips::Error
      0
    end

    # maybe_exif_rotate(): rotate/flip into orientation 1. Returns true if anything
    # changed, false when the tag is absent or already 1.
    def rotate!
      orientation = exif_orientation
      return false if orientation <= 1

      @image = image.autorot
      true
    end

    # WP_Image_Editor_GD::resize() — scale (never crop) into a box, in place.
    def resize!(max_width, max_height)
      rect = Geometry.resize(width, height, max_width, max_height, false)
      return false unless rect

      @image = render(rect)
      true
    end

    # WP_Image_Editor_GD::make_subsize() (class-wp-image-editor-gd.php:308): the pixels
    # for one computed Geometry::Rect of THIS image, without touching it.
    def make_subsize(rect)
      encode(render(rect))
    end

    # WP_Image_Editor_GD::save() of the current image.
    def save = encode(image)

    private

    # _resize(): imagecopyresampled() over the source rectangle into exactly the
    # destination dimensions.
    def render(rect)
      out = image
      crop = [rect.source_x, rect.source_y, rect.source_width, rect.source_height]
      out = out.extract_area(*crop) unless crop == [0, 0, width, height]
      unless out.width == rect.width && out.height == rect.height
        out = out.thumbnail_image(rect.width, height: rect.height, size: :force)
      end
      out
    end

    # _save(): GD re-encodes from pixels, so EXIF and other metadata do not survive into
    # derivatives; `strip: true` reproduces that.
    def encode(img)
      suffix = SAVE_SUFFIX.fetch(mime_type)
      options = { strip: true }
      options[:Q] = mime_type == "image/webp" ? WEBP_QUALITY : DEFAULT_QUALITY if %w[image/jpeg image/webp].include?(mime_type)
      bytes = img.write_to_buffer(suffix, **options)
      Saved.new(bytes: bytes, width: img.width, height: img.height, mime_type: mime_type)
    end
  end
end
