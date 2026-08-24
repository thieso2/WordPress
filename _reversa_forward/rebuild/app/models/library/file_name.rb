# frozen_string_literal: true

module Library
  # The two naming rules of the upload path, from wp-includes/functions.php:
  #   sanitize_file_name()   formatting.php:2035 — what a client's name becomes on disk
  #   wp_unique_filename()   functions.php:2589  — how a collision is resolved
  #
  # Both are pure functions of a name and a directory LISTING; neither touches storage.
  # The listing is what the legacy's `scandir( $dir )` saw, which under Active Storage is
  # the uploads service's directory plus the blob keys under the same prefix.
  #
  # AD-01: `sanitize_file_name_chars`, `sanitize_file_name`, `wp_unique_filename` and
  # `pre_wp_unique_filename_file_list` are filters, and `$unique_filename_callback` an
  # injection point. All gone; what is below is the permanent behaviour.
  module FileName
    # formatting.php:2039.
    SPECIAL_CHARS = ["?", "[", "]", "/", "\\", "=", "<", ">", ":", ";", ",", "'", "\"",
                     "&", "$", "#", "*", "(", ")", "|", "~", "`", "!", "{", "}", "%", "+",
                     "’", "«", "»", "”", "“", "\0"].freeze

    # Image sub-size names that a fresh upload must never collide with. :2628
    SUBSIZE_SUFFIX = /-(?:\d+x\d+|scaled|rotated)\z/

    # wp_get_image_editor_output_format(), media.php:6542 — its DEFAULT. Drives the
    # alternate-name collision check in wp_unique_filename() (:2758).
    OUTPUT_FORMAT = {
      "image/heic" => "image/jpeg",
      "image/heif" => "image/jpeg",
      "image/heic-sequence" => "image/jpeg",
      "image/heif-sequence" => "image/jpeg"
    }.freeze

    module_function

    # sanitize_file_name(), formatting.php:2035.
    def sanitize(filename, unfiltered_html: false)
      raw = filename.to_s
      name = Sanitizing::Formatting.remove_accents(raw)

      unless Sanitizing::Formatting.valid_utf8?(name)
        ext = php_extension(name)
        base = php_filename(name)
        name = "#{Sanitizing::Formatting.sanitize_title_with_dashes(base)}.#{ext}"
      end

      # Replace all whitespace characters with a basic space (U+0020). :2060
      name = name.gsub(/\p{Zs}/, " ")

      SPECIAL_CHARS.each { |c| name = name.gsub(c, "") }
      name = name.gsub("%20", "-").gsub("+", "-")
      name = name.gsub(/\.{2,}/, ".")
      name = name.gsub(/[\r\n\t -]+/, "-")
      name = php_trim(name, ".-_")

      unless name.include?(".")
        filetype = MimeTypes.check_filetype("test.#{name}", MimeTypes::TABLE)
        name = "unnamed-file.#{filetype.ext}" if filetype.ext == name
      end

      # Split the filename into a base and extension[s]. :2092
      parts = name.split(".", -1)
      return name if parts.length <= 2

      # Process multiple extensions: an intermediate 2-5 letter part that is not an
      # allowed extension gets a trailing underscore (`weird.php.png` → `weird.php_.png`).
      name = parts.shift
      extension = parts.pop
      mimes = MimeTypes.allowed(unfiltered_html: unfiltered_html)
      parts.each do |part|
        name += ".#{part}"
        next unless part.match?(/\A[a-zA-Z]{2,5}\d?\z/)

        allowed = mimes.keys.any? { |ext_preg| part.match?(/\A(#{ext_preg})\z/i) }
        name += "_" unless allowed
      end
      "#{name}.#{extension}"
    end

    # wp_unique_filename(), functions.php:2589, with `$dir` replaced by `existing` — the
    # names already present in the target directory. `in_uploads` is the legacy's
    # `str_contains( $dir, $upload_dir['basedir'] )`: only inside the uploads tree does
    # the dimension-like collision scan run.
    def unique(filename, existing:, in_uploads: true)
      filename = sanitize(filename)
      existing = Array(existing).map(&:to_s)
      number = ""

      ext = php_extension(filename)
      ext = ".#{ext}" unless ext.empty?
      name = File.basename(filename)
      name = "" if name == ext # Edge case: a file named '.ext'. :2610

      fname = php_filename(filename)
      # Always append a number to file names that can potentially match image sub-size
      # file names. :2627
      if !fname.empty? && fname.match?(SUBSIZE_SUFFIX)
        number = 1
        filename = filename.gsub("#{fname}#{ext}", "#{fname}-#{number}#{ext}")
      end

      mime_type = MimeTypes.check_filetype(filename).type
      is_image = mime_type && mime_type.start_with?("image/")

      lc_ext = ext.downcase
      lc_filename = nil
      # An uppercase extension gets an alternate lowercase name; both are tested, and
      # the lowercase one wins. :2650
      lc_filename = filename.sub(/#{Regexp.escape(ext)}\z/, lc_ext) if !ext.empty? && lc_ext != ext

      while existing.include?(filename) || (lc_filename && existing.include?(lc_filename))
        new_number = number.to_i + 1
        if lc_filename
          lc_filename = php_str_replace(["-#{number}#{lc_ext}", "#{number}#{lc_ext}"],
                                        "-#{new_number}#{lc_ext}", lc_filename)
        end
        filename =
          if "#{number}#{ext}".empty?
            "#{filename}-#{new_number}"
          else
            php_str_replace(["-#{number}#{ext}", "#{number}#{ext}"], "-#{new_number}#{ext}", filename)
          end
        number = new_number
      end

      filename = lc_filename if lc_filename

      # Prevent collisions with existing file names that contain dimension-like strings.
      # :2695
      files = []
      count = 10_000
      files = existing - [".", ".."] if !name.empty? && !ext.empty? && in_uploads
      unless files.empty?
        count = files.length
        i = 0
        while i <= count && existing_file_names?(filename, files)
          new_number = number.to_i + 1
          filename = php_str_replace(["-#{number}#{lc_ext}", "#{number}#{lc_ext}"],
                                     "-#{new_number}#{lc_ext}", filename)
          number = new_number
          i += 1
        end
      end

      # An image that will be converted, or whose sub-sizes could collide with another
      # type's when regenerated, also has its alternate names checked. :2745
      if is_image
        alt_types = []
        if OUTPUT_FORMAT[mime_type]
          alt_mime_type = OUTPUT_FORMAT[mime_type]
          alt_types = OUTPUT_FORMAT.select { |_, v| [mime_type, alt_mime_type].include?(v) }.keys
          alt_types << alt_mime_type
        else
          alt_types = OUTPUT_FORMAT.select { |_, v| v == mime_type }.keys
        end
        alt_types = (alt_types - [mime_type]).uniq

        alt_filenames = {}
        alt_types.each do |alt_type|
          alt_ext = MimeTypes.default_extension_for(alt_type)
          next unless alt_ext

          alt_ext = ".#{alt_ext}"
          alt_filenames[alt_ext] = filename.sub(/#{Regexp.escape(lc_ext)}\z/, alt_ext)
        end

        unless alt_filenames.empty?
          alt_filenames[lc_ext] = filename
          i = 0
          while i <= count && alternate_file_names?(alt_filenames.values, existing, files)
            new_number = number.to_i + 1
            alt_filenames = alt_filenames.to_h do |alt_ext, alt_filename|
              [alt_ext, php_str_replace(["-#{number}#{alt_ext}", "#{number}#{alt_ext}"],
                                        "-#{new_number}#{alt_ext}", alt_filename)]
            end
            filename = php_str_replace(["-#{number}#{lc_ext}", "#{number}#{lc_ext}"],
                                       "-#{new_number}#{lc_ext}", filename)
            number = new_number
            i += 1
          end
        end
      end

      filename
    end

    # _wp_check_existing_file_names(), functions.php:2870.
    def existing_file_names?(filename, files)
      fname = php_filename(filename)
      ext = php_extension(filename)
      return false if fname.empty?

      ext = ".#{ext}" unless ext.empty?
      regex = /\A#{Regexp.escape(fname)}-(?:\d+x\d+|scaled|rotated)#{Regexp.escape(ext)}\z/i
      files.any? { |file| file.match?(regex) }
    end

    # _wp_check_alternate_file_names(), functions.php:2849.
    def alternate_file_names?(filenames, existing, files)
      filenames.any? do |filename|
        existing.include?(filename) || (!files.empty? && existing_file_names?(filename, files))
      end
    end

    # ── PHP semantics, spelled out ───────────────────────────────────────────────

    # pathinfo( PATHINFO_EXTENSION ): the part after the LAST dot of the basename, or ''.
    def php_extension(path)
      base = File.basename(path.to_s)
      dot = base.rindex(".")
      dot.nil? ? "" : base[(dot + 1)..]
    end

    # pathinfo( PATHINFO_FILENAME ): the basename up to the last dot.
    def php_filename(path)
      base = File.basename(path.to_s)
      dot = base.rindex(".")
      dot.nil? ? base : base[0...dot]
    end

    # trim( $s, $chars ): strip any of the characters from both ends.
    def php_trim(string, chars)
      set = Regexp.escape(chars)
      string.sub(/\A[#{set}]+/, "").sub(/[#{set}]+\z/, "")
    end

    # str_replace( array $search, string $replace, $subject ): each search term in turn,
    # every occurrence.
    def php_str_replace(searches, replace, subject)
      Array(searches).reduce(subject) { |s, search| search.empty? ? s : s.gsub(search, replace) }
    end
  end
end
