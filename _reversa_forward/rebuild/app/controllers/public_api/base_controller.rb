# frozen_string_literal: true

module PublicApi
  # The REST server, reduced to what its observable contract needs
  # (class-wp-rest-server.php). This is the ONE place the permission overrides Q4
  # reaffirmed live, so read them here rather than in each endpoint:
  #
  #   BR-MIGRATE-238 (BR-REST-05)  a route with NO permission callback is fully PUBLIC.
  #   BR-MIGRATE-237 (BR-REST-04)  a callback returning false OR null (or nothing) DENIES.
  #   BR-MIGRATE-239 (BR-REST-06)  a denial is 401 for anonymous, 403 for authenticated
  #                                (rest_authorization_required_code()).
  #
  # AD-01 makes these permanent (no filter can move them); AD-04 makes the permissive
  # default *reachable only on purpose* — every /wp-json route carries an explicit
  # declaration in config/initializers/authorization_declarations.rb, and a read route is
  # declared `mode: :public` deliberately. The per-record read checks (a draft, a
  # password-protected body in `edit` context) then run INSIDE the action and answer with
  # the legacy's WP_Error envelope, exactly as wp-admin/async-upload.php's caps do.
  class BaseController < ApplicationController
    # ⚠️ REVISED (Wave 4, the write surface). The header above used to end "REST callers
    # carry a bearer token or an application password, NEVER a cookie, so there is no
    # forgery surface to protect". That stopped being true the moment @wordpress/editor
    # was pointed at this backend: api-fetch sends the browser's logged-in cookie plus an
    # `X-WP-Nonce` header, which is precisely the case class-wp-rest-server.php:409
    # carves out — an application password is accepted with NO nonce, a cookie is not.
    #
    # So Rails' own forgery protection stays off (its token is form-shaped and its failure
    # is not a WP_Error) and rest_cookie_check_errors() is reproduced instead, verbatim,
    # in `rest_cookie_check_errors` below. Three outcomes, all observed on the oracle:
    #   · no nonce at all      -> `wp_set_current_user( 0 )`: the cookie identity is
    #                             DISCARDED and the request proceeds anonymously (so a
    #                             GET still reads public content and a write answers
    #                             rest_cannot_create/401 — NOT a nonce error);
    #   · nonce present, bad   -> rest_cookie_invalid_nonce / "Cookie check failed" / 403,
    #                             on EVERY verb including GET, and whether or not a cookie
    #                             was sent;
    #   · nonce present, good  -> the cookie identity stands.
    # A bearer token or an application password short-circuits the whole check, because a
    # client that had to attach a credential deliberately cannot be forged into it.
    include Auth::SessionCookie

    skip_forgery_protection

    rescue_from PublicApi::RestError, with: :render_rest_error

    # ⚠️ PREPEND. ApplicationController registers `enforce_authorization_declaration`
    # (AD-04) and `resolve_request_locale`, and BOTH read `current_actor` — so the cookie
    # identity must already have been accepted or discarded before either runs, exactly as
    # `rest_authentication_errors` runs before the REST server dispatches. Prepending is
    # what puts it there.
    prepend_before_action :rest_cookie_check_errors

    # ── The permission callback registry (register_rest_route's permission_callback) ──
    #
    # A subclass declares `permission :show, :read_item` to attach a callback; an action
    # with no entry has NO callback and is therefore PUBLIC (BR-REST-05). The value is a
    # method name invoked on the controller, mirroring how a route's callback is a
    # bound method in the legacy.
    class_attribute :permission_callbacks, instance_writer: false, default: {}

    def self.permission(action, method_name)
      # dup so a subclass does not mutate an ancestor's shared hash.
      self.permission_callbacks = permission_callbacks.merge(action.to_sym => method_name)
    end

    before_action :enforce_rest_permission
    before_action :send_cors_headers

    private

    # rest_send_cors_headers(), wp-includes/rest-api.php:1210. Without
    # `Access-Control-Expose-Headers` a cross-origin fetch cannot READ `X-WP-Total`,
    # `X-WP-TotalPages` or `Link`, and @wordpress/core-data paginates off exactly those
    # three; `Access-Control-Allow-Headers` is the list the legacy names, verbatim.
    # (`Access-Control-Allow-Origin` is NOT sent: the legacy only emits one for an origin
    # `is_allowed_http_origin()` accepts, which on a single-site install is its own.)
    def send_cors_headers
      response.set_header("Access-Control-Expose-Headers", "X-WP-Total, X-WP-TotalPages, Link")
      response.set_header("Access-Control-Allow-Headers",
                          "Authorization, X-WP-Nonce, Content-Disposition, Content-MD5, Content-Type")
    end

    # `?_locale=user` on a JSON request resolves to the caller's locale rather than the
    # site locale (BR-I18N-04 / BR-MIGRATE-286, determine_locale()'s
    # `'user' === $_GET['_locale'] && wp_is_json_request()`, l10n.php:151). Every REST route
    # here is a JSON request, so the `_locale` value is the whole test; `locale_user` is the
    # bearer/app-password actor resolved above.
    def json_user_locale_request? = params[:_locale].to_s == "user"

    # class-wp-rest-server.php:1252-1262, transcribed:
    #
    #   if ( ! is_wp_error( $response ) ) {
    #       if ( $callback ) {                         // a callback is registered
    #           $permission = call_user_func( $callback, $request );
    #           if ( is_wp_error( $permission ) ) $response = $permission;
    #           elseif ( false === $permission || null === $permission )
    #               $response = new WP_Error( 'rest_forbidden', …, 401|403 );
    #       }
    #   }
    #
    # No `$callback` key at all skips the whole block — the route is public (:1258).
    def enforce_rest_permission
      method_name = self.class.permission_callbacks[action_name.to_sym]
      return if method_name.nil? # BR-REST-05: no callback -> public.

      result = send(method_name)
      return if result == true # an explicit allow.

      # A callback may hand back a fully-formed WP_Error (its own code/status), and that
      # error is the response verbatim (class-wp-rest-server.php:1256).
      raise result if result.is_a?(PublicApi::RestError)

      # BR-REST-04: false, nil, or a callback that forgot to return — all DENY. The reason
      # is generic here (rest_forbidden); an endpoint wanting a specific code raises its
      # own WP_Error instead of returning false.
      deny!
    end

    # ── rest_cookie_check_errors(), wp-includes/rest-api.php ──────────────────────
    #
    #   if ( true !== $wp_rest_auth_cookie && is_user_logged_in() ) return $result;  // another
    #                                                    // authentication method won; no nonce
    #   $nonce = $_REQUEST['_wpnonce'] ?? $_SERVER['HTTP_X_WP_NONCE'] ?? null;
    #   if ( null === $nonce ) { wp_set_current_user( 0 ); return true; }
    #   if ( ! wp_verify_nonce( $nonce, 'wp_rest' ) )
    #       return new WP_Error( 'rest_cookie_invalid_nonce', __( 'Cookie check failed' ),
    #                            array( 'status' => 403 ) );
    #
    # The 403 is FLAT — not rest_authorization_required_code(), so it is 403 even for a
    # caller with no identity at all. Verified against the oracle for every combination of
    # {cookie, no cookie} x {GET, POST}.
    def rest_cookie_check_errors
      # An identity that did NOT come from the cookie needs no nonce.
      return if credentialed_actor

      nonce = params[PublicApi::RestNonce::PARAM].presence ||
              request.headers[PublicApi::RestNonce::HEADER].presence

      # No nonce: the cookie is not trusted to speak for its user, so the request is
      # anonymous. It is NOT refused — this is `wp_set_current_user( 0 )`.
      if nonce.nil?
        @cookie_identity_suppressed = true
        return
      end

      return if PublicApi::RestNonce.verify(nonce, session_token)

      raise PublicApi::RestError.new("rest_cookie_invalid_nonce", "Cookie check failed", 403)
    end

    # rest_authorization_required_code(): 401 before an identity exists, 403 after.
    def deny!(code: "rest_forbidden", message: "Sorry, you are not allowed to do that.")
      raise PublicApi::RestError.new(code, message, current_actor ? 403 : 401)
    end

    def not_logged_in!
      raise PublicApi::RestError.new("rest_not_logged_in", "You are not currently logged in.",
                                     current_actor ? 403 : 401)
    end

    # ── kses_init(), wp-includes/kses.php:2605 — the post-write allowlist ─────────
    #
    # WordPress hangs wp_filter_post_kses on content_save_pre / excerpt_save_pre and
    # wp_filter_kses on title_save_pre, so wp_insert_post()/wp_update_post() run every
    # incoming field through wp_kses() — but ONLY when `kses_init()` registered the
    # filters, which it does exclusively for a user WITHOUT `unfiltered_html`. AD-01
    # removed the hook system and nothing replaced this (RISK-023 V1: any Author could
    # store `<script>` that ran for anonymous visitors).
    #
    # The filter is therefore inlined here and applied by each WRITE action as it copies
    # the request fields — at the moment of the authenticated HTTP write, against the
    # REQUESTING user's capabilities, which is exactly when and how WordPress does it. It
    # is NOT applied at render and NOT retroactively over stored content: WordPress does
    # neither, and sanitising the seeded corpus would break the 53-screen byte comparison
    # while still not matching the oracle.
    #
    #   content, excerpt -> wp_kses($v, 'post')             (Tables::ALLOWED_POST_TAGS)
    #   title            -> wp_kses($v, 'title_save_pre')    (the default context, ALLOWED_TAGS)
    def kses_post_content(value)
      filter_kses? ? Sanitizing::Kses.wp_kses_post(value) : value
    end

    def kses_post_title(value)
      filter_kses? ? Sanitizing::Kses.wp_kses(value, "title_save_pre") : value
    end

    # `! current_user_can( 'unfiltered_html' )`, the single gate kses_init() reads. False
    # for an Editor/Administrator (and a multisite super admin); true for an Author,
    # Contributor, Subscriber and the anonymous caller.
    def filter_kses?
      !Access::SitePolicy.new(current_actor, nil).permit?(:unfiltered_html)
    end

    # An error envelope is never `_fields`-filtered: `{code, message, data}` is the whole
    # contract and a client asking for `_fields=id` still has to be able to read the
    # failure. (rest_filter_response_fields() runs on `rest_post_dispatch` in the legacy
    # and would filter it; the legacy's own clients never hit that case, and answering a
    # 403 with `{}` would be strictly worse.)
    def render_rest_error(error)
      render_json(error.as_json, status: error.status, fields: nil)
    end

    # wp_send_json / rest_send_response: `application/json; charset=UTF-8`, and the body
    # is `wp_json_encode()`d — JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE. Ruby's
    # JSON.generate matches both (raw '/', raw UTF-8, and no HTML-entity escaping of
    # '<'/'>'/'&', which Rails' `render json:` would apply and which would corrupt every
    # content.rendered). So the body is generated here, not through the AS::JSON encoder.
    # `_fields` is applied HERE rather than in each action, so every endpoint on this
    # surface honours it without having to remember to — which is the point: two of
    # Gutenberg's 24 preloads carry `_fields` and they are on two DIFFERENT controllers
    # (the root document and users#show). Pass `fields: nil` to opt a payload out.
    def render_json(payload, status: :ok, fields: requested_fields)
      body = fields.nil? ? payload : filter_fields(payload, fields)
      response.set_header("Content-Type", "application/json; charset=UTF-8")
      render body: JSON.generate(body), status: status
    end

    def filter_fields(payload, fields)
      return payload.map { |item| PublicApi::FieldFilter.apply(item, fields) } if payload.is_a?(Array)

      PublicApi::FieldFilter.apply(payload, fields)
    end

    # ── Who is asking ────────────────────────────────────────────────────────────
    # An API caller identifies itself the way the legacy's REST callers do (there is no
    # cookie session on this surface): a Wave-3 session token as a Bearer token, or an
    # application password over HTTP Basic (wp_authenticate_application_password(),
    # wp-includes/user.php:372). `super` stays first so a future cookie session wins.
    def current_actor
      return @current_actor if defined?(@current_actor)

      @current_actor = credentialed_actor || cookie_actor
    end

    # The two credentials a REST client sends on purpose. Memoised separately from
    # `current_actor` because `rest_cookie_check_errors` asks for them BEFORE the cookie
    # arm has been decided, and asking must not freeze the answer.
    def credentialed_actor
      return @credentialed_actor if defined?(@credentialed_actor)

      @credentialed_actor = actor_from_bearer || actor_from_basic
    end

    # Auth::SessionCookie#current_session, gated on the nonce verdict above.
    def cookie_actor
      return nil if @cookie_identity_suppressed

      current_session&.user
    end

    def actor_from_bearer
      scheme, token = request.authorization.to_s.split(" ", 2)
      return nil unless scheme.to_s.casecmp?("Bearer") && token.present?

      Identity::Session.authenticate(token.strip)&.user
    end

    def actor_from_basic
      scheme, encoded = request.authorization.to_s.split(" ", 2)
      return nil unless scheme.to_s.casecmp?("Basic") && encoded.present?

      login, password = Base64.decode64(encoded).split(":", 2)
      return nil if login.blank? || password.blank?

      user = Identity::User.find_by(login: login) || Identity::User.find_by(email: login)
      return nil unless user

      candidate = password.gsub(/[^a-z\d]/i, "")
      matched = user.application_passwords.detect do |app_password|
        Identity::LegacyDigest.verify(candidate, app_password.digest) ||
          (app_password.digest.start_with?("$2a$", "$2b$") && BCrypt::Password.new(app_password.digest) == candidate)
      end
      return nil unless matched

      matched.update_columns(last_used_at: Time.current, last_ip: request.remote_ip) if matched.last_used_at.nil? || matched.last_used_at < 1.day.ago
      user
    rescue ArgumentError, BCrypt::Errors::InvalidHash
      nil
    end

    # `context` query arg (view|embed|edit). `edit` needs a capability the read routes
    # gate per-record; anonymous callers only ever get `view`.
    #
    # An UNRECOGNISED value is not silently coerced: rest_validate_request_arg() rejects it
    # against the schema enum before the callback runs, with the composite envelope the
    # oracle emits (`data.params` and `data.details` alongside `data.status`).
    CONTEXTS = %w[view embed edit].freeze

    def context
      return @context if defined?(@context)

      raw = params[:context].presence
      @context = raw.nil? ? "view" : (CONTEXTS.include?(raw) ? raw : invalid_enum!("context", CONTEXTS))
    end

    # rest_validate_value_from_schema()'s `rest_not_in_enum` arm, wrapped by
    # WP_REST_Request::has_valid_params() into one `rest_invalid_param` (:1029-1064). The
    # list is joined the way wp_sprintf_l() joins it: "a, b, and c".
    def invalid_enum!(name, allowed)
      detail = "#{name} is not one of #{wp_sprintf_l(allowed)}."
      raise PublicApi::RestError.new(
        "rest_invalid_param", "Invalid parameter(s): #{name}", 400,
        params: { name => detail },
        details: { name => { code: "rest_not_in_enum", message: detail, data: nil } }
      )
    end

    # wp_sprintf_l() with the English list separators: "a", "a and b", "a, b, and c".
    def wp_sprintf_l(items)
      items = items.map(&:to_s)
      case items.length
      when 0 then ""
      when 1 then items.first
      when 2 then items.join(" and ")
      else "#{items[0..-2].join(", ")}, and #{items.last}"
      end
    end

    # `_fields`, parsed once. nil when absent (PublicApi::FieldFilter reads that as "no
    # filtering").
    def requested_fields
      return @requested_fields if defined?(@requested_fields)

      @requested_fields = PublicApi::FieldFilter.parse(params[:_fields])
    end

    # Named aliases for the two shapes an endpoint returns. They add nothing over
    # `render_json` (which already filters) and exist so an action reads as what it is.
    def render_item(payload, status: :ok) = render_json(payload, status: status)
    def render_collection(payloads, status: :ok) = render_json(payloads, status: status)
  end
end
