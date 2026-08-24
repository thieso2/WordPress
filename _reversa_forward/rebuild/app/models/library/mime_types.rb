# frozen_string_literal: true

module Library
  # wp_get_mime_types() / get_allowed_mime_types() / wp_check_filetype(), from
  # wp-includes/functions.php. A pure lookup table and the two functions that read it.
  #
  # AD-01: the legacy exposes `mime_types` and `upload_mimes` filters over both tables.
  # Neither exists here; the tables below are the pre-filter defaults, read back from the
  # oracle (`wp_get_mime_types()`, WordPress 7.2-alpha-63330) and permanent.
  module MimeTypes
    # wp_get_mime_types(), functions.php:3471. Keys are PHP `preg` alternations of
    # extensions; values the MIME type they map to. Order matters: wp_check_filetype()
    # returns the FIRST match.
    TABLE = {
      "jpg|jpeg|jpe" => "image/jpeg",
      "gif" => "image/gif",
      "png" => "image/png",
      "bmp" => "image/bmp",
      "tiff|tif" => "image/tiff",
      "webp" => "image/webp",
      "avif" => "image/avif",
      "ico" => "image/x-icon",
      "heic" => "image/heic",
      "heif" => "image/heif",
      "heics" => "image/heic-sequence",
      "heifs" => "image/heif-sequence",
      "asf|asx" => "video/x-ms-asf",
      "wmv" => "video/x-ms-wmv",
      "wmx" => "video/x-ms-wmx",
      "wm" => "video/x-ms-wm",
      "avi" => "video/avi",
      "divx" => "video/divx",
      "flv" => "video/x-flv",
      "mov|qt" => "video/quicktime",
      "mpeg|mpg|mpe" => "video/mpeg",
      "mp4|m4v" => "video/mp4",
      "ogv" => "video/ogg",
      "webm" => "video/webm",
      "mkv" => "video/x-matroska",
      "3gp|3gpp" => "video/3gpp",
      "3g2|3gp2" => "video/3gpp2",
      "txt|asc|c|cc|h|srt" => "text/plain",
      "csv" => "text/csv",
      "tsv" => "text/tab-separated-values",
      "ics" => "text/calendar",
      "rtx" => "text/richtext",
      "css" => "text/css",
      "htm|html" => "text/html",
      "vtt" => "text/vtt",
      "dfxp" => "application/ttaf+xml",
      "mp3|m4a|m4b" => "audio/mpeg",
      "aac" => "audio/aac",
      "ra|ram" => "audio/x-realaudio",
      "wav|x-wav" => "audio/wav",
      "ogg|oga" => "audio/ogg",
      "flac" => "audio/flac",
      "mid|midi" => "audio/midi",
      "wma" => "audio/x-ms-wma",
      "wax" => "audio/x-ms-wax",
      "mka" => "audio/x-matroska",
      "rtf" => "application/rtf",
      "js" => "application/javascript",
      "pdf" => "application/pdf",
      "swf" => "application/x-shockwave-flash",
      "class" => "application/java",
      "tar" => "application/x-tar",
      "zip" => "application/zip",
      "gz|gzip" => "application/x-gzip",
      "rar" => "application/rar",
      "7z" => "application/x-7z-compressed",
      "exe" => "application/x-msdownload",
      "psd" => "application/octet-stream",
      "xcf" => "application/octet-stream",
      "doc" => "application/msword",
      "pot|pps|ppt" => "application/vnd.ms-powerpoint",
      "wri" => "application/vnd.ms-write",
      "xla|xls|xlt|xlw" => "application/vnd.ms-excel",
      "mdb" => "application/vnd.ms-access",
      "mpp" => "application/vnd.ms-project",
      "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "docm" => "application/vnd.ms-word.document.macroEnabled.12",
      "dotx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.template",
      "dotm" => "application/vnd.ms-word.template.macroEnabled.12",
      "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "xlsm" => "application/vnd.ms-excel.sheet.macroEnabled.12",
      "xlsb" => "application/vnd.ms-excel.sheet.binary.macroEnabled.12",
      "xltx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.template",
      "xltm" => "application/vnd.ms-excel.template.macroEnabled.12",
      "xlam" => "application/vnd.ms-excel.addin.macroEnabled.12",
      "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "pptm" => "application/vnd.ms-powerpoint.presentation.macroEnabled.12",
      "ppsx" => "application/vnd.openxmlformats-officedocument.presentationml.slideshow",
      "ppsm" => "application/vnd.ms-powerpoint.slideshow.macroEnabled.12",
      "potx" => "application/vnd.openxmlformats-officedocument.presentationml.template",
      "potm" => "application/vnd.ms-powerpoint.template.macroEnabled.12",
      "ppam" => "application/vnd.ms-powerpoint.addin.macroEnabled.12",
      "sldx" => "application/vnd.openxmlformats-officedocument.presentationml.slide",
      "sldm" => "application/vnd.ms-powerpoint.slide.macroEnabled.12",
      "onetoc|onetoc2|onetmp|onepkg" => "application/onenote",
      "oxps" => "application/oxps",
      "xps" => "application/vnd.ms-xpsdocument",
      "odt" => "application/vnd.oasis.opendocument.text",
      "odp" => "application/vnd.oasis.opendocument.presentation",
      "ods" => "application/vnd.oasis.opendocument.spreadsheet",
      "odg" => "application/vnd.oasis.opendocument.graphics",
      "odc" => "application/vnd.oasis.opendocument.chart",
      "odb" => "application/vnd.oasis.opendocument.database",
      "odf" => "application/vnd.oasis.opendocument.formula",
      "wp|wpd" => "application/wordperfect",
      "key" => "application/vnd.apple.keynote",
      "numbers" => "application/vnd.apple.numbers",
      "pages" => "application/vnd.apple.pages"
    }.freeze

    # get_allowed_mime_types() always drops these two (functions.php:3696).
    NEVER_ALLOWED = %w[swf exe].freeze
    # ...and these two unless the user holds `unfiltered_html` (functions.php:3702).
    UNFILTERED_ONLY = %w[htm|html js].freeze

    Verdict = Struct.new(:ext, :type, keyword_init: true)

    module_function

    # get_allowed_mime_types(), functions.php:3693. The `upload_mimes` filter is gone
    # (AD-01); the capability is the only remaining variable.
    def allowed(unfiltered_html: false)
      table = TABLE.reject { |ext, _| NEVER_ALLOWED.include?(ext) }
      table = table.reject { |ext, _| UNFILTERED_ONLY.include?(ext) } unless unfiltered_html
      table
    end

    # wp_check_filetype(), functions.php:3080 — the NAME-only verdict. `ext` is the
    # matched extension exactly as it appears in the filename (case preserved), which is
    # what the rename branch of wp_check_filetype_and_ext() relies on.
    def check_filetype(filename, mimes = nil)
      mimes = allowed if mimes.nil? || mimes.empty?
      name = filename.to_s
      mimes.each do |ext_preg, mime|
        match = name.match(/\.(#{ext_preg})\z/i)
        return Verdict.new(ext: match[1], type: mime) if match
      end
      Verdict.new(ext: false, type: false)
    end

    # wp_get_default_extension_for_mime_type(), functions.php:3053: the first extension
    # of the first table entry carrying the type, or false.
    def default_extension_for(mime_type)
      entry = TABLE.find { |_, type| type == mime_type }
      return false unless entry

      first = entry.first.split("|").first.to_s
      first.empty? ? false : first
    end
  end
end
