# frozen_string_literal: true

module Styling
  # BR-MIGRATE-208 — the persistence seam for user global styles.
  #
  # The legacy stores the user's theme.json in a `wp_global_styles` custom post
  # type, one row per theme, and reaches it through WP_Query/wp_insert_post
  # (wp-includes/class-wp-theme-json-resolver.php:478). This pack declares zero
  # dependencies (topology_decision.md option 3) and therefore may not touch the
  # persistence layer at all, so storage is expressed as this interface. The
  # Rails app supplies a concrete implementation; the pack only ever talks to
  # this contract.
  #
  # A record is a Hash with:
  #   'id'      => Integer|String, the record identifier
  #   'content' => String, the raw JSON document
  #   'title'   => String
  #   'name'    => String, the slug
  class GlobalStylesStore
    # The content a freshly created record carries —
    # class-wp-theme-json-resolver.php:512, verbatim.
    #
    # @return [String]
    def self.initial_content
      "{\"version\": #{ThemeJson::LATEST_SCHEMA}, \"isGlobalStylesUserThemeJSON\": true }"
    end

    # Not translatable in the legacy either, deliberately —
    # see https://core.trac.wordpress.org/ticket/54518.
    INITIAL_TITLE = 'Custom Styles'

    # BR-MIGRATE-208 — the single record for a theme, or nil.
    #
    # @param _stylesheet [String] the theme's stylesheet slug
    # @return [Hash, nil]
    def find_for_theme(_stylesheet)
      raise NotImplementedError, 'GlobalStylesStore#find_for_theme must be implemented by the application'
    end

    # BR-MIGRATE-208 — creates the theme's record on first access.
    #
    # @param _stylesheet [String]
    # @return [Hash, nil]
    def create_for_theme(_stylesheet)
      raise NotImplementedError, 'GlobalStylesStore#create_for_theme must be implemented by the application'
    end

    # PHP `urlencode()` — used to build the record slug
    # `wp-global-styles-<stylesheet>` (class-wp-theme-json-resolver.php:516).
    #
    # @param value [String]
    # @return [String]
    def self.urlencode(value)
      value.to_s.b.gsub(/[^A-Za-z0-9_.\-]/) do |char|
        char == ' ' ? '+' : format('%%%02X', char.ord)
      end
    end
  end
end
