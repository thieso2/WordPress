# frozen_string_literal: true

module Auth
  # The browser's half of a session: wp_set_auth_cookie() (wp-includes/pluggable.php
  # :1071), wp_validate_auth_cookie() (:782) and wp_clear_auth_cookie() (:1208),
  # reduced to what the auth screens' semantic contract needs (target_screens.md § Part
  # 3, modernized mode).
  #
  # ── What is reproduced, and what is not ──────────────────────────────────────
  # The legacy sets THREE cookies: `wordpress_<hash>` (or `wordpress_sec_<hash>` over
  # TLS) scoped to /wp-admin and /wp-content/plugins, and `wordpress_logged_in_<hash>`
  # scoped to the whole site (:1170-1175). Each carries `login|expiry|token|hmac`, and
  # the split exists so that the admin cookie can be marked Secure while the front-end
  # one is not (BR-MIGRATE-120 / BR-AUTH-10).
  #
  # Here there is ONE cookie, `wordpress_logged_in`, scoped to `/`:
  #   · the `<hash>` suffix (md5 of siteurl, COOKIEHASH) separated several WordPress
  #     installs sharing one domain; a cookie is already host-scoped here, and the
  #     rebuild is one site;
  #   · the auth/logged_in split served path-scoped Secure flags for /wp-admin; the
  #     target has no path-separated admin, so the single cookie is Secure whenever
  #     the request is (the legacy's own rule for `logged_in`, :1085, reduces to that
  #     when home and admin share a scheme);
  #   · the payload is the raw session token under Rails' encrypted cookie jar rather
  #     than the `login|expiry|token|hmac` quadruple. The HMAC keyed on a password
  #     fragment (BR-AUTH-05/06) exists to invalidate cookies on a password change;
  #     Identity::User destroys the session rows instead, which the cookie cannot
  #     outlive. BR-MIGRATE-121's validation order -- expiry, then user, then HMAC,
  #     then session token -- collapses to "is there a live session row", which is
  #     what the last step already decided.
  # What IS reproduced: the session/cookie lifetimes (BR-AUTH-09, Identity::Session),
  # the one-hour POST grace (BR-AUTH-08), the HttpOnly flag, the test cookie that
  # wp-login.php:405 sets on every visit and :1357 checks on submit, and the
  # `wp-resetpass` cookie the reset flow uses to keep the key out of the URL
  # (wp-login.php:911-921).
  module SessionCookie
    extend ActiveSupport::Concern

    COOKIE = "wordpress_logged_in"
    TEST_COOKIE = "wordpress_test_cookie"
    TEST_COOKIE_VALUE = "WP Cookie check"
    RESET_COOKIE = "wp-resetpass"

    included do
      helper_method :current_actor, :current_session
    end

    # The identity every Access declaration is evaluated against. Nil when the cookie
    # is absent, malformed, or names a session that is gone or expired (BR-AUTH-15:
    # the row is the authority).
    def current_actor
      current_session&.user
    end

    def current_session
      return @current_session if defined?(@current_session)

      # BR-MIGRATE-118 / BR-AUTH-08: POST requests get an hour's grace on expiry.
      grace = request.post? ? Identity::Session::POST_GRACE : 0
      @current_session = Identity::Session.authenticate(session_token, grace: grace)
    end

    # The raw token, for Identity::Nonce -- the binding material of BR-MIGRATE-125.
    def session_token
      cookies.encrypted[COOKIE].presence
    end

    # wp_set_auth_cookie(), pluggable.php:1071-1176.
    def issue_session_cookie!(user, remember:)
      ttl = Identity::Session.ttl_for(remember: remember)
      raw = user.start_session!(ttl: ttl, ip: request.remote_ip, user_agent: request.user_agent)
      cookies.encrypted[COOKIE] = {
        value: raw,
        httponly: true,
        secure: request.ssl?,
        same_site: :lax,
        path: "/",
        # :1081-1084: a remembered cookie outlives the session by 12 hours; a plain one
        # is a browser-session cookie (`$expire = 0`).
        expires: (remember ? Time.current + ttl + Identity::Session::COOKIE_GRACE : nil)
      }.compact
      forget_resolved_session
      raw
    end

    # wp_clear_auth_cookie(), pluggable.php:1208. The legacy clears the cookie and
    # leaves the session row to expire (wp_logout() destroys it separately, :748).
    def clear_session_cookie!
      cookies.delete(COOKIE, path: "/")
      forget_resolved_session
    end

    def forget_resolved_session
      remove_instance_variable(:@current_session) if instance_variable_defined?(:@current_session)
    end

    # wp-login.php:404-409: "Set a cookie now to see if they are supported by the
    # browser." A session cookie, HttpOnly, Secure only when the login URL is https.
    def set_test_cookie!
      cookies[TEST_COOKIE] = { value: TEST_COOKIE_VALUE, httponly: true, secure: request.ssl?, path: "/" }
    end

    # `$_COOKIE[TEST_COOKIE]` is what the BROWSER sent; the one set_test_cookie! just
    # wrote for the response does not count (setcookie() never updates $_COOKIE).
    def test_cookie_present? = request.cookies[TEST_COOKIE].present?

    # wp-login.php:911-915: `login:key`, scoped to the reset path, HttpOnly.
    def write_reset_cookie!(login, key, path:)
      cookies[RESET_COOKIE] = { value: "#{login}:#{key}", httponly: true, secure: request.ssl?, path: path }
    end

    # wp-login.php:918-919: `0 < strpos($cookie, ':')` -- the login must be non-empty.
    def read_reset_cookie
      value = cookies[RESET_COOKIE].to_s
      i = value.index(":")
      return nil if i.nil? || i.zero?

      value.split(":", 2)
    end

    def clear_reset_cookie!(path:)
      cookies.delete(RESET_COOKIE, path: path)
    end
  end
end
