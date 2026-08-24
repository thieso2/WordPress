# frozen_string_literal: true

module Localization
  # BC-16 -- locale RESOLUTION. The i18n gem owns the machinery (loading, lookup,
  # pluralisation); this class owns the one thing that is a business rule and can be
  # *wrong*: the order in which a request's locale is decided (BR-I18N-01..05,
  # BR-MIGRATE-283..287), and the injection guard on any user-supplied value
  # (BR-I18N-03 / BR-MIGRATE-285).
  #
  # Legacy origin: get_locale() (l10n.php:29), get_user_locale() (:94) and
  # determine_locale() (l10n.php:124).
  module Locale
    module_function

    # get_locale()'s final fallback (l10n.php:70) and WP_Locale_Switcher's seed for the
    # only shipped language (class-wp-locale-switcher.php:50). The site ships one locale.
    DEFAULT = "en_US"

    # WP locale string -> Rails I18n symbol. Only en_US ships, so the map has one real
    # entry; anything unknown falls back to I18n.default_locale rather than tripping
    # enforce_available_locales. This is the seam where the reproduced RULE (which WP
    # locale wins) hands off to the ABSORBED machinery (i18n's catalogue lookup).
    I18N = { "en_US" => :en }.freeze

    # ── Site locale: get_locale(), l10n.php:29-81 ────────────────────────────────────
    #
    # The single-site path: the `WPLANG` option, else 'en_US' (:63-71). get_locale() does
    # NOT sanitise the option -- it is administrator-set, not request-supplied -- so it is
    # read verbatim, and only an empty value falls through to the default (:69).
    #
    # Multisite (BR-MS-01, Wave 5 Tenancy) reads the CURRENT site's WPLANG first and the
    # network's as a fallback (:48-61); Configuration::Setting already reads through the
    # tenant's search_path, so this returns the active site's option. The network-wide
    # fallback is network-settings state owned by the Tenancy work, not by this class.
    def site_locale
      raw = Configuration::Setting["WPLANG"]
      value = raw.is_a?(String) ? raw : nil
      value.presence || DEFAULT
    end

    # get_user_locale(), l10n.php:94-112. A user's own locale, or the site locale when the
    # user has none or there is no user (:105-111). Under AD-01, Identity::User#locale is
    # the promoted column (users.locale), nil meaning "site default" -- exactly the
    # legacy's empty user meta.
    def user_locale(user)
      return site_locale if user.nil?

      loc = user.locale
      loc.present? ? loc : site_locale
    end

    # sanitize_locale_name(), formatting.php:2468. "Limit to A-Z, a-z, 0-9, '_', '-'."
    # BR-I18N-03 / BR-MIGRATE-285: a real injection guard, not cosmetics -- the locale
    # becomes part of a catalogue filesystem path, so `../` and every other path or NUL
    # byte is stripped BEFORE the value is used. Kept verbatim; the legacy `apply_filters(
    # 'sanitize_locale_name' )` is gone (AD-01), so the regex result is the final value.
    def sanitize_name(name)
      name.to_s.gsub(/[^A-Za-z0-9_-]/, "")
    end

    # ── determine_locale(): the request-locale precedence, l10n.php:124-176 ───────────
    #
    # Reproduced as an EXPLICIT decision over facts the surface states, never over request
    # globals. The five legacy sources, in order:
    #
    #   0. pre_determine_locale (:134) -- a FILTER. AD-01 removes every hook, so its
    #      pre-filter default (null) is permanent: the source contributes nothing and is
    #      not represented below. (BR-I18N-01 / BR-MIGRATE-283 -- absorbed by AD-01.)
    #   1. login screen + request wp_lang (:140-148) -- honoured ONLY here, because the
    #      login form must be translatable before a user exists. GET wins over cookie.
    #      Every value is sanitised. (BR-I18N-02 / BR-MIGRATE-284 -- the security boundary.)
    #   2. admin, or ?_locale=user on a JSON request (:149-153) -> the USER's locale.
    #      (BR-I18N-04 / BR-MIGRATE-286.)
    #   3. installation (:154-162) -> $_REQUEST['language'] / wp_local_package. The target
    #      installs via Rails migrations, not a web installer, so there is no `wp_installing()`
    #      request surface; the branch is kept for faithfulness and is unreachable in the
    #      live app. (BR-I18N-05 / BR-MIGRATE-287 -- no live surface.)
    #   4. fallback (:165-167) -> the site locale, get_locale().
    #
    # `wp_lang` on the login screen mirrors `!empty()` (l10n.php:142-147): PHP treats "" and
    # "0" as empty, and GET is preferred over cookie.
    def determine(admin:, json_user_request:, login_screen:,
                  user: nil, wp_lang_get: nil, wp_lang_cookie: nil,
                  installing: false, installing_language: nil)
      if login_screen
        wp_lang = present_for_wp_lang?(wp_lang_get) ? wp_lang_get
                  : (present_for_wp_lang?(wp_lang_cookie) ? wp_lang_cookie : nil)
        return sanitize_name(wp_lang) unless wp_lang.nil?
      end

      return user_locale(user) if admin || json_user_request

      if installing && installing_language.to_s != ""
        return sanitize_name(installing_language)
      end

      site_locale
    end

    # The current EFFECTIVE locale: a live switch (top of the stack) wins over the request
    # base, which wins over the site locale off the request path. This is what
    # switch_to_locale() compares against (:76) and what a lookup runs under.
    def current
      Current.instance.switched_locale || Current.instance.request_locale || site_locale
    end

    # array_merge( array('en_US'), get_available_languages() ) -- the set switch_to_locale()
    # will accept (class-wp-locale-switcher.php:50, :81). One shipped locale plus whatever
    # catalogues are installed (none today). Absorbed side: Catalogue owns "what is
    # installed"; the rule "en_US is always available" is reproduced here.
    def available_locales
      ([DEFAULT] + Catalogue.installed_locales).uniq
    end

    def available?(locale) = available_locales.include?(locale)

    def to_i18n(locale) = I18N.fetch(locale.to_s, I18n.default_locale)

    # PHP empty() for a request string: nil, "" and "0" are all "not supplied".
    def present_for_wp_lang?(value)
      s = value.to_s
      !(s == "" || s == "0")
    end
    private_class_method :present_for_wp_lang?
  end
end
