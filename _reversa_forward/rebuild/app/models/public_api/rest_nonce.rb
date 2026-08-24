# frozen_string_literal: true

module PublicApi
  # `wp_create_nonce( 'wp_rest' )` / `wp_verify_nonce( $nonce, 'wp_rest' )` — the ONE
  # nonce action the REST surface uses (wp-includes/rest-api.php, `rest_cookie_check_errors`).
  #
  # Nothing new is invented here: Identity::Nonce already IS the legacy's nonce family
  # (BR-MIGRATE-122..126) — an HMAC over (tick, action, uid, session token) that carries
  # its own validity, so BR-AUTH-15 (destroying a session invalidates every outstanding
  # nonce) falls out of the session lookup. This module only fixes the ACTION string and
  # names the two places a REST nonce travels, so the console layout that MINTS one and
  # the controller that VERIFIES it cannot drift apart.
  #
  # ⚠️ Why the REST surface has a nonce at all when PublicApi::BaseController's header
  # said it did not: it does now, because the surface grew a COOKIE. A bearer token and
  # an application password are sent deliberately by a client that has them, so there is
  # no forgery surface; a cookie is attached by the browser to any request any page can
  # provoke, so the cookie identity — and ONLY the cookie identity — must be proven to
  # have come from a page this site rendered. That is exactly the split
  # rest_cookie_check_errors() makes (class-wp-rest-server.php:409 accepts an application
  # password with no nonce), and it is reproduced verbatim in BaseController.
  module RestNonce
    ACTION = "wp_rest"

    # `$_SERVER['HTTP_X_WP_NONCE']` and `$_REQUEST['_wpnonce']` — the two places
    # rest_cookie_check_errors() looks, in that precedence order (the `_wpnonce` request
    # arg is consulted FIRST in the legacy; both are accepted here, and a request that
    # carries both must carry the same value for either to pass, so the order is not
    # observable).
    HEADER = "X-WP-Nonce"
    PARAM = :_wpnonce

    module_function

    # The token the console hands to @wordpress/api-fetch (`wpApiSettings.nonce`).
    def issue(session_token) = Identity::Nonce.issue(ACTION, session_token: session_token)

    # 1 / 2 / false — Identity::Nonce keeps the legacy's tri-state age (BR-AUTH-13).
    def verify(nonce, session_token) = Identity::Nonce.verify(nonce, ACTION, session_token: session_token)
  end
end
