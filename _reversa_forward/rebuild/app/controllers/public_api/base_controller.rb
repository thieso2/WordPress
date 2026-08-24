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
    # REST callers carry a bearer token or an application password, never a cookie, so
    # there is no forgery surface to protect (the legacy's nonce is a cookie-session
    # concern; class-wp-rest-server.php:409 accepts application passwords without one).
    skip_forgery_protection

    rescue_from PublicApi::RestError, with: :render_rest_error

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

    private

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

    # rest_authorization_required_code(): 401 before an identity exists, 403 after.
    def deny!(code: "rest_forbidden", message: "Sorry, you are not allowed to do that.")
      raise PublicApi::RestError.new(code, message, current_actor ? 403 : 401)
    end

    def not_logged_in!
      raise PublicApi::RestError.new("rest_not_logged_in", "You are not currently logged in.",
                                     current_actor ? 403 : 401)
    end

    def render_rest_error(error)
      render_json(error.as_json, status: error.status)
    end

    # wp_send_json / rest_send_response: `application/json; charset=UTF-8`, and the body
    # is `wp_json_encode()`d — JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE. Ruby's
    # JSON.generate matches both (raw '/', raw UTF-8, and no HTML-entity escaping of
    # '<'/'>'/'&', which Rails' `render json:` would apply and which would corrupt every
    # content.rendered). So the body is generated here, not through the AS::JSON encoder.
    def render_json(payload, status: :ok)
      response.set_header("Content-Type", "application/json; charset=UTF-8")
      render body: JSON.generate(payload), status: status
    end

    # ── Who is asking ────────────────────────────────────────────────────────────
    # An API caller identifies itself the way the legacy's REST callers do (there is no
    # cookie session on this surface): a Wave-3 session token as a Bearer token, or an
    # application password over HTTP Basic (wp_authenticate_application_password(),
    # wp-includes/user.php:372). `super` stays first so a future cookie session wins.
    def current_actor
      return @current_actor if defined?(@current_actor)

      @current_actor = super || actor_from_bearer || actor_from_basic
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
    def context = params[:context].presence_in(%w[view embed edit]) || "view"
  end
end
