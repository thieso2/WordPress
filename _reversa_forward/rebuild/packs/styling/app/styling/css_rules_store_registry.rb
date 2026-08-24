# frozen_string_literal: true

module Styling
  # BR-MIGRATE-217 — the named-store directory.
  #
  # The legacy keeps stores in the static `WP_Style_Engine_CSS_Rules_Store::$stores`
  # (class-wp-style-engine-css-rules-store.php:30). paradigm_decision.md option 1
  # forbids process-global mutable state, so the directory is an ordinary object
  # the caller owns and passes in. See README, "Deviations".
  class CssRulesStoreRegistry
    def initialize
      @stores = {}
    end

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:62.
    #
    # @param store_name [String]
    # @return [CssRulesStore, nil] nil for a blank or non-string name
    def store(store_name = 'default')
      return nil unless store_name.is_a?(String) && !PhpCompat.php_empty?(store_name)

      @stores[store_name] ||= CssRulesStore.new(store_name)
    end

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:76.
    #
    # @return [Hash{String=>CssRulesStore}]
    def stores
      @stores
    end

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:85.
    #
    # @return [void]
    def remove_all_stores
      @stores = {}
    end
  end
end
