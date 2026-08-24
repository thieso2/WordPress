# frozen_string_literal: true

module Discussion
  # The `moderation-hash` query argument — wp-comments-post.php:60-68.
  #
  # A commenter who did not consent to cookies is sent back with
  # `?unapproved=<id>&moderation-hash=wp_hash( $comment->comment_date_gmt )` so the
  # "awaiting moderation" note can be shown for their own pending comment without a
  # cookie (wp_get_unapproved_comment_author_email(), comment.php:2095, checks the same
  # hash later). wp_hash() is HMAC-MD5 under the installation's `auth` salt
  # (pluggable.php:2719). The salt is per installation — the oracle's value cannot be
  # reproduced and is never compared — so the target derives its own secret from
  # secret_key_base, exactly as Identity::Nonce does, and keeps the observable shape:
  # 32 lowercase hex characters over the comment's UTC submission timestamp in the
  # legacy's `Y-m-d H:i:s` form.
  module ModerationHash
    LENGTH = 32

    module_function

    def for(comment)
      data = comment.submitted_at.utc.strftime("%Y-%m-%d %H:%M:%S")
      OpenSSL::HMAC.hexdigest("SHA256", salt, data)[0, LENGTH]
    end

    def valid?(comment, presented)
      presented = presented.to_s
      return false if presented.empty?

      ActiveSupport::SecurityUtils.secure_compare(self.for(comment), presented)
    end

    def salt
      @salt ||= Rails.application.key_generator.generate_key("discussion/moderation-hash", 32)
    end
  end
end
