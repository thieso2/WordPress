# frozen_string_literal: true

module Sanitizing
  # KSES: the allowlist HTML filter.
  #
  # Legacy: wp-includes/kses.php (3,158 lines), kses 0.2.2 by Ulf Harnhammar.
  #
  # ⚠️ Owner override 2 / RISK-005 / finding F-KSES-05. Question Q5 proposed
  # migrating this off regular expressions; the owner ruled that the regex
  # implementation be reproduced faithfully. Every pattern below is the PHP
  # pattern body copied verbatim, with only the anchor and modifier translations
  # that PCRE→Onigmo *requires* — each of those is called out at its site and
  # catalogued in README.md. Do not "tidy" a regex here.
  #
  # AD-01 (paradigm_decision.md option 1): there is no hook system, so
  # `pre_kses`, `wp_kses_allowed_html`, `wp_kses_uri_attributes`,
  # `safe_style_css` and `safecss_filter_attr_allow_css` have no analogue. What
  # the unfiltered legacy produces is what this module produces, permanently.
  module Kses
    # PCRE `$` (no /m) — see Sanitizing::Bytes::PCRE_EOS.
    EOS = Bytes::PCRE_EOS

    # wp-includes/kses.php:1288 — wp_kses_split()'s token pattern, /x.
    # PCRE→Onigmo: the two `$` alternatives become #{EOS}. Ruby's `$` matches at
    # every line end, so a `<!--` followed by a newline would tokenize
    # differently and a comment could be split into a tag-like span.
    SPLIT_PATTERN = Bytes.regexp(<<~REGEX, Regexp::EXTENDED)
      (                      # Detect comments of various flavors before attempting to find tags.
      	(<!--.*?(-->|#{EOS}))   #  - Normative HTML comments.
      	|
      	</[^a-zA-Z][^>]*>  #  - Closing tags with invalid tag names.
      	|
      	<![^>]*>           #  - Invalid markup declaration nodes. Not all invalid nodes
      	                   #    are matched so as to avoid breaking legacy behaviors.
      )
      |
      (<[^>]*(>|#{EOS})|>)        # Tag-like spans of text.
    REGEX

    # wp-includes/kses.php:1428 — the bogus-comment state test. `^`/`$` in the
    # legacy mean whole-subject; `\A`/#{EOS} say so in Ruby.
    BOGUS_COMMENT = Bytes.regexp("\\A(?:</[^a-zA-Z][^>]*>|<![a-z][^>]*>)#{EOS}")

    # wp-includes/kses.php:1459 — "It's seriously malformed."
    ELEMENT_PATTERN = Bytes.regexp("\\A<\\s*(/\\s*)?([a-zA-Z0-9-]+)([^>]*)>?#{EOS}")

    # wp-includes/kses.php:2100 — BR-KSES-06: repair truncated colon entities.
    TRUNCATED_COLON = Bytes.regexp('(&#0*58(?![;0-9])|&#x0*3a(?![;a-f0-9]))', Regexp::IGNORECASE)

    # wp-includes/kses.php:2101 — BR-KSES-05: the colon, four ways.
    COLON_SPLIT = Bytes.regexp('(?:\\:|&#0*58;|&#x0*3a;|&colon;)', Regexp::IGNORECASE)

    # wp-includes/kses.php:2019 — control characters that are never legal.
    CONTROL_CHARACTERS = Bytes.regexp('[\x00-\x08\x0B\x0C\x0E-\x1F]')

    # wp-includes/kses.php:2113 — `-$` at the end of a comment body.
    TRAILING_DASH = Bytes.regexp("-#{EOS}")

    # wp-includes/kses.php:1528 — the closing XHTML slash.
    XHTML_SLASH = Bytes.regexp("\\s*/\\s*#{EOS}")

    # wp-includes/kses.php:1635 — `data-*` wildcard attribute names.
    DATA_ATTRIBUTE = Bytes.regexp("\\Adata-[a-z0-9_-]+#{EOS}")

    # wp-includes/kses.php:1906 — the maxval/minval integer shape.
    NUMERIC_VALUE = Bytes.regexp("\\A\\s{0,6}[0-9]{1,6}\\s{0,6}#{EOS}")

    # wp-includes/kses.php:2083 — wp_kses_html_error()'s pattern.
    HTML_ERROR = Bytes.regexp("\\A(\"[^\"]*(\"|#{EOS})|'[^']*('|#{EOS})|\\S)*\\s*")

    module_function

    # BR-MIGRATE-298 (BR-KSES-01) — the allowlist entry point.
    # Legacy: wp_kses(), wp-includes/kses.php:961.
    #
    # ⚠️ RISK-008 / implication 6: the legacy comment says "expects unslashed
    # data" and wp_magic_quotes() had already slashed every superglobal by the
    # time this ran. Rails params are never slashed, so callers hand us the raw
    # string and there is deliberately no unslash pass here.
    def wp_kses(content, allowed_html, allowed_protocols = nil)
      allowed_protocols = Tables::ALLOWED_PROTOCOLS if allowed_protocols.nil? || allowed_protocols.empty?

      content = wp_kses_no_null(content, slash_zero: 'keep')
      content = wp_kses_normalize_entities(content)
      content = wp_kses_hook(content, allowed_html, allowed_protocols)

      Bytes.utf8(wp_kses_split(content, allowed_html, allowed_protocols))
    end

    # Legacy: wp_kses_post(), wp-includes/kses.php:2501.
    def wp_kses_post(data)
      wp_kses(data, 'post')
    end

    # BR-MIGRATE-306 (BR-KSES-09) — the 'data' context (comments, most fields).
    # Legacy: wp_kses_data(), wp-includes/kses.php:2434.
    def wp_kses_data(data)
      wp_kses(data, 'data')
    end

    # Legacy: wp_filter_nohtml_kses(), wp-includes/kses.php:2530. The legacy
    # unslashes, filters with the empty allowlist and re-slashes; without magic
    # quotes only the middle step survives (RISK-008).
    def wp_filter_nohtml_kses(data)
      wp_kses(data, 'strip')
    end

    # Legacy: wp_kses_hook(), wp-includes/kses.php:1233 — the `pre_kses` filter.
    #
    # AD-01 removes the filter, but two of its listeners are core defaults
    # registered in wp-includes/default-filters.php:307-308 rather than plugin
    # behaviour, so they are inlined here as fixed pipeline steps:
    #   * wp_pre_kses_less_than() — ported, see Formatting.
    #   * wp_pre_kses_block_attributes() — NOT ported; it calls
    #     filter_block_content(), i.e. the block parser, which is not in this
    #     pack. Documented in README as a known divergence.
    def wp_kses_hook(content, _allowed_html, _allowed_protocols)
      Formatting.wp_pre_kses_less_than(content)
    end

    # BR-MIGRATE-306 (BR-KSES-09) — allowlists are context-specific: post, strip,
    # data, entities, user_description, pre_user_description.
    # Legacy: wp_kses_allowed_html(), wp-includes/kses.php:1063.
    def wp_kses_allowed_html(context = '')
      return context if context.is_a?(Hash)

      case context.to_s
      when 'post'
        Tables::ALLOWED_POST_TAGS
      when 'user_description', 'pre_term_description', 'pre_user_description'
        tags = deep_dup(Tables::ALLOWED_TAGS)
        tags['a']['rel'] = true
        tags['a']['target'] = true
        tags
      when 'strip'
        {}
      when 'entities'
        Tables::ALLOWED_ENTITY_NAMES
      else # 'data' and everything else
        Tables::ALLOWED_TAGS
      end
    end

    # Legacy: wp_kses_split(), wp-includes/kses.php:1278.
    # The legacy passes state through the `$pass_allowed_html` /
    # `$pass_allowed_protocols` globals purely because preg_replace_callback took
    # a function name; a block closes over them instead, which is the same value.
    def wp_kses_split(content, allowed_html, allowed_protocols)
      Bytes.binary(content).gsub(SPLIT_PATTERN) do |match|
        wp_kses_split2(match, allowed_html, allowed_protocols)
      end
    end

    # Legacy: wp_kses_split2(), wp-includes/kses.php:1395.
    def wp_kses_split2(content, allowed_html, allowed_protocols)
      content = wp_kses_stripslashes(content)

      # Not a syntax token: a plaintext greater-than sign.
      return '&gt;'.b unless content.start_with?('<'.b)

      # Bogus comment state: everything up to the nearest `>` becomes a comment.
      if BOGUS_COMMENT.match?(content)
        opener = content[1]
        inner = content[2..-2].to_s

        loop do
          prev = inner
          inner = Bytes.binary(wp_kses(inner, allowed_html, allowed_protocols))
          break if prev == inner
        end

        return "<#{opener}#{inner}>".b
      end

      # Normative HTML comments parse differently from tags.
      if content.start_with?('<!--'.b)
        inner = content.gsub('<!--'.b, ''.b).gsub('-->'.b, ''.b)

        loop do
          newstring = Bytes.binary(wp_kses(inner, allowed_html, allowed_protocols))
          break if newstring == inner

          inner = newstring
        end

        return ''.b if inner.empty?

        # Prevent multiple dashes in comments.
        inner = inner.gsub(/--+/n, '-'.b)
        # Prevent three dashes closing a comment. PCRE `-$` also matches before a
        # subject-final newline; Ruby's `$` would match before *any* newline.
        inner = inner.sub(TRAILING_DASH, ''.b)

        return "<!--#{inner}-->".b
      end

      matches = ELEMENT_PATTERN.match(content)
      return ''.b if matches.nil?

      # preg_replace_callback gives '' for a non-participating group, Ruby gives
      # nil — hence the `.to_s`. This is one of the four PCRE/Onigmo differences
      # handoff.md calls out.
      slash = matches[1].to_s.strip
      elem = matches[2].to_s
      attrlist = matches[3].to_s

      allowed_html = wp_kses_allowed_html(allowed_html) unless allowed_html.is_a?(Hash)

      # They are using a not allowed HTML element.
      return ''.b unless allowed_html.key?(elem.downcase)

      # No attributes are allowed for closing elements.
      return "</#{elem}>".b unless slash.empty?

      wp_kses_attr(elem, attrlist, allowed_html, allowed_protocols)
    end

    # Legacy: wp_kses_attr(), wp-includes/kses.php:1522.
    def wp_kses_attr(element, attr, allowed_html, allowed_protocols)
      allowed_html = wp_kses_allowed_html(allowed_html) unless allowed_html.is_a?(Hash)

      # Is there a closing XHTML slash at the end of the attributes?
      xhtml_slash = XHTML_SLASH.match?(attr) ? ' /'.b : ''.b

      element_low = element.downcase
      limits = allowed_html[element_low]
      return "<#{element}#{xhtml_slash}>".b if limits.nil? || limits == true || (limits.respond_to?(:empty?) && limits.empty?)

      attrarr = wp_kses_hair(attr, allowed_protocols)

      required_attrs = limits.select { |_k, v| v.is_a?(Hash) && v['required'] == true }

      # A required-attribute failure can strip a self-closing tag entirely, but a
      # non-self-closing tag only loses its attributes: KSES cannot find the
      # matching closing tag.
      stripped_tag = xhtml_slash.empty? ? "<#{element}>".b : ''.b

      attr2 = +''.b
      attrarr.each do |arreach|
        required = required_attrs.key?(arreach[:name].downcase)

        checked = wp_kses_attr_check(arreach, arreach[:vless], element, allowed_html)
        if checked
          attr2 << ' '.b << arreach[:whole]
          required_attrs.delete(arreach[:name].downcase) if required
        elsif required
          return stripped_tag
        end
      end

      return stripped_tag unless required_attrs.empty?

      attr2 = attr2.gsub(/[<>]/n, ''.b)

      "<#{element}#{attr2}#{xhtml_slash}>".b
    end

    # Legacy: wp_kses_attr_check(), wp-includes/kses.php:1604. PHP takes `$name`,
    # `$value` and `$whole` by reference; the Ruby takes the mutable attribute
    # hash instead, which is the same three slots.
    def wp_kses_attr_check(arreach, vless, element, allowed_html)
      name_low = arreach[:name].downcase
      element_low = element.downcase

      unless allowed_html.key?(element_low)
        return clear_attribute(arreach)
      end

      allowed_attr = allowed_html[element_low]
      allowed_attr = {} unless allowed_attr.is_a?(Hash)

      limits = allowed_attr[name_low]
      if limits.nil? || limits == ''
        # Allow `data-*` attributes. The name may only contain A-Za-z0-9_-.
        if name_low.start_with?('data-'.b) && allowed_attr['data-*'] &&
           DATA_ATTRIBUTE.match?(name_low)
          limits = allowed_attr['data-*']
        else
          return clear_attribute(arreach)
        end
      end

      if name_low == 'style'.b
        decoded_value = HtmlDecoder.decode_attribute(arreach[:value])
        new_value = Css.safecss_filter_attr(decoded_value)

        return clear_attribute(arreach) if new_value.nil? || new_value.empty?

        if new_value != decoded_value
          encoded_value = Bytes.binary(Formatting.esc_attr(new_value))
          arreach[:whole] = arreach[:whole].gsub(arreach[:value], encoded_value) unless arreach[:value].empty?
          arreach[:value] = encoded_value
        end
      end

      if limits.is_a?(Hash)
        limits.each do |currkey, currval|
          unless wp_kses_check_attr_val(arreach[:value], vless, currkey, currval)
            return clear_attribute(arreach)
          end
        end
      end

      true
    end

    # BR-MIGRATE-298 (BR-KSES-01) — attribute list parsing.
    # Legacy: wp_kses_hair(), wp-includes/kses.php:1708.
    def wp_kses_hair(attr, allowed_protocols)
      syntax_characters = {
        '&'.b => '&amp;'.b,
        '<'.b => '&lt;'.b,
        '>'.b => '&gt;'.b,
        "'".b => '&apos;'.b,
        '"'.b => '&quot;'.b
      }

      AttributeParser.parse(attr).map do |name, value|
        is_bool = value == true
        if !is_bool && Tables::URI_ATTRIBUTES.include?(name)
          value = wp_kses_bad_protocol(value, allowed_protocols)
        end

        recoded = is_bool ? ''.b : value.gsub(/[&<>'"]/n) { |c| syntax_characters[c] }
        whole = is_bool ? name.dup : %(#{name}="#{recoded}").b

        { name: name, value: recoded, whole: whole, vless: is_bool ? 'y' : 'n' }
      end
    end

    # Legacy: wp_kses_check_attr_val(), wp-includes/kses.php:1872.
    def wp_kses_check_attr_val(value, vless, checkname, checkvalue)
      case checkname.to_s.downcase
      when 'maxlen'
        value.bytesize <= checkvalue
      when 'minlen'
        value.bytesize >= checkvalue
      when 'maxval'
        NUMERIC_VALUE.match?(value) && value.to_i <= checkvalue
      when 'minval'
        NUMERIC_VALUE.match?(value) && value.to_i >= checkvalue
      when 'valueless'
        checkvalue.to_s.downcase == vless
      when 'values'
        checkvalue.include?(value.downcase)
      when 'value_callback'
        # AD-01: the legacy calls a named PHP function here. The only core use is
        # _wp_kses_allow_pdf_objects() on <object data>, which needs
        # wp_upload_dir() — site state this leaf pack cannot see. Documented as a
        # divergence in README; failing closed is the safe direction.
        false
      else
        true
      end
    end

    # BR-MIGRATE-298 (BR-KSES-01) — protocol filtering, applied repeatedly so
    # `javascript:javascript:alert(1)` cannot survive.
    # Legacy: wp_kses_bad_protocol(), wp-includes/kses.php:1983.
    def wp_kses_bad_protocol(content, allowed_protocols)
      content = wp_kses_no_null(content)

      # Short-circuit for the two common cases.
      if (content.start_with?('https://'.b) && allowed_protocols.include?('https')) ||
         (content.start_with?('http://'.b) && allowed_protocols.include?('http'))
        return content
      end

      iterations = 0
      original_content = content
      loop do
        original_content = content
        content = wp_kses_bad_protocol_once(content, allowed_protocols)
        iterations += 1
        break unless original_content != content && iterations < 6
      end

      return ''.b if original_content != content

      content
    end

    # BR-MIGRATE-303 (BR-KSES-06) truncated colon entities are repaired first;
    # BR-MIGRATE-302 (BR-KSES-05) the colon is `:`, `&#58;`, `&#x3a;`, `&colon;`;
    # BR-MIGRATE-304 (BR-KSES-07) a `feed:` prefix re-enters this function, capped
    # at two levels.
    # Legacy: wp_kses_bad_protocol_once(), wp-includes/kses.php:2099.
    def wp_kses_bad_protocol_once(content, allowed_protocols, count = 1)
      content = Bytes.binary(content)
      # BR-KSES-06. `$1;` in PHP is `\1;` in Ruby.
      content = content.gsub(TRUNCATED_COLON) { "#{Regexp.last_match(1)};".b }
      # BR-KSES-05. preg_split(..., 2) — Ruby's String#split with a limit keeps
      # leading and trailing empty fields exactly as preg_split does.
      content2 = content.split(COLON_SPLIT, 2)

      if content2.length > 1 && !/\/\?/n.match?(content2[0])
        content = php_trim(content2[1])
        protocol = wp_kses_bad_protocol_once2(content2[0], allowed_protocols)
        if protocol == 'feed:'.b
          # BR-KSES-07: cap at two levels.
          return ''.b if count > 2

          count += 1
          content = wp_kses_bad_protocol_once(content, allowed_protocols, count)
          return content if content.nil? || content.empty?
        end
        content = protocol + content
      end

      content
    end

    # BR-MIGRATE-301 (BR-KSES-04) — scheme normalisation is exactly four steps,
    # in this order: decode entities, strip whitespace, remove nulls, lowercase.
    # BR-MIGRATE-305 (BR-KSES-08) — a disallowed scheme yields '', which leaves
    # the URL schemeless rather than passing it through.
    # Legacy: wp_kses_bad_protocol_once2(), wp-includes/kses.php:2136.
    def wp_kses_bad_protocol_once2(scheme, allowed_protocols)
      scheme = wp_kses_decode_entities(scheme) # 1. decode entities
      scheme = scheme.gsub(/\s/n, ''.b)        # 2. strip whitespace
      scheme = wp_kses_no_null(scheme)         # 3. remove nulls
      scheme = scheme.downcase                 # 4. lowercase

      allowed = allowed_protocols.any? { |protocol| protocol.downcase.b == scheme }

      allowed ? "#{scheme}:".b : ''.b
    end

    # Legacy: wp_kses_no_null(), wp-includes/kses.php:2019.
    def wp_kses_no_null(content, slash_zero: 'remove')
      content = Bytes.binary(content).gsub(CONTROL_CHARACTERS, ''.b)
      content = content.gsub(/\\+0+/n, ''.b) if slash_zero == 'remove'
      content
    end

    # Legacy: wp_kses_stripslashes(), wp-includes/kses.php:2043.
    #
    # ⚠️ RISK-008. This changes `\"` to `"` and is a leftover of the days of
    # preg_replace(//e). It is NOT an unslash pass and is NOT compensating for
    # wp_magic_quotes(): it runs inside wp_kses_split2() on every token in the
    # legacy too, slashed input or not. Removing it would diverge, so it stays.
    def wp_kses_stripslashes(content)
      Bytes.binary(content).gsub(/\\"/n, '"'.b)
    end

    # Legacy: wp_kses_array_lc(), wp-includes/kses.php:2055.
    def wp_kses_array_lc(inarray)
      inarray.each_with_object({}) do |(key, val), out|
        out[key.to_s.downcase] = (val || {}).each_with_object({}) do |(k2, v2), inner|
          inner[k2.to_s.downcase] = v2
        end
      end
    end

    # Legacy: wp_kses_html_error(), wp-includes/kses.php:2082. Unreferenced in the
    # legacy since wp_kses_hair() moved to the HTML API, but it is public API, so
    # it is ported. `^`/`$` are whole-subject anchors in PCRE.
    def wp_kses_html_error(attr)
      Bytes.utf8(
        Bytes.binary(attr).sub(HTML_ERROR, ''.b)
      )
    end

    # BR-MIGRATE-307 (BR-KSES-10) — every `&` becomes `&amp;`, then valid named
    # and numeric references are selectively restored.
    # Legacy: wp_kses_normalize_entities(), wp-includes/kses.php:2168.
    def wp_kses_normalize_entities(content, context = 'html')
      content = Bytes.binary(content).gsub('&'.b, '&amp;'.b)

      content = content.gsub(/&amp;#(0*[1-9][0-9]{0,6});/n) { wp_kses_normalize_entities2(Regexp.last_match(1)) }
      content = content.gsub(/&amp;#[Xx](0*[1-9A-Fa-f][0-9A-Fa-f]{0,5});/n) { wp_kses_normalize_entities3(Regexp.last_match(1)) }
      content = if context == 'xml'
                  content.gsub(/&amp;([A-Za-z]{2,8}[0-9]{0,2});/n) { wp_kses_xml_named_entities(Regexp.last_match(1)) }
                else
                  content.gsub(/&amp;([A-Za-z]{2,8}[0-9]{0,2});/n) { wp_kses_named_entities(Regexp.last_match(1)) }
                end

      content
    end

    # Legacy: wp_kses_named_entities(), wp-includes/kses.php:2228.
    def wp_kses_named_entities(name)
      return ''.b if name.nil? || name.empty?

      Tables::ALLOWED_ENTITY_NAMES.include?(name) ? "&#{name};".b : "&amp;#{name};".b
    end

    # Legacy: wp_kses_xml_named_entities(), wp-includes/kses.php:2254.
    def wp_kses_xml_named_entities(name)
      return ''.b if name.nil? || name.empty?

      return "&#{name};".b if Tables::ALLOWED_XML_ENTITY_NAMES.include?(name)
      return Tables::ENTITY_MAP[name].b if Tables::ALLOWED_ENTITY_NAMES.include?(name)

      "&amp;#{name};".b
    end

    # Legacy: wp_kses_normalize_entities2(), wp-includes/kses.php:2285.
    def wp_kses_normalize_entities2(digits)
      return ''.b if digits.nil? || digits.empty?

      if valid_unicode?(digits.to_i)
        "&##{digits.sub(/\A0+/n, '').rjust(3, '0')};".b
      else
        "&amp;##{digits};".b
      end
    end

    # Legacy: wp_kses_normalize_entities3(), wp-includes/kses.php:2315.
    def wp_kses_normalize_entities3(hexchars)
      return ''.b if hexchars.nil? || hexchars.empty?

      if valid_unicode?(hexchars.to_i(16))
        "&#x#{hexchars.sub(/\A0+/n, '')};".b
      else
        "&amp;#x#{hexchars};".b
      end
    end

    # Legacy: valid_unicode(), wp-includes/kses.php:2345.
    def valid_unicode?(codepoint)
      i = codepoint.to_i

      i == 0x9 || i == 0xA || i == 0xD ||
        (i >= 0x20 && i <= 0xD7FF) ||
        (i >= 0xE000 && i <= 0xFFFD) ||
        (i >= 0x10000 && i <= 0x10FFFF)
    end

    # BR-MIGRATE-301 (BR-KSES-04) step 1.
    # Legacy: wp_kses_decode_entities(), wp-includes/kses.php:2375.
    #
    # PHP's chr() takes its argument modulo 256, so `&#9731;` decodes to a single
    # byte, not to a snowman. Reproduced deliberately: this is what the scheme
    # comparison has always seen.
    def wp_kses_decode_entities(content)
      content = Bytes.binary(content)
      content = content.gsub(/&#([0-9]+);/n) { (Regexp.last_match(1).to_i % 256).chr }
      content.gsub(/&#[Xx]([0-9A-Fa-f]+);/n) { (Regexp.last_match(1).to_i(16) % 256).chr }
    end

    # Internal: the by-reference "clear the three slots and reject" of
    # wp_kses_attr_check(). Legacy: wp-includes/kses.php:1612.
    def clear_attribute(arreach)
      arreach[:name] = ''.b
      arreach[:value] = ''.b
      arreach[:whole] = ''.b
      false
    end

    # PHP trim()'s default character list is " \t\n\r\0\x0B" — note that it
    # includes NUL and vertical tab but NOT form feed, which Ruby's String#strip
    # does remove. Reproduced exactly.
    PHP_TRIM = Bytes.regexp("\\A[ \\t\\n\\r\\x00\\x0B]+|[ \\t\\n\\r\\x00\\x0B]+\\z")

    def php_trim(str)
      Bytes.binary(str).gsub(PHP_TRIM, ''.b)
    end

    def deep_dup(hash)
      hash.each_with_object({}) do |(k, v), out|
        out[k] = v.is_a?(Hash) ? deep_dup(v) : v
      end
    end
  end
end
