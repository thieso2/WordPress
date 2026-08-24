# frozen_string_literal: true

module Styling
  # BR-MIGRATE-217 — port of WP_Style_Engine_CSS_Rules_Store,
  # wp-includes/style-engine/class-wp-style-engine-css-rules-store.php:21.
  #
  # A named bag of CssRule objects. Named stores coexist and are rendered
  # independently; see CssRulesStoreRegistry for the naming.
  class CssRulesStore
    # @param name [String]
    def initialize(name = '')
      @name = name
      @rules = {}
    end

    # @return [String]
    attr_accessor :name

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:120.
    #
    # @return [Hash{String=>CssRule}] keyed by selector, or "group selector"
    def all_rules
      @rules
    end

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:137.
    # Gets the rule for a selector, creating it on first use.
    #
    # @param selector [String]
    # @param rules_group [String]
    # @return [CssRule, nil] nil when the selector is empty
    def add_rule(selector, rules_group = '')
      selector = selector ? PhpCompat.php_trim(selector.to_s) : ''
      rules_group = rules_group ? PhpCompat.php_trim(rules_group.to_s) : ''

      return nil if PhpCompat.php_empty?(selector)

      unless PhpCompat.php_empty?(rules_group)
        key = "#{rules_group} #{selector}"
        @rules[key] = CssRule.new(selector, {}, rules_group) if PhpCompat.php_empty?(@rules[key])
        return @rules[key]
      end

      @rules[selector] = CssRule.new(selector) if PhpCompat.php_empty?(@rules[selector])
      @rules[selector]
    end

    # BR-MIGRATE-217 — class-wp-style-engine-css-rules-store.php:167.
    #
    # @param selector [String]
    # @return [void]
    def remove_rule(selector)
      @rules.delete(selector)
    end
  end
end
