# frozen_string_literal: true

module Access
  # The `edit_comment` arm, wp-includes/capabilities.php:554-586: editing a comment is
  # editing the post it hangs off. Every write action the legacy admin exposes on a
  # single comment -- edit, approve, unapprove, spam, trash, delete -- is gated on
  # `current_user_can( 'edit_comment', $id )` (wp-admin/comment.php:84,110,295;
  # wp-admin/edit-comments.php:80; wp-admin/includes/ajax-actions.php:749,1491), so they
  # all share this mapping.
  class CommentPolicy < BasePolicy
    WRITE_ACTIONS = %i[edit approve unapprove spam trash delete].freeze

    def required_capabilities(action)
      action = action.to_sym
      return edit_comment if WRITE_ACTIONS.include?(action)

      case action
      when :read     then record&.approved? ? [] : ["moderate_comments"]
      # The moderation QUEUE (status filters, bulk actions): `moderate_comments`,
      # ajax-actions.php:1018 in combination with edit_comment.
      when :moderate then ["moderate_comments"]
      else []
      end
    end

    private

    def edit_comment
      return [DO_NOT_ALLOW] if record.nil?                        # :567 (BR-MIGRATE-106)

      post = record.post
      if post
        # :578: `$caps = map_meta_cap( 'edit_post', $user_id, $post->ID )`
        Access::PostPolicy.for(actor, post).required_capabilities(:edit)
      else
        # :580: "If the post doesn't exist, we have an orphaned comment. Fall back to
        # the edit_posts capability, instead." Unreachable here -- comments.post_id is a
        # NOT NULL foreign key -- but it is the legacy's answer, so it is kept.
        ["edit_posts"]
      end
    end
  end
end
