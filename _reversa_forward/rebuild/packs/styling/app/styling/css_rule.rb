# frozen_string_literal: true

module Styling
  # Port of WP_Style_Engine_CSS_Rule,
  # wp-includes/style-engine/class-wp-style-engine-css-rule.php:17.
  #
  # One selector plus its declarations, optionally wrapped in a rules group
  # (`@media (...)`, `@layer ...`, or a parent selector for nested CSS).
  class CssRule
    # @param selector [String]
    # @param declarations [Hash{String=>Object}, CssDeclarations]
    # @param rules_group [String]
    def initialize(selector = '', declarations = {}, rules_group = '')
      @selector = nil
      @declarations = nil
      @rules_group = nil
      self.selector = selector
      add_declarations(declarations)
      self.rules_group = rules_group
    end

    # @return [String]
    attr_reader :selector, :rules_group

    # class-wp-style-engine-css-rule.php:69.
    #
    # @param value [String]
    # @return [CssRule] self
    def selector=(value)
      @selector = value
    end

    # class-wp-style-engine-css-rule.php:119.
    #
    # @param value [String]
    # @return [CssRule] self
    def rules_group=(value)
      @rules_group = value
    end

    # class-wp-style-engine-css-rule.php:84.
    # Preserves declaration options when given a CssDeclarations object.
    #
    # @param declarations [Hash{String=>Object}, CssDeclarations]
    # @return [CssRule] self
    def add_declarations(declarations)
      is_object = !declarations.is_a?(Hash)
      declarations_hash = is_object ? declarations.declarations : declarations
      declaration_options = is_object ? declarations.declaration_options : {}

      if @declarations.nil?
        if is_object
          @declarations = declarations
          return self
        end
        @declarations = CssDeclarations.new
      end

      declarations_hash.each do |property, value|
        @declarations.add_declaration(property, value, declaration_options[property] || {})
      end

      self
    end

    # @return [CssDeclarations]
    def declarations
      @declarations
    end

    # class-wp-style-engine-css-rule.php:170.
    #
    # @param should_prettify [Boolean]
    # @param indent_count [Integer]
    # @return [String] the rule, or an empty string when it has no declarations
    def css(should_prettify = false, indent_count = 0)
      rule_indent = should_prettify ? "\t" * indent_count : ''
      nested_rule_indent = should_prettify ? "\t" * (indent_count + 1) : ''
      declarations_indent = should_prettify ? indent_count + 1 : 0
      nested_declarations_indent = should_prettify ? indent_count + 2 : 0
      suffix = should_prettify ? "\n" : ''
      spacer = should_prettify ? ' ' : ''

      sel = selector.to_s
      if should_prettify
        sel = sel.split(',', -1).map { |part| PhpCompat.php_trim(part) }.join(',')
        sel = PhpCompat.as_text(PhpCompat.as_bytes(sel).gsub(',', ",\n"))
      end

      group = rules_group.to_s
      has_group = !PhpCompat.php_empty?(group)
      css_declarations = @declarations.declarations_string(
        should_prettify,
        has_group ? nested_declarations_indent : declarations_indent
      )

      return '' if PhpCompat.php_empty?(css_declarations)

      if has_group
        return "#{rule_indent}#{group}#{spacer}{#{suffix}#{nested_rule_indent}#{sel}#{spacer}{#{suffix}" \
               "#{css_declarations}#{suffix}#{nested_rule_indent}}#{suffix}#{rule_indent}}"
      end

      "#{rule_indent}#{sel}#{spacer}{#{suffix}#{css_declarations}#{suffix}#{rule_indent}}"
    end
  end
end
