# frozen_string_literal: true

module Styling
  # Small, self-contained ports of the handful of WordPress/PHP primitives the
  # styling rules depend on. Kept private to this pack because
  # topology_decision.md option 3 forbids any cross-pack dependency, and
  # paradigm_decision.md option 1 forbids the filter hooks the originals carry
  # (`sanitize_key`, `safe_style_css`, ... are applied here as their unfiltered
  # defaults and cannot be changed).
  #
  # Pure Ruby: no Rails, no framework runtime, stdlib only.
  module PhpCompat
    module_function

    # PHP `empty()`.
    #
    # @param value [Object]
    # @return [Boolean]
    def php_empty?(value)
      case value
      when nil, false then true
      when true then false
      when String then value.empty? || value == '0'
      when Integer then value.zero?
      when Float then value.zero?
      when Array, Hash then value.empty?
      else false
      end
    end

    # PHP `is_scalar()` — int, float, string, bool (NOT null, array, object).
    #
    # @param value [Object]
    # @return [Boolean]
    def php_scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
    end

    # PHP `is_numeric()` for the value shapes theme.json can carry.
    #
    # @param value [Object]
    # @return [Boolean]
    def php_numeric?(value)
      return true if value.is_a?(Numeric) && !value.is_a?(Complex)
      return false unless value.is_a?(String)

      !!(value.strip =~ /\A[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\z/)
    end

    # PHP `(string)` cast. Differs from Ruby's `to_s` for floats with an
    # integral value: PHP renders 1.0 as "1", Ruby as "1.0".
    #
    # @param value [Object]
    # @return [String]
    def to_php_string(value)
      case value
      when true then '1'
      when false, nil then ''
      when Float
        return value.to_i.to_s if value.finite? && value == value.to_i

        value.to_s
      else value.to_s
      end
    end

    # PHP strings are byte arrays and its regexes here carry no /u modifier, so
    # invalid UTF-8 flows through unharmed. Ruby regexes raise on it, so a
    # byte-invalid string is re-tagged BINARY for the duration of the operation
    # and re-tagged UTF-8 on the way out — same bytes, same result.
    #
    # @param str [String]
    # @return [String]
    def as_bytes(str)
      str.valid_encoding? ? str : str.dup.force_encoding(Encoding::BINARY)
    end

    # @param str [String]
    # @return [String]
    def as_text(str)
      str.encoding == Encoding::BINARY ? str.dup.force_encoding(Encoding::UTF_8) : str
    end

    # Port of `sanitize_key()` — wp-includes/formatting.php:2191.
    # The `sanitize_key` filter is deliberately absent (paradigm option 1).
    #
    # @param key [Object]
    # @return [String]
    def sanitize_key(key)
      return '' unless php_scalar?(key)

      as_text(as_bytes(to_php_string(key)).downcase.gsub(/[^a-z0-9_\-]/, ''))
    end

    # Port of `wp_strip_all_tags()` — wp-includes/formatting.php:5610.
    #
    # @param text [Object]
    # @param remove_breaks [Boolean]
    # @return [String]
    def strip_all_tags(text, remove_breaks = false)
      return '' if text.nil?
      return '' unless php_scalar?(text)

      out = as_bytes(to_php_string(text))
      out = out.gsub(%r{<(script|style)[^>]*?>.*?</\1>}mi, '')
      out = strip_tags(out)
      out = out.gsub(/[\r\n\t ]+/, ' ') if remove_breaks
      as_text(php_trim(out))
    end

    # PHP `trim()` default charlist: " \t\n\r\0\x0B".
    #
    # @param str [String]
    # @return [String]
    def php_trim(str)
      as_bytes(str).gsub(/\A[ \t\n\r\0\x0B]+/, '').gsub(/[ \t\n\r\0\x0B]+\z/, '')
    end

    # PHP `strip_tags()`, restricted to the shapes CSS values can take.
    #
    # @param str [String]
    # @return [String]
    def strip_tags(str)
      as_bytes(str).gsub(/<!--.*?-->/m, '').gsub(/<[^>]*>?/m, '')
    end

    # Port of `_wp_array_get()` — wp-includes/functions.php.
    #
    # @param data [Object]
    # @param path [Array]
    # @param default_value [Object]
    # @return [Object]
    def array_get(data, path, default_value = nil)
      return default_value unless path.is_a?(Array) && !path.empty?

      cursor = data
      path.each do |key|
        return default_value unless cursor.is_a?(Hash)
        return default_value unless cursor.key?(key)

        cursor = cursor[key]
      end
      cursor
    end

    # Port of `_wp_array_set()` — wp-includes/functions.php. Mutates `data`.
    #
    # @param data [Hash]
    # @param path [Array]
    # @param value [Object]
    # @return [Hash]
    def array_set(data, path, value)
      return data unless data.is_a?(Hash) && path.is_a?(Array) && !path.empty?

      cursor = data
      path[0..-2].each do |key|
        cursor[key] = {} unless cursor[key].is_a?(Hash)
        cursor = cursor[key]
      end
      cursor[path[-1]] = value
      data
    end

    # PHP `array_replace_recursive()` for hash trees. Lists replace wholesale;
    # hashes merge key by key.
    #
    # @param base [Object]
    # @param incoming [Object]
    # @return [Object]
    def array_replace_recursive(base, incoming)
      return deep_dup(incoming) unless base.is_a?(Hash) && incoming.is_a?(Hash)

      result = deep_dup(base)
      incoming.each do |key, value|
        result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                        array_replace_recursive(result[key], value)
                      elsif result[key].is_a?(Array) && value.is_a?(Array)
                        # PHP replaces element-wise by numeric index and keeps
                        # any surplus elements of the base array.
                        merged = deep_dup(result[key])
                        value.each_with_index { |item, index| merged[index] = deep_dup(item) }
                        merged
                      else
                        deep_dup(value)
                      end
      end
      result
    end

    # @param value [Object]
    # @return [Object] a deep copy of hashes/arrays, the value itself otherwise
    def deep_dup(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), acc| acc[k] = deep_dup(v) }
      when Array then value.map { |v| deep_dup(v) }
      when String then value.dup
      else value
      end
    end

    # Character-class fragments of `_wp_to_kebab_case()`
    # (wp-includes/functions.php:5305), transcribed from PCRE `\x{..}` escapes
    # to Ruby `\u{..}` escapes.
    LOWER_RANGE  = 'a-z\u{df}-\u{f6}\u{f8}-\u{ff}'
    NON_CHAR_RANGE = '\u{0}-\u{2f}\u{3a}-\u{40}\u{5b}-\u{60}\u{7b}-\u{bf}'
    PUNCTUATION_RANGE = '\u{2000}-\u{206f}'
    SPACE_RANGE = ' \t\u{b}\f\u{a0}\u{feff}\n\r\u{2028}\u{2029}\u{1680}\u{180e}' \
                  '\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}' \
                  '\u{2008}\u{2009}\u{200a}\u{202f}\u{205f}\u{3000}'
    UPPER_RANGE = 'A-Z\u{c0}-\u{d6}\u{d8}-\u{de}'
    BREAK_RANGE = NON_CHAR_RANGE + PUNCTUATION_RANGE + SPACE_RANGE

    RS_BREAK  = "[#{BREAK_RANGE}]"
    RS_DIGITS = '\d+'
    RS_LOWER  = "[#{LOWER_RANGE}]"
    # NOTE: verbatim from lodash/WordPress — `\d+` inside a character class means
    # the `+` is a literal member of the class. Preserved on purpose.
    RS_MISC   = "[^#{BREAK_RANGE}#{RS_DIGITS}#{LOWER_RANGE}#{UPPER_RANGE}]"
    RS_UPPER  = "[#{UPPER_RANGE}]"
    RS_MISC_LOWER = "(?:#{RS_LOWER}|#{RS_MISC})"
    RS_MISC_UPPER = "(?:#{RS_UPPER}|#{RS_MISC})"
    # PHP `$` (no /D) == Ruby `\Z`: end of subject, or before a final newline.
    RS_ORD_LOWER = '\d*(?:1st|2nd|3rd|(?![123])\dth)(?=\b|[A-Z_])'
    RS_ORD_UPPER = '\d*(?:1ST|2ND|3RD|(?![123])\dTH)(?=\b|[a-z_])'

    KEBAB_REGEXP = Regexp.new(
      [
        "#{RS_UPPER}?#{RS_LOWER}+(?=#{RS_BREAK}|#{RS_UPPER}|\\Z)",
        "#{RS_MISC_UPPER}+(?=#{RS_BREAK}|#{RS_UPPER}#{RS_MISC_LOWER}|\\Z)",
        "#{RS_UPPER}?#{RS_MISC_LOWER}+",
        "#{RS_UPPER}+",
        RS_ORD_UPPER,
        RS_ORD_LOWER,
        RS_DIGITS
      ].join('|')
    ).freeze

    # Port of `_wp_to_kebab_case()` — wp-includes/functions.php:5305.
    #
    # @param input [Object]
    # @return [String]
    def to_kebab_case(input)
      return '' unless php_scalar?(input)

      value = to_php_string(input)
      # PCRE's /u modifier makes preg_match_all() bail on invalid UTF-8, and the
      # legacy then joins an empty match set. Same outcome here.
      return '' unless value.valid_encoding?

      value.delete("'").scan(KEBAB_REGEXP).join('-').downcase(:ascii)
    end
  end
end
