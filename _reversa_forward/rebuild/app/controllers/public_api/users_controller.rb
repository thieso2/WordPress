# frozen_string_literal: true

module PublicApi
  # /wp/v2/users — WP_REST_Users_Controller. The collection is public but shows only
  # authors of published content (get_items with has_published_posts, the anonymous
  # default), ordered by name ASC. `users/me` has NO public reading: with no identity it
  # is rest_not_logged_in (401), reproduced through the permission callback so the body is
  # the WP_Error envelope rather than the route gate's bare 403.
  class UsersController < BaseController
    include CollectionPagination

    permission :show, :read_item
    permission :me, :require_login

    def index
      scope = author_scope.order(Arel.sql("LOWER(display_name) ASC"), :id)
      total = scope.count
      records = scope.offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/users")
      render_json(records.map { |u| UserSerializer.new(u).as_json })
    end

    def show
      render_json(UserSerializer.new(loaded_user).as_json)
    end

    def me
      render_json(UserSerializer.new(current_actor).as_json)
    end

    private

    # has_published_posts: the authors of published posts/pages (public post types).
    def author_scope
      author_ids = Publishing::Post.where(status: "published",
                                          type: %w[Publishing::Article Publishing::Page])
                                   .distinct.pluck(:author_id).compact
      Identity::User.where(id: author_ids)
    end

    def require_login
      return true if current_actor

      not_logged_in!
    end

    # get_item_permissions_check: a user id nobody can see is rest_user_invalid_id (404).
    # For view context, a user is visible only if they authored published content.
    def read_item
      user = loaded_user
      return true if author_scope.exists?(id: user.id)
      return true if current_actor && Access::UserPolicy.new(current_actor, user).permit?(:edit)

      false
    end

    def loaded_user
      @loaded_user ||= Identity::User.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_user_invalid_id", "Invalid user ID.", 404))
    end
  end
end
