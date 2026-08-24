# frozen_string_literal: true

module Markup
  # One deferred byte-level splice: replace `length` bytes at `start` with `text`.
  #
  # BR-MIGRATE-220: `set_attribute()`, `remove_attribute()`, `add_class()`,
  # `remove_class()` and `set_modifiable_text()` all enqueue one of these rather than
  # touching the document; they are applied, in ascending order, by
  # `Markup::TagProcessor#get_updated_html`.
  #
  # Legacy: wp-includes/html-api/class-wp-html-text-replacement.php:21.
  class TextReplacement
    attr_accessor :start, :length, :text

    def initialize(start, length, text)
      @start = start
      @length = length
      @text = text
    end
  end
end
