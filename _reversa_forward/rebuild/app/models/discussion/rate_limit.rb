# frozen_string_literal: true

module Discussion
  # NEW — deviation BR-CMT-04 / BR-MIGRATE-068, recorded in parity_specs.md's
  # "6 deliberate deviations" table. The rule as written says the legacy's flood verdict
  # defaults to false and that "no rate limit is enforced by core itself"; with hooks
  # removed by AD-01 there would be no way to add one, so the target enforces one here.
  #
  # ⚠️ FINDING (verified against the live oracle, not inferred). The rule statement is
  # WRONG about the legacy. Core DOES enforce a flood limit by default, through three
  # levels of indirection that a static read of comment.php:938 does not reveal:
  #
  #   default-filters.php:310  add_action('check_comment_flood', 'check_comment_flood_db')
  #   comment.php:887          check_comment_flood_db() { add_filter('wp_is_comment_flood',
  #                                                        'wp_check_comment_flood') }
  #   default-filters.php:311  add_filter('comment_flood_filter', 'wp_throttle_comment_flood')
  #   comment.php:2315         wp_throttle_comment_flood() -> true when the gap is < 15s
  #
  # Probed on the running oracle: two comments from the same author 2 seconds apart —
  # the second came back WP_Error('comment_flood', 'You are posting comments too
  # quickly. Slow down.', 429). So this is not a behaviour the target invents; it is a
  # behaviour the target makes REACHABLE without a hook. The constants below are the
  # legacy's own, and the message and status are preserved verbatim.
  #
  # BR-MIGRATE-067 (BR-CMT-03): flood detection looks back ONE HOUR, matched by user_id
  # when logged in, otherwise by IP, or by email in either case — which is why the
  # interval below is derived from the `comments` table itself, exactly as the legacy
  # query derives it, and not from a counter that could drift away from it.
  class RateLimit < ApplicationRecord
    self.table_name = "comment_rate_limits"

    # BR-MIGRATE-067: the legacy's `$hour_ago` lookback.
    WINDOW = 1.hour
    # wp_throttle_comment_flood(): `( $time_newcomment - $time_lastcomment ) < 15`.
    MINIMUM_INTERVAL = 15.seconds
    # The volume ceiling the legacy has no equivalent for — the added half of the
    # deviation, and the reason `comment_rate_limits` exists as a table at all
    # (target_data_model.md).
    MAX_PER_WINDOW = 5

    # wp_allow_comment(): WP_Error( 'comment_flood', …, 429 ). Preserved verbatim —
    # functional strings are not copy-edited.
    CODE = "comment_flood"
    MESSAGE = "You are posting comments too quickly. Slow down."
    HTTP_STATUS = 429

    validates :author_key, presence: true
    validates :window_start, presence: true

    # BR-MIGRATE-067: `user_id` when logged in, otherwise the IP — "or by email in
    # either case".
    def self.author_keys_for(comment)
      keys = []
      if comment.user_id
        keys << "user:#{comment.user_id}"
      elsif comment.author_ip.present?
        keys << "ip:#{comment.author_ip}"
      end
      keys << "email:#{comment.author_email}" if comment.author_email.present?
      keys
    end

    def self.exceeded?(comment, now: Time.current)
      keys = author_keys_for(comment)
      # An anonymous submission with neither an IP nor an email is unattributable, and
      # the legacy query would match every other such row. Nothing to throttle against.
      return false if keys.empty?

      last = last_submission_at(comment, now: now)
      return true if last && (now - last) < MINIMUM_INTERVAL

      record!(keys, now: now).any? { |row| row.count > MAX_PER_WINDOW }
    end

    # The legacy's flood query, expressed against the same rows:
    #   SELECT comment_date_gmt FROM comments
    #    WHERE comment_date_gmt >= $hour_ago
    #      AND ( <user_id|IP> = %s OR comment_author_email = %s )
    #    ORDER BY comment_date_gmt DESC LIMIT 1
    def self.last_submission_at(comment, now: Time.current)
      identities = []
      if comment.user_id
        identities << Comment.where(user_id: comment.user_id)
      elsif comment.author_ip.present?
        identities << Comment.where(author_ip: comment.author_ip)
      end
      identities << Comment.where(author_email: comment.author_email) if comment.author_email.present?
      return nil if identities.empty?

      scope = Comment.where(submitted_at: (now - WINDOW)..now)
      scope = scope.where.not(id: comment.id) if comment.id
      scope.merge(identities.reduce { |a, b| a.or(b) }).maximum(:submitted_at)
    end

    def self.record!(keys, now: Time.current)
      window_start = now.beginning_of_hour
      keys.map do |key|
        row = find_or_create_by!(author_key: key, window_start: window_start)
        row.increment!(:count)
        row
      end
    end
  end
end
