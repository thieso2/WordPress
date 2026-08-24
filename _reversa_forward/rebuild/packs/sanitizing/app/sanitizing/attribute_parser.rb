# frozen_string_literal: true

module Sanitizing
  # The attribute tokenizer wp_kses_hair() needs.
  #
  # Legacy: wp_kses_hair() (wp-includes/kses.php:1708) builds the synthetic tag
  # `"<wp {$attr}>"`, hands it to WP_HTML_Tag_Processor and reads the attributes
  # back. That processor lives in the `markup` pack, and topology_decision.md
  # option 3 forbids a dependency on it, so the exact subset KSES exercises is
  # reimplemented here: WP_HTML_Tag_Processor::parse_next_attribute()
  # (class-wp-html-tag-processor.php:2213), plus the incomplete-input rule in
  # next_token() (class-wp-html-tag-processor.php:1016).
  #
  # The whole algorithm is byte-oriented in the legacy (strspn/strcspn/strpos),
  # so it is byte-oriented here too. See Sanitizing::Bytes.
  module AttributeParser
    WHITESPACE = " \t\f\r\n".b
    WHITESPACE_OR_SLASH = " \t\f\r\n/".b
    NAME_TERMINATORS = "=/> \t\f\r\n".b
    UNQUOTED_TERMINATORS = "> \t\f\r\n".b

    module_function

    # BR-MIGRATE-298 (BR-KSES-01) — parses an attribute list exactly as the legacy
    # HTML API does, returning `[[lowercased_name, value_or_true], ...]` in source
    # order. Returns `[]` when the synthetic tag would not close before the end of
    # the document, which is what the legacy does: next_token() reports
    # STATE_INCOMPLETE_INPUT, get_attribute_names_with_prefix() returns null and
    # wp_kses_hair() drops every attribute.
    #
    # Legacy: wp-includes/kses.php:1708 + class-wp-html-tag-processor.php:2213.
    def parse(attr)
      html = "<wp #{Bytes.binary(attr)}>".b
      doc_length = html.bytesize
      pos = 3
      attributes = {}
      incomplete = false

      loop do
        state = parse_next_attribute(html, doc_length, pos, attributes)
        pos = state[:pos]
        incomplete = state[:incomplete]
        break unless state[:continue]
      end

      return [] if incomplete || pos >= doc_length
      return [] if html.index('>'.b, pos).nil?

      attributes.map do |comparable, token|
        [comparable, attribute_value(html, token)]
      end
    end

    # Legacy: WP_HTML_Tag_Processor::parse_next_attribute(),
    # class-wp-html-tag-processor.php:2213.
    def parse_next_attribute(html, doc_length, pos, attributes)
      skipped_length = span(html, WHITESPACE_OR_SLASH, pos)
      pos += skipped_length
      return { pos: pos, continue: false, incomplete: true } if pos >= doc_length

      # Fast path for the tag-ending `>`; also where the self-closing flag is read.
      return { pos: pos, continue: false, incomplete: false } if html[pos] == '>'.b

      # An `=` as the first byte is part of the attribute *name*.
      # https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
      name_length = if html[pos] == '='.b
                      1 + cspan(html, NAME_TERMINATORS, pos + 1)
                    else
                      cspan(html, NAME_TERMINATORS, pos)
                    end

      if name_length.zero? || pos + name_length >= doc_length
        return { pos: pos, continue: false, incomplete: false }
      end

      attribute_start = pos
      attribute_name = html[attribute_start, name_length]
      pos += name_length
      return { pos: pos, continue: false, incomplete: true } if pos >= doc_length

      pos += span(html, WHITESPACE, pos)
      return { pos: pos, continue: false, incomplete: true } if pos >= doc_length

      has_value = html[pos] == '='.b
      if has_value
        pos += 1
        pos += span(html, WHITESPACE, pos)
        return { pos: pos, continue: false, incomplete: true } if pos >= doc_length

        byte = html[pos]
        if byte == "'".b || byte == '"'.b
          value_start = pos + 1
          end_quote_at = html.index(byte, value_start) || doc_length
          value_length = end_quote_at - value_start
          attribute_end = end_quote_at + 1
          pos = attribute_end
        else
          value_start = pos
          value_length = cspan(html, UNQUOTED_TERMINATORS, value_start)
          attribute_end = value_start + value_length
          pos = attribute_end
        end
      else
        value_start = pos
        value_length = 0
        attribute_end = attribute_start + name_length
      end

      return { pos: pos, continue: false, incomplete: true } if attribute_end >= doc_length

      # The tokenizer replaces U+0000 NULL in attribute names with U+FFFD, and
      # only the first declaration of a repeated attribute is kept.
      comparable = attribute_name.gsub("\x00".b, HtmlDecoder::REPLACEMENT).downcase
      unless attributes.key?(comparable)
        attributes[comparable] = {
          name: attribute_name,
          value_start: value_start,
          value_length: value_length,
          is_true: !has_value
        }
      end

      { pos: pos, continue: true, incomplete: false }
    end

    # Legacy: WP_HTML_Tag_Processor::get_decoded_attribute_value(),
    # class-wp-html-tag-processor.php:2936.
    def attribute_value(html, token)
      return true if token[:is_true]

      raw = html[token[:value_start], token[:value_length]].to_s.dup
      raw = raw.gsub("\r\n".b, "\n".b).gsub("\r".b, "\n".b).gsub("\x00".b, HtmlDecoder::REPLACEMENT)
      HtmlDecoder.decode_attribute(raw)
    end

    # PHP strspn(): length of the initial run of bytes drawn from `set`.
    def span(html, set, offset)
      n = 0
      n += 1 while offset + n < html.bytesize && set.include?(html[offset + n])
      n
    end

    # PHP strcspn(): length of the initial run of bytes *not* in `set`.
    def cspan(html, set, offset)
      n = 0
      n += 1 while offset + n < html.bytesize && !set.include?(html[offset + n])
      n
    end
  end
end
