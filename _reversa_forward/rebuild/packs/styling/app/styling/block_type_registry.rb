# frozen_string_literal: true

module Styling
  # BR-MIGRATE-200 — the slice of WP_Block_Type_Registry the block-supports
  # rules need, wp-includes/class-wp-block-type-registry.php.
  #
  # paradigm_decision.md option 1: no `get_instance()` singleton. The registry
  # is an ordinary object the caller owns and passes into
  # `BlockSupports#apply_block_supports`.
  class BlockTypeRegistry
    def initialize
      @registered_block_types = {}
    end

    # @param block_type [BlockType]
    # @return [BlockType]
    def register(block_type)
      @registered_block_types[block_type.name] = block_type
    end

    # BR-MIGRATE-200 — an unregistered name yields nil, which is what makes
    # supports contribute nothing.
    #
    # @param name [String, nil]
    # @return [BlockType, nil]
    def registered(name)
      @registered_block_types[name]
    end

    # @return [Hash{String=>BlockType}]
    def all_registered
      @registered_block_types
    end
  end
end
