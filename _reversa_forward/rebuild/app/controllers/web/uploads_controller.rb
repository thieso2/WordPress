# frozen_string_literal: true

module Web
  # The media upload endpoint — the server side of wp-admin/async-upload.php, which is
  # `wp_ajax_upload_attachment()` (wp-admin/includes/ajax-actions.php:2596) →
  # `media_handle_upload()` (wp-admin/includes/media.php:296). Wave 3 ships it API-shaped:
  # a multipart POST answered with the legacy's JSON envelope, so the Wave 4 console's
  # uploader (console.media-new, target_screens.md) has something to talk to.
  #
  # Every message below is the legacy's string, verbatim (no copy editing). The envelope
  # is wp_ajax_upload_attachment()'s: `{"success": false, "data": {"message", "filename"}}`
  # on refusal — emitted with HTTP 200, as wp_die() does there — and `{"success": true,
  # "data": <attachment>}` on success, the attachment being the shape of
  # wp_prepare_attachment_for_js() (media.php).
  #
  # AD-04: declared `mode: :authenticated` in config/initializers/authorization_declarations.rb.
  # The capability checks the legacy performs INSIDE the action — `upload_files`
  # (ajax-actions.php:2604) and `edit_post` on the target post (:2621) — are performed
  # inside the action here too, through Access policies, and answer with the legacy's
  # JSON refusals rather than a bare 403.
  #
  # Also serves the uploads URL space: GET /wp-content/uploads/<path> streams the blob at
  # that key (in production the static file server answers first, from the same
  # directory — lib/active_storage/service/uploads_service.rb).
  class UploadsController < ApplicationController
    # The legacy gates this POST with a nonce (`check_ajax_referer( 'media-form' )`,
    # ajax-actions.php:2597), not a CSRF token. The token-authenticated callers this
    # endpoint serves — a session token as a bearer, or an application password over Basic —
    # carry no cookie for a forgery to ride on, which is also why the legacy's REST media
    # endpoint accepts application passwords without one.
    #
    # ⚠️ RISK-023 V6, and it is a TRIPWIRE rather than a live hole. The skip on its own says
    # "no forgery check on this write"; what actually keeps it safe is that
    # `#current_actor`'s cookie arm is `ApplicationController#current_actor`, which is nil —
    # so a cookie-authenticated caller cannot reach the action at all, and a cross-site POST
    # bearing the victim's cookies is refused by the AD-04 :authenticated gate (verified
    # against the running app: 403). The danger is that the note on #current_actor invites
    # exactly the change that would arm it — "`super` stays first so a cookie session, once
    # it exists, wins unchanged" — and wiring that in would silently make this a real CSRF
    # hole with nothing left to catch it.
    #
    # So the skip is now conditional on the request actually being token-authenticated.
    # Every caller today sends an Authorization header, so this changes nothing observable;
    # a cookie caller, if one is ever wired up, must present the token (the standing in for
    # `check_ajax_referer( 'media-form' )` until Identity::Nonce is threaded through).
    #
    # The condition is AMBIENT AUTHORITY, which is what check_ajax_referer actually defends:
    # a request is made to prove itself only when it carries cookies the browser attached on
    # its own AND brings no credential of its own. A token caller is exempt (nothing to
    # ride), and so is a cookie-less caller — which keeps the legacy's answer for a plain
    # credential-less API call: `wp_die( -1, 403 )` for the nonce, and the AD-04 gate's 403
    # here. Widening this to every credential-less request would turn that 403 into a 422.
    #
    # NOTE the absent `only:`. `skip_before_action` folds `only:` and `if:` into ONE
    # condition set and then inverts the lot, so `only: :create, if: <cond>` reads as "skip
    # whenever the action is create OR <cond>" — the skip fires unconditionally on create
    # and the `if:` does nothing at all. Dropping `only:` is what makes the condition bite;
    # `#show` is a GET, and a GET is a verified request by definition, so it is unaffected.
    skip_forgery_protection if: lambda {
      request.authorization.present? || request.cookies.empty?
    }

    NOT_ALLOWED = "Sorry, you are not allowed to upload files."                  # ajax-actions.php:2609
    NOT_ALLOWED_TO_ATTACH = "Sorry, you are not allowed to attach files to this post." # ajax-actions.php:2626
    # `image_size_names_choose` default minus `full`, wp-includes/media.php:4750-4759.
    JS_SIZE_NAMES = %w[thumbnail medium large].freeze

    def create
      upload = params[:file] || params["async-upload"]
      filename = upload.respond_to?(:original_filename) ? upload.original_filename.to_s : ""

      unless Access::AssetPolicy.new(current_actor, nil).permit?(:upload)
        return refuse(NOT_ALLOWED, filename)
      end

      post = nil
      # `isset( $_REQUEST['post_id'] )` (ajax-actions.php:2619): a present-but-empty or "0"
      # post_id still runs the edit_post check, which a missing post fails (verified against
      # the oracle: post_id= and post_id=0 both answer "not allowed to attach").
      if params.key?(:post_id)
        post = Publishing::Post.find_by(id: params[:post_id])
        # current_user_can( 'edit_post', $post_id ): a missing post maps to do_not_allow.
        unless post && Access::PostPolicy.new(current_actor, post).permit?(:edit)
          return refuse(NOT_ALLOWED_TO_ATTACH, filename)
        end
      end

      # No `$_FILES['async-upload']` at all fails _wp_handle_upload()'s is_uploaded_file()
      # test (file.php:938).
      return refuse(Library::UploadError::FAILED_UPLOAD_TEST, filename) unless upload.respond_to?(:read)

      asset = Library::Asset.upload!(
        io: upload, filename: filename,
        uploader: current_actor, attached_to_id: post&.id,
        # media_handle_upload() (media.php:302): the parent's post_date decides the
        # /YYYY/MM folder -- except for a page, which is never backdated (:303).
        time: post.is_a?(Publishing::Page) ? nil : (post&.published_at || post&.created_at),
        title: params[:title].presence,
        alt_text: params[:alt_text].to_s, caption: params[:caption].to_s,
        unfiltered_html: holds?("unfiltered_html")
      )
      render json: { success: true, data: attachment_json(asset) }
    rescue Library::UploadError => e
      refuse(e.message, filename)
    end

    # GET /wp-content/uploads/*path — wp_get_attachment_url()'s URL space.
    def show
      key = params[:path].to_s
      return head :not_found if key.empty? || key.split("/").include?("..")

      blob = ActiveStorage::Blob.find_by(key: key)
      if blob
        send_data blob.download, type: blob.content_type, disposition: "inline",
                                 filename: blob.filename.to_s
      else
        # A corpus file copied in by `assets:sync` has no blob row but is on disk.
        service = ActiveStorage::Blob.service
        path = service.respond_to?(:path_for) ? service.path_for(key) : nil
        return head :not_found unless path && File.file?(path)

        send_file path, disposition: "inline"
      end
    end

    private

    def refuse(message, filename)
      # esc_html( $_FILES['async-upload']['name'] ), ajax-actions.php:2610.
      render json: { success: false, data: { message: message, filename: Sanitizing::Formatting.esc_html(filename) } }
    end

    # wp_prepare_attachment_for_js(), wp-includes/media.php:4648 — the fields the
    # uploader reads back. Image sizes are the `image_size_names_choose` DEFAULT
    # (thumbnail, medium, large — media.php:4750, AD-01: the filter is gone) that the
    # metadata actually carries, with `full` appended last (:4808).
    def attachment_json(asset)
      meta = asset.metadata.to_h
      mime = asset.mime_type.to_s
      json = {
        id: asset.id, title: asset.title, filename: File.basename(asset.file),
        url: "#{site_url}#{asset.url}", alt: asset.alt_text, author: asset.uploader_id.to_s,
        caption: asset.caption, name: asset.slug, status: "inherit",
        uploadedTo: asset.attached_to_id.to_i,
        date: (asset.created_at.to_f * 1000).to_i, modified: (asset.updated_at.to_f * 1000).to_i,
        menuOrder: 0, mime: mime, type: mime.split("/").first, subtype: mime.split("/").last,
        filesizeInBytes: asset.byte_size
      }
      if asset.image? && asset.width.to_i.positive?
        json[:width] = asset.width
        json[:height] = asset.height
        json[:orientation] = asset.height > asset.width ? "portrait" : "landscape"
        base = "#{site_url}#{Library::UploadDirectory::BASEURL}/#{File.dirname(asset.file)}"
        sizes = JS_SIZE_NAMES.filter_map do |name|
          size = (meta["sizes"] || {})[name] or next
          [name, { height: size["height"], width: size["width"], url: "#{base}/#{size["file"]}",
                   orientation: size["height"].to_i > size["width"].to_i ? "portrait" : "landscape" }]
        end.to_h
        sizes["full"] = { url: "#{site_url}#{asset.url}", height: asset.height, width: asset.width,
                          orientation: json[:orientation] }
        json[:sizes] = sizes
      end
      json
    end

    def holds?(capability)
      return false if current_actor.nil?

      Access::RoleCatalogue.capabilities_for(current_actor.roles).include?(capability)
    end

    # Who is uploading. Wave 3 has no cookie session surface yet (that is Wave 4's
    # console), so the API-shaped callers identify themselves the way the legacy's API
    # callers do: a session token as a bearer token, or an application password over
    # HTTP Basic (wp_authenticate_application_password(), wp-includes/user.php:372).
    # `super` stays first so a cookie session, once it exists, wins unchanged.
    def current_actor
      return @current_actor if defined?(@current_actor)

      @current_actor = super || actor_from_bearer || actor_from_basic
    end

    def actor_from_bearer
      scheme, token = request.authorization.to_s.split(" ", 2)
      return nil unless scheme.to_s.casecmp?("Bearer") && token.present?

      Identity::Session.authenticate(token.strip)&.user
    end

    # user.php:421 — by login, else by email; :447 — non-alphanumerics are stripped from
    # the presented password before it is checked against each stored digest.
    def actor_from_basic
      scheme, encoded = request.authorization.to_s.split(" ", 2)
      return nil unless scheme.to_s.casecmp?("Basic") && encoded.present?

      login, password = Base64.decode64(encoded).split(":", 2)
      return nil if login.blank? || password.blank?

      user = Identity::User.find_by(login: login) || Identity::User.find_by(email: login)
      return nil unless user

      candidate = password.gsub(/[^a-z\d]/i, "")
      matched = user.application_passwords.detect do |app_password|
        Identity::LegacyDigest.verify(candidate, app_password.digest) ||
          (app_password.digest.start_with?("$2a$", "$2b$") && BCrypt::Password.new(app_password.digest) == candidate)
      end
      return nil unless matched

      # WP_Application_Passwords::record_application_password_usage() — at most once a day.
      matched.update_columns(last_used_at: Time.current, last_ip: request.remote_ip) if matched.last_used_at.nil? || matched.last_used_at < 1.day.ago
      user
    rescue ArgumentError, BCrypt::Errors::InvalidHash
      nil
    end
  end
end
