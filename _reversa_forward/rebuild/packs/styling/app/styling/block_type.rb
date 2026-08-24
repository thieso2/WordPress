# frozen_string_literal: true

module Styling
  # BR-MIGRATE-204 — the slice of WP_Block_Type the block-supports rules need,
  # wp-includes/class-wp-block-type.php.
  #
  # Only `name`, `attributes` and `supports` are modelled; rendering,
  # registration metadata and the REST controller live outside this pack.
  class BlockType
    # @return [String]
    attr_reader :name
    # @return [Hash{String=>Hash}] JSON-schema-ish attribute definitions
    attr_accessor :attributes
    # @return [Hash] the block's `supports` declaration
    attr_accessor :supports

    # @param name [String]
    # @param attributes [Hash{String=>Hash}, nil]
    # @param supports [Hash]
    def initialize(name, attributes: {}, supports: {})
      @name = name
      @attributes = attributes
      @supports = supports || {}
    end

    # BR-MIGRATE-204 — class-wp-block-type.php:495.
    # Validates the incoming attributes against the block schema, dropping
    # invalid values, and then populates every missing attribute that declares
    # a default. Block supports therefore never see a raw attribute bag.
    #
    # @param attributes [Hash{String=>Object}]
    # @return [Hash{String=>Object}] prepared attributes
    def prepare_attributes_for_render(attributes)
      # If there are no attribute definitions for the block type, skip
      # processing and return verbatim.
      return attributes if @attributes.nil?

      prepared = attributes.dup

      attributes.each do |attribute_name, value|
        schema = @attributes[attribute_name]
        next if schema.nil?

        prepared.delete(attribute_name) unless self.class.value_valid_for_schema?(value, schema)
      end

      # Populate values of any missing attributes for which the block type
      # defines a default.
      @attributes.each do |attribute_name, schema|
        next if prepared.key?(attribute_name)
        next unless schema.is_a?(Hash) && schema.key?('default') && !schema['default'].nil?

        prepared[attribute_name] = schema['default']
      end

      prepared
    end

    # BR-MIGRATE-204 — a deliberately reduced port of
    # `rest_validate_value_from_schema()` (wp-includes/rest-api.php): only the
    # `type` (including unions) and `enum` keywords are honoured. See README.
    #
    # @param value [Object]
    # @param schema [Hash]
    # @return [Boolean]
    def self.value_valid_for_schema?(value, schema)
      return true unless schema.is_a?(Hash)

      if schema.key?('enum') && schema['enum'].is_a?(Array)
        return false unless schema['enum'].include?(value)
      end

      types = schema['type']
      return true if types.nil?

      types = [types] unless types.is_a?(Array)
      types.any? { |type| matches_type?(value, type) }
    end

    # @param value [Object]
    # @param type [String]
    # @return [Boolean]
    def self.matches_type?(value, type)
      case type
      when 'null' then value.nil?
      when 'boolean' then value == true || value == false || [0, 1, '0', '1', 'true', 'false'].include?(value)
      when 'object' then value.is_a?(Hash)
      when 'array' then value.is_a?(Array)
      when 'number' then PhpCompat.php_numeric?(value)
      when 'integer' then PhpCompat.php_numeric?(value) && value.to_f.round == value.to_f
      when 'string' then !value.is_a?(Array) && !value.is_a?(Hash) && !value.nil?
      else true
      end
    end
  end
end
