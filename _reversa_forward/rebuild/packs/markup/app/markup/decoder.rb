# frozen_string_literal: true

module Markup
  # Decodes HTML character references in text nodes and attribute values.
  #
  # The Tag Processor defers decoding: it stores byte offsets and only decodes when a
  # caller asks for a value (BR-MIGRATE-220). This is where that decoding happens.
  #
  # Legacy: wp-includes/html-api/class-wp-html-decoder.php:12.
  module Decoder
    REPLACEMENT_CHARACTER = "\xEF\xBF\xBD".b.freeze # U+FFFD, as UTF-8 bytes.

    # C1 controls are remapped as if they had been stored in Windows-1252. This applies
    # only to numeric character references; raw bytes in the stream are left alone.
    #
    # Legacy: wp-includes/html-api/class-wp-html-decoder.php:363.
    WINDOWS_1252_MAPPING = [
      0x20AC, 0x81,   0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
      0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D,   0x017D, 0x8F,
      0x90,   0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D,   0x017E, 0x0178
    ].freeze

    HEX_DIGITS = "0123456789abcdefABCDEF"
    DEC_DIGITS = "0123456789"
    WHITESPACE = " \t\f\r\n"

    AMPERSAND = 0x26
    HASH = 0x23
    SEMICOLON = 0x3B

    class << self
      # Decodes a text node's raw source into the text a browser would render.
      #
      # The returned String is tagged UTF-8, which is the encoding the HTML API accepts.
      # Callers inside this pack that need to keep scanning bytes use `decode` directly.
      #
      # BR-MIGRATE-220. Legacy: class-wp-html-decoder.php:143.
      def decode_text_node(text)
        decode("data", text).force_encoding(Encoding::UTF_8)
      end

      # Decodes an attribute value's raw source.
      #
      # In attribute context an "ambiguous ampersand" — a semicolon-less reference
      # followed by an alphanumeric or `=` — is left as literal text, which is why the
      # context has to be passed all the way down.
      #
      # BR-MIGRATE-220. Legacy: class-wp-html-decoder.php:163.
      def decode_attribute(text)
        decode("attribute", text).force_encoding(Encoding::UTF_8)
      end

      # Decodes every character reference in `text` for the given context.
      #
      # `context` is "data" (text nodes) or "attribute". The result is a binary String:
      # decoding happens mid-scan, and the byte offsets around it still have to line up.
      #
      # BR-MIGRATE-220. Legacy: class-wp-html-decoder.php:186.
      def decode(context, text)
        text = text.b
        decoded = +""
        at = 0
        was_at = 0
        stop = text.bytesize

        while at < stop
          next_reference_at = text.index("&", at)
          break if next_reference_at.nil?

          replacement, token_length = read_character_reference(context, text, next_reference_at)
          if replacement
            at = next_reference_at
            decoded << text.byteslice(was_at, at - was_at)
            decoded << replacement
            at += token_length
            was_at = at
            next
          end

          at += 1
        end

        return text.dup if was_at.zero?

        decoded << text.byteslice(was_at, stop - was_at) if was_at < stop
        decoded
      end

      # Reads a single character reference beginning at `at`.
      #
      # Returns `[replacement_bytes, matched_byte_length]`, or `nil` when the bytes at
      # `at` are not a character reference and must be treated as plain text. The legacy
      # signals the same two facts through a return value plus an out-parameter.
      #
      # BR-MIGRATE-220. Legacy: class-wp-html-decoder.php:258.
      def read_character_reference(context, text, at = 0)
        text = text.b
        length = text.bytesize
        return nil if at + 1 >= length
        return nil unless text.getbyte(at) == AMPERSAND

        return read_numeric_character_reference(text, at, length) if text.getbyte(at + 1) == HASH

        name_at = at + 1
        # The shortest named character reference is two bytes, e.g. `GT`.
        return nil if name_at + 2 > length

        name_length = longest_named_reference_at(text, name_at, length)
        return nil if name_length.nil?

        replacement = NamedCharacterReferences::TABLE[text.byteslice(name_at, name_length)]
        after_name = name_at + name_length

        # A semicolon-terminated reference is never ambiguous, and in text-node context
        # nothing is ambiguous either.
        if context != "attribute" || text.getbyte(after_name - 1) == SEMICOLON || after_name >= length
          return [replacement, after_name - at]
        end

        follower = text.getbyte(after_name)
        return nil if follower == 0x3D || # EQUALS SIGN
                      (follower >= 0x30 && follower <= 0x39) || # ASCII digits 0-9
                      (follower >= 0x41 && follower <= 0x5A) || # ASCII upper alpha A-Z
                      (follower >= 0x61 && follower <= 0x7A)    # ASCII lower alpha a-z

        [replacement, after_name - at]
      end

      # Encodes a code point as UTF-8, or U+FFFD when it cannot be encoded.
      #
      # BR-MIGRATE-220. Legacy: class-wp-html-decoder.php:502 (`mb_chr()`, which returns
      # false for surrogates and for values above U+10FFFF).
      def code_point_to_utf8_bytes(code_point)
        return REPLACEMENT_CHARACTER if code_point >= 0xD800 && code_point <= 0xDFFF

        code_point.chr(Encoding::UTF_8).b
      rescue RangeError
        REPLACEMENT_CHARACTER
      end

      # Whether the decoded value of `haystack` starts with `search_text`.
      #
      # Comparison happens against the decoded text without ever materialising the whole
      # decoded string, which is what makes prefix checks cheap on long attribute values.
      #
      # BR-MIGRATE-222 (prefix-oriented attribute inspection).
      # Legacy: class-wp-html-decoder.php:37.
      def attribute_starts_with(haystack, search_text, case_sensitivity = "case-sensitive")
        haystack = haystack.b
        search_text = search_text.b
        search_length = search_text.bytesize
        loose_case = case_sensitivity == "ascii-case-insensitive"
        haystack_end = haystack.bytesize
        search_at = 0
        haystack_at = 0

        while search_at < search_length && haystack_at < haystack_end
          haystack_byte = haystack.byteslice(haystack_at, 1)
          search_byte = search_text.byteslice(search_at, 1)
          chars_match = loose_case ? haystack_byte.downcase == search_byte.downcase : haystack_byte == search_byte

          next_chunk = nil
          token_length = nil
          if haystack.getbyte(haystack_at) == AMPERSAND
            next_chunk, token_length = read_character_reference("attribute", haystack, haystack_at)
          end

          return false if next_chunk.nil? && !chars_match

          if next_chunk.nil?
            haystack_at += 1
            search_at += 1
            next
          end

          match_length = [next_chunk.bytesize, search_length - search_at].min
          expected = search_text.byteslice(search_at, match_length)
          actual = next_chunk.byteslice(0, match_length)
          if loose_case
            return false unless expected.downcase == actual.downcase
          elsif expected != actual
            return false
          end

          haystack_at += token_length
          search_at += match_length
        end

        search_at == search_length
      end

      private

      # Longest-match lookup into the frozen HTML5 table.
      #
      # The legacy uses a `WP_Token_Map` whose precomputed groups make this a two-byte
      # bucket probe; the semantics it provides — longest match wins, case-sensitive,
      # semicolon significant — are what the parser depends on, so this port keeps the
      # semantics and drops the bucket layout.
      def longest_named_reference_at(text, name_at, length)
        max = NamedCharacterReferences::MAX_LENGTH
        available = length - name_at
        max = available if available < max
        candidate = max
        while candidate >= 2
          return candidate if NamedCharacterReferences::TABLE.key?(text.byteslice(name_at, candidate))

          candidate -= 1
        end
        nil
      end

      # Legacy: class-wp-html-decoder.php:285.
      def read_numeric_character_reference(text, at, length)
        return nil if at + 2 >= length

        digits_at = at + 2
        first = text.getbyte(digits_at)
        if first == 0x78 || first == 0x58 # `x` or `X`
          numeric_base = 16
          numeric_digits = HEX_DIGITS
          max_digits = 6 # &#x10FFFF;
          digits_at += 1
        else
          numeric_base = 10
          numeric_digits = DEC_DIGITS
          max_digits = 7 # &#1114111;
        end

        zero_count = ByteScan.span(text, "0", digits_at)
        digit_count = ByteScan.span(text, numeric_digits, digits_at + zero_count)
        after_digits = digits_at + zero_count + digit_count
        has_semicolon = after_digits < length && text.getbyte(after_digits) == SEMICOLON
        end_of_span = has_semicolon ? after_digits + 1 : after_digits

        # `&#` or `&#x` without digits falls back to plaintext.
        return nil if digit_count.zero? && zero_count.zero?

        # Whereas `&#` and only zeros is invalid.
        return [REPLACEMENT_CHARACTER, end_of_span - at] if digit_count.zero?

        # Too many digits to be a valid code point; not worth parsing.
        return [REPLACEMENT_CHARACTER, end_of_span - at] if digit_count > max_digits

        code_point = text.byteslice(digits_at + zero_count, digit_count).to_i(numeric_base)
        if code_point >= 0x80 && code_point <= 0x9F
          code_point = WINDOWS_1252_MAPPING[code_point - 0x80]
        end

        [code_point_to_utf8_bytes(code_point), end_of_span - at]
      end
    end
  end
end
