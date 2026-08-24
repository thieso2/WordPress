# frozen_string_literal: true

module Sanitizing
  # Attribute-value character reference decoding.
  #
  # Legacy: wp-includes/html-api/class-wp-html-decoder.php:186 (decode) and :258
  # (read_character_reference), reached from wp_kses_hair() (kses.php:1708) via
  # WP_HTML_Tag_Processor::get_attribute() and from wp_kses_attr_check()
  # (kses.php:1641) for the `style` attribute.
  #
  # topology_decision.md option 3 forbids this pack from depending on the `markup`
  # pack, where the HTML API lives, so the decoding that KSES needs is
  # reimplemented here. Only the part KSES can actually reach is ported; see
  # README "HTML character references".
  module HtmlDecoder
    # wp-includes/html-api/class-wp-html-decoder.php:355 — C1 controls are
    # remapped as though they had been stored in Windows-1252.
    WINDOWS_1252 = [
      0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
      0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
      0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
      0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178
    ].freeze

    REPLACEMENT = "\u{FFFD}".b

    module_function

    # BR-MIGRATE-307 (BR-KSES-10) — decodes character references in an attribute
    # value. Legacy: WP_HTML_Decoder::decode_attribute(), class-wp-html-decoder.php:163.
    def decode_attribute(text)
      decode('attribute', text)
    end

    # Legacy: WP_HTML_Decoder::decode(), class-wp-html-decoder.php:186.
    def decode(context, text)
      text = Bytes.binary(text)
      decoded = +''.b
      at = 0
      was_at = 0
      len = text.bytesize

      while at < len
        nxt = text.index('&'.b, at)
        break if nxt.nil?

        reference, token_length = read_character_reference(context, text, nxt)
        if reference
          at = nxt
          decoded << text[was_at, at - was_at]
          decoded << reference
          at += token_length
          was_at = at
          next
        end

        at += 1
      end

      return text if was_at.zero?

      decoded << text[was_at, len - was_at] if was_at < len
      decoded
    end

    # Legacy: WP_HTML_Decoder::read_character_reference(), class-wp-html-decoder.php:258.
    # Returns [replacement_bytes, byte_length] or [nil, nil].
    def read_character_reference(context, text, at)
      len = text.bytesize
      return [nil, nil] if at + 1 >= len
      return [nil, nil] unless text[at] == '&'.b

      if text[at + 1] == '#'.b
        return [nil, nil] if at + 2 >= len

        digits_at = at + 2
        if text[digits_at] == 'x'.b || text[digits_at] == 'X'.b
          base = 16
          digit_re = /\A[0-9a-fA-F]*/n
          max_digits = 6
          digits_at += 1
        else
          base = 10
          digit_re = /\A[0-9]*/n
          max_digits = 7
        end

        zero_count = text[digits_at..].to_s[/\A0*/n].to_s.length
        digit_count = text[(digits_at + zero_count)..].to_s[digit_re].to_s.length
        after_digits = digits_at + zero_count + digit_count
        has_semicolon = after_digits < len && text[after_digits] == ';'.b
        end_of_span = has_semicolon ? after_digits + 1 : after_digits

        return [nil, nil] if digit_count.zero? && zero_count.zero?
        return [REPLACEMENT, end_of_span - at] if digit_count.zero?
        return [REPLACEMENT, end_of_span - at] if digit_count > max_digits

        code_point = text[digits_at + zero_count, digit_count].to_i(base)
        if code_point >= 0x80 && code_point <= 0x9F
          code_point = WINDOWS_1252[code_point - 0x80]
        end

        return [code_point_to_utf8_bytes(code_point), end_of_span - at]
      end

      name_at = at + 1
      return [nil, nil] if name_at + 2 > len

      name = text[name_at..][/\A[A-Za-z][A-Za-z0-9]{0,30};/n]
      return [nil, nil] if name.nil?

      replacement = Tables::ENTITY_MAP[name[0..-2]]
      return [nil, nil] if replacement.nil?

      after_name = name_at + name.length
      # The legacy no-semicolon forms are unreachable inside wp_kses(); see README.
      return [replacement.b, after_name - at] if context != 'attribute' || text[after_name - 1] == ';'.b

      [replacement.b, after_name - at]
    end

    # Legacy: WP_HTML_Decoder::code_point_to_utf8_bytes(), class-wp-html-decoder.php:502.
    # PHP's mb_chr() returns false for surrogates and out-of-range points, and the
    # legacy substitutes U+FFFD for them.
    def code_point_to_utf8_bytes(code_point)
      return REPLACEMENT if code_point > 0x10FFFF
      return REPLACEMENT if code_point >= 0xD800 && code_point <= 0xDFFF

      code_point.chr(Encoding::UTF_8).b
    rescue RangeError
      REPLACEMENT
    end
  end
end
