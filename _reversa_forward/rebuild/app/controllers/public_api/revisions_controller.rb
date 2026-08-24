# frozen_string_literal: true

module PublicApi
  # `GET /wp/v2/posts/:parent/revisions` — WP_REST_Revisions_Controller. Gutenberg's
  # "Revisions" panel reads it, and its absence was found by DRIVING the editor rather than
  # by the request specs: every endpoint the specs covered answered, and this one 404'd.
  #
  # Reuses AutosaveSerializer, which already emits WP_REST_Revisions_Controller's own item
  # shape (autosaves ARE revisions in the legacy — the autosave controller subclasses the
  # revisions one). Only regular revisions are listed here; the autosave endpoint lists the
  # autosave, exactly as the legacy splits them.
  class RevisionsController < BaseController
    permission :index, :read_revisions
    permission :show, :read_revisions
    permission :destroy, :delete_revision

    def index
      render_collection(AutosaveSerializer.collection(revisions, post: parent_post))
    end

    def show
      revision = revisions.find_by(id: params[:id]) || not_found!
      render_item(AutosaveSerializer.new(revision, post: parent_post).as_json)
    end

    # DELETE /wp/v2/posts/:parent/revisions/:id — wp_delete_post_revision(). The legacy
    # answers with {deleted: true, previous: <item>}, the same shape a force-deleted post
    # uses, and requires `delete_post` on the PARENT.
    def destroy
      revision = revisions.find_by(id: params[:id]) || not_found!
      previous = AutosaveSerializer.new(revision, post: parent_post).as_json
      previous.delete(:_links)
      revision.destroy!
      render json: { deleted: true, previous: previous }
    end

    private

    def parent_scope = params[:parent_type].to_s == "pages" ? Publishing::Page : Publishing::Article

    def parent_post
      @parent_post ||= parent_scope.find_by(id: params[:parent]) ||
                       raise(RestError.new(:rest_post_invalid_parent, "Invalid post parent ID.", 404))
    end

    def revisions = Publishing::Revision.where(post_id: parent_post.id).regular.newest_first

    def not_found!
      raise RestError.new(:rest_post_invalid_id, "Invalid post ID.", 404)
    end

    # WP_REST_Revisions_Controller::get_items_permissions_check → `edit_post` on the PARENT
    # (revisions are editorial history, never public).
    def read_revisions
      return true if current_actor && Access::PostPolicy.for(current_actor, parent_post).permit?(:edit)

      raise RestError.new(:rest_cannot_read, "Sorry, you are not allowed to view revisions of this post.",
                          current_actor ? 403 : 401)
    end

    def delete_revision
      return true if current_actor && Access::PostPolicy.for(current_actor, parent_post).permit?(:delete)

      raise RestError.new(:rest_cannot_delete, "Sorry, you are not allowed to delete revisions of this post.",
                          current_actor ? 403 : 401)
    end
  end
end
