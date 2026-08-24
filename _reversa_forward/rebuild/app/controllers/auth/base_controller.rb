# frozen_string_literal: true

module Auth
  # The authentication surface: wp-login.php, one screen per action instead of one URL
  # dispatching on `$action` (DEV-006). Modernized mode (target_screens.md § Part 3):
  # the contract is semantic -- states, events, exits -- and every LITERAL-marked
  # string is verbatim. DEV-009 lets only branding differ.
  #
  # A delivery surface, so the only place allowed to depend on Access
  # (target_architecture.md Note 2). Nothing below the controllers does.
  class BaseController < ApplicationController
    include SessionCookie

    layout "auth"

    # `admin_url()` -- the legacy's default landing and the `wp_safe_redirect()`
    # fallback (pluggable.php:1639). target_screens.md § auth.login: "redirect to
    # {{redirect_to}} or console.index"; console.index is `/console` (§ Part 4).
    CONSOLE_PATH = "/console"
    # `admin_url( 'profile.php' )`, the landing for a user who can read but not edit
    # (wp-login.php:1421). The console track owns the route; the path is the spec's.
    PROFILE_PATH = "/console/profile"

    # wp-login.php:405: every visit to the login surface sets the test cookie.
    before_action :set_test_cookie!

    # wp-login.php:399: nocache_headers() on every action.
    before_action :no_store

    helper_method :login_link_separator, :registration_open?, :site_title

    private

    # The login surface is the ONE place a request-supplied `wp_lang` is honoured, because
    # the login form must be translatable before a user exists (BR-I18N-02 / BR-MIGRATE-284,
    # determine_locale()'s `'wp-login.php' === $GLOBALS['pagenow']` guard, l10n.php:140). The
    # value is sanitised inside Localization::Locale.determine (sanitize_locale_name(),
    # BR-I18N-03) because it becomes part of a catalogue path.
    def login_surface? = true

    # PHP `! empty( $_REQUEST['x'] )` / `$_GET['x']` truthiness, which wp-login.php uses
    # for `reauth` (:1314), `rememberme` (:1478), `loggedout` (:1447) and the
    # `redirect_to` fallbacks (:850, :1127): absent, "" and "0" are all false.
    def php_truthy?(value)
      case value
      when String then !(value.empty? || value == "0")
      when Array, Hash then !value.empty?
      else value.present?
      end
    end

    # wp-login.php:469 `apply_filters( 'login_link_separator', ' | ' )`, unfiltered.
    def login_link_separator = " | "

    # wp-login.php:1108 / :1581 `get_option( 'users_can_register' )`.
    def registration_open? = Identity::Registration.open?

    # `get_bloginfo( 'name', 'display' )`. BR-MIGRATE-014 leaves it HTML-escaped at
    # rest; Configuration::Setting.display marks it safe for that reason.
    def site_title = site_name

    # `wp_specialchars_decode( get_option( 'blogname' ), ENT_QUOTES )` -- the plain-text
    # form every notification email uses (user.php:3361).
    def site_title_plain
      CGI.unescapeHTML(Configuration::Setting["blogname"].to_s).presence || site_name.to_s
    end

    # wp_safe_redirect() -> wp_validate_redirect() (pluggable.php:1632-1725), the rule
    # that decides where `redirect_to` may send a browser: only http(s), only this
    # host, a bare path made absolute, and anything else replaced by the fallback.
    # `allowed_redirect_hosts` is unfiltered (AD-01): the home host alone.
    def safe_redirect_target(location, fallback = CONSOLE_PATH)
      location = location.to_s.gsub(/\A[ \t\n\r\0\x08\x0B]+|[ \t\n\r\0\x08\x0B]+\z/, "")
      return fallback if location.empty?
      # :1674: browsers obey `//host`, so it is a URL with a host.
      location = "http:#{location}" if location.start_with?("//")

      test = location.split("?", 2).first.to_s
      uri = begin
        URI.parse(test)
      rescue URI::InvalidURIError
        return fallback
      end
      return fallback if uri.scheme && !%w[http https].include?(uri.scheme.downcase)
      # :1697: a relative path is made absolute against the current request's directory.
      if uri.host.nil? && !uri.path.to_s.empty? && !uri.path.start_with?("/")
        dir = File.dirname(request.path)
        location = "/#{"#{dir}/".delete_prefix("/")}#{location}".squeeze("/")
      end
      # :1707: scheme, user, pass or port without a host is malformed.
      return fallback if uri.host.nil? && (uri.scheme || uri.userinfo || uri.port)
      return fallback if uri.host && uri.host.downcase != request.host.downcase

      location
    end

    # "The link you followed..." is not an auth screen. A request that is not a form
    # submission the screen declares is answered the way Turbo expects (4xx), with the
    # screen's own error state.
    def render_error_state(template, status: :unprocessable_content)
      render template, status: status
    end

    def no_store
      response.headers["Cache-Control"] = "no-cache, must-revalidate, max-age=0, no-store, private"
    end

    # Turbo submits forms with fetch and follows a 303; a 302 works too, but the
    # convention makes the intent visible (DEV-006, "Turbo-aware redirect").
    def redirect_after_submit(target)
      redirect_to target, status: :see_other
    end

    # Access, used the way a surface may: which legacy capability the actor holds
    # decides the post-login landing (wp-login.php:1415-1422). The owner's override
    # (BR-CAP-05) is not in play here -- these are plain capability lookups.
    def actor_has_capability?(user, capability)
      Access::RoleCatalogue.capabilities_for(user.roles).include?(capability.to_s)
    end
  end
end
