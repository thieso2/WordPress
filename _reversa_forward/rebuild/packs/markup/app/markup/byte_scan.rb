# frozen_string_literal: true

module Markup
  # Byte-level scanning primitives.
  #
  # The legacy HTML API is written entirely against PHP's byte-oriented string
  # functions (`strspn`, `strcspn`, `strpos`, `substr`). BR-MIGRATE-220 makes that
  # byte orientation load-bearing: every offset the Tag Processor records is a byte
  # offset into the source document, and every modification is spliced back in at a
  # byte offset. Ruby's String is character-oriented once an encoding is attached, so
  # the whole pack works on ASCII-8BIT ("binary") strings and uses these helpers as
  # direct stand-ins for the PHP functions.
  #
  # Legacy origin: wp-includes/html-api/class-wp-html-tag-processor.php (throughout).
  module ByteScan
    # Cache of 256-entry membership tables, keyed by the character-set string.
    SETS = {} # rubocop:disable Style/MutableConstant
    private_constant :SETS

    class << self
      # Equivalent of PHP `strspn()`: how many bytes at `offset` are members of `chars`.
      #
      # BR-MIGRATE-220. Legacy: PHP strspn(), used e.g. at
      # wp-includes/html-api/class-wp-html-tag-processor.php:2217.
      def span(string, chars, offset = 0, length = nil)
        table = table_for(chars)
        limit = limit_for(string, offset, length)
        at = offset
        at += 1 while at < limit && table[string.getbyte(at)]
        at - offset
      end

      # Equivalent of PHP `strcspn()`: how many bytes at `offset` are NOT in `chars`.
      #
      # BR-MIGRATE-220. Legacy: PHP strcspn(), used e.g. at
      # wp-includes/html-api/class-wp-html-tag-processor.php:2252.
      def cspan(string, chars, offset = 0, length = nil)
        table = table_for(chars)
        limit = limit_for(string, offset, length)
        at = offset
        at += 1 while at < limit && !table[string.getbyte(at)]
        at - offset
      end

      private

      def table_for(chars)
        SETS[chars] ||= begin
          table = Array.new(256, false)
          chars.each_byte { |byte| table[byte] = true }
          table.freeze
        end
      end

      def limit_for(string, offset, length)
        size = string.bytesize
        return size if length.nil?

        stop = offset + length
        stop > size ? size : stop
      end
    end
  end
end
