# frozen_string_literal: true

module PublicApi
  # /wp/v2/media — WP_REST_Attachments_Controller. An attachment inherits its parent's
  # status; a published-parent attachment is public, so the collection is served with no
  # permission callback (BR-REST-05) and shows attachments whose parent post is readable.
  # The item registers `read_item`: a missing id is rest_post_invalid_id (404).
  #
  # Default order is date DESC (the posts controller default the attachments controller
  # inherits). See MediaSerializer for the cross-track value-parity limitation.
  class MediaController < BaseController
    include CollectionPagination

    permission :show, :read_item

    def index
      scope = readable_scope
      scope = scope.where(attached_to_id: params[:parent].to_i) if params[:parent].present?
      total = scope.count
      records = scope.order(created_at: :desc, id: :desc)
                     .offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/media")
      render_json(records.map { |a| MediaSerializer.new(a).as_json })
    end

    def show
      render_json(MediaSerializer.new(loaded_asset).as_json)
    end

    private

    # Attachments whose parent post is published (an unattached or draft-parent asset is
    # not public). WP checks `inherit`+parent readability; this reproduces the visible set.
    def readable_scope
      published_ids = Publishing::Post.where(status: "published").select(:id)
      Library::Asset.where(attached_to_id: published_ids)
    end

    def read_item
      asset = loaded_asset
      parent = asset.attached_to_id && Publishing::Post.find_by(id: asset.attached_to_id)
      return true if parent && parent.status.to_s == "published"

      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts)
    end

    def loaded_asset
      @loaded_asset ||= Library::Asset.find_by(id: params[:id]) ||
                        raise(PublicApi::RestError.new("rest_post_invalid_id", "Invalid post ID.", 404))
    end
  end
end
