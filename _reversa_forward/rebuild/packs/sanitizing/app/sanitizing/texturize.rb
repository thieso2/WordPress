# frozen_string_literal: true

module Sanitizing
  # Curly quotes, dashes, ellipses and primes.
  #
  # Legacy: wptexturize(), wp-includes/formatting.php:37, with
  # wptexturize_primes() (:320) and _wptexturize_pushpop_element() (:391).
  #
  # BR-MIGRATE-295 (BR-FMT-04, ⚠️ owner override Q5): this stays a regex
  # transformation over rendered HTML, and it skips a maintained list of
  # block-level and code tags.
  # BR-MIGRATE-294 (BR-FMT-03): it runs on output, never on stored content.
  #
  # AD-01: `run_wptexturize`, `no_texturize_tags`, `no_texturize_shortcodes`,
  # `wp_spaces_regexp` and `$wp_cockneyreplace` are all extension points in the
  # legacy. Here the unfiltered defaults are the permanent behaviour, and the
  # English `_x()` translations are the only strings (the target is single-locale
  # at Wave 0; see README).
  module Texturize
    EOS = Bytes::PCRE_EOS
    SPACES = Formatting::SPACES

    OPENING_QUOTE = '&#8220;'
    CLOSING_QUOTE = '&#8221;'
    APOS = '&#8217;'
    PRIME = '&#8242;'
    DOUBLE_PRIME = '&#8243;'
    OPENING_SINGLE_QUOTE = '&#8216;'
    CLOSING_SINGLE_QUOTE = '&#8217;'
    EN_DASH = '&#8211;'
    EM_DASH = '&#8212;'

    OPEN_Q_FLAG = '<!--oq-->'
    OPEN_SQ_FLAG = '<!--osq-->'
    APOS_FLAG = '<!--apos-->'

    # wp-includes/formatting.php:106.
    NO_TEXTURIZE_TAGS = %w[pre code kbd style script tt].freeze

    # wp-includes/formatting.php:117 — the cockney autocorrect pairs.
    COCKNEY = "'tain't,'twere,'twas,'tis,'twill,'til,'bout,'nuff,'round,'cause,'em".split(',').freeze
    COCKNEY_REPLACE = '&#8217;tain&#8217;t,&#8217;twere,&#8217;twas,&#8217;tis,&#8217;twill,&#8217;til,&#8217;bout,&#8217;nuff,&#8217;round,&#8217;cause,&#8217;em'.split(',').freeze

    STATIC_CHARACTERS = (['...', '``', "''", ' (tm)'] + COCKNEY).freeze
    STATIC_REPLACEMENTS = (['&#8230;', OPENING_QUOTE, CLOSING_QUOTE, ' &#8482;'] + COCKNEY_REPLACE).freeze

    # wp-includes/formatting.php:155-186. Patterns copied verbatim; PCRE `\Z`
    # means "end of subject or before a final newline" and Ruby's `\Z` means
    # exactly the same, so those need no translation. `\A` likewise.
    APOS_PATTERNS = [
      [Bytes.regexp("'(\\d\\d)'(?=\\Z|[.,:;!?)}\\-\\]]|&gt;|#{SPACES})", nil), "#{APOS_FLAG}\\1#{CLOSING_SINGLE_QUOTE}"],
      [Bytes.regexp("'(\\d\\d)\"(?=\\Z|[.,:;!?)}\\-\\]]|&gt;|#{SPACES})", nil), "#{APOS_FLAG}\\1#{CLOSING_QUOTE}"],
      [Bytes.regexp("'(?=\\d\\d(?:\\Z|(?![%\\d]|[.,]\\d)))"), APOS_FLAG],
      [Bytes.regexp("(?<=\\A|#{SPACES})'(\\d[.,\\d]*)'"), "#{OPEN_SQ_FLAG}\\1#{CLOSING_SINGLE_QUOTE}"],
      # `[` is literal inside a PCRE character class; Onigmo reads it as the start
      # of a *nested* class (it supports class set operations), so it must be
      # escaped. Same language, different metacharacter set.
      [Bytes.regexp("(?<=\\A|[(\\[{\"\\-]|&lt;|#{SPACES})'"), OPEN_SQ_FLAG],
      [Bytes.regexp("(?<!#{SPACES})'(?!\\Z|[.,:;!?\"'(){}\\[\\]\\-]|&[lg]t;|#{SPACES})"), APOS_FLAG]
    ].freeze

    QUOTE_PATTERNS = [
      [Bytes.regexp("(?<=\\A|#{SPACES})\"(\\d[.,\\d]*)\""), "#{OPEN_Q_FLAG}\\1#{CLOSING_QUOTE}"],
      [Bytes.regexp("(?<=\\A|[(\\[{\\-]|&lt;|#{SPACES})\"(?!#{SPACES})"), OPEN_Q_FLAG]
    ].freeze

    # wp-includes/formatting.php:199-204. ⚠️ PCRE→Onigmo: the legacy writes `^`
    # and `$` here, not `\A`/`\Z`, and with no `/m` those mean start- and
    # end-of-subject. Ruby's `^`/`$` are LINE anchors, so a literal copy would
    # convert " -- " on any line, not just at the ends of the chunk. `\A` and
    # #{EOS} restore the PCRE meaning.
    DASH_PATTERNS = [
      [/---/n, EM_DASH],
      [Bytes.regexp("(?<=\\A|#{SPACES})--(?=#{EOS}|#{SPACES})"), EM_DASH],
      [Bytes.regexp('(?<!xn)--'), EN_DASH],
      [Bytes.regexp("(?<=\\A|#{SPACES})-(?=#{EOS}|#{SPACES})"), EN_DASH]
    ].freeze

    # wp-includes/formatting.php:288 — "9x9 (times), but never 0x9999".
    # ⚠️ PCRE→Onigmo: `(?(?<=0)A|B)` is an *assertion* conditional. Onigmo only
    # implements the numbered form `(?(1)A|B)`, so the mechanical equivalent
    # `(?:(?<=0)A|(?<!0)B)` is used. The two branches are mutually exclusive on
    # every input, exactly as the conditional made them.
    TIMES_DETECT = /(?<=\d)x\d/n
    TIMES_PATTERN = Bytes.regexp('\b(\d(?:(?<=0)[\d.,]+|(?<!0)[\d.,]*))x(\d[\d.,]*)\b')

    # wp-includes/formatting.php:238 — "Replace each & with &#038; unless it
    # already looks like an entity."
    BARE_AMPERSAND = Bytes.regexp('&(?!#(?:\d+|x[a-f0-9]+);|[a-z1-4]{1,8};)', Regexp::IGNORECASE)

    # wp-includes/formatting.php:697 — _get_wptexturize_split_regex(). The PCRE
    # assertion conditional is rewritten the same way as in
    # Formatting::HTML_SPLIT_REGEX.
    SPLIT_REGEX = Bytes.regexp("(<(?:(?=!--)#{Formatting::COMMENT_BODY}|(?!!--)[^>]*>?))")

    module_function

    # BR-MIGRATE-295 (BR-FMT-04) — Legacy: wptexturize(), wp-includes/formatting.php:37.
    def wptexturize(text)
      text = Bytes.binary(text)
      return Bytes.utf8(text) if text.empty?

      no_texturize_tags_stack = []

      # ⚠️ The legacy also tracks a shortcode stack, driven by $shortcode_tags.
      # There is no shortcode registry in this pack, so `found_shortcodes` is
      # permanently false — see README, "Not ported".
      textarr = Formatting.php_preg_split_delim_capture(SPLIT_REGEX, text).reject(&:empty?)

      textarr.map! do |curl|
        first = curl[0]

        if first == '<'.b
          next curl if curl.start_with?('<!--'.b)

          curl = curl.gsub(BARE_AMPERSAND, '&#038;'.b)
          pushpop_element(curl, no_texturize_tags_stack, NO_TEXTURIZE_TAGS)
          next curl
        end

        next curl if Kses.php_trim(curl).empty?
        next curl unless no_texturize_tags_stack.empty?

        STATIC_CHARACTERS.each_with_index do |needle, i|
          curl = curl.gsub(Bytes.binary(needle), Bytes.binary(STATIC_REPLACEMENTS[i]))
        end

        if curl.include?("'".b)
          APOS_PATTERNS.each { |pattern, replacement| curl = curl.gsub(pattern, Bytes.binary(replacement)) }
          curl = primes(curl, "'", PRIME, OPEN_SQ_FLAG, CLOSING_SINGLE_QUOTE)
          curl = curl.gsub(Bytes.binary(APOS_FLAG), Bytes.binary(APOS))
          curl = curl.gsub(Bytes.binary(OPEN_SQ_FLAG), Bytes.binary(OPENING_SINGLE_QUOTE))
        end

        if curl.include?('"'.b)
          QUOTE_PATTERNS.each { |pattern, replacement| curl = curl.gsub(pattern, Bytes.binary(replacement)) }
          curl = primes(curl, '"', DOUBLE_PRIME, OPEN_Q_FLAG, CLOSING_QUOTE)
          curl = curl.gsub(Bytes.binary(OPEN_Q_FLAG), Bytes.binary(OPENING_QUOTE))
        end

        if curl.include?('-'.b)
          DASH_PATTERNS.each { |pattern, replacement| curl = curl.gsub(pattern, Bytes.binary(replacement)) }
        end

        if TIMES_DETECT.match?(curl)
          curl = curl.gsub(TIMES_PATTERN) { "#{Regexp.last_match(1)}&#215;#{Regexp.last_match(2)}".b }
        end

        curl.gsub(BARE_AMPERSAND, '&#038;'.b)
      end

      Bytes.utf8(textarr.join)
    end

    # Legacy: wptexturize_primes(), wp-includes/formatting.php:320.
    def primes(haystack, needle, prime, open_quote, close_quote)
      needle = Bytes.binary(needle)
      prime = Bytes.binary(prime)
      open_quote = Bytes.binary(open_quote)
      close_quote = Bytes.binary(close_quote)
      flag = '<!--wp-prime-or-quote-->'.b

      quote_pattern = Bytes.regexp("#{Regexp.escape(needle)}(?=\\Z|[.,:;!?)}\\-\\]]|&gt;|#{SPACES})")
      prime_pattern = Bytes.regexp("(?<=\\d)#{Regexp.escape(needle)}")
      flag_after_digit = Bytes.regexp("(?<=\\d)#{Regexp.escape(flag)}")
      flag_no_digit = Bytes.regexp("(?<!\\d)#{Regexp.escape(flag)}")

      sentences = haystack.split(open_quote, -1)

      sentences = sentences.each_with_index.map do |sentence, key|
        next sentence unless sentence.include?(needle)

        if key != 0 && sentence.scan(close_quote).length.zero?
          count = sentence.scan(quote_pattern).length
          sentence = sentence.gsub(quote_pattern, flag)

          if count > 1
            # "This sentence appears to have multiple closing quotes.
            #  Attempt Vulcan logic."
            count2 = sentence.scan(flag_no_digit).length
            sentence = sentence.gsub(flag_no_digit, close_quote)

            if count2.zero?
              count2 = sentence.scan(flag + '.'.b).length
              pos = if count2.positive?
                      sentence.rindex(flag + '.'.b)
                    else
                      sentence.rindex(flag)
                    end
              sentence = sentence[0, pos].to_s + close_quote + sentence[(pos + flag.bytesize)..].to_s
            end

            sentence = sentence.gsub(prime_pattern, prime)
            sentence = sentence.gsub(flag_after_digit, prime)
            sentence = sentence.gsub(flag, close_quote)
          elsif count == 1
            # "Found only one closing quote candidate, so give it priority over primes."
            sentence = sentence.gsub(flag, close_quote)
            sentence = sentence.gsub(prime_pattern, prime)
          else
            sentence = sentence.gsub(prime_pattern, prime)
          end
        else
          sentence = sentence.gsub(prime_pattern, prime)
          sentence = sentence.gsub(quote_pattern, close_quote)
        end

        if needle == '"'.b && sentence.include?('"'.b)
          sentence = sentence.gsub('"'.b, close_quote)
        end

        sentence
      end

      sentences.join(open_quote)
    end

    # Legacy: _wptexturize_pushpop_element(), wp-includes/formatting.php:391.
    def pushpop_element(text, stack, disabled_elements)
      if text[1] && text[1] != '/'.b
        opening_tag = true
        name_offset = 1
      elsif stack.empty?
        return
      else
        opening_tag = false
        name_offset = 2
      end

      # PHP: `$space = -1` then `substr($text, $name_offset, -1)`, i.e. "everything
      # but the final `>`" — a negative length, not an index.
      space = text.index(' '.b)
      tag = if space.nil?
              text[name_offset..-2].to_s
            else
              text[name_offset, space - name_offset].to_s
            end

      return unless disabled_elements.include?(tag.dup.force_encoding(Encoding::UTF_8))

      if opening_tag
        stack.push(tag)
      elsif stack.last == tag
        stack.pop
      end
    end
  end
end
