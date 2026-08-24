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
    before_action :load_asset
    before_action :authorize_edit

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
  end
end
