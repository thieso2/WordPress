# frozen_string_literal: true

module Console
  # console.media — the single-asset edit screen (P-EDIT). Legacy origin: the attachment
  # edit screen (wp-admin/post.php for a post_type='attachment', get_media_item() fields,
  # includes/media.php) and its save through wp_update_post() / get_attachment_fields_to_save().
  #
  # 🔑 AD-03: alt text is a COLUMN now (assets.alt_text), not `_wp_attachment_image_alt`
  # postmeta; caption is a column too. There is no `description` column (the legacy's
  # post_content), so that field is not reproduced.
  #
  # Authorization: current_user_can( 'edit_post', $id ) on the attachment —
  # Access::AssetPolicy(:edit), which maps to edit_posts / edit_others_posts (the
  # attachment post type registers with capability_type 'post', capabilities.php).
  class MediaController < BaseController
    # size_format( wp_max_upload_size() ) is rendered into "Maximum upload file size: %s."
    # (media.php:2327). The byte limit is environment-derived in the legacy; a
    # representative default stands in here (the screen is modernized, not golden-compared).
    MAX_UPLOAD_SIZE = 64.megabytes

    before_action :load_asset,       only: %i[edit update]
    before_action :authorize_edit,   only: %i[edit update]
    before_action :authorize_upload, only: %i[new create]

    # GET /console/media/new — console.media-new. wp-admin/media-new.php: the upload UI
    # (media_upload_form()). $title = "Upload Media" (media-new.php:41). Gated on
    # current_user_can( 'upload_files' ) — media-new.php:15, the verbatim wp_die below.
    def new
      @page_title = "Upload Media"
      @screen = "console.media-new"
      render :new
    end

    # POST /console/media/new — media-new.php's `html-upload` branch (the Browser
    # Uploader): media_handle_upload( 'async-upload', $post_id ), then
    # wp_redirect( admin_url( 'upload.php' ) ) (media-new.php:29-39). The plupload async
    # path targets the API-shaped POST /console/media (web/uploads#create); this is the
    # no-JS fallback that lands back on the Media Library list.
    def create
      upload = params[:"async-upload"] || params[:file]

      if upload.respond_to?(:read)
        Library::Asset.upload!(
          io: upload,
          filename: upload.respond_to?(:original_filename) ? upload.original_filename.to_s : "",
          uploader: current_actor,
          attached_to_id: upload_target_id
        )
      end

      redirect_to "/console/media", status: :see_other
    rescue Library::UploadError => e
      @page_title = "Upload Media"
      @screen = "console.media-new"
      flash.now[:error] = e.message
      render :new, status: :unprocessable_content
    end

    # GET /console/media/:id/edit.
    def edit
      @page_title = "Edit Media" # post.php attachment labels edit_item (LITERAL, post.php:100)
      render :edit
    end

    # PATCH/PUT /console/media/:id — wp_update_post() over the attachment's editable fields.
    def update
      @asset.title    = params[:title].to_s if params.key?(:title)
      # get_attachment_fields_to_save(): alt text is stripped of tags (media.php).
      @asset.alt_text = Sanitizing::Formatting.strip_tags(params[:alt].to_s).strip if params.key?(:alt)
      @asset.caption  = params[:caption].to_s if params.key?(:caption)

      if @asset.save
        flash[:success] = "Media file updated." # upload.php messages[4]
        redirect_to edit_console_medium_path(@asset), status: :see_other
      else
        @page_title = "Edit Media"
        flash.now[:error] = @asset.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    private

    def load_asset
      @asset = Library::Asset.find_by(id: params[:id])
      # post.php:200 — wp_die on an id that names no attachment.
      not_found!("Invalid attachment ID.") if @asset.nil?
    end

    def authorize_edit
      return if performed?

      authorize!(Access::AssetPolicy, @asset, :edit,
                 "Sorry, you are not allowed to edit this attachment.")
    end

    # media-new.php:15 — `if ( ! current_user_can( 'upload_files' ) ) wp_die( 'Sorry, you
    # are not allowed to upload files.' )`. AssetPolicy(:upload) is the record-less
    # `upload_files` primitive.
    def authorize_upload
      authorize!(Access::AssetPolicy, nil, :upload,
                 "Sorry, you are not allowed to upload files.")
    end

    # media-new.php:20-26 — `$post_id` defaults to 0, is set from $_REQUEST['post_id']
    # only when it names a post the actor may edit, else falls back to 0 (unattached).
    def upload_target_id
      return nil unless params.key?(:post_id)

      post = Publishing::Post.find_by(id: params[:post_id])
      return nil unless post && Access::PostPolicy.new(current_actor, post).permit?(:edit)

      post.id
    end
  end
end
