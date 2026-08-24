# frozen_string_literal: true

module Web
  # web.attachment — `/:year/:monthnum/:slug/:attachment_slug/`, the attachment permalink
  # nested under its parent post's permalink (get_attachment_link, wp-includes/link-template.php).
  #
  # ⚠️ The screen IS a redirect, not a page. On a default WordPress 7.2 install
  # `wp_attachment_pages_enabled` is '0', and canonical.php:553 301-redirects every
  # attachment URL to the FILE itself (`wp_get_attachment_url()`, wp-includes/post.php:7191:
  # uploads baseurl + the attached file's relative path). Verified against the oracle for
  # all three corpus attachments — see spec/parity/corpus/requests.yml:62 and
  # Presentation::Screen#attachment?.
  class AttachmentsController < ApplicationController
    def show
      asset = Library::Asset.find_by(slug: encoded_slug)
      file = asset&.metadata.to_h["file"].to_s
      return not_found if file.empty?

      # wp_redirect( $redirect_url, 301 ) — canonical.php:1002 via :553.
      redirect_to "#{site_url}/wp-content/uploads/#{file}", status: :moved_permanently
    end

    private

    # BR-MIGRATE-033: attachment slugs are stored the way sanitize_title() wrote them —
    # non-ASCII characters percent-encoded in LOWERCASE hex (`utf8_uri_encode()`,
    # wp-includes/formatting.php:1160), e.g. `asset-oracle-image-png-%f0%9f%98%80`. The
    # legacy matches the RAW request path against post_name; Rails hands the segment over
    # decoded, so it is re-encoded here before the lookup.
    def encoded_slug
      params[:attachment_slug].to_s.gsub(/[^\x00-\x7F]/) do |char|
        char.bytes.map { |byte| format("%%%02x", byte) }.join
      end
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
