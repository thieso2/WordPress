# frozen_string_literal: true

module Styling
  # BR-MIGRATE-216 — port of WP_Style_Engine_CSS_Declarations,
  # wp-includes/style-engine/class-wp-style-engine-css-declarations.php:17.
  #
  # Holds property => value pairs for one CSS rule. Property names are
  # sanitized and values validated *as they are added*; the CSS-safety filter
  # runs at render time, exactly as in the legacy (see README, BR-MIGRATE-216).
  class CssDeclarations
    # @param declarations [Hash{String=>Object}]
    def initialize(declarations = {})
      @declarations = {}
      @declaration_options = {}
      add_declarations(declarations)
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:67.
    # Sanitizes the property, rejects non-string and blank values, and only
    # then records the pair.
    #
    # @param property [Object] the CSS property
    # @param value [Object] the CSS value
    # @param options [Hash] `{ 'important' => true }` to render with !important
    # @return [CssDeclarations] self, for chaining
    def add_declaration(property, value, options = {})
      property = sanitize_property(property)
      return self if PhpCompat.php_empty?(property)

      # Bail early if value is not a string. Prevents fatal errors from
      # malformed block markup.
      return self unless value.is_a?(String)

      value = PhpCompat.php_trim(value)
      return self if value == ''

      options = { 'important' => false }.merge(stringify_keys(options))
      # PHP array_filter(): drops every falsey option.
      options = options.reject { |_k, v| PhpCompat.php_empty?(v) }

      @declarations[property] = value
      if options.empty?
        @declaration_options.delete(property)
      else
        @declaration_options[property] = options
      end

      self
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:110.
    #
    # @param property [String]
    # @return [CssDeclarations] self
    def remove_declaration(property)
      @declarations.delete(property)
      @declaration_options.delete(property)
      self
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:124.
    #
    # @param declarations [Hash{String=>Object}]
    # @return [CssDeclarations] self
    def add_declarations(declarations)
      declarations.each { |property, value| add_declaration(property, value) }
      self
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:139.
    #
    # @param properties [Array<String>]
    # @return [CssDeclarations] self
    def remove_declarations(properties = [])
      properties.each { |property| remove_declaration(property) }
      self
    end

    # @return [Hash{String=>String}] the sanitized declarations
    def declarations
      @declarations
    end

    # @return [Hash{String=>Hash}] declaration options keyed by property name
    def declaration_options
      @declaration_options
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:207.
    # Renders the declaration list. This is where `safecss_filter_attr()` runs
    # in the legacy, and it stays here so the output string is byte-identical.
    #
    # @param should_prettify [Boolean]
    # @param indent_count [Integer]
    # @return [String]
    def declarations_string(should_prettify = false, indent_count = 0)
      indent = should_prettify ? "\t" * indent_count : ''
      suffix = should_prettify ? ' ' : ''
      suffix = "\n" if should_prettify && indent_count.positive?
      spacer = should_prettify ? ' ' : ''

      output = +''
      @declarations.each do |property, value|
        filtered = self.class.filter_declaration(property, value, spacer, @declaration_options[property] || {})
        output << "#{indent}#{filtered};#{suffix}" if filtered && filtered != ''
      end

      # PHP rtrim() is byte-oriented; see PhpCompat.as_bytes.
      PhpCompat.as_text(PhpCompat.as_bytes(output).sub(/[ \t\n\r\0\x0B]+\z/, ''))
    end

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:184.
    # paradigm option 1: no filter hook wraps `safecss_filter_attr`.
    #
    # @param property [String]
    # @param value [String]
    # @param spacer [String]
    # @param options [Hash]
    # @return [String] the filtered declaration, or an empty string
    def self.filter_declaration(property, value, spacer = '', options = {})
      filtered_value = PhpCompat.strip_all_tags(value, true)
      return '' if filtered_value == ''

      important = options['important'] == true
      filtered_declaration = CssSafety.safecss_filter_attr("#{property}:#{spacer}#{filtered_value}")

      # Only append !important in the presence of an option value and when
      # sanitization returns a single declaration.
      if important && filtered_declaration != '' && !filtered_declaration.include?(';')
        return "#{filtered_declaration} !important"
      end

      filtered_declaration
    end

    private

    # BR-MIGRATE-216 — class-wp-style-engine-css-declarations.php:236.
    #
    # @param property [Object]
    # @return [String]
    def sanitize_property(property)
      PhpCompat.sanitize_key(property)
    end

    # @param hash [Hash]
    # @return [Hash{String=>Object}]
    def stringify_keys(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
    end
  end
end
