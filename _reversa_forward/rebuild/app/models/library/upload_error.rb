# frozen_string_literal: true

module Library
  # `_wp_handle_upload()` (wp-admin/includes/file.php:809) answers a refused upload with
  # `array( 'error' => $message )`, and media_handle_sideload() wraps that in a WP_Error.
  # Here the refusal is an exception whose message IS the legacy string, verbatim — the
  # upload endpoint prints it in the same JSON envelope wp_ajax_upload_attachment() does.
  class UploadError < StandardError
    # file.php:946 (single-site text; the multisite variant is Wave 5).
    EMPTY = "File is empty. Please upload something more substantial. This error could also be caused by uploads being disabled in your php.ini file or by post_max_size being defined as smaller than upload_max_filesize in php.ini."
    # file.php:968.
    FORBIDDEN_TYPE = "Sorry, you are not allowed to upload this file type."
    # file.php:938 — what a missing `$_FILES` entry fails as.
    FAILED_UPLOAD_TEST = "Specified file failed upload test."
  end
end
