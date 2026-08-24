# frozen_string_literal: true

module PublicApi
  # WP_REST_Comments_Controller::prepare_item_for_response(), `view` context
  # (wp-includes/rest-api/endpoints/class-wp-rest-comments-controller.php:770). Only the
  # fields an anonymous caller sees — the edit-context arms (author_email, author_ip,
  # author_user_agent) are omitted, exactly as get_comment's read check drops them.
  class CommentSerializer
    include Entity

    # comment_approved column -> REST status string (:1900). Only `approved` comments are
    # ever served on the public read surface, but the full map is here for completeness.
    STATUS = { "approved" => "approved", "pending" => "hold", "spam" => "spam",
               "trashed" => "trash" }.freeze

    def initialize(comment)
      @comment = comment
    end

    def self.collection(comments) = comments.map { |c| new(c).as_json }

    def as_json
      {
        id: comment.id,
        post: comment.post_id.to_i,
        parent: comment.parent_id.to_i,
        author: comment.user_id.to_i,
        author_name: comment.author_name.to_s,
        author_url: comment.author_url.to_s,
        date: iso(comment.submitted_at),
        date_gmt: iso(comment.submitted_at),
        content: { rendered: Composition::Renderers::CommentBlocks::CommentText.call(comment.content) },
        link: comment_link,
        status: STATUS.fetch(comment.status.to_s, comment.status.to_s),
        type: "comment",
        author_avatar_urls: Avatar.urls(avatar_email),
        meta: { "_wp_note_status": nil },
        _links: links_for
      }
    end

    private

    attr_reader :comment

    def post = comment.post
    def page? = post.is_a?(Publishing::Page)
    def post_rest_base = page? ? "pages" : "posts"
    def post_type = page? ? "page" : "post"

    # get_comment_link(): the post permalink with a `#comment-<id>` fragment (no comment
    # paging in this corpus, so no `comment-page-N` segment).
    def comment_link = "#{Entity.links.permalink(post)}#comment-#{comment.id}"

    # get_comment_author_email(): the registered user's email if any, else the guest email.
    def avatar_email = comment.user&.email.presence || comment.author_email.to_s

    # WP_REST_Comments_Controller::prepare_links() (:1560), in source order: self,
    # collection, author (registered commenter only), up (the post), in-reply-to (a reply
    # only), children (a comment that has replies only).
    def links_for
      out = {
        self: [{ href: Url.rest("/wp/v2/comments/#{comment.id}"), targetHints: { allow: %w[GET] } }],
        collection: [{ href: Url.rest("/wp/v2/comments") }]
      }
      if comment.user_id.to_i.positive?
        out[:author] = [{ embeddable: true, href: Url.rest("/wp/v2/users/#{comment.user_id}") }]
      end
      if post
        out[:up] = [{ embeddable: true, post_type: post_type,
                      href: Url.rest("/wp/v2/#{post_rest_base}/#{comment.post_id}") }]
      end
      if comment.parent_id.to_i.positive?
        out[:"in-reply-to"] = [{ embeddable: true, href: Url.rest("/wp/v2/comments/#{comment.parent_id}") }]
      end
      if Discussion::Comment.where(parent_id: comment.id).exists?
        out[:children] = [{ embeddable: true, href: Url.rest("/wp/v2/comments?parent=#{comment.id}") }]
      end
      out
    end
  end
end
