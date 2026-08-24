# frozen_string_literal: true

module Composition
  # BR-MIGRATE-192/193. One registered block type, loaded from db/blocks/types.json,
  # which `rake composition:generate_blocks` derives from the legacy's 115 block.json
  # files. Nothing here is hand-maintained.
  class BlockType
    attr_reader :name, :title, :category, :api_version, :attributes, :supports,
                :uses_context, :provides_context, :style_handle

    def initialize(schema)
      @name = schema.fetch("name")
      @title = schema["title"]
      @category = schema["category"]
      @api_version = schema["apiVersion"]
      @attributes = schema["attributes"] || {}
      @supports = schema["supports"] || {}
      @uses_context = schema["usesContext"] || []
      @provides_context = schema["providesContext"] || {}
      @dynamic = schema["dynamic"]
      @style_handle = schema["styleHandle"]
    end

    def dynamic? = @dynamic
    def short_name = name.sub(%r{\Acore/}, "")

    # BR-MIGRATE-204 (BR-BSUP-05): "Attributes pass through
    # prepare_attributes_for_render() so schema defaults are applied BEFORE any support
    # sees them." Ordering matters — a support that reads an attribute before its default
    # is applied sees nil where the legacy sees the default.
    def prepare_attributes(supplied)
      given = supplied || {}
      @attributes.each_with_object({}) do |(key, definition), out|
        if given.key?(key)
          out[key] = coerce(given[key], definition)
        elsif definition.key?("default")
          out[key] = definition["default"]
        end
      end.merge(given.reject { |k, _| @attributes.key?(k) })
    end

    private

    # The legacy validates loosely: a value of the wrong type is passed through rather
    # than rejected, because block markup is user content and refusing it would lose the
    # post. Only the cheap, safe coercions are applied.
    def coerce(value, definition)
      case definition["type"]
      when "boolean" then value == true || value == "true"
      when "number"  then value.is_a?(Numeric) ? value : (Float(value) rescue value)
      when "integer" then value.is_a?(Integer) ? value : (Integer(value) rescue value)
      else value
      end
    end
  end
end
