# frozen_string_literal: true

module Library
  # wp_check_filetype_and_ext(), wp-includes/functions.php:3124 — the verdict that
  # decides whether an upload is accepted, what MIME type is recorded, and whether the
  # file is RENAMED to the extension its bytes actually warrant.
  #
  # AGG-Asset invariant: "MIME type is determined from content, not from the filename
  # extension alone." The legacy does it in three passes and so does this:
  #   1. the name proposes a type (wp_check_filetype);
  #   2. an image's bytes are read (wp_get_image_mime); a mismatch renames the file to
  #      the extension the bytes warrant — `png-named.jpg` becomes `png-named.png`;
  #   3. anything not settled as an image goes through fileinfo, with the legacy's exact
  #      list of forgiven mismatches (text/plain for csv, application/zip for office
  #      documents, audio/video major-type matches) and "everything else must match".
  # Finally the type must be in the allowed table.
  #
  # AD-01: `getimagesize_mimes_to_exts` and `wp_check_filetype_and_ext` were filters.
  # Both are gone; the tables below are the pre-filter defaults, permanently.
  module FileTypeCheck
    Verdict = Struct.new(:ext, :type, :proper_filename, :real_mime, keyword_init: true) do
      def allowed? = !!(ext && type)
    end

    # functions.php:3158 — the rename map. Only these image types can correct a name.
    MIME_TO_EXT = {
      "image/jpeg" => "jpg",
      "image/png" => "png",
      "image/gif" => "gif",
      "image/bmp" => "bmp",
      "image/tiff" => "tif",
      "image/webp" => "webp",
      "image/avif" => "avif",
      "image/heic" => "heic",
      "image/heif" => "heic",
      "image/heic-sequence" => "heic",
      "image/heif-sequence" => "heic"
    }.freeze

    HEIC_IMAGE_EXTENSIONS = %w[heif heics heifs].freeze

    # functions.php:3231 — fileinfo "often misidentifies obscure files as one of these".
    NONSPECIFIC_TYPES = %w[application/octet-stream application/encrypted
                           application/CDFV2-encrypted application/zip].freeze
    GOOGLE_DOCS_TYPES = %w[
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    ].freeze

    module_function

    # `bytes` is the whole upload; `filename` the client's name. `unfiltered_html` is
    # the one capability get_allowed_mime_types() consults (functions.php:3698).
    def call(bytes, filename, unfiltered_html: false)
      data = bytes.to_s.b
      name = filename.to_s
      mimes = MimeTypes.allowed(unfiltered_html: unfiltered_html)
      proper_filename = false

      named = MimeTypes.check_filetype(name, mimes)
      ext = named.ext
      type = named.type
      real_mime = false

      # "We can't do any further validation without a file to work with." :3134
      return Verdict.new(ext: ext, type: type, proper_filename: false, real_mime: false) if data.empty?

      # Validate image types. :3142
      if type && type.start_with?("image/")
        real_mime = image_mime(data)

        if real_mime && (real_mime != type || HEIC_IMAGE_EXTENSIONS.include?(ext))
          if MIME_TO_EXT[real_mime]
            # Replace whatever is after the last period with the correct extension. :3190
            parts = name.split(".", -1)
            parts.pop
            parts << MIME_TO_EXT[real_mime]
            new_filename = parts.join(".")
            proper_filename = new_filename if new_filename != name

            renamed = MimeTypes.check_filetype(new_filename, mimes)
            ext = renamed.ext
            type = renamed.type
          else
            # Reset $real_mime and try validating again. :3208
            real_mime = false
          end
        end
      end

      # Validate files that didn't get validated during previous checks. :3214
      if type && !real_mime
        real_mime = Fileinfo.mime(data)
        GOOGLE_DOCS_TYPES.each do |google|
          real_mime = google if real_mime.scan(google).length == 2
        end

        major = ->(mime) { mime.to_s.split("/").first.to_s }
        reject = false

        if NONSPECIFIC_TYPES.include?(real_mime)
          reject = !%w[application video audio].include?(major.call(type))
        elsif real_mime.start_with?("video/", "audio/")
          reject = major.call(real_mime) != major.call(type)
        elsif real_mime == "text/plain"
          reject = !%w[text/plain text/csv application/csv text/richtext text/tsv text/vtt].include?(type)
        elsif real_mime == "application/csv"
          reject = !%w[text/csv text/plain application/csv].include?(type)
        elsif real_mime == "text/rtf"
          reject = !%w[text/rtf text/plain application/rtf].include?(type)
        else
          # Everything else including image/* and application/*: assume it's dangerous
          # when the real content type doesn't match the file extension. :3324
          reject = type != real_mime
        end

        if reject
          type = false
          ext = false
        end
      end

      # The mime type must be allowed. :3337
      if type && !MimeTypes.allowed(unfiltered_html: unfiltered_html).value?(type)
        type = false
        ext = false
      end

      Verdict.new(ext: ext, type: type, proper_filename: proper_filename, real_mime: real_mime)
    end

    # wp_get_image_mime(), functions.php:3368: exif_imagetype() → image_type_to_mime_type(),
    # with the RIFF/WEBP and `ftyp` (AVIF/HEIC/HEIF) fallbacks. PHP 8.4's own constants
    # name the types as below (image/vnd.microsoft.icon for ICO, image/psd, …).
    def image_mime(data)
      return "image/gif" if data.start_with?("GIF87a".b, "GIF89a".b)
      return "image/jpeg" if data.start_with?("\xFF\xD8\xFF".b)
      return "image/png" if data.start_with?("\x89PNG\r\n\x1a\n".b)
      return "application/x-shockwave-flash" if data.start_with?("FWS".b, "CWS".b, "ZWS".b)
      return "image/psd" if data.start_with?("8BPS".b)
      return "image/bmp" if data.start_with?("BM".b)
      return "image/tiff" if data.start_with?("II*\x00".b, "MM\x00*".b)
      return "image/vnd.microsoft.icon" if data.start_with?("\x00\x00\x01\x00".b)
      return "image/webp" if data.bytesize >= 12 && data[0, 4] == "RIFF".b && data[8, 4] == "WEBP".b
      return "image/avif" if ftyp?(data, %w[avif avis])
      return "image/heic" if ftyp?(data, %w[heic])
      return "image/heif" if ftyp?(data, %w[heif])

      if ftyp?(data, nil)
        # mif1, msf1 … — the legacy defers to fileinfo and accepts only an HEIC answer.
        mime = Fileinfo.mime(data)
        return mime if %w[image/heic image/heif image/heic-sequence image/heif-sequence].include?(mime)
      end

      false
    end

    def ftyp?(data, brands)
      return false if data.bytesize < 12 || data[4, 4] != "ftyp".b

      brands.nil? || brands.include?(data[8, 4])
    end
  end
end
