# frozen_string_literal: true

module PublicApi
  # /wp/v2/posts — WP_REST_Posts_Controller for the `post` subtype.
  #
  # Collection: no permission callback, so it is PUBLIC (BR-REST-05). WHICH posts appear
  # is Retrieval::PostQuery's job — the same object the front-end loop uses — so an
  # untrusted request can never widen the status set past `published` (BR-MIGRATE-041).
  #
  # Item: a permission callback IS registered (`read_item`), so BR-REST-04 governs it — a
  # missing id is rest_post_invalid_id (404); an unreadable status returns false and the
  # server answers 401/403 (BR-REST-06).
  class PostsController < BaseController
    include CollectionPagination

    permission :show, :read_item

    REST_BASE = "posts"
    POST_TYPE = "post"

    def index
      query = Retrieval::PostQuery.new(index_vars, trusted: false)
      total = query.total
      records = query.records.includes(:author).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/#{self.class::REST_BASE}")
      render_json(records.map { |p| PostSerializer.new(p).as_json })
    end

    def show
      render_json(PostSerializer.new(loaded_post).as_json)
    end

    private

    def index_vars
      {
        post_type: self.class::POST_TYPE,
        paged: page_param,
        posts_per_page: per_page_param,
        orderby: params[:orderby], order: params[:order],
        s: params[:search]
      }.compact
    end

    def model_scope = Publishing::Article

    # get_item_permissions_check(): invalid id -> 404; unreadable -> false (deny).
    def read_item
      post = loaded_post
      return true if post.status.to_s == "published"

      # A non-published post needs edit rights on it (map_meta_cap read_post -> edit_post
      # for private/draft). Anonymous -> false -> 401.
      Access::PostPolicy.new(current_actor, post).permit?(:edit)
    end

    def loaded_post
      @loaded_post ||= model_scope.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_post_invalid_id", "Invalid post ID.", 404))
    end
  end
end
