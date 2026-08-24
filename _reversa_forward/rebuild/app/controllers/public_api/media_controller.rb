# frozen_string_literal: true

module PublicApi
  # /wp/v2/media — WP_REST_Attachments_Controller. An attachment inherits its parent's
  # status; a published-parent attachment is public, so the collection is served with no
  # permission callback (BR-REST-05) and shows attachments whose parent post is readable.
  # The item registers `read_item`: a missing id is rest_post_invalid_id (404).
  #
  # Default order is date DESC (the posts controller default the attachments controller
  # inherits). See MediaSerializer for the cross-track value-parity limitation.
  #
  # ── The WRITE surface (Gutenberg's media library talks to it) ────────────────────
  # POST /wp/v2/media accepts BOTH shapes the legacy accepts, and answers each with its
  # own error family, which is the whole reason they are separate methods here:
  #
  #   * the raw-body shape — `Content-Disposition: attachment; filename="x.png"` with the
  #     bytes as the body — upload_from_data(), :360. Its refusals are
  #     rest_upload_no_data / rest_upload_no_content_type / rest_upload_no_content_disposition
  #     / rest_upload_invalid_disposition, and a refused STORE is rest_upload_sideload_error.
  #   * the multipart shape — a `file` part — upload_from_file(), :415. A refused store
  #     here is rest_upload_unknown_error, NOT the sideload code. Verified on the oracle:
  #     the same forbidden `.xyz` file answers rest_upload_sideload_error through the raw
  #     body and rest_upload_unknown_error through multipart.
  #
  # The bytes themselves go through Library::Asset.upload! — the ONE upload path
  # (media_handle_sideload() end to end, including the sub-size generation), shared with
  # Web::UploadsController. Nothing about storage, naming or metadata is decided here.
  class MediaController < BaseController
    include CollectionPagination
    include WriteSupport

    permission :show,    :read_item
    permission :create,  :create_item
    permission :update,  :update_item
    permission :destroy, :delete_item

    # class-wp-rest-attachments-controller.php:1150 — `filename="…"` (quoted or not),
    # `filename*=` is not read by the legacy either.
    DISPOSITION_FILENAME = /filename\s*=\s*(?:"([^"]*)"|([^;\s]+))/i

    def index
      scope = readable_scope
      scope = scope.where(attached_to_id: params[:parent].to_i) if params[:parent].present?
      total = scope.count
      records = scope.order(created_at: :desc, id: :desc)
                     .offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/media")
      set_allow_header(collection_allow)
      render_json(records.map { |a| MediaSerializer.new(a, context: context, allow: item_allow(a)).as_json })
    end

    def show
      asset = loaded_asset
      set_allow_header(item_allow(asset))
      render_json(serialize(asset))
    end

    # POST /wp/v2/media — create_item(), :306.
    def create
      bytes, filename = upload_payload
      parent = requested_parent
      asset = Library::Asset.upload!(
        io: StringIO.new(bytes), filename: filename,
        uploader: current_actor, attached_to_id: parent&.id,
        # media_handle_upload() (media.php:302): the parent's post_date decides the
        # /YYYY/MM folder — except for a page, which is never backdated (:303).
        time: parent.is_a?(Publishing::Page) ? nil : (parent&.published_at || parent&.created_at),
        title: params[:title].present? ? raw_text(params[:title]) : nil,
        alt_text: params[:alt_text].to_s,
        caption: params.key?(:caption) ? raw_text(params[:caption]) : "",
        unfiltered_html: holds?("unfiltered_html")
      )
      apply_slug!(asset)
      set_allow_header(item_allow(asset))
      # :341 — the created attachment is answered in `edit` context.
      render_created(serialize(asset, context: "edit"), location: Url.rest("/wp/v2/media/#{asset.id}"))
    rescue Library::UploadError => e
      raise store_refusal(e)
    end

    # POST|PUT|PATCH /wp/v2/media/:id — update_item(), :455.
    def update
      asset = loaded_asset
      attributes = {}
      attributes[:alt_text] = Sanitizing::Formatting.strip_tags(params[:alt_text].to_s) if sent?(:alt_text)
      attributes[:caption] = raw_text(params[:caption]) if sent?(:caption)
      attributes[:title] = raw_text(params[:title]) if sent?(:title)
      attributes[:slug] = unique_slug(Sanitizing::Formatting.sanitize_title(params[:slug].to_s), asset) if params[:slug].present?
      attributes[:attached_to_id] = requested_parent&.id if sent?(:post)
      asset.update!(attributes)
      set_allow_header(item_allow(asset))
      render_json(serialize(asset.reload, context: "edit"))
    end

    # DELETE /wp/v2/media/:id — delete_item(), :560. An attachment does NOT support
    # trashing (`EMPTY_TRASH_DAYS` never applies to it), so `force` is mandatory.
    def destroy
      asset = loaded_asset
      unless force_param?
        raise PublicApi::RestError.new("rest_trash_not_supported",
                                       "The post does not support trashing. Set 'force=true' to delete.",
                                       501)
      end
      previous = serialize(asset, context: "edit", links: false)
      asset.destroy!
      set_allow_header(%w[GET POST PUT PATCH DELETE])
      render_json({ deleted: true, previous: previous })
    end

    private

    # ── serialisation ────────────────────────────────────────────────────────────

    def serialize(asset, context: self.context, links: true)
      json = MediaSerializer.new(asset, context: context, allow: item_allow(asset),
                                        actions: item_actions(asset, context)).as_json
      links ? json : json.except(:_links)
    end

    # ── the two upload shapes ────────────────────────────────────────────────────

    # Returns [bytes, filename] or raises the legacy's WP_Error for the shape it got.
    def upload_payload
      file = params[:file] || params["async-upload"]
      return multipart_payload(file) if file.respond_to?(:read)

      raw_body_payload
    end

    # upload_from_file(), :415: the only pre-store check is that a part arrived.
    def multipart_payload(file)
      bytes = file.read.to_s.b
      raise upload_error("rest_upload_no_data", "No data supplied.") if bytes.empty?

      @store_error_code = "rest_upload_unknown_error"
      [bytes, file.try(:original_filename).to_s]
    end

    # upload_from_data(), :360 — the checks in the legacy's own order: body, then
    # Content-Type, then Content-Disposition, then the filename inside it.
    def raw_body_payload
      bytes = request.raw_post.to_s.b
      raise upload_error("rest_upload_no_data", "No data supplied.") if bytes.empty?
      raise upload_error("rest_upload_no_content_type", "No Content-Type supplied.") if request.media_type.blank?

      disposition = request.headers["Content-Disposition"].to_s
      if disposition.blank?
        raise upload_error("rest_upload_no_content_disposition", "No Content-Disposition supplied.")
      end

      match = DISPOSITION_FILENAME.match(disposition)
      filename = (match && (match[1] || match[2])).to_s
      if filename.empty?
        raise upload_error("rest_upload_invalid_disposition",
                           "Invalid Content-Disposition supplied. Content-Disposition needs to be " \
                           'formatted as `attachment; filename="image.png"` or similar.')
      end

      @store_error_code = "rest_upload_sideload_error"
      [bytes, filename]
    end

    def upload_error(code, message) = PublicApi::RestError.new(code, message, 400)

    # _wp_handle_upload()'s `array( 'error' => … )`, wrapped: the MESSAGE is the legacy's
    # (Library::UploadError carries it verbatim) and the CODE is the one belonging to the
    # shape the request used. Status 500, as the legacy sets it — an odd status for a
    # rejected file type, and the documented one.
    def store_refusal(error)
      PublicApi::RestError.new(@store_error_code || "rest_upload_unknown_error", error.message, 500)
    end

    # ── the parent post (`post` argument) ────────────────────────────────────────

    def requested_parent
      return nil unless params[:post].present? && params[:post].to_i.positive?

      @requested_parent ||= Publishing::Post.find_by(id: params[:post].to_i)
    end

    # ── slug ────────────────────────────────────────────────────────────────────

    def apply_slug!(asset)
      return if params[:slug].blank?

      asset.update!(slug: unique_slug(Sanitizing::Formatting.sanitize_title(params[:slug].to_s), asset))
    end

    # wp_unique_post_slug() for an attachment: unique across all attachments.
    def unique_slug(base, asset)
      base = "asset" if base.blank?
      return base unless Library::Asset.where(slug: base).where.not(id: asset.id).exists?

      suffix = 2
      suffix += 1 while Library::Asset.where(slug: "#{base}-#{suffix}").where.not(id: asset.id).exists?
      "#{base}-#{suffix}"
    end

    # ── read scope ──────────────────────────────────────────────────────────────

    # Attachments whose parent post is published (an unattached or draft-parent asset is
    # not public). WP checks `inherit`+parent readability; this reproduces the visible set.
    def readable_scope
      published_ids = Publishing::Post.where(status: "published").select(:id)
      Library::Asset.where(attached_to_id: published_ids)
    end

    # ── permission callbacks (class-wp-rest-attachments-controller.php) ─────────

    def read_item
      asset = loaded_asset
      parent = asset.attached_to_id && Publishing::Post.find_by(id: asset.attached_to_id)
      return true if parent && parent.status.to_s == "published"

      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts)
    end

    # create_item_permissions_check(), :286. The attachment post type registers
    # `'create_posts' => 'upload_files'` (post.php, create_initial_post_types), so the
    # PARENT posts-controller check is already the upload_files check — which is why the
    # legacy answers a refused upload with the posts controller's message.
    def create_item
      unless current_actor && Access::AssetPolicy.new(current_actor, nil).permit?(:upload)
        raise rest_denied("rest_cannot_create", "Sorry, you are not allowed to create posts as this user.")
      end

      # ":296 — Attaching media to a post requires ability to edit said post."
      if params[:post].present? && params[:post].to_i.positive?
        parent = requested_parent
        unless parent && Access::PostPolicy.for(current_actor, parent).permit?(:edit)
          raise rest_denied("rest_cannot_edit", "Sorry, you are not allowed to upload media to this post.")
        end
      end
      true
    end

    # update_item_permissions_check() → the posts controller's, against `edit_post` on
    # an attachment (post_status 'inherit', so owner vs. others decides). :455
    def update_item
      asset = loaded_asset
      return true if Access::AssetPolicy.new(current_actor, asset).permit?(:edit)

      raise rest_denied("rest_cannot_edit", "Sorry, you are not allowed to edit this post.")
    end

    def delete_item
      asset = loaded_asset
      return true if Access::AssetPolicy.new(current_actor, asset).permit?(:delete)

      raise rest_denied("rest_cannot_delete", "Sorry, you are not allowed to delete this post.")
    end

    # ── rest_send_allow_header() / targetHints ──────────────────────────────────

    def item_allow(asset)
      allow = %w[GET]
      if current_actor
        editable = Access::AssetPolicy.new(current_actor, asset).permit?(:edit)
        allow.concat(%w[POST PUT PATCH]) if editable
        allow << "DELETE" if Access::AssetPolicy.new(current_actor, asset).permit?(:delete)
      end
      allow
    end

    def collection_allow
      allow = %w[GET]
      allow << "POST" if current_actor && Access::AssetPolicy.new(current_actor, nil).permit?(:upload)
      allow
    end

    # rest_prepare_attachment's action links, edit context only (:1660).
    def item_actions(asset, context)
      return [] unless context.to_s == "edit" && current_actor

      actions = []
      actions << "unfiltered-html" if holds?("unfiltered_html")
      actions << "assign-author" if Access::SitePolicy.new(current_actor, nil).permit?(:edit_others_posts)
      actions
    end

    def holds?(capability)
      return false if current_actor.nil?

      Access::RoleCatalogue.capabilities_for(current_actor.roles).include?(capability)
    end

    def loaded_asset
      @loaded_asset ||= Library::Asset.find_by(id: params[:id]) ||
                        raise(PublicApi::RestError.new("rest_post_invalid_id", "Invalid post ID.", 404))
    end
  end
end
