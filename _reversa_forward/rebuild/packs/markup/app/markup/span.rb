# frozen_string_literal: true

module Markup
  # A (start, length) byte range inside the source document.
  #
  # BR-MIGRATE-220: the Tag Processor never builds a tree, so a "node" is nothing more
  # than a byte range. BR-MIGRATE-221: bookmarks are stored as spans and are shifted as
  # updates are applied, which is what lets `seek()` return to a token after edits.
  #
  # Legacy: wp-includes/html-api/class-wp-html-span.php:25.
  class Span
    attr_accessor :start, :length

    def initialize(start, length)
      @start = start
      @length = length
    end
  end
end
