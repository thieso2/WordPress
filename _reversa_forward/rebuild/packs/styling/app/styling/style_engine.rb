# frozen_string_literal: true

module Styling
  # BR-MIGRATE-219 — port of WP_Style_Engine plus the public functions in
  # wp-includes/style-engine.php.
  #
  # The engine turns one block style object into *both* the class names and the
  # inline declarations it implies, from a single pass over
  # BlockStyleDefinitions::METADATA.
  #
  # paradigm_decision.md option 1: there is no `$store_name` static. Callers
  # that want the rules stored pass a CssRulesStoreRegistry explicitly.
  module StyleEngine
    module_function

    # class-wp-style-engine.php:385. Extracts `heavenly-blue` from
    # `var:preset|color|heavenlyBlue`.
    #
    # @param style_value [Object]
    # @param property_key [Object]
    # @return [String] the kebab-case slug, or an empty string
    def slug_from_preset_value(style_value, property_key)
      if style_value.is_a?(String) && property_key.is_a?(String) &&
         style_value.include?("var:preset|#{property_key}|")
        index = style_value.rindex('|') + 1
        return PhpCompat.to_kebab_case(style_value[index..])
      end
      ''
    end

    # class-wp-style-engine.php:406.
    #
    # @param style_value [Object]
    # @param css_vars [Hash{String=>String}]
    # @return [String] e.g. `var(--wp--preset--color--black)`, or ''
    def css_var_value(style_value, css_vars)
      css_vars.each do |property_key, pattern|
        slug = slug_from_preset_value(style_value, property_key)
        next unless valid_style_value?(slug)

        return "var(#{pattern.gsub('$slug', slug)})"
      end
      ''
    end

    # class-wp-style-engine.php:428. `'0'` is valid; every other PHP-empty
    # value is not.
    #
    # @param style_value [Object]
    # @return [Boolean]
    def valid_style_value?(style_value)
      style_value == '0' || !PhpCompat.php_empty?(style_value)
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:479.
    # Single pass over the metadata producing class names and declarations for
    # the same style object.
    #
    # @param block_styles [Hash]
    # @param convert_vars_to_classnames [Boolean] skip `var:preset|…` → `var(--wp--…)`
    # @return [Hash] `{ 'classnames' => Array<String>, 'declarations' => Hash }`
    def parse_block_styles(block_styles, convert_vars_to_classnames: false)
      parsed = { 'classnames' => [], 'declarations' => {} }
      return parsed if PhpCompat.php_empty?(block_styles) || !block_styles.is_a?(Hash)

      BlockStyleDefinitions::METADATA.each do |group_key, group|
        next if PhpCompat.php_empty?(block_styles[group_key])

        group.each_value do |style_definition|
          style_value = PhpCompat.array_get(block_styles, style_definition['path'], nil)
          next unless valid_style_value?(style_value)

          names = classnames(style_value, style_definition)
          parsed['classnames'].concat(names) unless names.empty?

          declarations = css_declarations(style_value, style_definition, convert_vars_to_classnames)
          next if PhpCompat.php_empty?(declarations)

          # Combine background gradient and background image into a single
          # comma-separated background-image value, matching the JS engine.
          if declarations.key?('background-image') && parsed['declarations'].key?('background-image')
            declarations['background-image'] =
              "#{declarations['background-image']}, #{parsed['declarations']['background-image']}"
          end
          parsed['declarations'].merge!(declarations)
        end
      end

      parsed
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:548.
    #
    # @param style_value [Object]
    # @param style_definition [Hash]
    # @return [Array<String>]
    def classnames(style_value, style_definition)
      return [] if PhpCompat.php_empty?(style_value)

      names = []
      return names if PhpCompat.php_empty?(style_definition['classnames'])

      style_definition['classnames'].each do |classname, property_key|
        if property_key == true
          names << classname
          next
        end

        slug = slug_from_preset_value(style_value, property_key)
        names << classname.gsub('$slug', slug) unless PhpCompat.php_empty?(slug)
      end

      names
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:593.
    #
    # @param style_value [Object]
    # @param style_definition [Hash]
    # @param skip_css_vars [Boolean]
    # @return [Hash{String=>String}]
    def css_declarations(style_value, style_definition, skip_css_vars = false)
      case style_definition['value_func']
      when :url_or_value_css_declaration
        return url_or_value_css_declaration(style_value, style_definition)
      when :individual_property_css_declarations
        return individual_property_css_declarations(style_value, style_definition, skip_css_vars)
      end

      declarations = {}
      property_keys = style_definition['property_keys']

      if style_value.is_a?(String) && style_value.include?('var:')
        if !skip_css_vars && !PhpCompat.php_empty?(style_definition['css_vars'])
          css_var = css_var_value(style_value, style_definition['css_vars'])
          declarations[property_keys['default']] = css_var if valid_style_value?(css_var)
        end
        return declarations
      end

      # Box-model-like properties (margin, padding, border-*) arrive as hashes.
      if style_value.is_a?(Hash)
        return declarations unless property_keys.key?('individual')

        style_value.each do |key, value|
          if value.is_a?(String) && value.include?('var:') && !skip_css_vars &&
             !PhpCompat.php_empty?(style_definition['css_vars'])
            value = css_var_value(value, style_definition['css_vars'])
          end

          individual_property = property_keys['individual'] % PhpCompat.to_kebab_case(key)
          declarations[individual_property] = value if !PhpCompat.php_empty?(individual_property) &&
                                                       valid_style_value?(value)
        end

        return declarations
      end

      declarations[property_keys['default']] = style_value
      declarations
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:672.
    # Longhand properties: `border-{top|right|bottom|left}-{color|width|style}`.
    #
    # @param style_value [Object]
    # @param individual_property_definition [Hash]
    # @param skip_css_vars [Boolean]
    # @return [Hash{String=>String}]
    def individual_property_css_declarations(style_value, individual_property_definition, skip_css_vars = false)
      unless style_value.is_a?(Hash) && !style_value.empty? &&
             !PhpCompat.php_empty?(individual_property_definition['path'])
        return {}
      end

      group_key = individual_property_definition['path'][0]
      individual_property_key = individual_property_definition['path'][1]
      declarations = {}

      style_value.each do |css_property, value|
        next if PhpCompat.php_empty?(value)

        style_definition = PhpCompat.array_get(BlockStyleDefinitions::METADATA, [group_key, css_property], nil)
        next unless style_definition && style_definition.dig('property_keys', 'individual')

        if value.is_a?(String) && value.include?('var:') && !skip_css_vars &&
           !PhpCompat.php_empty?(individual_property_definition['css_vars'])
          value = css_var_value(value, individual_property_definition['css_vars'])
        end

        declarations[style_definition['property_keys']['individual'] % individual_property_key] = value
      end

      declarations
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:721.
    #
    # @param style_value [Object]
    # @param style_definition [Hash]
    # @return [Hash{String=>String}]
    def url_or_value_css_declaration(style_value, style_definition)
      return {} if PhpCompat.php_empty?(style_value)

      declarations = {}
      default_key = style_definition.dig('property_keys', 'default')
      return declarations if default_key.nil?

      value = nil
      if style_value.is_a?(Hash) && !PhpCompat.php_empty?(style_value['url'])
        value = "url('#{style_value['url']}')"
      elsif style_value.is_a?(String)
        value = style_value
      end

      declarations[default_key] = value unless value.nil?
      declarations
    end

    # BR-MIGRATE-219 — class-wp-style-engine.php:756.
    #
    # @param css_declarations [Hash{String=>String}]
    # @param css_selector [String, nil]
    # @return [String] a full rule when a selector is given, declarations otherwise
    def compile_css(css_declarations, css_selector)
      return '' if PhpCompat.php_empty?(css_declarations) || !css_declarations.is_a?(Hash)

      return CssRule.new(css_selector, css_declarations).css if css_selector && css_selector != ''

      CssDeclarations.new(css_declarations).declarations_string
    end

    # BR-MIGRATE-218 — class-wp-style-engine.php:791.
    #
    # @param css_rules [Array<CssRule>]
    # @param optimize [Boolean]
    # @param prettify [Boolean]
    # @return [String]
    def compile_stylesheet_from_css_rules(css_rules, optimize: false, prettify: false)
      processor = Processor.new
      processor.add_rules(css_rules)
      processor.css(optimize: optimize, prettify: prettify)
    end

    # BR-MIGRATE-217 — class-wp-style-engine.php:450.
    # The store is supplied by the caller instead of being looked up in a
    # static registry (paradigm option 1).
    #
    # @param store [CssRulesStore, nil]
    # @param css_selector [String]
    # @param css_declarations [Hash, CssDeclarations]
    # @param rules_group [String]
    # @return [void]
    def store_css_rule(store, css_selector, css_declarations, rules_group = '')
      return if store.nil? || PhpCompat.php_empty?(css_selector) || PhpCompat.php_empty?(css_declarations)

      store.add_rule(css_selector, rules_group).add_declarations(css_declarations)
    end

    # BR-MIGRATE-219 — port of `wp_style_engine_get_styles()`,
    # wp-includes/style-engine.php:62. Returns class names *and* inline styles
    # for the same style object.
    #
    # @param block_styles [Hash]
    # @param selector [String, nil] when given, `css` is a full rule
    # @param store [CssRulesStore, nil] when given, the rule is also stored
    # @param convert_vars_to_classnames [Boolean]
    # @return [Hash] `{ 'css' =>, 'declarations' =>, 'classnames' => }`, empties dropped
    def get_styles(block_styles, selector: nil, store: nil, convert_vars_to_classnames: false)
      parsed = parse_block_styles(block_styles, convert_vars_to_classnames: convert_vars_to_classnames)

      output = {}

      unless PhpCompat.php_empty?(parsed['declarations'])
        output['css'] = compile_css(parsed['declarations'], selector)
        output['declarations'] = parsed['declarations']
        store_css_rule(store, selector, parsed['declarations']) unless store.nil?
      end

      output['classnames'] = parsed['classnames'].uniq.join(' ') unless PhpCompat.php_empty?(parsed['classnames'])

      output.reject { |_k, v| PhpCompat.php_empty?(v) }
    end

    # BR-MIGRATE-217/218 — port of
    # `wp_style_engine_get_stylesheet_from_css_rules()`,
    # wp-includes/style-engine.php:139.
    #
    # @param css_rules [Array<Hash>] each `{ 'selector' =>, 'declarations' =>, 'rules_group' => }`
    # @param store [CssRulesStore, nil]
    # @param optimize [Boolean]
    # @param prettify [Boolean]
    # @return [String]
    def get_stylesheet_from_css_rules(css_rules, store: nil, optimize: false, prettify: false)
      return '' if PhpCompat.php_empty?(css_rules)

      rule_objects = []
      css_rules.each do |css_rule|
        declarations = css_rule['declarations']
        next if PhpCompat.php_empty?(css_rule['selector']) ||
                PhpCompat.php_empty?(declarations) ||
                !(declarations.is_a?(Hash) || declarations.is_a?(CssDeclarations))

        rules_group = css_rule['rules_group']
        store_css_rule(store, css_rule['selector'], declarations, rules_group || '') unless store.nil?

        rule_objects << CssRule.new(css_rule['selector'], declarations, rules_group || '')
      end

      return '' if rule_objects.empty?

      compile_stylesheet_from_css_rules(rule_objects, optimize: optimize, prettify: prettify)
    end

    # BR-MIGRATE-217 — port of `wp_style_engine_get_stylesheet_from_context()`,
    # wp-includes/style-engine.php:196. Each named store renders independently.
    #
    # @param store [CssRulesStore]
    # @param optimize [Boolean]
    # @param prettify [Boolean]
    # @return [String]
    def get_stylesheet_from_store(store, optimize: false, prettify: false)
      compile_stylesheet_from_css_rules(store.all_rules.values, optimize: optimize, prettify: prettify)
    end
  end
end
