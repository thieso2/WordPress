# frozen_string_literal: true

module Styling
  # `WP_Theme_JSON::get_stylesheet()`, class-wp-theme-json.php:1968, and the
  # tree of methods under it: `get_css_variables` (:2482), `get_preset_classes`
  # (:2445), `get_block_classes` (:2192), `get_styles_for_block` (:3815),
  # `get_layout_styles` (:2219), `get_root_layout_rules` (:4203),
  # `compute_style_properties` (:3006), `get_setting_nodes` (:3207),
  # `get_style_nodes` (:3268) and `get_block_nodes` (:3519).
  #
  # Wave 0 ported WP_Theme_JSON's four-origin CASCADE and left the GENERATOR out
  # (README §3). This is the generator. It is a separate class rather than more
  # methods on `ThemeJson` because it needs one thing the cascade does not — the
  # block metadata — and because the god-object is what the migration is trying
  # not to reproduce.
  #
  # Rules discharged: BR-MIGRATE-211 (`:root` for custom properties, `body` for
  # block styles), BR-MIGRATE-212 (presets become both custom properties and
  # utility classes), BR-MIGRATE-213 (viewport breakpoints become media queries),
  # BR-MIGRATE-214 (the styleable elements).
  #
  # ⚠️ AD-01: `wp_theme_json_get_style_nodes` (:3324) is a filter and is gone.
  # Core registers exactly one callback on it, `wp_filter_out_block_nodes`
  # (script-loader.php:2605), unconditionally, on every front-end request — so
  # the filter is not extensibility, it is a mode. It is expressed here as the
  # `skip_block_nodes` option, which the caller sets and nothing else can.
  class Stylesheet
    # class-wp-theme-json.php:254.
    PROPERTIES_METADATA = {
      'aspect-ratio' => %w[dimensions aspectRatio],
      'background' => %w[color gradient],
      'background-color' => %w[color background],
      'background-image' => %w[background backgroundImage],
      'background-position' => %w[background backgroundPosition],
      'background-repeat' => %w[background backgroundRepeat],
      'background-size' => %w[background backgroundSize],
      'background-attachment' => %w[background backgroundAttachment],
      'border-radius' => %w[border radius],
      'border-top-left-radius' => %w[border radius topLeft],
      'border-top-right-radius' => %w[border radius topRight],
      'border-bottom-left-radius' => %w[border radius bottomLeft],
      'border-bottom-right-radius' => %w[border radius bottomRight],
      'border-color' => %w[border color],
      'border-width' => %w[border width],
      'border-style' => %w[border style],
      'border-top-color' => %w[border top color],
      'border-top-width' => %w[border top width],
      'border-top-style' => %w[border top style],
      'border-right-color' => %w[border right color],
      'border-right-width' => %w[border right width],
      'border-right-style' => %w[border right style],
      'border-bottom-color' => %w[border bottom color],
      'border-bottom-width' => %w[border bottom width],
      'border-bottom-style' => %w[border bottom style],
      'border-left-color' => %w[border left color],
      'border-left-width' => %w[border left width],
      'border-left-style' => %w[border left style],
      'color' => %w[color text],
      'text-align' => %w[typography textAlign],
      'column-count' => %w[typography textColumns],
      'font-family' => %w[typography fontFamily],
      'font-size' => %w[typography fontSize],
      'font-style' => %w[typography fontStyle],
      'font-weight' => %w[typography fontWeight],
      'letter-spacing' => %w[typography letterSpacing],
      'line-height' => %w[typography lineHeight],
      'margin' => %w[spacing margin],
      'margin-top' => %w[spacing margin top],
      'margin-right' => %w[spacing margin right],
      'margin-bottom' => %w[spacing margin bottom],
      'margin-left' => %w[spacing margin left],
      'min-height' => %w[dimensions minHeight],
      'min-width' => %w[dimensions minWidth],
      'outline-color' => %w[outline color],
      'outline-offset' => %w[outline offset],
      'outline-style' => %w[outline style],
      'outline-width' => %w[outline width],
      'padding' => %w[spacing padding],
      'padding-top' => %w[spacing padding top],
      'padding-right' => %w[spacing padding right],
      'padding-bottom' => %w[spacing padding bottom],
      'padding-left' => %w[spacing padding left],
      '--wp--style--root--padding' => %w[spacing padding],
      '--wp--style--root--padding-top' => %w[spacing padding top],
      '--wp--style--root--padding-right' => %w[spacing padding right],
      '--wp--style--root--padding-bottom' => %w[spacing padding bottom],
      '--wp--style--root--padding-left' => %w[spacing padding left],
      'text-decoration' => %w[typography textDecoration],
      'text-shadow' => %w[typography textShadow],
      'text-transform' => %w[typography textTransform],
      'text-indent' => %w[typography textIndent],
      'filter' => %w[filter duotone],
      'box-shadow' => %w[shadow],
      'height' => %w[dimensions height],
      'width' => %w[dimensions width],
      'writing-mode' => %w[typography writingMode]
    }.freeze

    # class-wp-theme-json.php:653.
    VALID_ELEMENT_PSEUDO_SELECTORS = {
      'link' => [':link', ':any-link', ':visited', ':hover', ':focus', ':focus-visible', ':active'],
      'button' => [':link', ':any-link', ':visited', ':hover', ':focus', ':focus-visible', ':active']
    }.freeze

    # class-wp-theme-json.php:664.
    VALID_BLOCK_PSEUDO_SELECTORS = {
      'core/button' => [':hover', ':focus', ':focus-visible', ':active'],
      'core/navigation-link' => [':hover', ':focus', ':focus-visible', ':active']
    }.freeze

    # class-wp-theme-json.php:687. `-current` is a CLASS selector, not a real
    # pseudo-class; the `-` prefix is how the legacy tells them apart.
    VALID_BLOCK_CUSTOM_STATES = { 'core/navigation-link' => ['-current'] }.freeze

    # get_layout_styles():2237 — "Allow alphanumeric classnames, spaces,
    # wildcard, sibling, child combinator and pseudo class selectors."
    # ⚠️ `^…$` in the PCRE are LINE anchors; `\A…\z` here, so a newline cannot
    # smuggle a second selector into a layout rule.
    LAYOUT_SELECTOR_PATTERN = /\A[a-zA-Z0-9\-.,\ *+>:()]*\z/

    ROOT_PADDING_PREFIX = '--wp--style--root--'

    # @param theme_json [ThemeJson] the merged document
    # @param blocks_metadata [Hash{String=>Hash}] from `BlocksMetadata.build`
    # @param block_definitions [Hash{String=>Hash}] the block.json data, needed
    #   for `supports.layout` and `supports.spacing.blockGap.__experimentalDefault`
    def initialize(theme_json, blocks_metadata = {}, block_definitions = {})
      # The generator only ever reads the merged tree, never the object's methods:
      # `$this->theme_json` is what every method under `get_stylesheet()` touches.
      @data = theme_json.raw_data
      @blocks_metadata = blocks_metadata || {}
      @block_definitions = block_definitions || {}
    end

    # class-wp-theme-json.php:1968.
    #
    # @param types [Array<String>] any of `variables`, `styles`, `presets`, `custom-css`
    # @param origins [Array<String>, nil] defaults to VALID_ORIGINS
    # @param options [Hash] `scope`, `root_selector`, `skip_root_layout_styles`,
    #   `base_layout_styles`, `include_block_style_variations`, `skip_block_nodes`
    # @return [String]
    def get_stylesheet(types = %w[variables styles presets], origins = nil, options = {})
      origins ||= ThemeJson::VALID_ORIGINS
      style_nodes = self.class.style_nodes(@data, @blocks_metadata, options)
      setting_nodes = self.class.setting_nodes(@data, @blocks_metadata)

      root_style_key = style_nodes.index { |n| n['selector'] == ThemeJson::ROOT_BLOCK_SELECTOR }
      root_settings_key = setting_nodes.index { |n| n['selector'] == ThemeJson::ROOT_BLOCK_SELECTOR }

      unless PhpCompat.php_empty?(options['scope'])
        setting_nodes = setting_nodes.map { |n| n.merge('selector' => Selectors.scope_selector(options['scope'], n['selector'])) }
        style_nodes = style_nodes.map { |n| self.class.scope_style_node_selectors(options['scope'], n) }
      end

      unless PhpCompat.php_empty?(options['root_selector'])
        setting_nodes[root_settings_key]['selector'] = options['root_selector'] if root_settings_key
        style_nodes[root_style_key]['selector'] = options['root_selector'] if root_style_key
      end

      stylesheet = +''
      stylesheet << css_variables(setting_nodes, origins) if types.include?('variables')

      if types.include?('styles')
        if root_style_key && PhpCompat.php_empty?(options['skip_root_layout_styles'])
          stylesheet << root_layout_rules(style_nodes[root_style_key]['selector'],
                                          style_nodes[root_style_key], options)
        end
        stylesheet << block_classes(style_nodes)
      end

      stylesheet << preset_classes(setting_nodes, origins) if types.include?('presets')
      # Custom CSS last, so it has the highest specificity.
      stylesheet << PhpCompat.array_get(@data, %w[styles css], '').to_s if types.include?('custom-css')
      stylesheet
    end

    # ── node builders ─────────────────────────────────────────────────────────

    # class-wp-theme-json.php:3207.
    #
    # @return [Array<Hash>]
    def self.setting_nodes(theme_json, selectors = {})
      return [] unless theme_json['settings'].is_a?(Hash)

      nodes = [{ 'path' => ['settings'], 'selector' => ThemeJson::ROOT_CSS_PROPERTIES_SELECTOR }]
      blocks = theme_json['settings']['blocks']
      return nodes unless blocks.is_a?(Hash)

      blocks.each_key do |name|
        nodes << {
          'path' => ['settings', 'blocks', name],
          'selector' => PhpCompat.array_get(selectors, [name, 'selector'], nil),
          'selectors' => PhpCompat.array_get(selectors, [name, 'selectors'], {}) || {}
        }
      end
      nodes
    end

    # BR-MIGRATE-214 — class-wp-theme-json.php:3268.
    #
    # @return [Array<Hash>]
    def self.style_nodes(theme_json, selectors = {}, options = {})
      return [] unless theme_json['styles'].is_a?(Hash)

      nodes = [{ 'path' => ['styles'], 'selector' => ThemeJson::ROOT_BLOCK_SELECTOR }]

      elements = theme_json['styles']['elements']
      if elements.is_a?(Hash)
        ThemeJson::ELEMENTS.each do |element, selector|
          next unless elements.key?(element)

          nodes << { 'path' => %w[styles elements] + [element], 'selector' => selector }

          (VALID_ELEMENT_PSEUDO_SELECTORS[element] || []).each do |pseudo|
            next unless elements[element].is_a?(Hash) && elements[element].key?(pseudo)

            nodes << { 'path' => %w[styles elements] + [element],
                       'selector' => Selectors.append_to_selector(selector, pseudo) }
          end
        end
      end

      return nodes unless theme_json['styles']['blocks'].is_a?(Hash)

      # AD-01, see the class comment: this is `wp_filter_out_block_nodes`, made a
      # parameter because the filter it lived on no longer exists.
      return nodes if options['skip_block_nodes']

      nodes + block_nodes(theme_json, selectors, options)
    end

    # class-wp-theme-json.php:3519.
    #
    # @return [Array<Hash>]
    def self.block_nodes(theme_json, selectors = {}, options = {})
      blocks = PhpCompat.array_get(theme_json, %w[styles blocks], nil)
      return [] unless blocks.is_a?(Hash)

      include_variations = options['include_block_style_variations'] || false
      # BR-MIGRATE-213.
      media_queries = ThemeJson.viewport_media_queries(PhpCompat.array_get(theme_json, %w[settings viewport], nil))
      nodes = []

      blocks.each do |name, node|
        node_path = ['styles', 'blocks', name]
        selector = PhpCompat.array_get(selectors, [name, 'selector'], nil)
        duotone_selector = PhpCompat.array_get(selectors, [name, 'duotone'], nil)
        feature_selectors = PhpCompat.array_get(selectors, [name, 'selectors'], nil)
        elements = PhpCompat.array_get(selectors, [name, 'elements'], {}) || {}

        variation_selectors = []
        if include_variations && node.is_a?(Hash) && node['variations'].is_a?(Hash)
          node['variations'].each_key do |variation|
            variation_selectors << {
              'name' => variation,
              'path' => node_path + %w[variations] + [variation],
              'selector' => PhpCompat.array_get(selectors, [name, 'styleVariations', variation], nil)
            }
          end
        end

        nodes << { 'name' => name, 'path' => node_path, 'selector' => selector,
                   'selectors' => feature_selectors, 'elements' => elements,
                   'duotone' => duotone_selector, 'variations' => variation_selectors,
                   'css' => selector }

        # Responsive block nodes, emitted right after the base node so the
        # cascade reads `.block{}` then `@media{.block{}}`.
        media_queries.each_key do |breakpoint|
          next unless node.is_a?(Hash) && node.key?(breakpoint)

          nodes << { 'name' => name, 'path' => node_path + [breakpoint],
                     'media_query' => media_queries[breakpoint], 'selector' => selector,
                     'selectors' => feature_selectors, 'elements' => elements,
                     'variations' => variation_selectors, 'css' => selector }
        end

        (VALID_BLOCK_PSEUDO_SELECTORS[name] || []).each do |pseudo|
          has_pseudo = node.is_a?(Hash) && node.key?(pseudo)
          has_responsive_pseudo = media_queries.keys.any? do |breakpoint|
            PhpCompat.array_get(node, [breakpoint, pseudo], nil) != nil ||
              (node.is_a?(Hash) && node[breakpoint].is_a?(Hash) && node[breakpoint].key?(pseudo))
          end
          next unless has_pseudo || has_responsive_pseudo

          pseudo_feature_selectors = {}
          (feature_selectors || {}).each do |feature, feature_selector|
            pseudo_feature_selectors[feature] =
              if feature_selector.is_a?(Hash)
                feature_selector.transform_values { |sub| Selectors.append_to_selector(sub, pseudo) }
              else
                Selectors.append_to_selector(feature_selector, pseudo)
              end
          end

          pseudo_selector = Selectors.append_to_selector(selector, pseudo)
          if has_pseudo
            nodes << { 'name' => name, 'path' => node_path + [pseudo], 'selector' => pseudo_selector,
                       'selectors' => pseudo_feature_selectors, 'elements' => elements,
                       'duotone' => duotone_selector, 'variations' => variation_selectors,
                       'css' => pseudo_selector }
          end

          media_queries.each_key do |breakpoint|
            next unless node.is_a?(Hash) && node[breakpoint].is_a?(Hash) && node[breakpoint].key?(pseudo)

            nodes << { 'name' => name, 'path' => node_path + [breakpoint, pseudo],
                       'media_query' => media_queries[breakpoint], 'selector' => pseudo_selector,
                       'selectors' => pseudo_feature_selectors, 'elements' => elements,
                       'variations' => variation_selectors, 'css' => pseudo_selector }
          end
        end

        (VALID_BLOCK_CUSTOM_STATES[name] || []).each do |custom_state|
          next unless node.is_a?(Hash) && node.key?(custom_state)

          custom_css_selector = PhpCompat.array_get(selectors, [name, 'states', custom_state], nil)
          next if custom_css_selector.nil?

          nodes << { 'name' => name, 'path' => node_path + [custom_state],
                     'selector' => custom_css_selector, 'selectors' => feature_selectors,
                     'elements' => elements, 'duotone' => duotone_selector,
                     'variations' => variation_selectors, 'css' => custom_css_selector }

          (VALID_BLOCK_PSEUDO_SELECTORS[name] || []).each do |pseudo|
            next unless node[custom_state].is_a?(Hash) && node[custom_state].key?(pseudo)

            compound = Selectors.append_to_selector(custom_css_selector, pseudo)
            nodes << { 'name' => name, 'path' => node_path + [custom_state, pseudo],
                       'selector' => compound, 'selectors' => feature_selectors,
                       'elements' => elements, 'duotone' => duotone_selector,
                       'variations' => variation_selectors, 'css' => compound }
          end
        end

        # An element styled only inside a breakpoint still needs a node, so the
        # names are collected from every place they can appear first.
        block_node = node.is_a?(Hash) ? node : {}
        element_names = (block_node['elements'].is_a?(Hash) ? block_node['elements'].keys : [])
        media_queries.each_key do |breakpoint|
          inner = PhpCompat.array_get(block_node, [breakpoint, 'elements'], nil)
          element_names += inner.keys if inner.is_a?(Hash)
        end
        element_names = element_names.uniq

        element_names.each do |element|
          element_selector = PhpCompat.array_get(selectors, [name, 'elements', element], nil)
          next if element_selector.nil?

          element_path = node_path + %w[elements] + [element]
          if block_node['elements'].is_a?(Hash) && block_node['elements'].key?(element)
            nodes << { 'path' => element_path, 'selector' => element_selector }
          end

          media_queries.each_key do |breakpoint|
            next unless PhpCompat.array_get(block_node, [breakpoint, 'elements', element], nil)

            nodes << { 'path' => node_path + [breakpoint, 'elements', element],
                       'selector' => element_selector, 'media_query' => media_queries[breakpoint] }
          end

          (VALID_ELEMENT_PSEUDO_SELECTORS[element] || []).each do |pseudo|
            if PhpCompat.array_get(block_node, ['elements', element, pseudo], nil)
              nodes << { 'path' => element_path,
                         'selector' => Selectors.append_to_selector(element_selector, pseudo) }
            end

            media_queries.each_key do |breakpoint|
              next unless PhpCompat.array_get(block_node, [breakpoint, 'elements', element, pseudo], nil)

              nodes << { 'path' => node_path + [breakpoint, 'elements', element],
                         'selector' => Selectors.append_to_selector(element_selector, pseudo),
                         'media_query' => media_queries[breakpoint] }
            end
          end
        end
      end

      nodes
    end

    # class-wp-theme-json.php:3334 — the public entry `wp_add_global_styles_for_blocks()`
    # walks, one node per block that theme.json styles.
    #
    # @return [Array<Hash>]
    def styles_block_nodes = self.class.block_nodes(@data, @blocks_metadata)

    # class-wp-theme-json.php:2724.
    def self.scope_style_node_selectors(scope, node)
      node = node.dup
      node['selector'] = Selectors.scope_selector(scope, node['selector'])
      return node if PhpCompat.php_empty?(node['selectors'])

      node['selectors'] = node['selectors'].each_with_object({}) do |(feature, selector), out|
        out[feature] =
          if selector.is_a?(String)
            Selectors.scope_selector(scope, selector)
          elsif selector.is_a?(Hash)
            selector.transform_values { |sub| Selectors.scope_selector(scope, sub) }
          else
            selector
          end
      end
      node
    end

    # ── the three stylesheet sections ─────────────────────────────────────────

    # BR-MIGRATE-211/212 — class-wp-theme-json.php:2482.
    #
    # @return [String]
    def css_variables(nodes, origins)
      root_settings = @data['settings'].is_a?(Hash) ? @data['settings'] : {}
      nodes.each_with_object(+'') do |metadata, stylesheet|
        next if metadata['selector'].nil?

        selector = metadata['selector']
        feature_selectors = metadata['selectors'] || {}
        node = PhpCompat.array_get(@data, metadata['path'], {}) || {}

        # Presets are grouped by the selector they belong to: a block that
        # declares a feature-level selector gets its variables there, not on the
        # block root.
        vars_by_selector = { selector => [] }

        ThemeJson::PRESETS_METADATA.each do |preset_metadata|
          next if PhpCompat.php_empty?(preset_metadata['css_vars'])

          values_by_slug = ThemeJson.settings_values_by_slug(node, preset_metadata, origins,
                                                             root_settings: root_settings)
          next if PhpCompat.php_empty?(values_by_slug)

          target = self.class.feature_selector(feature_selectors, preset_metadata['path'][0], selector)
          vars_by_selector[target] ||= []
          values_by_slug.each do |slug, value|
            vars_by_selector[target] << {
              'name' => ThemeJson.replace_slug_in_string(preset_metadata['css_vars'], slug),
              'value' => value
            }
          end
        end

        # Theme vars always use the block's default selector.
        ThemeJson.compute_theme_vars(node).each { |theme_var| vars_by_selector[selector] << theme_var }

        vars_by_selector.each { |rule_selector, declarations| stylesheet << ThemeJson.to_ruleset(rule_selector, declarations) }
      end
    end

    # class-wp-theme-json.php:2554.
    def self.feature_selector(feature_selectors, feature_key, default_selector)
      feature = feature_selectors.is_a?(Hash) ? feature_selectors[feature_key] : nil
      return default_selector if feature.nil?
      return feature if feature.is_a?(String)
      return feature['root'] if feature.is_a?(Hash) && feature['root'].is_a?(String)

      default_selector
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2445.
    #
    # @return [String]
    def preset_classes(nodes, origins)
      nodes.each_with_object(+'') do |metadata, rules|
        next if metadata['selector'].nil?

        node = PhpCompat.array_get(@data, metadata['path'], {}) || {}
        rules << ThemeJson.compute_preset_classes(node, metadata['selector'], origins)
      end
    end

    # class-wp-theme-json.php:2192.
    #
    # @return [String]
    def block_classes(style_nodes)
      style_nodes.each_with_object(+'') do |metadata, rules|
        next if metadata['selector'].nil?

        rules << styles_for_block(metadata)
      end
    end

    # ── the per-node renderer ─────────────────────────────────────────────────

    # class-wp-theme-json.php:3815.
    #
    # @param block_metadata [Hash]
    # @return [String]
    def styles_for_block(block_metadata)
      node = PhpCompat.deep_dup(PhpCompat.array_get(@data, block_metadata['path'], {}) || {})
      use_root_padding = PhpCompat.array_get(@data, %w[settings useRootPaddingAwareAlignments], nil) == true
      selector = block_metadata['selector']
      settings = @data['settings'].is_a?(Hash) ? @data['settings'] : {}
      is_root_selector = selector == ThemeJson::ROOT_BLOCK_SELECTOR
      media_query = block_metadata['media_query']
      block_name = block_metadata['name']

      feature_declarations = feature_declarations_for_node(block_metadata, node)
      feature_declarations = self.class.update_paragraph_text_indent_selector(feature_declarations, settings, block_name)
      feature_declarations = self.class.update_button_width_declarations(feature_declarations, settings)

      # ⚠️ Block style variations are NOT rendered here. `include_block_style_variations`
      # is false on every path `wp_get_global_stylesheet()` and
      # `wp_add_global_styles_for_blocks()` take, so `$block_metadata['variations']`
      # is always empty and the 180-line branch at :3838 is unreachable in the
      # front end. See the README for what that costs.

      # Which element, if any, this node is for — `[ 'styles', 'elements', 'link' ]`.
      is_processing_element = block_metadata['path'].include?('elements')
      current_element = is_processing_element ? block_metadata['path'].last : nil
      element_pseudo_allowed = current_element ? (VALID_ELEMENT_PSEUDO_SELECTORS[current_element] || []) : []

      # :4008 — the pseudo must not be followed by a dash, so `:focus` does not
      # match `:focus-visible`.
      pseudo_selector = element_pseudo_allowed.find do |pseudo|
        selector.to_s.match?(/#{Regexp.escape(pseudo)}(?!-)/)
      end

      declarations =
        if pseudo_selector && node.is_a?(Hash) && node.key?(pseudo_selector) &&
           element_pseudo_allowed.include?(pseudo_selector)
          self.class.compute_style_properties(node[pseudo_selector], settings, nil, @data, selector, use_root_padding)
        else
          self.class.compute_style_properties(node, settings, nil, @data, selector, use_root_padding)
        end

      block_rules = +''

      # 1. `filter` declarations move to the duotone selector; a root background
      #    forces `html { min-height }`.
      declarations_duotone = []
      should_set_root_min_height = false
      declarations = declarations.reject do |declaration|
        if declaration['name'] == 'filter'
          declarations_duotone << declaration if declaration['value'] != 'unset'
          next true
        end
        if is_root_selector && %w[background-image background].include?(declaration['name'])
          should_set_root_min_height = true
        end
        false
      end

      if should_set_root_min_height
        block_rules << ThemeJson.to_ruleset('html', [{
                                              'name' => 'min-height',
                                              'value' => 'calc(100% - var(--wp-admin--admin-bar--height, 0px))'
                                            }])
      end

      declarations = self.class.update_separator_declarations(declarations) if selector == '.wp-block-separator'

      # 2. The general rule. BR-MIGRATE-211: the root block selector `body` and a
      #    top-level element selector stay unwrapped so their specificity stays
      #    (0,0,1); everything else is capped at 0-1-0 by `:root :where()`.
      element_only_selector = is_root_selector || (
        !current_element.nil? &&
        ThemeJson::ELEMENTS.key?(current_element) &&
        !ThemeJson::ELEMENT_CLASS_NAMES.key?(current_element) &&
        ThemeJson::ELEMENTS[current_element] == selector
      )
      general_selector = element_only_selector ? selector : ":root :where(#{selector})"
      block_rules << ThemeJson.to_ruleset(general_selector, declarations)

      # 3. The duotone rule.
      if block_metadata['duotone'] && !PhpCompat.php_empty?(declarations_duotone)
        block_rules << ThemeJson.to_ruleset(block_metadata['duotone'], declarations_duotone)
      end

      # 4. Layout block-gap styles.
      block_rules << layout_styles(block_metadata) if !is_root_selector && !PhpCompat.php_empty?(block_name)

      # 5. Feature-level rules.
      feature_declarations.each do |feature_selector, individual|
        block_rules << ThemeJson.to_ruleset(":root :where(#{feature_selector})", individual)
      end

      # 7. Custom CSS. (6 is the style-variation branch — see above.)
      if node.is_a?(Hash) && node.key?('css') && !is_root_selector
        css_feature_selector = PhpCompat.array_get(block_metadata, %w[selectors css], nil)
        css_feature_selector = css_feature_selector['root'] if css_feature_selector.is_a?(Hash)
        css_selector = css_feature_selector.is_a?(String) ? css_feature_selector : selector
        block_rules << self.class.process_blocks_custom_css(node['css'], css_selector)
      end

      # 8. A responsive node wraps everything it produced in its media query.
      return "#{media_query}{#{block_rules}}" if media_query && !PhpCompat.php_empty?(block_rules)

      block_rules
    end

    # class-wp-theme-json.php:4203.
    #
    # @return [String]
    def root_layout_rules(selector, block_metadata, options = {})
      css = +''
      settings = @data['settings'].is_a?(Hash) ? @data['settings'] : {}
      use_root_padding = PhpCompat.array_get(@data, %w[settings useRootPaddingAwareAlignments], nil) == true

      layout = settings['layout'].is_a?(Hash) ? settings['layout'] : {}
      if layout.key?('contentSize') || layout.key?('wideSize')
        content_size = layout['contentSize'] || layout['wideSize']
        content_size = self.class.safe_css_declaration?('max-width', content_size) ? content_size : 'initial'
        wide_size = layout['wideSize'] || layout['contentSize']
        wide_size = self.class.safe_css_declaration?('max-width', wide_size) ? wide_size : 'initial'
        css << "#{ThemeJson::ROOT_CSS_PROPERTIES_SELECTOR} { --wp--style--global--content-size: #{content_size};"
        css << "--wp--style--global--wide-size: #{wide_size}; }"
      end

      # Reset the browser's body margin BEFORE the theme.json ruleset, so a
      # theme-declared margin wins the cascade.
      css << ':where(body) { margin: 0; }'

      if use_root_padding
        css << '.wp-site-blocks { padding-top: var(--wp--style--root--padding-top); padding-bottom: var(--wp--style--root--padding-bottom); }'
        css << '.has-global-padding { padding-right: var(--wp--style--root--padding-right); padding-left: var(--wp--style--root--padding-left); }'
        css << '.has-global-padding > .alignfull { margin-right: calc(var(--wp--style--root--padding-right) * -1); margin-left: calc(var(--wp--style--root--padding-left) * -1); }'
        css << '.has-global-padding :where(:not(.alignfull.is-layout-flow) > .has-global-padding:not(.wp-block-block, .alignfull)) { padding-right: 0; padding-left: 0; }'
        css << '.has-global-padding :where(:not(.alignfull.is-layout-flow) > .has-global-padding:not(.wp-block-block, .alignfull)) > .alignfull { margin-left: 0; margin-right: 0; }'
      end

      if PhpCompat.php_empty?(options['base_layout_styles'])
        css << '.wp-site-blocks > .alignleft { float: left; margin-right: 2em; }'
        css << '.wp-site-blocks > .alignright { float: right; margin-left: 2em; }'
        css << '.wp-site-blocks > .aligncenter { justify-content: center; margin-left: auto; margin-right: auto; }'
      end

      if settings['spacing'].is_a?(Hash) && settings['spacing'].key?('blockGap')
        block_gap_value = self.class.property_value(@data, %w[styles spacing blockGap], @data)
        css << ":where(.wp-site-blocks) > * { margin-block-start: #{block_gap_value}; margin-block-end: 0; }"
        css << ':where(.wp-site-blocks) > :first-child { margin-block-start: 0; }'
        css << ':where(.wp-site-blocks) > :last-child { margin-block-end: 0; }'
        css << "#{ThemeJson::ROOT_CSS_PROPERTIES_SELECTOR} { --wp--style--block-gap: #{block_gap_value}; }"
      end

      css << layout_styles(block_metadata, options)
      css
    end

    # class-wp-theme-json.php:2219.
    #
    # @return [String]
    def layout_styles(block_metadata, options = {})
      block_rules = +''
      # `WP_Block_Type_Registry::get_instance()->get_registered( $name )`, :2262.
      # topology_decision.md option 3: the registry is an argument, not a singleton.
      block_type = block_metadata['name'] ? @block_definitions[block_metadata['name']] : nil

      if block_metadata['name']
        supports = (block_type && block_type['supports']) || {}
        # `block_has_support( $block_type, 'layout', false )` — layout.php's own
        # test, which accepts either the stable or the experimental key.
        has_layout = !PhpCompat.php_empty?(supports['layout']) ||
                     !PhpCompat.php_empty?(supports['__experimentalLayout'])
        return block_rules unless has_layout
      end

      selector = block_metadata['selector'] || ''
      spacing_settings = PhpCompat.array_get(@data, %w[settings spacing], nil)
      has_block_gap_support = spacing_settings.is_a?(Hash) && spacing_settings.key?('blockGap')
      has_fallback_gap_support = !has_block_gap_support
      node = options['node'] || PhpCompat.array_get(@data, block_metadata['path'], {}) || {}
      layout_definitions = LayoutDefinitions::ALL

      if has_block_gap_support || has_fallback_gap_support
        block_gap_value =
          if has_block_gap_support
            self.class.property_value(node, %w[spacing blockGap], nil)
          else
            default = selector == ThemeJson::ROOT_BLOCK_SELECTOR ? '0.5em' : nil
            if PhpCompat.php_empty?(block_type)
              default
            else
              PhpCompat.array_get(block_type, %w[supports spacing blockGap __experimentalDefault], nil)
            end
          end

        if block_gap_value.is_a?(Hash)
          if block_gap_value.key?('top') && block_gap_value.key?('left')
            gap_row = self.class.property_value(node, %w[spacing blockGap top], nil)
            gap_column = self.class.property_value(node, %w[spacing blockGap left], nil)
            block_gap_value = gap_row == gap_column ? gap_row : "#{gap_row} #{gap_column}"
          else
            block_gap_value = nil
          end
        end

        unless block_gap_value.nil? || block_gap_value == false || block_gap_value == ''
          layout_definitions.each do |layout_key, layout_definition|
            next if !has_block_gap_support && layout_key != 'flex' && layout_key != 'grid'

            class_name = layout_definition['className']
            spacing_rules = layout_definition['spacingStyles'] || []
            next if PhpCompat.php_empty?(class_name) || PhpCompat.php_empty?(spacing_rules)

            spacing_rules.each do |spacing_rule|
              next unless spacing_rule['selector'] &&
                          LAYOUT_SELECTOR_PATTERN.match?(spacing_rule['selector']) &&
                          !PhpCompat.php_empty?(spacing_rule['rules'])

              declarations = []
              spacing_rule['rules'].each do |css_property, css_value|
                current = css_value.is_a?(String) ? css_value : block_gap_value
                declarations << { 'name' => css_property, 'value' => current } if self.class.safe_css_declaration?(css_property, current)
              end

              layout_selector =
                if has_block_gap_support
                  if selector == ThemeJson::ROOT_BLOCK_SELECTOR
                    ":root :where(.#{class_name})#{spacing_rule['selector']}"
                  else
                    ":root :where(#{selector}-#{class_name})#{spacing_rule['selector']}"
                  end
                elsif selector == ThemeJson::ROOT_BLOCK_SELECTOR
                  ":where(.#{class_name}#{spacing_rule['selector']})"
                else
                  ":where(#{selector}.#{class_name}#{spacing_rule['selector']})"
                end
              block_rules << ThemeJson.to_ruleset(layout_selector, declarations)
            end
          end
        end
      end

      if selector == ThemeJson::ROOT_BLOCK_SELECTOR
        valid_display_modes = %w[block flex grid]
        layout_definitions.each_value do |layout_definition|
          class_name = layout_definition['className']
          base_style_rules = layout_definition['baseStyles'] || []
          next if PhpCompat.php_empty?(class_name) || !base_style_rules.is_a?(Array)

          display_mode = layout_definition['displayMode']
          if !PhpCompat.php_empty?(display_mode) && display_mode.is_a?(String) && valid_display_modes.include?(display_mode)
            block_rules << ThemeJson.to_ruleset("#{selector} .#{class_name}",
                                                [{ 'name' => 'display', 'value' => display_mode }])
          end

          base_style_rules.each do |base_style_rule|
            # Classic themes have no `.wp-site-blocks` wrapper, so the flow and
            # constrained alignment rules would target nothing.
            next if !PhpCompat.php_empty?(options['base_layout_styles']) &&
                    %w[default constrained].include?(layout_definition['name'])
            next unless base_style_rule['selector'] &&
                        LAYOUT_SELECTOR_PATTERN.match?(base_style_rule['selector']) &&
                        !PhpCompat.php_empty?(base_style_rule['rules'])

            declarations = []
            layout_settings = PhpCompat.array_get(@data, %w[settings layout], nil)
            layout_settings = {} unless layout_settings.is_a?(Hash)
            base_style_rule['rules'].each do |css_property, css_value|
              # :2400 — a rule referencing a size the theme never declared is skipped.
              if css_value.is_a?(String) &&
                 (css_value.include?('--global--content-size') || css_value.include?('--global--wide-size')) &&
                 !layout_settings.key?('contentSize') && !layout_settings.key?('wideSize')
                next
              end

              declarations << { 'name' => css_property, 'value' => css_value } if self.class.safe_css_declaration?(css_property, css_value)
            end

            block_rules << ThemeJson.to_ruleset(".#{class_name}#{base_style_rule['selector']}", declarations)
          end
        end
      end

      return "#{options['media_query']}{#{block_rules}}" if !PhpCompat.php_empty?(options['media_query']) && !PhpCompat.php_empty?(block_rules)

      block_rules
    end

    # class-wp-theme-json.php:5680. ⚠️ `$node` is passed BY REFERENCE and the
    # method DELETES from it: a feature that gets its own selector must not also
    # appear under the block's root selector. The Ruby mutates the hash for the
    # same reason, which is why `styles_for_block` deep-dups the node first.
    #
    # @param metadata [Hash]
    # @param node [Hash] mutated
    # @return [Hash{String=>Array}]
    def feature_declarations_for_node(metadata, node)
      declarations = {}
      return declarations unless metadata['selectors'].is_a?(Hash)

      settings = @data['settings'].is_a?(Hash) ? @data['settings'] : {}

      metadata['selectors'].each do |feature, feature_selectors|
        next if feature == 'root' || feature == 'css' || PhpCompat.php_empty?(node[feature])

        if feature_selectors.is_a?(Hash)
          feature_selectors.each do |subfeature, subfeature_selector|
            next if subfeature == 'root' || PhpCompat.php_empty?(PhpCompat.array_get(node, [feature, subfeature], nil))

            subfeature_node = { feature => { subfeature => node[feature][subfeature] } }
            new_declarations = self.class.compute_style_properties(subfeature_node, settings, nil, @data)

            if declarations.key?(subfeature_selector)
              declarations[subfeature_selector].concat(new_declarations)
            else
              declarations[subfeature_selector] = new_declarations
            end

            node[feature].delete(subfeature)
          end
        end

        if feature_selectors.is_a?(String) ||
           (feature_selectors.is_a?(Hash) && !PhpCompat.php_empty?(feature_selectors['root']))
          feature_selector = feature_selectors.is_a?(String) ? feature_selectors : feature_selectors['root']
          feature_node = { feature => node[feature] }
          new_declarations = self.class.compute_style_properties(feature_node, settings, nil, @data)

          if declarations.key?(feature_selector)
            declarations[feature_selector].concat(new_declarations)
          else
            declarations[feature_selector] = new_declarations
          end

          node.delete(feature)
        end
      end

      declarations
    end

    class << self
      # class-wp-theme-json.php:3006.
      #
      # @return [Array<Hash>]
      def compute_style_properties(styles, settings = {}, properties = nil, theme_json = nil,
                                   selector = nil, use_root_padding = nil)
        return [] if PhpCompat.php_empty?(styles)

        properties ||= PROPERTIES_METADATA
        declarations = []
        root_variable_duplicates = []

        properties.each do |css_property, value_path|
          next unless value_path.is_a?(Array)

          is_root_style = css_property.start_with?(ROOT_PADDING_PREFIX)
          next if is_root_style && (selector != ThemeJson::ROOT_BLOCK_SELECTOR || !use_root_padding)

          value = property_value(styles, value_path, theme_json)

          # Root-level padding does not support CSS shorthand strings.
          next if css_property == '--wp--style--root--padding' && value.is_a?(String)

          root_variable_duplicates << css_property[ROOT_PADDING_PREFIX.length..] if is_root_style && use_root_padding

          if css_property == 'background-image'
            background_image_input = {}
            background_image_input['backgroundImage'] = value unless PhpCompat.php_empty?(value)
            gradient_value = PhpCompat.array_get(styles, %w[background gradient], nil)
            background_image_input['gradient'] = gradient_value unless PhpCompat.php_empty?(gradient_value)
            unless PhpCompat.php_empty?(background_image_input)
              background_styles = StyleEngine.get_styles({ 'background' => background_image_input })
              value = PhpCompat.array_get(background_styles, ['declarations', css_property], nil)
            end
          end

          if PhpCompat.php_empty?(value) && selector != ThemeJson::ROOT_BLOCK_SELECTOR &&
             !PhpCompat.php_empty?(PhpCompat.array_get(styles, %w[background backgroundImage id], nil))
            value = 'cover' if css_property == 'background-size'
            if css_property == 'background-position'
              background_size = PhpCompat.array_get(styles, %w[background backgroundSize], nil)
              value = background_size == 'contain' ? '50% 50%' : nil
            end
          end

          # Skip when empty and not "0", or when it is a longhand array.
          next if (PhpCompat.php_empty?(value) && !PhpCompat.php_numeric?(value)) || value.is_a?(Array) || value.is_a?(Hash)

          value = FluidTypography.font_size_value({ 'size' => value }, settings) if css_property == 'font-size'

          # aspect-ratio only works if a fixed height cannot override it.
          declarations << { 'name' => 'min-height', 'value' => 'unset' } if css_property == 'aspect-ratio'

          declarations << { 'name' => css_property, 'value' => value }
        end

        # A root custom property replaces the property it duplicates.
        root_variable_duplicates.each do |duplicate|
          index = declarations.index { |d| d['name'] == duplicate }
          declarations.delete_at(index) unless index.nil?
        end

        declarations
      end

      # class-wp-theme-json.php:3141.
      #
      # @return [Object]
      def property_value(styles, path, theme_json = nil)
        value = PhpCompat.array_get(styles, path, '')
        return '' if value == '' || value.nil?

        if value.is_a?(Hash) && value.key?('ref')
          ref_value = PhpCompat.array_get(theme_json, value['ref'].to_s.split('.'), nil)
          ref_value_url = ref_value.is_a?(Hash) ? ref_value['url'] : nil
          if !PhpCompat.php_empty?(ref_value) && (ref_value.is_a?(String) || ref_value_url.is_a?(String))
            value = ref_value
          end
          # ⚠️ The legacy calls `_doing_it_wrong()` for a ref pointing at a ref.
          # AD-01 leaves no place for that notice; the value is simply not
          # resolved a second time, exactly as in the legacy.
        end

        value
      end

      # class-wp-theme-json.php:3347. A separator with only a background colour
      # gets that colour as its text colour too, because the legacy markup draws
      # the line with `currentColor`.
      def update_separator_declarations(declarations)
        background_color = ''
        border_color_matches = false
        text_color_matches = false

        declarations.each do |declaration|
          if declaration['name'] == 'background-color' && PhpCompat.php_empty?(background_color) && !declaration['value'].nil?
            background_color = declaration['value']
          elsif declaration['name'] == 'border-color'
            border_color_matches = true
          elsif declaration['name'] == 'color'
            text_color_matches = true
          end
          break if !PhpCompat.php_empty?(background_color) && border_color_matches && text_color_matches
        end

        if !PhpCompat.php_empty?(background_color) && !border_color_matches && !text_color_matches
          declarations += [{ 'name' => 'color', 'value' => background_color }]
        end
        declarations
      end

      # class-wp-theme-json.php:3390.
      def update_paragraph_text_indent_selector(feature_declarations, settings, block_name)
        return feature_declarations unless block_name == 'core/paragraph'

        block_settings = PhpCompat.array_get(settings, ['blocks', 'core/paragraph'], nil)
        text_indent_setting = PhpCompat.array_get(block_settings, %w[typography textIndent], nil) ||
                              PhpCompat.array_get(settings, %w[typography textIndent], nil) ||
                              'subsequent'
        return feature_declarations unless text_indent_setting == 'all'

        old_selector = '.wp-block-paragraph + .wp-block-paragraph'
        return feature_declarations unless feature_declarations.key?(old_selector)

        declarations = feature_declarations.delete(old_selector)
        feature_declarations['.wp-block-paragraph'] = declarations
        feature_declarations
      end

      # class-wp-theme-json.php:3434.
      def update_button_width_declarations(feature_declarations, settings)
        return feature_declarations unless feature_declarations.key?('.wp-block-button')

        feature_declarations['.wp-block-button'] = feature_declarations['.wp-block-button'].map do |declaration|
          next declaration unless declaration['name'] == 'width' && !declaration['value'].nil?

          value = declaration['value']
          percentage = nil
          percentage = value.to_f if value.is_a?(String) && value.end_with?('%')

          if percentage.nil? && value.is_a?(String) && value.start_with?('var(--wp--preset--dimension--')
            slug = value[('var(--wp--preset--dimension--'.length)...-1]
            block_sizes = PhpCompat.array_get(settings, ['blocks', 'core/button', 'dimensions', 'dimensionSizes'], {}) || {}
            root_sizes = PhpCompat.array_get(settings, %w[dimensions dimensionSizes], {}) || {}
            # PHP's `+` on arrays: keys from the left win.
            dimension_sizes = root_sizes.merge(block_sizes)
            dimension_sizes.each_value do |origin_sizes|
              next unless origin_sizes.is_a?(Array)

              found = origin_sizes.find { |preset| preset.is_a?(Hash) && preset['slug'] == slug && preset.key?('size') }
              next if found.nil?

              size = found['size']
              percentage = size.to_f if size.is_a?(String) && size.end_with?('%')
              break
            end
          end

          next declaration if percentage.nil?

          n = PhpCompat.to_php_string(percentage)
          declaration.merge('value' => "calc(#{n} * 1% - (var(--wp--style--block-gap, 0.5em) * (1 - #{n} / 100)))")
        end
        feature_declarations
      end

      # class-wp-theme-json.php:5066. ⚠️ The legacy wraps the filtered value in
      # `esc_html()` before testing it for emptiness. `esc_html` can only make a
      # non-empty string longer, so the test is unchanged — and `esc_html` lives
      # in another pack.
      def safe_css_declaration?(property_name, property_value)
        filtered = CssSafety.safecss_filter_attr("#{property_name}: #{property_value}")
        !PhpCompat.php_empty?(PhpCompat.php_trim(filtered))
      end

      # class-wp-theme-json.php:2048 — `&` nesting for a block's custom CSS,
      # forced to 0-1-0 specificity.
      def process_blocks_custom_css(css, selector)
        return '' if PhpCompat.php_empty?(css)

        processed = +''
        css.to_s.split('&', -1).each do |part|
          next if PhpCompat.php_empty?(part)

          unless part.include?('{')
            processed << ":root :where(#{PhpCompat.php_trim(selector)}){#{PhpCompat.php_trim(part)}}"
            next
          end

          pieces = part.gsub('}', '').split('{', -1)
          next if pieces.length != 2

          nested_selector = pieces[0]
          css_value = pieces[1]

          # `::before` and friends, with any leading combinator, are lifted out
          # of the selector and re-appended after the `:where()` wrapper —
          # `:where()` cannot contain a pseudo-ELEMENT.
          match = nested_selector.match(/([>+~\s]*::[a-zA-Z-]+)/)
          pseudo_part = match ? match[1] : ''
          nested_selector = nested_selector.sub(pseudo_part, '') if match

          part_selector =
            if nested_selector.start_with?(' ')
              Selectors.scope_selector(selector, nested_selector)
            else
              Selectors.append_to_selector(selector, nested_selector)
            end
          processed << ":root :where(#{part_selector})#{pseudo_part}{#{PhpCompat.php_trim(css_value)}}"
        end
        processed
      end
    end
  end
end
