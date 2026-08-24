# frozen_string_literal: true

module Styling
  # BR-MIGRATE-200…205 — port of WP_Block_Supports,
  # wp-includes/class-wp-block-supports.php:21.
  #
  # A registry of named "supports", each of which may contribute HTML
  # attributes to the block wrapper at render time and/or register attributes
  # on block types at boot.
  #
  # paradigm_decision.md option 1 deviations, both recorded in the README:
  #   * no `get_instance()` singleton — instantiate one BlockSupports;
  #   * no `public static $block_to_render` — the block being rendered is
  #     passed explicitly into `apply_block_supports` (BR-MIGRATE-205).
  class BlockSupports
    def initialize
      @block_supports = {}
    end

    # @return [Hash{String=>Hash}] the registered supports, in registration order
    attr_reader :block_supports

    # BR-MIGRATE-203 — class-wp-block-supports.php:99.
    # A config without an `apply` callable still registers fine; it simply
    # contributes nothing at render time.
    #
    # @param block_support_name [String]
    # @param block_support_config [Hash] `{ apply:, register_attribute: }`
    # @return [void]
    def register(block_support_name, block_support_config)
      @block_supports[block_support_name] =
        block_support_config.merge(name: block_support_name)
      nil
    end

    # BR-MIGRATE-200…205 — class-wp-block-supports.php:114.
    #
    # * 200 — a block whose name is not in `registry` receives nothing.
    # * 204 — attributes go through `prepare_attributes_for_render` first, so
    #   schema defaults are in place before any support sees them.
    # * 203 — supports without an `apply` callable are skipped.
    # * BR-MIGRATE-202 — non-scalar values *and booleans* are skipped; the explicit
    #   boolean check is what stops `true` from stringifying to `'1'`.
    # * BR-MIGRATE-201 — the first support to write an attribute takes the slot; later
    #   ones append after a single space.
    # * 205 — `block_to_render` is a parameter, not a static.
    #
    # @param block_to_render [Hash, nil] `{ 'blockName' => …, 'attrs' => … }`
    # @param registry [BlockTypeRegistry]
    # @return [Hash{String=>String}] HTML attribute values keyed by name
    def apply_block_supports(block_to_render, registry)
      return {} unless block_to_render.is_a?(Hash)

      block_type = registry.registered(block_to_render['blockName'])

      # If no registered block type, assume styles have been previously handled.
      return {} if block_type.nil?

      block_attributes =
        if block_to_render.key?('attrs') && block_to_render['attrs'].is_a?(Hash)
          block_type.prepare_attributes_for_render(block_to_render['attrs'])
        else
          {}
        end

      output = {}
      @block_supports.each_value do |block_support_config|
        apply = block_support_config[:apply] || block_support_config['apply']
        next if apply.nil?

        new_attributes = apply.call(block_type, block_attributes)
        next if PhpCompat.php_empty?(new_attributes)

        new_attributes.each do |attribute_name, attribute_value|
          next unless PhpCompat.php_scalar?(attribute_value)
          next if attribute_value == true || attribute_value == false

          attribute_value = PhpCompat.to_php_string(attribute_value)
          if !output.key?(attribute_name) || output[attribute_name] == ''
            output[attribute_name] = attribute_value
          else
            output[attribute_name] = "#{output[attribute_name]} #{attribute_value}"
          end
        end
      end

      output
    end

    # BR-MIGRATE-203 — class-wp-block-supports.php:169.
    # Runs every support's `register_attribute` callable against every
    # registered block type. Supports with no `register_attribute` are skipped;
    # this is the half of BR-MIGRATE-203 that says a support may register
    # attributes even when it contributes nothing at render time.
    #
    # @param registry [BlockTypeRegistry]
    # @return [void]
    def register_attributes(registry)
      registry.all_registered.each_value do |block_type|
        next unless block_type.is_a?(BlockType)

        block_type.attributes = {} if PhpCompat.php_empty?(block_type.attributes)

        @block_supports.each_value do |block_support_config|
          register_attribute = block_support_config[:register_attribute] ||
                               block_support_config['register_attribute']
          next if register_attribute.nil?

          register_attribute.call(block_type)
        end
      end
      nil
    end
  end
end
