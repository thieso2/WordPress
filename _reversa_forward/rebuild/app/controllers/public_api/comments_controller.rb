# frozen_string_literal: true

module PublicApi
  # /wp/v2/comments — WP_REST_Comments_Controller. The collection has no permission
  # callback, so it is PUBLIC (BR-REST-05); WHICH comments appear is constrained inside
  # the action to `approved` comments on readable (published) posts — an anonymous caller
  # can never widen past that (get_items forces status=approve for a caller without
  # `moderate_comments`, :340). Default order is date_gmt DESC (:390).
  #
  # Item: a `read_item` permission callback is registered — a missing id is
  # rest_comment_invalid_id (404); an unapproved comment or one on an unreadable post is
  # denied 401/403 (BR-REST-04/06).
  class CommentsController < BaseController
    include CollectionPagination

    permission :show, :read_item

    def index
      scope = readable_scope
      scope = scope.where(post_id: params[:post].to_i) if params[:post].present?
      total = scope.count
      records = scope.order(submitted_at: :desc, id: :desc)
                     .offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/comments")
      render_json(records.map { |c| CommentSerializer.new(c).as_json })
    end

    def show
      render_json(CommentSerializer.new(loaded_comment).as_json)
    end

    private

    # Approved comments whose post is published (the anonymous-visible set).
    def readable_scope
      published_ids = Publishing::Post.where(status: "published").select(:id)
      Discussion::Comment.where(status: "approved", post_id: published_ids)
                         .includes(:post, :user)
    end

    def read_item
      comment = loaded_comment
      return true if comment.status.to_s == "approved" &&
                     comment.post&.status.to_s == "published"

      # A held/spam comment, or one on a non-public post, needs moderate/edit rights.
      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:moderate_comments)
    end

    def loaded_comment
      @loaded_comment ||= Discussion::Comment.find_by(id: params[:id]) ||
                          raise(PublicApi::RestError.new("rest_comment_invalid_id",
                                                         "Invalid comment ID.", 404))
    end
  end
end
