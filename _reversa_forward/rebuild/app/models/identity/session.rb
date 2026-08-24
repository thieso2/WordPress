# frozen_string_literal: true

module Identity
  # Replaces usermeta['session_tokens'], a serialized array (BR-AUTH-15). T-03 explodes
  # it into rows. Only the digest is stored; the token itself is never at rest.
  class Session < ApplicationRecord
    self.table_name = "sessions"
    belongs_to :user, class_name: "Identity::User"
    validates :token_digest, presence: true, uniqueness: true
    scope :live, -> { where(expires_at: Time.current..) }

    # BR-MIGRATE-119 / BR-AUTH-09 (wp-includes/pluggable.php:1073): the session lives 14
    # days with "Remember Me" and 2 days without. In remember-me mode the BROWSER cookie
    # outlives the session by 12 hours (`$expire = $expiration + 12 * HOUR_IN_SECONDS`,
    # :1081) -- so that a cookie presented in that window is rejected by the server
    # rather than silently absent, which is what makes the expiry observable.
    REMEMBER_TTL = 14.days
    DEFAULT_TTL = 2.days
    COOKIE_GRACE = 12.hours

    # BR-MIGRATE-118 / BR-AUTH-08 (pluggable.php:806): a POST (or Ajax) request gets one
    # extra hour on an otherwise-expired session, so a form that was open when the
    # session lapsed still submits.
    POST_GRACE = 1.hour

    def self.ttl_for(remember:) = remember ? REMEMBER_TTL : DEFAULT_TTL

    def self.issue!(user, ttl: 14.days, ip: nil, user_agent: nil)
      raw = SecureRandom.hex(32)
      create!(user: user, token_digest: Digest::SHA256.hexdigest(raw),
              expires_at: Time.current + ttl, ip: ip, user_agent: user_agent)
      raw
    end

    # `grace` is BR-AUTH-08's one hour, granted by the caller that knows the request
    # method. The default is the strict check every other caller (nonces included)
    # relies on.
    def self.authenticate(raw, grace: 0)
      return nil if raw.blank?

      where(expires_at: (Time.current - grace)..).find_by(token_digest: Digest::SHA256.hexdigest(raw.to_s))
    end

    # `<` and not `<=`, so this is the exact complement of the `live` scope above. The
    # two disagreed at the boundary instant: `live` included a session whose expires_at
    # was exactly now, while `expired?` called the same row expired. The oracle settles
    # which one is right -- WP_Session_Tokens::is_still_valid() is
    # `$session['expiration'] >= time()` (wp-includes/class-wp-session-tokens.php:203),
    # so a session is live up to and including its expiry instant.
    def expired? = expires_at < Time.current

    # `remember` is not stored -- the legacy does not store it either; the cookie's own
    # expiry attribute is the only place it survives. The session's TTL tells the cookie
    # writer which mode it was issued in.
    def remembered? = expires_at - created_at > DEFAULT_TTL + 1.hour
  end
end
