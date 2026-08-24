# frozen_string_literal: true

module PublicApi
  # /wp/v2/posts/:id/autosaves and /wp/v2/pages/:id/autosaves —
  # WP_REST_Autosaves_Controller. One of Gutenberg's 24 boot-time preloads
  # (`/wp/v2/posts/1/autosaves?context=edit`), and the endpoint the editor writes to every
  # few seconds thereafter.
  #
  # The model already owns the rule: Publishing::Post#autosave! is
  # wp_create_post_autosave() (wp-admin/includes/post.php:1957) — ONE autosave per author,
  # overwritten in place, and DELETED (returning nil) when its content has caught up with
  # the record. This controller exposes it and adds the one decision that is the
  # endpoint's own (:236-248):
  #
  #   $should_update_parent_draft_post = ! wp_check_post_lock( $post->ID )
  #                                      && ( $is_draft && $post->post_author === $user_id );
  #
  # "When a post is still in draft form, updates from the author can directly update the
  # post. Other autosaves must be stored as per-user autosave revisions." So a draft you
  # own and nobody else is holding open is UPDATED IN PLACE — through the aggregate's own
  # `update!`, so the revision/status/slug invariants still apply — and the response is the
  # POST wearing the autosave shape (parent 0, no `_links`). Anything else takes the
  # revision path.
  class AutosavesController < BaseController
    permission :index,  :read_items
    permission :create, :create_item

    # Set by the routes: "posts" or "pages".
    def index
      render_collection(AutosaveSerializer.collection(autosaves, post: parent_post))
    end

    def create
      post = parent_post
      if update_parent_draft_in_place?(post)
        post.actor = current_actor
        post.title = params[:title].to_s if params.key?(:title)
        post.content = params[:content].to_s if params.key?(:content)
        post.excerpt = params[:excerpt].to_s if params.key?(:excerpt)
        post.save!
        return render_item(AutosaveSerializer.new(post.reload, post: post).as_json)
      end

      revision = post.autosave!(
        title: params.key?(:title) ? params[:title].to_s : post.title.to_s,
        content: params.key?(:content) ? params[:content].to_s : post.content.to_s,
        excerpt: params.key?(:excerpt) ? params[:excerpt].to_s : post.excerpt.to_s,
        actor: current_actor
      )
      # `autosave!` answers nil when the autosave has caught up with the record and was
      # therefore removed (post.php:1982). The legacy still answers with an item — the
      # record itself, which is what the removed autosave had become.
      render_item(AutosaveSerializer.new(revision || post, post: post).as_json)
    end

    private

    # :236-248, transcribed. `wp_check_post_lock` is Post#edit_lock_holder_if_live: a lock
    # held by SOMEONE ELSE inside the 150-second window (Publishing::Post::LOCK_WINDOW).
    def update_parent_draft_in_place?(post)
      return false if post.edit_lock_holder_if_live(actor: current_actor).present?
      return false unless %w[draft auto_draft].include?(post.status.to_s)

      current_actor.present? && post.author_id == current_actor.id
    end

    # wp_get_post_autosave(): the autosaves of this post. The legacy's collection is every
    # author's; `Publishing::Revision.autosaves` is the same set.
    def autosaves
      parent_post.revisions.autosaves.newest_first.to_a
    end

    def parent_scope = params[:parent_type].to_s == "pages" ? Publishing::Page : Publishing::Article

    # get_parent() (class-wp-rest-revisions-controller.php:152) — note the code is
    # `rest_post_invalid_parent`, NOT the posts controller's `rest_post_invalid_id`.
    def parent_post
      @parent_post ||= parent_scope.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_post_invalid_parent",
                                                      "Invalid post parent ID.", 404))
    end

    # get_items_permissions_check(), :160: `current_user_can( 'edit_post', $parent->ID )`.
    def read_items
      return true if Access::PostPolicy.for(current_actor, parent_post).permit?(:edit)

      raise PublicApi::RestError.new("rest_cannot_read",
                                     "Sorry, you are not allowed to view autosaves of this post.",
                                     current_actor ? 403 : 401)
    end

    # create_item_permissions_check(), :186: "Autosave revisions inherit permissions from
    # the parent post" — it delegates to the posts controller's update check, so the code
    # and message are the posts controller's.
    def create_item
      return true if Access::PostPolicy.for(current_actor, parent_post).permit?(:edit)

      raise PublicApi::RestError.new("rest_cannot_edit", "Sorry, you are not allowed to edit this post.",
                                     current_actor ? 403 : 401)
    end
  end
end
