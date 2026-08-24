# frozen_string_literal: true

module Styling
  # `WP_Theme_JSON::get_blocks_metadata()`, class-wp-theme-json.php:1764, plus
  # `wp_get_block_css_selector()`, wp-includes/global-styles-and-settings.php:503.
  #
  # This is the map from a block name to every CSS selector the stylesheet
  # generator can address it with: its root selector, its feature and subfeature
  # selectors, its per-element selectors (BR-MIGRATE-214), its duotone selector,
  # its style-variation selectors and its custom-state selectors.
  #
  # ⚠️ topology_decision.md option 3: the legacy reads
  # `WP_Block_Type_Registry::get_instance()` — a singleton this pack may not have.
  # `build` therefore takes the block definitions as an argument: the same
  # `block.json` shape the registry holds (`name`, `selectors`, `supports`,
  # `styles`). The application owns the registry and passes it in.
  #
  # ⚠️ `WP_Block_Styles_Registry` is not represented. Variations registered at
  # runtime rather than in `block.json` are therefore absent — AD-01 removes
  # runtime registration, so `block.json`'s `styles` array is the whole set.
  class BlocksMetadata
    # class-wp-theme-json.php:899 — the features that may carry their own
    # selector. The KEY is the block.json supports key, the VALUE the theme.json
    # feature name.
    BLOCK_SUPPORT_FEATURE_LEVEL_SELECTORS = {
      '__experimentalBorder' => 'border',
      'color' => 'color',
      'dimensions' => 'dimensions',
      'spacing' => 'spacing',
      'typography' => 'typography'
    }.freeze

    class << self
      # class-wp-theme-json.php:1764.
      #
      # @param block_definitions [Hash{String=>Hash}, Array<Hash>] block.json data
      #   per block; a hash keyed by block name or a list carrying `name`.
      # @return [Hash{String=>Hash}] metadata keyed by block name
      def build(block_definitions)
        each_definition(block_definitions).each_with_object({}) do |(name, block_type), metadata|
          entry = {}
          root_selector = css_selector(block_type, name)
          entry['selector'] = root_selector
          entry['selectors'] = block_selectors(block_type, name, root_selector)

          elements = block_element_selectors(root_selector)
          entry['elements'] = elements unless PhpCompat.php_empty?(elements)

          duotone = duotone_selector(block_type, name, root_selector)
          entry['duotone'] = duotone unless duotone.nil?

          variations = style_variation_selectors(block_type, root_selector)
          entry['styleVariations'] = variations unless PhpCompat.php_empty?(variations)

          states = PhpCompat.array_get(block_type, %w[selectors states], nil)
          entry['states'] = states if states.is_a?(Hash) && !states.empty?

          metadata[name] = entry
        end
      end

      # `wp_get_block_css_selector()`, global-styles-and-settings.php:503.
      #
      # @param block_type [Hash] the block.json data
      # @param block_name [String]
      # @param target [String, Array<String>] `'root'`, `'filter.duotone'`, …
      # @param fallback [Boolean] fall back to the broader selector
      # @return [String, nil]
      def css_selector(block_type, block_name, target = 'root', fallback: false)
        return nil if PhpCompat.php_empty?(target)

        selectors = block_type['selectors']
        has_selectors = !PhpCompat.php_empty?(selectors)

        root_selector =
          if has_selectors && selectors.key?('root')
            selectors['root']
          elsif PhpCompat.array_get(block_type, %w[supports __experimentalSelector], nil).is_a?(String)
            block_type['supports']['__experimentalSelector']
          else
            # :523 — the default is derived from the name, with `core/` dropped
            # and every remaining `/` turned into `-`.
            ".wp-block-#{block_name.to_s.sub('core/', '').tr('/', '-')}"
          end

        return root_selector if target == 'root'

        target = target.split('.') if target.is_a?(String)

        if target.length == 1
          fallback_selector = fallback ? root_selector : nil

          if has_selectors
            feature_selector = PhpCompat.array_get(selectors, [target.first, 'root'], nil)
            return feature_selector if !PhpCompat.php_empty?(feature_selector)

            feature_selector = PhpCompat.array_get(selectors, target, nil)
            return feature_selector.is_a?(String) ? feature_selector : fallback_selector
          end

          feature_selector = PhpCompat.array_get(block_type['supports'], [target.first, '__experimentalSelector'], nil)
          return fallback_selector if feature_selector.nil?

          return Selectors.scope_selector(root_selector, feature_selector)
        end

        subfeature_selector = has_selectors ? PhpCompat.array_get(selectors, target, nil) : nil
        return subfeature_selector if !PhpCompat.php_empty?(subfeature_selector)
        return css_selector(block_type, block_name, target[0], fallback: fallback) if fallback

        nil
      end

      # class-wp-theme-json.php:5621.
      #
      # @param block_type [Hash]
      # @param block_name [String]
      # @param root_selector [String]
      # @return [Hash]
      def block_selectors(block_type, block_name, root_selector)
        return block_type['selectors'] unless PhpCompat.php_empty?(block_type['selectors'])

        selectors = { 'root' => root_selector }
        BLOCK_SUPPORT_FEATURE_LEVEL_SELECTORS.each do |key, feature|
          feature_selector = css_selector(block_type, block_name, key)
          selectors[feature] = { 'root' => feature_selector } unless feature_selector.nil?
        end
        selectors
      end

      # BR-MIGRATE-214 — class-wp-theme-json.php:5645. Every styleable element,
      # scoped under each branch of the block's root selector.
      #
      # @param root_selector [String]
      # @return [Hash{String=>String}]
      def block_element_selectors(root_selector)
        # ⚠️ `explode(',', …)`, NOT split_selector_list: the legacy is naive here
        # and a comma inside `:is()` would split. Transcribed as written.
        block_selectors = root_selector.to_s.split(',', -1)
        ThemeJson::ELEMENTS.each_with_object({}) do |(el_name, el_selector), out|
          element_selector = []
          block_selectors.each do |selector|
            if selector == el_selector
              element_selector = [el_selector]
              break
            end
            element_selector << Selectors.prepend_to_selector(el_selector, "#{selector} ")
          end
          out[el_name] = element_selector.join(',')
        end
      end

      private

      def each_definition(block_definitions)
        return block_definitions.map { |b| [b['name'], b] } if block_definitions.is_a?(Array)

        block_definitions.map { |name, b| [name, b || {}] }
      end

      # :1804 — the duotone selector, with the `color.__experimentalDuotone`
      # fallback the legacy still honours.
      def duotone_selector(block_type, block_name, root_selector)
        selector = css_selector(block_type, block_name, 'filter.duotone')
        return selector unless selector.nil?

        duotone_support = PhpCompat.array_get(block_type, %w[supports color __experimentalDuotone], nil)
        return nil if PhpCompat.php_empty?(duotone_support)

        Selectors.scope_selector(root_selector, duotone_support)
      end

      # :1822 — block.json's `styles` array. `WP_Block_Styles_Registry` has no
      # counterpart here; see the class comment.
      def style_variation_selectors(block_type, root_selector)
        styles = block_type['styles']
        return {} unless styles.is_a?(Array)

        styles.each_with_object({}) do |style, out|
          next unless style.is_a?(Hash) && style['name']

          out[style['name']] = Selectors.block_style_variation_selector(style['name'], root_selector)
        end
      end
    end
  end
end
