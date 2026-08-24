# frozen_string_literal: true

require 'json'

module Styling
  # BR-MIGRATE-218 — port of WP_Style_Engine_Processor,
  # wp-includes/style-engine/class-wp-style-engine-processor.php:17.
  #
  # Collects rules from stores and/or loose rules, deduplicates them by
  # selector (merging their declarations), optionally combines selectors that
  # carry identical declarations, and renders the stylesheet.
  class Processor
    def initialize
      @stores = {}
      @css_rules = {}
    end

    # BR-MIGRATE-217/218 — class-wp-style-engine-processor.php:41.
    #
    # @param store [CssRulesStore]
    # @return [Processor] self
    def add_store(store)
      raise ArgumentError, '$store must be an instance of WP_Style_Engine_CSS_Rules_Store' unless store.is_a?(CssRulesStore)

      @stores[store.name] = store
      self
    end

    # BR-MIGRATE-218 — class-wp-style-engine-processor.php:65.
    # First writer for a selector wins the slot; later rules for the same
    # selector (or the same `group selector` pair) have their declarations
    # merged into it.
    #
    # @param css_rules [CssRule, Array<CssRule>]
    # @return [Processor] self
    def add_rules(css_rules)
      css_rules = [css_rules] unless css_rules.is_a?(Array)

      css_rules.each do |rule|
        selector = rule.selector
        rules_group = rule.rules_group

        unless PhpCompat.php_empty?(rules_group)
          key = "#{rules_group} #{selector}"
          if @css_rules.key?(key)
            @css_rules[key].add_declarations(rule.declarations)
          else
            @css_rules[key] = rule
          end
          next
        end

        if @css_rules.key?(selector)
          @css_rules[selector].add_declarations(rule.declarations)
          next
        end
        @css_rules[selector] = rule
      end

      self
    end

    # BR-MIGRATE-218 — class-wp-style-engine-processor.php:114.
    #
    # @param optimize [Boolean] combine selectors with identical declarations
    # @param prettify [Boolean] add newlines and indents
    # @return [String] the computed CSS
    def css(optimize: false, prettify: false)
      @stores.each_value { |store| add_rules(store.all_rules.values) }

      combine_rules_selectors if optimize == true

      out = +''
      @css_rules.each_value do |rule|
        out << rule.css(prettify)
        out << "\n" if prettify
      end
      out
    end

    private

    # BR-MIGRATE-218 — class-wp-style-engine-processor.php:145.
    # Selectors whose declarations (and declaration options) are identical are
    # merged into one comma-joined selector, which is appended at the end of
    # the rule list — the ordering the legacy produces and the reason the
    # output string is the observable of this rule.
    #
    # @return [void]
    def combine_rules_selectors
      selectors_json = {}
      @css_rules.each_value do |rule|
        declarations = rule.declarations.declarations.sort.to_h
        declaration_options = rule.declarations.declaration_options.sort.to_h
        declaration_options = declaration_options.transform_values do |options|
          options.is_a?(Hash) ? options.sort.to_h : options
        end
        selectors_json[rule.selector] = JSON.generate(
          'declarations' => declarations,
          'declaration_options' => declaration_options
        )
      end

      selectors_json.keys.each do |selector|
        json = selectors_json[selector]
        next if json.nil?

        duplicates = selectors_json.select { |_k, v| v.equal?(json) || v == json }.keys
        next if duplicates.length <= 1

        # Legacy quirk: `selectors_json` is keyed by the bare selector while
        # `css_rules` may be keyed by "group selector". When they disagree the
        # legacy dereferences null; here the rule is left alone instead.
        source = @css_rules[selector]
        next if source.nil?

        declarations = source.declarations

        duplicates.each do |key|
          selectors_json.delete(key)
          @css_rules.delete(key)
        end

        duplicate_selectors = duplicates.join(',')
        @css_rules[duplicate_selectors] = CssRule.new(duplicate_selectors, declarations)
      end
    end
  end
end
