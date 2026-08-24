# frozen_string_literal: true

module Localization
  # BC-16 -- translation CATALOGUES. This is the seam between reproduced behaviour and
  # absorbed machinery, and the split is the point:
  #
  #   ABSORBED by the i18n gem (topology_decision.md, `internationalization` "removed"):
  #     * loading a catalogue from disk -- the legacy read .mo files through POMO or
  #       .l10n.php PHP-array files (BR-I18N-08 / BR-MIGRATE-290, wp-settings.php:123).
  #       The i18n gem loads its own YAML/backend catalogues; there is no POMO port.
  #     * the lookup table itself, and plural-form selection.
  #
  #   REPRODUCED here (a real invariant that can be wrong):
  #     * the LOOKUP KEY. BR-I18N-09 / BR-MIGRATE-291: the source English string IS the
  #       key, and _x() disambiguates two identical strings by prefixing a context with an
  #       EOT (\4) separator -- the exact key Translation_Entry::key() builds
  #       (pomo/entry.php:157-158: `$context . "\4" . $singular`). Reproduced so that a
  #       future translated catalogue keyed the WordPress way resolves identically.
  #     * the miss behaviour: translate()/_x() return the SOURCE string unchanged when the
  #       domain is not loaded or the key is absent (translate(), l10n.php:194-196;
  #       Translations::translate(), pomo/translations.php:155). The site ships only en_US,
  #       so every key misses and every call returns its source -- which is why the 25
  #       screens are byte-identical English.
  class Catalogue
    # pomo/entry.php:158 -- "Prepend context and EOT, like in MO files."
    EOT = "\u0004"

    class << self
      # Translation_Entry::key(), pomo/entry.php:152-159. No context -> the bare singular;
      # a context -> `context . "\4" . singular`. This is the string the i18n backend (or a
      # POMO-shaped catalogue) is keyed on.
      def context_key(text, context = nil)
        return text.to_s if context.nil? || context.to_s == ""

        "#{context}#{EOT}#{text}"
      end

      # translate(), l10n.php:194. Source string is the key; a miss returns it unchanged.
      # The `gettext` / `gettext_{$domain}` filters (:207-220) are gone (AD-01), so the
      # lookup result is final.
      def translate(text, domain: "default")
        lookup(context_key(text), domain) || text.to_s
      end

      # translate_with_gettext_context() / _x(), l10n.php:261 & :409. Same as translate but
      # the key carries the context prefix (BR-I18N-09). Note the RETURN never includes the
      # context or the EOT -- _x's contract is "translated context string without pipe"
      # (:407); the prefix exists only to pick the row.
      def translate_with_context(text, context, domain: "default")
        lookup(context_key(text, context), domain) || text.to_s
      end

      # Locales with an installed catalogue beyond the built-in en_US -- what
      # get_available_languages() enumerates from the languages directory. Absorbed: the
      # i18n gem holds the loaded catalogues; today none are translated, so this is empty
      # and switch_to_locale() will accept only en_US (Localization::Locale.available?).
      def installed_locales
        []
      end

      # BR-I18N-07 / BR-MIGRATE-289: switching locale reloads EVERY already-loaded
      # textdomain in the new locale (class-wp-locale-switcher.php:245-265 load_translations).
      # The reload is the i18n gem's job -- setting the effective locale re-points every
      # subsequent lookup at the new catalogue -- so the observable "all domains follow the
      # switch" is expressed by moving I18n.locale, which is per-request thread state, not a
      # process global.
      def reload_all(locale)
        target = Localization::Locale.to_i18n(locale)
        I18n.locale = target if I18n.available_locales.include?(target)
      end

      private

      # The absorbed edge: ask the i18n backend under the current effective locale. A
      # missing key returns nil so the caller falls back to the source string. Kept narrow
      # on purpose -- everything about HOW the catalogue is stored lives behind this.
      def lookup(key, _domain)
        return nil unless I18n.exists?(key, scope: :catalogue)

        I18n.t(key, scope: :catalogue, default: nil)
      end
    end
  end
end
