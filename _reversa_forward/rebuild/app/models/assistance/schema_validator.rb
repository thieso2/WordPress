# frozen_string_literal: true

module Assistance
  # BR-MIGRATE-274 (BR-AI-06): both input and output are validated against JSON Schema
  # (class-wp-ability.php:519, :711). The legacy delegates to rest_validate_value_from_schema()
  # in wp-includes/rest-api.php. That whole function is part of the REST validation subsystem;
  # this reproduces the subset the abilities pipeline actually exercises against a schema —
  # type, required/properties, enum, numeric and length bounds, and array items — returning the
  # first human-readable failure reason, or nil when the value conforms.
  #
  # It is a pure leaf: no Rails, no other namespace. The oracle's behaviour that the pipeline
  # depends on (a value of the wrong type for an `integer` property fails; a conforming value
  # passes) is reproduced; this is not a general-purpose JSON Schema engine.
  module SchemaValidator
    module_function

    # @return [String, nil] the failure reason, or nil if valid.
    def validate(value, schema, param = "value")
      return nil if schema.nil? || schema.empty?

      schema = stringify(schema)

      if schema.key?("type")
        type_error = check_type(value, schema["type"], param)
        return type_error if type_error
      end

      if schema.key?("enum") && !schema["enum"].include?(value)
        return "#{param} is not one of #{schema["enum"].inspect}."
      end

      case resolved_type(value)
      when "object"
        err = validate_object(value, schema, param)
        return err if err
      when "array"
        err = validate_array(value, schema, param)
        return err if err
      when "number", "integer"
        err = validate_number(value, schema, param)
        return err if err
      when "string"
        err = validate_string(value, schema, param)
        return err if err
      end

      nil
    end

    def check_type(value, type, param)
      types = Array(type)
      return nil if types.any? { |t| matches_type?(value, t) }

      "#{param} is not of type #{types.join(", ")}."
    end

    def matches_type?(value, type)
      case type
      when "string"  then value.is_a?(String)
      when "integer" then value.is_a?(Integer)
      when "number"  then value.is_a?(Numeric)
      when "boolean" then value == true || value == false
      when "object"  then value.is_a?(Hash)
      when "array"   then value.is_a?(Array)
      when "null"    then value.nil?
      else true # unknown type keyword — do not reject
      end
    end

    def validate_object(value, schema, param)
      Array(schema["required"]).each do |key|
        key = key.to_s
        unless value.key?(key) || value.key?(key.to_sym)
          return "#{param} is missing required property #{key}."
        end
      end

      props = schema["properties"] || {}
      props.each do |key, subschema|
        present = value.key?(key.to_s) ? value[key.to_s] : value[key.to_sym]
        next unless value.key?(key.to_s) || value.key?(key.to_sym)

        err = validate(present, subschema, "#{param}[#{key}]")
        return err if err
      end

      if schema["additionalProperties"] == false
        allowed = props.keys.map(&:to_s)
        extra = value.keys.map(&:to_s) - allowed
        return "#{param} has unexpected propert#{extra.one? ? "y" : "ies"} #{extra.join(", ")}." unless extra.empty?
      end

      nil
    end

    def validate_array(value, schema, param)
      if schema["items"]
        value.each_with_index do |item, i|
          err = validate(item, schema["items"], "#{param}[#{i}]")
          return err if err
        end
      end
      if schema["minItems"] && value.length < schema["minItems"]
        return "#{param} must contain at least #{schema["minItems"]} items."
      end
      if schema["maxItems"] && value.length > schema["maxItems"]
        return "#{param} must contain at most #{schema["maxItems"]} items."
      end
      nil
    end

    def validate_number(value, schema, param)
      if schema["minimum"] && value < schema["minimum"]
        return "#{param} must be greater than or equal to #{schema["minimum"]}."
      end
      if schema["maximum"] && value > schema["maximum"]
        return "#{param} must be less than or equal to #{schema["maximum"]}."
      end
      nil
    end

    def validate_string(value, schema, param)
      if schema["minLength"] && value.length < schema["minLength"]
        return "#{param} must be at least #{schema["minLength"]} characters long."
      end
      if schema["maxLength"] && value.length > schema["maxLength"]
        return "#{param} must be at most #{schema["maxLength"]} characters long."
      end
      nil
    end

    def resolved_type(value)
      case value
      when Hash then "object"
      when Array then "array"
      when Integer then "integer"
      when Numeric then "number"
      when String then "string"
      when true, false then "boolean"
      when nil then "null"
      else "unknown"
      end
    end

    def stringify(schema)
      schema.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end
  end
end
