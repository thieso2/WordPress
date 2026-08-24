# frozen_string_literal: true

module Markup
  # Where an attribute lives inside the currently-matched tag, in bytes.
  #
  # BR-MIGRATE-220 / BR-MIGRATE-222: attributes are recorded as offsets into the source
  # rather than as decoded strings, so discovery (`get_attribute_names_with_prefix`) and
  # modification both work without materialising anything.
  #
  # Legacy: wp-includes/html-api/class-wp-html-attribute-token.php:24.
  class AttributeToken
    attr_accessor :name, :value_starts_at, :value_length, :start, :length, :is_true

    def initialize(name, value_start, value_length, start, length, is_true)
      @name = name
      @value_starts_at = value_start
      @value_length = value_length
      @start = start
      @length = length
      @is_true = is_true
    end
  end
end
