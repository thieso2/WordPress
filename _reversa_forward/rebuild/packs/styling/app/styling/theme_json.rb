# frozen_string_literal: true

module Styling
  # BR-MIGRATE-206, 210…215 — the *rules* of WP_Theme_JSON,
  # wp-includes/class-wp-theme-json.php:32.
  #
  # topology_decision.md merges global styles into this pack precisely so the
  # 216 KB god-object is not reproduced. What is ported here is the declarative
  # core: the constants that define the shape of the system, the origin merge,
  # preset expansion, viewport breakpoints and element selectors. The
  # stylesheet renderer (get_stylesheet, layout, block/feature selectors,
  # duotone, spacing scales) is deliberately out of scope — see README.
  class ThemeJson
    # BR-MIGRATE-211 — class-wp-theme-json.php:47.
    ROOT_CSS_PROPERTIES_SELECTOR = ':root'
    # BR-MIGRATE-211 — class-wp-theme-json.php:55.
    ROOT_BLOCK_SELECTOR = 'body'

    # BR-MIGRATE-206 — class-wp-theme-json.php:64. Order is significant: it is
    # the cascade order.
    VALID_ORIGINS = %w[default blocks theme custom].freeze

    # class-wp-theme-json-schema.php / class-wp-theme-json.php:1078.
    LATEST_SCHEMA = 3

    # BR-MIGRATE-210 — class-wp-theme-json.php:371.
    PROTECTED_PROPERTIES = { 'spacing.blockGap' => %w[spacing blockGap] }.freeze

    # BR-MIGRATE-212 — class-wp-theme-json.php:132. Each entry says where the
    # presets live, which key holds the value, the custom-property pattern and
    # the utility classes to generate.
    PRESETS_METADATA = [
      {
        'path' => %w[dimensions aspectRatios],
        'prevent_override' => %w[dimensions defaultAspectRatios],
        'use_default_names' => false,
        'value_key' => 'ratio',
        'css_vars' => '--wp--preset--aspect-ratio--$slug',
        'classes' => {},
        'properties' => ['aspect-ratio']
      },
      {
        'path' => %w[color palette],
        'prevent_override' => %w[color defaultPalette],
        'use_default_names' => false,
        'value_key' => 'color',
        'css_vars' => '--wp--preset--color--$slug',
        'classes' => {
          '.has-$slug-color' => 'color',
          '.has-$slug-background-color' => 'background-color',
          '.has-$slug-border-color' => 'border-color'
        },
        'properties' => ['color', 'background-color', 'border-color']
      },
      {
        'path' => %w[color gradients],
        'prevent_override' => %w[color defaultGradients],
        'use_default_names' => false,
        'value_key' => 'gradient',
        'css_vars' => '--wp--preset--gradient--$slug',
        'classes' => { '.has-$slug-gradient-background' => 'background' },
        'properties' => ['background']
      },
      {
        'path' => %w[color duotone],
        'prevent_override' => %w[color defaultDuotone],
        'use_default_names' => false,
        # CSS custom properties for duotone are handled by block supports.
        'value_func' => nil,
        'css_vars' => nil,
        'classes' => {},
        'properties' => ['filter']
      },
      {
        'path' => %w[typography fontSizes],
        'prevent_override' => %w[typography defaultFontSizes],
        'use_default_names' => true,
        'value_func' => :typography_font_size_value,
        'css_vars' => '--wp--preset--font-size--$slug',
        'classes' => { '.has-$slug-font-size' => 'font-size' },
        'properties' => ['font-size']
      },
      {
        'path' => %w[typography fontFamilies],
        'prevent_override' => false,
        'use_default_names' => false,
        'value_key' => 'fontFamily',
        'css_vars' => '--wp--preset--font-family--$slug',
        'classes' => { '.has-$slug-font-family' => 'font-family' },
        'properties' => ['font-family']
      },
      {
        'path' => %w[spacing spacingSizes],
        'prevent_override' => %w[spacing defaultSpacingSizes],
        'use_default_names' => true,
        'value_key' => 'size',
        'css_vars' => '--wp--preset--spacing--$slug',
        'classes' => {},
        'properties' => %w[padding margin]
      },
      {
        'path' => %w[shadow presets],
        'prevent_override' => %w[shadow defaultPresets],
        'use_default_names' => false,
        'value_key' => 'shadow',
        'css_vars' => '--wp--preset--shadow--$slug',
        'classes' => {},
        'properties' => ['box-shadow']
      },
      {
        'path' => %w[border radiusSizes],
        'prevent_override' => false,
        'use_default_names' => false,
        'value_key' => 'size',
        'css_vars' => '--wp--preset--border-radius--$slug',
        'classes' => {},
        'properties' => ['border-radius']
      },
      {
        'path' => %w[dimensions dimensionSizes],
        'prevent_override' => false,
        'use_default_names' => false,
        'value_key' => 'size',
        'css_vars' => '--wp--preset--dimension--$slug',
        'classes' => {},
        'properties' => ['width', 'height', 'min-height']
      }
    ].freeze

    # class-wp-theme-json.php:325 (the `background-image` entry is the one
    # merge() needs; the rest of PROPERTIES_METADATA is not ported).
    BACKGROUND_IMAGE_PATH = %w[background backgroundImage].freeze

    # BR-MIGRATE-213 — class-wp-theme-json.php:697.
    DEFAULT_VIEWPORT_BREAKPOINTS = { 'mobile' => '480px', 'tablet' => '782px' }.freeze

    # BR-MIGRATE-214 — class-wp-theme-json.php:868.
    #
    # NOTE: BR-MIGRATE-214 enumerates link, heading, h1..h6, button, caption
    # and cite. WordPress 7.2-alpha-63330 — the version being migrated — also
    # ships `textInput` and `select`. The constant below is the legacy source
    # of truth; the discrepancy is recorded in the README.
    ELEMENTS = {
      'link' => 'a:where(:not(.wp-element-button))',
      'heading' => 'h1, h2, h3, h4, h5, h6',
      'h1' => 'h1',
      'h2' => 'h2',
      'h3' => 'h3',
      'h4' => 'h4',
      'h5' => 'h5',
      'h6' => 'h6',
      'button' => '.wp-element-button, .wp-block-button__link',
      'caption' => '.wp-element-caption, .wp-block-audio figcaption, .wp-block-embed figcaption, ' \
                   '.wp-block-gallery figcaption, .wp-block-image figcaption, ' \
                   '.wp-block-table figcaption, .wp-block-video figcaption',
      'cite' => 'cite',
      'textInput' => 'textarea, input:where([type=email],[type=number],[type=password],' \
                     '[type=search],[type=text],[type=tel],[type=url])',
      'select' => 'select'
    }.freeze

    # BR-MIGRATE-214 — class-wp-theme-json.php:886.
    ELEMENT_CLASS_NAMES = { 'button' => 'wp-element-button', 'caption' => 'wp-element-caption' }.freeze

    # BR-MIGRATE-215 — class-wp-theme-json.php:1091.
    # The document is migrated forward *at load time*, then presets are re-keyed
    # by origin so later merges can address each origin's layer independently.
    #
    # @param theme_json [Hash]
    # @param origin [String] one of VALID_ORIGINS; anything else becomes 'theme'
    def initialize(theme_json = { 'version' => LATEST_SCHEMA }, origin = 'theme')
      origin = 'theme' unless VALID_ORIGINS.include?(origin)

      @theme_json = ThemeJsonSchema.migrate(PhpCompat.deep_dup(theme_json), origin)

      # class-wp-theme-json.php:1284 — `sanitize()` keeps only the top-most level
      # keys it knows. This is the one line of the schema pruning that is ported,
      # because `$schema` otherwise survives into the merged document and shows up
      # in every raw-data comparison against the oracle.
      @theme_json = @theme_json.select { |key, _| VALID_TOP_LEVEL_KEYS.include?(key) } if @theme_json.is_a?(Hash)

      # class-wp-theme-json.php:1447-1468 — the tail of `sanitize()`. The schema
      # PRUNING half is still not ported (see README §3), but these three passes
      # are not pruning: they REWRITE values that the stylesheet generator then
      # reads, so leaving them out made `get_stylesheet` diverge from the oracle
      # on every `var:preset|…` reference and on every `appearanceTools` theme.
      %w[styles settings].each do |subtree|
        next unless @theme_json[subtree].is_a?(Hash)

        @theme_json[subtree] = self.class.resolve_custom_css_format(@theme_json[subtree])
      end
      if @theme_json['settings'].is_a?(Hash) && @theme_json['settings'].key?('viewport')
        @theme_json['settings']['viewport'] =
          self.class.sanitize_viewport_settings(@theme_json['settings']['viewport'])
      end
      # class-wp-theme-json.php:1103.
      @theme_json = self.class.maybe_opt_in_into_settings(@theme_json)

      # Internally, presets are keyed by origin.
      self.class.setting_nodes(@theme_json).each do |node|
        PRESETS_METADATA.each do |preset_metadata|
          path = node['path'] + preset_metadata['path']
          preset = PhpCompat.array_get(@theme_json, path, nil)
          next if preset.nil?

          # Only when the preset is not already keyed by origin (PHP:
          # `isset($preset[0]) || empty($preset)`).
          already_keyed = preset.is_a?(Hash) && !preset.empty?
          PhpCompat.array_set(@theme_json, path, { origin => preset }) unless already_keyed
        end
      end

      # spacingScale (which generates presets) is also keyed by origin.
      scale_path = %w[settings spacing spacingScale]
      spacing_scale = PhpCompat.array_get(@theme_json, scale_path, nil)
      if spacing_scale.is_a?(Hash) && (spacing_scale.keys & VALID_ORIGINS).empty?
        PhpCompat.array_set(@theme_json, scale_path, { origin => spacing_scale })
      end

      # Pre-generate the spacingSizes from spacingScale.
      origin_scale_path = scale_path + [origin]
      spacing_scale = PhpCompat.array_get(@theme_json, origin_scale_path, nil)
      return if spacing_scale.nil?

      sizes_path = %w[settings spacing spacingSizes] + [origin]
      spacing_sizes = PhpCompat.array_get(@theme_json, sizes_path, [])
      scale_sizes = self.class.compute_spacing_sizes(spacing_scale)
      PhpCompat.array_set(@theme_json, sizes_path, self.class.merge_spacing_sizes(scale_sizes, spacing_sizes))
    end

    # class-wp-theme-json.php:5102.
    #
    # @return [Hash] the underlying tree
    def raw_data
      @theme_json
    end

    # class-wp-theme-json.php:1931.
    #
    # @return [Hash] the `settings` node
    def settings
      @theme_json['settings'] || {}
    end

    # BR-MIGRATE-206 — class-wp-theme-json.php:4314.
    # Merges an incoming document on top of this one. Everything merges leaf by
    # leaf *except* presets, `spacing.units` and `background.backgroundImage`,
    # which are whole-value replacements because they are single definitions
    # rather than trees.
    #
    # @param incoming [ThemeJson]
    # @return [void]
    def merge(incoming)
      # PHP's get_raw_data() returns a copy; Ruby returns the object, and the
      # spacing-scale pass below writes into it, so copy explicitly.
      incoming_data = PhpCompat.deep_dup(incoming.raw_data)
      @theme_json = PhpCompat.array_replace_recursive(@theme_json, incoming_data)

      # Recompute the spacing sizes against the new hierarchy. spacingScale and
      # spacingSizes are keyed by origin and VALID_ORIGINS is ordered, so a
      # partial scale inherits the missing keys from the earlier layers. This
      # runs before the presets merge so default spacing sizes can still be
      # removed from the theme origin when prevent_override is true.
      flattened_spacing_scale = {}
      VALID_ORIGINS.each do |scale_origin|
        scale_path = %w[settings spacing spacingScale] + [scale_origin]

        base_spacing_scale = PhpCompat.array_get(@theme_json, scale_path, {})
        flattened_spacing_scale = flattened_spacing_scale.merge(base_spacing_scale) if base_spacing_scale.is_a?(Hash)

        spacing_scale = PhpCompat.array_get(incoming_data, scale_path, nil)
        next if spacing_scale.nil?

        flattened_spacing_scale = flattened_spacing_scale.merge(spacing_scale) if spacing_scale.is_a?(Hash)

        sizes_path = %w[settings spacing spacingSizes] + [scale_origin]
        spacing_sizes = PhpCompat.array_get(incoming_data, sizes_path, [])
        scale_sizes = self.class.compute_spacing_sizes(flattened_spacing_scale)
        PhpCompat.array_set(incoming_data, sizes_path,
                            self.class.merge_spacing_sizes(scale_sizes, spacing_sizes))
      end

      nodes = self.class.setting_nodes(incoming_data)
      slugs_global = self.class.default_slugs(@theme_json, ['settings'])

      nodes.each do |node|
        # Replace spacing.units wholesale.
        units_path = node['path'] + %w[spacing units]
        content = PhpCompat.array_get(incoming_data, units_path, nil)
        PhpCompat.array_set(@theme_json, units_path, content) unless content.nil?

        # Replace the presets.
        PRESETS_METADATA.each do |preset_metadata|
          prevent_override = preset_metadata['prevent_override']
          if prevent_override.is_a?(Array)
            global_value = PhpCompat.array_get(@theme_json, ['settings'] + prevent_override, nil)
            prevent_override = PhpCompat.array_get(@theme_json, node['path'] + prevent_override, global_value)
          end

          VALID_ORIGINS.each do |origin|
            base_path = node['path'] + preset_metadata['path']
            path = base_path + [origin]

            content = PhpCompat.array_get(incoming_data, path, nil)
            next if content.nil?

            content = PhpCompat.deep_dup(content)

            # Name theme presets from the defaults when they omit a name.
            if origin == 'theme' && preset_metadata['use_default_names'] && content.is_a?(Array)
              content.each do |item|
                next unless item.is_a?(Hash) && !item.key?('name')

                name = name_from_defaults(item['slug'], base_path)
                item['name'] = name unless name.nil?
              end
            end

            # Drop theme presets that collide with default slugs.
            if origin == 'theme' && prevent_override
              slugs_node = self.class.default_slugs(@theme_json, node['path'])
              preset_global = PhpCompat.array_get(slugs_global, preset_metadata['path'], [])
              preset_node = PhpCompat.array_get(slugs_node, preset_metadata['path'], [])
              preset_global = [] unless preset_global.is_a?(Array)
              preset_node = [] unless preset_node.is_a?(Array)
              # PHP array_merge_recursive() on two lists concatenates them.
              preset_slugs = preset_global + preset_node
              content = self.class.filter_slugs(content, preset_slugs)
            end

            PhpCompat.array_set(@theme_json, path, content)
          end
        end
      end

      # Background image styles are replaced, not merged: they are a single
      # object definition for the style.
      self.class.style_node_paths(@theme_json).each do |path|
        background_image_path = path + BACKGROUND_IMAGE_PATH
        content = PhpCompat.array_get(incoming_data, background_image_path, nil)
        PhpCompat.array_set(@theme_json, background_image_path, content) unless content.nil?
      end
      nil
    end

    # BR-MIGRATE-210 — class-wp-theme-json.php:371.
    # Strips every PROTECTED_PROPERTIES path from a user-origin document so the
    # user origin can never override it.
    #
    # NOTE: WordPress 7.2-alpha-63330 declares PROTECTED_PROPERTIES but no
    # longer references it anywhere. This method implements the rule as the
    # migration spec states it; see README.
    #
    # @param theme_json [Hash] a raw user-origin tree
    # @return [Hash] a copy with the protected style paths removed
    def self.remove_protected_properties(theme_json)
      out = PhpCompat.deep_dup(theme_json)
      return out unless out.is_a?(Hash)

      style_node_paths(out).each do |node_path|
        PROTECTED_PROPERTIES.each_value do |property_path|
          path = node_path + property_path
          parent = PhpCompat.array_get(out, path[0..-2], nil)
          parent.delete(path[-1]) if parent.is_a?(Hash)
        end
      end
      out
    end

    # class-wp-theme-json.php:385.
    VALID_TOP_LEVEL_KEYS = %w[
      blockTypes customTemplates description patterns settings slug styles
      templateParts title version
    ].freeze

    # class-wp-theme-json.php:1045 — the settings `settings.appearanceTools: true`
    # switches on, one path at a time.
    APPEARANCE_TOOLS_OPT_INS = [
      %w[background backgroundImage],
      %w[background backgroundSize],
      %w[background gradient],
      %w[border color],
      %w[border radius],
      %w[border style],
      %w[border width],
      %w[color link],
      %w[color heading],
      %w[color button],
      %w[color caption],
      %w[dimensions aspectRatio],
      %w[dimensions height],
      %w[dimensions minHeight],
      %w[dimensions minWidth],
      %w[dimensions width],
      %w[position sticky],
      %w[spacing blockGap],
      %w[spacing margin],
      %w[spacing padding],
      %w[typography lineHeight],
      %w[typography textColumns]
    ].freeze

    # class-wp-theme-json.php:1220. Expands `appearanceTools: true` at the root and
    # per block, then removes the flag — so a merged document never carries it.
    #
    # @param theme_json [Hash]
    # @return [Hash]
    def self.maybe_opt_in_into_settings(theme_json)
      result = theme_json
      settings = result['settings']
      return result unless settings.is_a?(Hash)

      do_opt_in_into_settings(settings) if settings['appearanceTools'] == true

      blocks = settings['blocks']
      blocks.each_value { |block| do_opt_in_into_settings(block) if block.is_a?(Hash) && block['appearanceTools'] == true } if blocks.is_a?(Hash)

      result
    end

    # class-wp-theme-json.php:1248. ⚠️ `'unset prop'` is the legacy's own marker:
    # `null` is a legitimate value for `spacing.blockGap`, so "absent" cannot be
    # spelled `nil`.
    #
    # @param context [Hash] mutated in place
    # @return [void]
    def self.do_opt_in_into_settings(context)
      APPEARANCE_TOOLS_OPT_INS.each do |path|
        marker = 'unset prop'
        PhpCompat.array_set(context, path, true) if PhpCompat.array_get(context, path, marker) == marker
      end
      context.delete('appearanceTools')
    end

    # class-wp-theme-json.php:5572. `var:preset|color|x` is theme.json's internal
    # spelling of a custom property; CSS wants `var(--wp--preset--color--x)`.
    #
    # @param value [String]
    # @return [String]
    def self.convert_custom_properties(value)
      return value unless value.is_a?(String) && value.start_with?('var:')

      "var(--wp--#{value[4..].to_s.gsub('|', '--')})"
    end

    # class-wp-theme-json.php:5598.
    #
    # @param tree [Object]
    # @return [Object]
    def self.resolve_custom_css_format(tree)
      return tree unless tree.is_a?(Hash) || tree.is_a?(Array)

      each_entry(tree) do |key, data|
        if data.is_a?(String) && data.start_with?('var:')
          tree[key] = convert_custom_properties(data)
        elsif data.is_a?(Hash) || data.is_a?(Array)
          tree[key] = resolve_custom_css_format(data)
        end
      end
      tree
    end

    # PHP arrays are one type; Ruby has two. This keeps `resolve_custom_css_format`
    # a single recursion over both.
    def self.each_entry(tree, &block)
      if tree.is_a?(Array)
        tree.each_index { |i| block.call(i, tree[i]) }
      else
        tree.keys.each { |k| block.call(k, tree[k]) }
      end
    end
    private_class_method :each_entry

    # BR-MIGRATE-212 — class-wp-theme-json.php:2482 (get_css_variables) reduced
    # to one settings node. Produces the CSS custom properties for the presets
    # plus the `--wp--custom--*` theme variables.
    #
    # @param settings [Hash] a settings node
    # @param origins [Array<String>]
    # @return [Array<Hash>] `[{ 'name' =>, 'value' => }, …]`
    def self.compute_preset_vars(settings, origins, root_settings: nil)
      declarations = []
      PRESETS_METADATA.each do |preset_metadata|
        next if PhpCompat.php_empty?(preset_metadata['css_vars'])

        settings_values_by_slug(settings, preset_metadata, origins, root_settings: root_settings).each do |slug, value|
          declarations << {
            'name' => replace_slug_in_string(preset_metadata['css_vars'], slug),
            'value' => value
          }
        end
      end
      declarations
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2909.
    #
    # @param settings [Hash]
    # @return [Array<Hash>]
    def self.compute_theme_vars(settings)
      custom_values = settings['custom'] || {}
      flatten_tree(custom_values).map { |key, value| { 'name' => "--wp--custom--#{key}", 'value' => value } }
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2623.
    # The other half of the rule: the same presets also become utility classes.
    #
    # @param settings [Hash]
    # @param selector [String]
    # @param origins [Array<String>]
    # @return [String] the generated rulesets
    def self.compute_preset_classes(settings, selector, origins)
      # Classes at the global level need no prefix and must not gain specificity.
      selector = '' if selector == ROOT_BLOCK_SELECTOR || selector == ROOT_CSS_PROPERTIES_SELECTOR

      stylesheet = +''
      PRESETS_METADATA.each do |preset_metadata|
        next if PhpCompat.php_empty?(preset_metadata['classes'])

        slugs = settings_slugs(settings, preset_metadata, origins)
        preset_metadata['classes'].each do |klass, property|
          slugs.each_key do |slug|
            css_var = replace_slug_in_string(preset_metadata['css_vars'], slug)
            class_name = replace_slug_in_string(klass, slug)
            # Block-level presets are wrapped in :where() so they keep the same
            # 0-1-0 specificity as a root-level preset.
            new_selector = selector == '' ? class_name : ":where(#{selector})#{class_name}"
            stylesheet << to_ruleset(new_selector, [{ 'name' => property, 'value' => "var(#{css_var}) !important" }])
          end
        end
      end
      stylesheet
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2583.
    #
    # @param selector [String]
    # @param declarations [Array<Hash>]
    # @return [String]
    def self.to_ruleset(selector, declarations)
      return '' if PhpCompat.php_empty?(declarations)

      block = declarations.each_with_object(+'') do |element, carry|
        value = element['value']
        value = PhpCompat.to_php_string(value) if PhpCompat.php_numeric?(value) && !value.is_a?(String)
        next unless value.is_a?(String)

        carry << "#{element['name']}: #{value};"
      end

      "#{selector}{#{block}}"
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2782.
    #
    # @param settings [Hash]
    # @param preset_metadata [Hash]
    # @param origins [Array<String>]
    # @return [Hash{String=>Object}] value keyed by kebab-case slug
    def self.settings_values_by_slug(settings, preset_metadata, origins, root_settings: nil)
      preset_per_origin = PhpCompat.array_get(settings, preset_metadata['path'], {})
      result = {}
      return result unless preset_per_origin.is_a?(Hash)

      origins.each do |origin|
        next unless preset_per_origin.key?(origin) && preset_per_origin[origin].is_a?(Array)

        preset_per_origin[origin].each do |preset|
          slug = PhpCompat.to_kebab_case(preset['slug'])

          if preset_metadata['value_key'] && !preset[preset_metadata['value_key']].nil?
            result[slug] = preset[preset_metadata['value_key']]
          elsif preset_metadata['value_func']
            # `wp_parse_args($settings, wp_get_global_settings())`,
            # block-supports/typography.php:591 — a BLOCK-level settings node falls
            # back to the document's root settings, top-level key by top-level key.
            effective = root_settings.is_a?(Hash) ? root_settings.merge(settings) : settings
            value = send(preset_metadata['value_func'], preset, effective)
            result[slug] = value
          end
        end
      end
      result
    end

    # BR-MIGRATE-212 — class-wp-theme-json.php:2824.
    #
    # @param settings [Hash]
    # @param preset_metadata [Hash]
    # @param origins [Array<String>, nil]
    # @return [Hash{String=>String}] slug => slug, used as a set
    def self.settings_slugs(settings, preset_metadata, origins = nil)
      origins ||= VALID_ORIGINS
      preset_per_origin = PhpCompat.array_get(settings, preset_metadata['path'], {})
      result = {}
      return result unless preset_per_origin.is_a?(Hash)

      origins.each do |origin|
        next unless preset_per_origin.key?(origin) && preset_per_origin[origin].is_a?(Array)

        preset_per_origin[origin].each do |preset|
          slug = PhpCompat.to_kebab_case(preset['slug'])
          result[slug] = slug
        end
      end
      result
    end

    # class-wp-theme-json.php:2855.
    #
    # @param input [String]
    # @param slug [String]
    # @return [String]
    def self.replace_slug_in_string(input, slug)
      input.to_s.gsub('$slug', slug)
    end

    # class-wp-theme-json.php:2960.
    #
    # @param tree [Hash]
    # @param prefix [String]
    # @param token [String]
    # @return [Hash{String=>Object}]
    def self.flatten_tree(tree, prefix = '', token = '--')
      result = {}
      return result unless tree.is_a?(Hash)

      tree.each do |property, value|
        new_key = prefix + PhpCompat.to_kebab_case(property).downcase(:ascii).tr('/', '-')

        if value.is_a?(Hash)
          flatten_tree(value, "#{new_key}#{token}", token).each { |k, v| result[k] = v }
        else
          result[new_key] = value
        end
      end
      result
    end

    # BR-MIGRATE-212 — `wp_get_typography_font_size_value()`,
    # block-supports/typography.php:565. Delegates to `FluidTypography`, which
    # ports the fluid path in full: twentytwentyfive sets
    # `settings.typography.fluid: true`, so every font-size custom property on
    # every screen is a `clamp()` and the Wave 0 shortcut was wrong for all of them.
    #
    # @param preset [Hash]
    # @param settings [Hash]
    # @return [String, nil]
    def self.typography_font_size_value(preset, settings = {})
      FluidTypography.font_size_value(preset, settings)
    end

    # BR-MIGRATE-213 — class-wp-theme-json.php:720.
    # Breakpoints are validated, normalized and ordered before they become
    # media queries.
    #
    # @param viewport_settings [Object] `settings.viewport` from theme.json
    # @param include_desktop [Boolean]
    # @return [Hash{String=>String}] `{'@mobile' =>, '@tablet' =>, '@desktop' =>}`
    def self.viewport_media_queries(viewport_settings = nil, include_desktop: false)
      breakpoints = sanitize_viewport_settings(viewport_settings)

      queries = {}
      queries['@mobile'] = "@media (width <= #{breakpoints['mobile']})" if breakpoints.key?('mobile')

      if breakpoints.key?('tablet')
        queries['@tablet'] = if breakpoints.key?('mobile')
                               "@media (#{breakpoints['mobile']} < width <= #{breakpoints['tablet']})"
                             else
                               "@media (width <= #{breakpoints['tablet']})"
                             end
      end

      if include_desktop
        desktop = breakpoints.key?('tablet') ? breakpoints['tablet'] : breakpoints['mobile']
        queries['@desktop'] = "@media (width > #{desktop})"
      end

      queries
    end

    # BR-MIGRATE-213 — class-wp-theme-json.php:765.
    # Only plain `px`, `em` and `rem` lengths are accepted; CSS functions,
    # percentages and other units are rejected because the value is
    # interpolated straight into a media query.
    #
    # PCRE `^…$` becomes Ruby `\A…\z`: Ruby's `^`/`$` are line anchors, which
    # would let `10px\n<injection>` through.
    #
    # @param value [Object]
    # @return [Boolean]
    VIEWPORT_BREAKPOINT_SIZE = /\A(?:\d+|\d*\.\d+)(?:px|em|rem)\z/
    def self.valid_viewport_breakpoint_size?(value)
      return false unless value.is_a?(String)

      value = PhpCompat.php_trim(value)
      return false if value == ''

      value.match?(VIEWPORT_BREAKPOINT_SIZE)
    end

    # BR-MIGRATE-213 — class-wp-theme-json.php:790.
    # em/rem are converted against a 16px base purely so mobile and tablet can
    # be ordered; the generated query keeps the original unit.
    #
    # @param value [Object]
    # @return [Float, nil]
    def self.viewport_breakpoint_value_in_pixels(value)
      return nil unless valid_viewport_breakpoint_size?(value)

      value = PhpCompat.php_trim(value)
      if value.end_with?('rem')
        number = value[0..-4].to_f
        unit = 'rem'
      else
        unit = value[-2..]
        number = value[0..-3].to_f
      end

      unit == 'px' ? number : number * 16
    end

    # BR-MIGRATE-213 — class-wp-theme-json.php:826.
    #
    # @param viewport_settings [Object]
    # @return [Hash{String=>String}]
    def self.sanitize_viewport_settings(viewport_settings)
      return DEFAULT_VIEWPORT_BREAKPOINTS.dup unless viewport_settings.is_a?(Hash)

      breakpoints = {}
      DEFAULT_VIEWPORT_BREAKPOINTS.each_key do |breakpoint|
        value = viewport_settings[breakpoint]
        px = viewport_breakpoint_value_in_pixels(value)
        next if px.nil?

        breakpoints[breakpoint] = { 'value' => PhpCompat.php_trim(value), 'px' => px }
      end

      return DEFAULT_VIEWPORT_BREAKPOINTS.dup if breakpoints.empty?

      if breakpoints.length == 1
        breakpoint = breakpoints.keys.first
        return { breakpoint => breakpoints[breakpoint]['value'] }
      end

      sanitized = { 'mobile' => breakpoints['mobile']['value'] }
      if breakpoints.key?('tablet') && breakpoints['mobile']['px'] < breakpoints['tablet']['px']
        sanitized['tablet'] = breakpoints['tablet']['value']
      end
      sanitized
    end

    # BR-MIGRATE-214 — class-wp-theme-json.php:868.
    #
    # @param element [String]
    # @return [String, nil] the CSS selector for a styleable element
    def self.element_selector(element)
      ELEMENTS[element]
    end

    # BR-MIGRATE-214 — class-wp-theme-json.php:1023.
    #
    # @param element [String]
    # @return [String] the element's class name, or '' when it has none
    def self.element_class_name(element)
      ELEMENT_CLASS_NAMES[element] || ''
    end

    # class-wp-theme-json.php:5406.
    # `ksort($merged, SORT_NUMERIC)` — slugs are numeric strings ('40', '50').
    #
    # @param base [Array<Hash>] sizes generated from spacingScale
    # @param incoming [Array<Hash>] explicit spacingSizes
    # @return [Array<Hash>]
    def self.merge_spacing_sizes(base, incoming)
      base = [] unless base.is_a?(Array)
      incoming = [] unless incoming.is_a?(Array)
      # Preserve the order if there are no base (spacingScale) values.
      return incoming if base.empty?

      merged = {}
      base.each { |item| merged[item['slug']] = item }
      incoming.each { |item| merged[item['slug']] = item }
      merged.sort_by { |slug, _| slug.to_f }.map { |_, item| item }
    end

    # class-wp-theme-json.php:5458. Generates the spacing presets outward from
    # the medium step, using t-shirt sizing for the names.
    #
    # Not one of the 20 rules, but the constructor and merge() both run it, so
    # omitting it would make BR-MIGRATE-206 diverge whenever a theme declares
    # `settings.spacing.spacingScale`.
    #
    # @param spacing_scale [Hash] steps, mediumStep, unit, operator, increment
    # @return [Array<Hash>] presets, or [] when the scale is unusable
    def self.compute_spacing_sizes(spacing_scale)
      return [] unless spacing_scale.is_a?(Hash)

      steps = spacing_scale['steps']
      medium_step = spacing_scale['mediumStep']
      increment = spacing_scale['increment']
      operator = spacing_scale['operator']

      unless PhpCompat.php_numeric?(steps) && steps != 0 &&
             PhpCompat.php_numeric?(medium_step) &&
             !spacing_scale['unit'].nil? &&
             ['+', '*'].include?(operator) &&
             PhpCompat.php_numeric?(increment)
        return []
      end

      steps = steps.to_f
      medium_step = medium_step.to_f
      increment = increment.to_f

      unit = spacing_scale['unit'] == '%' ? '%' : sanitize_unit(spacing_scale['unit'])
      current_step = medium_step
      steps_mid_point = php_round_half_up(steps / 2)
      x_small_count = nil
      below_sizes = []
      slug = 40
      remainder = 0

      below_midpoint_count = steps_mid_point - 1
      while steps > 1 && slug.positive? && below_midpoint_count.positive?
        current_step = if operator == '+'
                         current_step - increment
                       elsif increment > 1
                         current_step / increment
                       else
                         current_step * increment
                       end

        if current_step <= 0
          remainder = below_midpoint_count
          break
        end

        below_sizes << {
          'name' => below_midpoint_count == steps_mid_point - 1 ? 'Small' : "#{x_small_count}X-Small",
          'slug' => slug.to_s,
          'size' => "#{PhpCompat.to_php_string(php_round(current_step, 2))}#{unit}"
        }

        x_small_count = 2 if below_midpoint_count == steps_mid_point - 2
        x_small_count += 1 if below_midpoint_count < steps_mid_point - 2

        slug -= 10
        below_midpoint_count -= 1
      end

      below_sizes.reverse!
      below_sizes << {
        'name' => 'Medium',
        'slug' => '50',
        'size' => "#{PhpCompat.to_php_string(spacing_scale['mediumStep'])}#{unit}"
      }

      current_step = medium_step
      x_large_count = nil
      above_sizes = []
      slug = 60
      steps_above = (steps - steps_mid_point) + remainder

      above_midpoint_count = 0
      while above_midpoint_count < steps_above
        current_step = if operator == '+'
                         current_step + increment
                       elsif increment >= 1
                         current_step * increment
                       else
                         current_step / increment
                       end

        above_sizes << {
          'name' => above_midpoint_count.zero? ? 'Large' : "#{x_large_count}X-Large",
          'slug' => slug.to_s,
          'size' => "#{PhpCompat.to_php_string(php_round(current_step, 2))}#{unit}"
        }

        x_large_count = 2 if above_midpoint_count == 1
        x_large_count += 1 if above_midpoint_count > 1

        slug += 10
        above_midpoint_count += 1
      end

      below_sizes + above_sizes
    end

    # PHP `round($value, $precision)` — half away from zero, unlike Ruby's
    # Float#round for exactly-representable halves (Ruby matches, but this
    # keeps the intent explicit).
    #
    # @param value [Float]
    # @param precision [Integer]
    # @return [Float]
    def self.php_round(value, precision = 0)
      value.to_f.round(precision, half: :up)
    end

    # PHP `round($value, 0)` returning an Integer for loop arithmetic.
    #
    # @param value [Float]
    # @return [Integer]
    def self.php_round_half_up(value)
      value.to_f.round(half: :up)
    end

    # A restricted `sanitize_title()` for CSS unit strings: lowercase, keep
    # `[a-z0-9_-]`, collapse whitespace to dashes. Accent folding and the full
    # WordPress slug pipeline are NOT ported (see README).
    #
    # @param unit [Object]
    # @return [String]
    def self.sanitize_unit(unit)
      slug = PhpCompat.to_php_string(unit).downcase(:ascii)
      slug = slug.gsub(/[^a-z0-9\s_-]/, '')
      slug = slug.gsub(/[\s_]+/, '-').gsub(/-+/, '-')
      slug.gsub(/\A-+|-+\z/, '')
    end

    # class-wp-theme-json.php:3207, reduced: the root settings node plus one
    # node per `settings.blocks.<name>` actually present in the data. The
    # legacy walks the block registry to attach selectors; selectors are not
    # needed by any rule in this pack.
    #
    # @param theme_json [Hash]
    # @return [Array<Hash>] `[{ 'path' => [...] }, …]`
    def self.setting_nodes(theme_json)
      return [] unless theme_json.is_a?(Hash) && theme_json['settings'].is_a?(Hash)

      nodes = [{ 'path' => ['settings'], 'selector' => ROOT_CSS_PROPERTIES_SELECTOR }]
      blocks = theme_json['settings']['blocks']
      return nodes unless blocks.is_a?(Hash)

      blocks.each_key { |name| nodes << { 'path' => ['settings', 'blocks', name], 'selector' => nil } }
      nodes
    end

    # class-wp-theme-json.php:3519 (get_block_nodes), reduced to the node paths
    # merge() and remove_protected_properties() need.
    #
    # @param theme_json [Hash]
    # @return [Array<Array<String>>]
    def self.style_node_paths(theme_json)
      paths = []
      return paths unless theme_json.is_a?(Hash) && theme_json['styles'].is_a?(Hash)

      styles = theme_json['styles']
      paths << ['styles']

      if styles['elements'].is_a?(Hash)
        styles['elements'].each_key { |element| paths << ['styles', 'elements', element] }
      end

      if styles['blocks'].is_a?(Hash)
        styles['blocks'].each do |name, block|
          paths << ['styles', 'blocks', name]
          next unless block.is_a?(Hash) && block['elements'].is_a?(Hash)

          block['elements'].each_key { |element| paths << ['styles', 'blocks', name, 'elements', element] }
        end
      end

      paths
    end

    # class-wp-theme-json.php:4568.
    #
    # @param data [Hash]
    # @param node_path [Array<String>]
    # @return [Hash] preset path => the default origin's slugs
    def self.default_slugs(data, node_path)
      slugs = {}
      PRESETS_METADATA.each do |metadata|
        path = node_path + metadata['path'] + ['default']
        preset = PhpCompat.array_get(data, path, nil)
        next if preset.nil? || !preset.is_a?(Array)

        PhpCompat.array_set(slugs, metadata['path'], preset.filter_map { |item| item['slug'] if item.is_a?(Hash) && item.key?('slug') })
      end
      slugs
    end

    # class-wp-theme-json.php:4629.
    #
    # @param node [Array<Hash>]
    # @param slugs [Array<String>]
    # @return [Array<Hash>]
    def self.filter_slugs(node, slugs)
      return node if PhpCompat.php_empty?(slugs)
      return node unless node.is_a?(Array)

      node.select { |value| value.is_a?(Hash) && value.key?('slug') && !slugs.include?(value['slug']) }
    end

    private

    # class-wp-theme-json.php:4605.
    #
    # @param slug [String]
    # @param base_path [Array<String>]
    # @return [String, nil]
    def name_from_defaults(slug, base_path)
      default_content = PhpCompat.array_get(@theme_json, base_path + ['default'], nil)
      return nil if PhpCompat.php_empty?(default_content)

      default_content.each do |item|
        return item['name'] if item.is_a?(Hash) && item['slug'] == slug
      end
      nil
    end
  end
end
