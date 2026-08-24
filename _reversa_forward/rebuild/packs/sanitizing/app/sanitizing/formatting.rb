# frozen_string_literal: true

module Sanitizing
  # Output escaping and text transformation.
  #
  # Legacy: wp-includes/formatting.php (6,405 lines).
  #
  # BR-MIGRATE-292 (BR-FMT-01): escaping is applied at output and chosen by
  # context; there is deliberately no single universal escaper here either.
  # BR-MIGRATE-295 (BR-FMT-04, ⚠️ override Q5): wpautop() and wptexturize() stay
  # regex transformations over rendered HTML, skipping a maintained list of
  # block-level and code tags.
  #
  # AD-01: `esc_html`, `attribute_escape`, `js_escape`, `clean_url`,
  # `sanitize_title`, `run_wptexturize`, `no_texturize_tags`,
  # `no_texturize_shortcodes` and `wp_spaces_regexp` are all filters in the
  # legacy and have no analogue here; the unfiltered default is the behaviour.
  # The one exception, called out at its site, is where WordPress core itself
  # registers the default listener in wp-includes/default-filters.php, which is
  # core behaviour rather than extension.
  module Formatting
    EOS = Bytes::PCRE_EOS

    # wp-includes/formatting.php:5960 — wp_spaces_regexp()'s unfiltered value.
    SPACES = '[\r\n\t ]|\xC2\xA0|&nbsp;'

    # wp-includes/formatting.php:486 — wpautop()'s block-element list.
    # BR-MIGRATE-295 (BR-FMT-04): "a maintained list of block-level and code tags".
    ALL_BLOCKS = '(?:table|thead|tfoot|caption|col|colgroup|tbody|tr|td|th|div|dl|dd|dt|ul|ol|li|pre|form|map|area|blockquote|address|style|p|h[1-6]|hr|fieldset|legend|section|article|aside|hgroup|header|footer|nav|figure|figcaption|details|menu|summary)'

    # wp-includes/formatting.php:626 — get_html_split_regex().
    #
    # ⚠️ PCRE→Onigmo. Two translations were forced here and neither is cosmetic:
    #
    #  1. Possessive quantifiers (`*+`) are kept verbatim — Onigmo has them and
    #     they mean the same "no backtracking into this group".
    #  2. PCRE's *assertion* conditional `(?(?=!-) A | B )` does not exist in
    #     Onigmo, which only supports the numbered form `(?(1)A|B)`. The
    #     mechanical equivalent `(?: (?=!-) A | (?!!-) B )` is used instead: for
    #     every input, exactly one branch is reachable and it is the same branch
    #     PCRE would have taken. This is a rewrite of *syntax*, not of the
    #     allowlist, and it is verified by the differential harness.
    COMMENT_BODY = '!(?:-(?!->)[^\-]*+)*+(?:-->)?'
    CDATA_BODY = '!\[CDATA\[[^\]]*+(?:\](?!\]>)[^\]]*+)*+(?:\]\]>)?'
    HTML_SPLIT_REGEX = Bytes.regexp(
      "(<(?:(?=!--|!\\[CDATA\\[)(?:(?=!-)#{COMMENT_BODY}|(?!!-)#{CDATA_BODY})|[^>]*>?))"
    )

    module_function

    # ── Escaping ────────────────────────────────────────────────────────────

    # BR-MIGRATE-292 (BR-FMT-01) — escaping for HTML blocks.
    # Legacy: esc_html(), wp-includes/formatting.php:4754.
    def esc_html(text)
      Bytes.utf8(_wp_specialchars(wp_check_invalid_utf8(text), :ent_quotes))
    end

    # BR-MIGRATE-292 (BR-FMT-01) — escaping for HTML attributes.
    # Legacy: esc_attr(), wp-includes/formatting.php:4781.
    def esc_attr(text)
      Bytes.utf8(_wp_specialchars(wp_check_invalid_utf8(text), :ent_quotes))
    end

    # BR-MIGRATE-292 (BR-FMT-01) — escaping for textarea values. Note this one
    # does NOT normalize entities first: it is a bare htmlspecialchars().
    # Legacy: esc_textarea(), wp-includes/formatting.php:4808.
    def esc_textarea(text)
      Bytes.utf8(htmlspecialchars(Bytes.binary(text), :ent_quotes, double_encode: true))
    end

    # BR-MIGRATE-292 (BR-FMT-01) — escaping for JavaScript string literals.
    # Legacy: esc_js(), wp-includes/formatting.php:4724.
    def esc_js(text)
      safe = _wp_specialchars(wp_check_invalid_utf8(text), :ent_compat)
      # PCRE `(?(1)27|39)` is a *numbered* conditional, and Onigmo supports that
      # form, so this pattern is ported character-for-character.
      safe = php_stripslashes(safe).gsub(ESC_JS_QUOTE, "'".b)
      safe = safe.gsub("\r".b, ''.b)
      Bytes.utf8(php_addslashes(safe).gsub("\n".b) { "\\n".b })
    end

    # wp-includes/formatting.php:4728.
    ESC_JS_QUOTE = Bytes.regexp('&#(x)?0*(?(1)27|39);?', Regexp::IGNORECASE)

    # BR-MIGRATE-293 (BR-FMT-02) — esc_url() encodes `&` to `&#038;` for markup.
    # Legacy: esc_url(), wp-includes/formatting.php:4551.
    def esc_url(url, protocols = nil, context = 'display')
      url = Bytes.binary(url)
      return Bytes.utf8(url) if url.empty?

      url = url.sub(/\A[ \t\n\r\0\x0B]+/n, ''.b).gsub(' '.b, '%20'.b)
      url = url.gsub(/[^a-z0-9\-~+_.?#=!&;,\/:%@$|*'()\[\]\x80-\xff]/in, ''.b)
      return Bytes.utf8(url) if url.empty?

      unless url.downcase.start_with?('mailto:'.b)
        url = _deep_replace(['%0d', '%0a', '%0D', '%0A'], url)
      end

      url = url.gsub(';//'.b, '://'.b)

      # No scheme and not relative: presume http:// (or https:// when the caller's
      # protocol list leads with https).
      if !url.include?(':'.b) && !['/'.b, '#'.b, '?'.b].include?(url[0]) &&
         !/\A[a-z0-9-]+?\.php/in.match?(url)
        scheme = (protocols.is_a?(Array) && protocols.first == 'https') ? 'https://'.b : 'http://'.b
        url = scheme + url
      end

      # BR-FMT-02: only the display context rewrites & and '.
      if context == 'display'
        url = Kses.wp_kses_normalize_entities(url)
        url = url.gsub('&amp;'.b, '&#038;'.b)
        url = url.gsub("'".b, '&#039;'.b)
      end

      # The `[`/`]` percent-encoding branch of the legacy needs wp_parse_url(),
      # i.e. PHP's parse_url(). Ported with URI-free byte arithmetic; see README.
      if url.include?('['.b) || url.include?(']'.b)
        url = percent_encode_brackets(url)
      end

      if url[0] == '/'.b
        good = url
      else
        protocols = Tables::ALLOWED_PROTOCOLS unless protocols.is_a?(Array)
        good = Kses.wp_kses_bad_protocol(url, protocols)
        return '' if good.downcase != url.downcase
      end

      Bytes.utf8(good)
    end

    # BR-MIGRATE-293 (BR-FMT-02) — esc_url_raw()/sanitize_url() do NOT encode `&`,
    # for storage and Location headers.
    # Legacy: esc_url_raw(), wp-includes/formatting.php:4669; sanitize_url(), :4691.
    def esc_url_raw(url, protocols = nil)
      esc_url(url, protocols, 'db')
    end
    def sanitize_url(url, protocols = nil)
      esc_url(url, protocols, 'db')
    end

    # Legacy: _deep_replace(), wp-includes/formatting.php:4497.
    def _deep_replace(search, subject)
      subject = Bytes.binary(subject)
      loop do
        before = subject
        search.each { |needle| subject = subject.gsub(Bytes.binary(needle), ''.b) }
        break if subject == before
      end
      subject
    end

    # Legacy: _wp_specialchars(), wp-includes/formatting.php:945.
    # Only the quote styles core uses are ported (ENT_NOQUOTES / ENT_COMPAT /
    # ENT_QUOTES / ENT_XML1); the 'single'/'double' back-compat spellings are not.
    def _wp_specialchars(text, quote_style = :ent_noquotes, double_encode: false)
      text = Bytes.binary(text)
      return ''.b if text.empty?
      return text unless /['"&<>]/n.match?(text)

      unless double_encode
        # "Guarantee every &entity; is valid, convert &garbage; into &amp;garbage;"
        text = Kses.wp_kses_normalize_entities(text, quote_style == :ent_xml1 ? 'xml' : 'html')
      end

      htmlspecialchars(text, quote_style, double_encode: double_encode)
    end

    # PHP htmlspecialchars(). The `double_encode: false` rule is PHP's: an `&`
    # that already begins a well-formed reference of the *HTML 4.01* doctype is
    # copied through untouched.
    ENTITY_START = /\A&(?:\#[0-9]+;|\#[xX][0-9a-fA-F]+;|([a-zA-Z][a-zA-Z0-9]*);)/n

    def htmlspecialchars(text, quote_style, double_encode: true)
      text = Bytes.binary(text)
      # PHP's htmlspecialchars() is called by the legacy with ENT_QUOTES alone —
      # no ENT_SUBSTITUTE — so an invalid UTF-8 sequence makes it return the
      # empty string rather than substituting U+FFFD. esc_textarea() is the only
      # caller that reaches this with unchecked bytes.
      return ''.b unless valid_utf8?(text)

      out = +''.b
      i = 0
      len = text.bytesize

      while i < len
        byte = text[i]
        case byte
        when '&'.b
          if !double_encode && (m = ENTITY_START.match(text[i..]))
            # PHP resolves the named-entity set from the doctype flag, so
            # ENT_XML1 knows `&apos;` and does not know `&nbsp;`.
            known = quote_style == :ent_xml1 ? Tables::XML1_ENTITY_NAMES : Tables::HTML401_ENTITY_NAMES
            if m[1].nil? || known.include?(m[1])
              out << m[0]
              i += m[0].bytesize
              next
            end
          end
          out << '&amp;'.b
        when '<'.b then out << '&lt;'.b
        when '>'.b then out << '&gt;'.b
        when '"'.b
          out << (quote_style == :ent_noquotes ? byte : '&quot;'.b)
        when "'".b
          # PHP folds ENT_XML1 to `ENT_QUOTES | ENT_XML1` (formatting.php:963) and
          # the XML doctype spells the apostrophe `&apos;`, not `&#039;`.
          out << case quote_style
                 when :ent_quotes then '&#039;'.b
                 when :ent_xml1 then '&apos;'.b
                 else byte
                 end
        else
          out << byte
        end
        i += 1
      end

      out
    end

    # Legacy: wp_check_invalid_utf8(), wp-includes/formatting.php:1127.
    # blog_charset is UTF-8 in the target (RISK-006: utf8mb4 → PostgreSQL text),
    # so the non-UTF-8 short-circuit is not ported.
    def wp_check_invalid_utf8(text, strip = false)
      text = Bytes.binary(text)
      return ''.b if text.empty?
      return text if valid_utf8?(text)

      strip ? scrub_utf8(text) : ''.b
    end

    def valid_utf8?(text)
      text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    def scrub_utf8(text)
      Bytes.binary(text.dup.force_encoding(Encoding::UTF_8).scrub("\u{FFFD}"))
    end

    # ── kses collaborators ──────────────────────────────────────────────────

    # Legacy: wp_pre_kses_less_than(), wp-includes/formatting.php:5273, registered
    # by core on `pre_kses` in wp-includes/default-filters.php:307. It is core's
    # own default rather than plugin behaviour, so it is inlined into
    # Kses.wp_kses_hook rather than dropped with the hook system.
    def wp_pre_kses_less_than(content)
      Bytes.binary(content).gsub(/<[^>]*?((?=<)|>|#{EOS})/n) do |match|
        match.include?('>'.b) ? match : Bytes.binary(esc_html(match))
      end
    end

    # ── Slugs and keys ──────────────────────────────────────────────────────

    # BR-MIGRATE-296 (BR-FMT-06) — sanitize_key() lowercases and restricts to
    # [a-z0-9_-]. Legacy: sanitize_key(), wp-includes/formatting.php:2191.
    def sanitize_key(key)
      return '' unless key.is_a?(String) || key.is_a?(Numeric) || key == true || key == false

      Bytes.utf8(Bytes.binary(key.to_s).downcase.gsub(/[^a-z0-9_\-]/n, ''.b))
    end

    # BR-MIGRATE-296 (BR-FMT-06) — sanitize_title() produces a URL-safe slug.
    # Legacy: sanitize_title(), wp-includes/formatting.php:2228.
    #
    # The legacy's slug shape comes from sanitize_title_with_dashes(), attached
    # to the `sanitize_title` filter by core in default-filters.php:309. As with
    # wp_pre_kses_less_than that is core's own default, so it is inlined; AD-01
    # removes only the ability to *replace* it.
    def sanitize_title(title, fallback_title = '', context = 'save')
      raw_title = title
      title = remove_accents(title) if context == 'save'
      title = sanitize_title_with_dashes(title, raw_title, context)
      title = fallback_title if title == ''
      title
    end

    def sanitize_title_for_query(title)
      sanitize_title(title, '', 'query')
    end

    # Legacy: sanitize_title_with_dashes(), wp-includes/formatting.php:2282.
    def sanitize_title_with_dashes(title, _raw_title = '', context = 'display')
      title = Bytes.binary(title)
      title = strip_tags(title)
      # Preserve escaped octets.
      title = title.gsub(/%([a-fA-F0-9][a-fA-F0-9])/n) { "---#{Regexp.last_match(1)}---".b }
      title = title.gsub('%'.b, ''.b)
      title = title.gsub(/---([a-fA-F0-9][a-fA-F0-9])---/n) { "%#{Regexp.last_match(1)}".b }

      if valid_utf8?(title)
        title = Bytes.binary(title.dup.force_encoding(Encoding::UTF_8).downcase)
        title = utf8_uri_encode(title, 200)
      end

      title = title.downcase

      if context == 'save'
        title = php_str_replace(%w[%c2%a0 %e2%80%91 %e2%80%93 %e2%80%94], '-', title)
        title = php_str_replace(['&nbsp;', '&#8209;', '&#160;', '&ndash;', '&#8211;', '&mdash;', '&#8212;'], '-', title)
        title = title.gsub('/'.b, '-'.b)
        title = php_str_replace(STRIP_ENTIRELY, '', title)
        title = php_str_replace(WIDTH_BEARING_INVISIBLES, '-', title)
        title = title.gsub('%c3%97'.b, 'x'.b)
      end

      title = title.gsub(/&.+?;/n, ''.b)
      title = title.gsub('.'.b, '-'.b)

      title = title.gsub(/[^%a-z0-9 _-]/n, ''.b)
      title = title.gsub(/\s+/n, '-'.b)
      title = title.gsub(/-+/n, '-'.b)

      Bytes.utf8(title.gsub(/\A-+|-+\z/n, ''.b))
    end

    # wp-includes/formatting.php:2306 — stripped entirely by sanitize_title_with_dashes.
    STRIP_ENTIRELY = %w[
      %c2%ad %c2%a1 %c2%bf %c2%ab %c2%bb %e2%80%b9 %e2%80%ba
      %e2%80%98 %e2%80%99 %e2%80%9c %e2%80%9d %e2%80%9a %e2%80%9b %e2%80%9e %e2%80%9f
      %e2%80%a2 %c2%a9 %c2%ae %c2%b0 %e2%80%a6 %e2%84%a2
      %c2%b4 %cb%8a %cc%81 %cd%81 %cc%80 %cc%84 %cc%8c
      %e2%80%8b %e2%80%8c %e2%80%8d %e2%80%8e %e2%80%8f
      %e2%80%aa %e2%80%ab %e2%80%ac %e2%80%ad %e2%80%ae %ef%bb%bf %ef%bf%bc
    ].freeze

    # wp-includes/formatting.php:2360 — converted to a hyphen instead.
    WIDTH_BEARING_INVISIBLES = %w[
      %e2%80%80 %e2%80%81 %e2%80%82 %e2%80%83 %e2%80%84 %e2%80%85 %e2%80%86
      %e2%80%87 %e2%80%88 %e2%80%89 %e2%80%8a %e2%80%a8 %e2%80%a9 %e2%80%af
    ].freeze

    # Legacy: remove_accents(), wp-includes/formatting.php:1611. The locale-
    # specific branches (de*, da_DK, ca, sr_RS, bs_BA) and the non-UTF-8 branch
    # are NOT ported; see README.
    def remove_accents(text)
      text = Bytes.binary(text)
      return Bytes.utf8(text) unless /[\x80-\xff]/n.match?(text)
      return Bytes.utf8(remove_accents_latin1(text)) unless valid_utf8?(text)

      utf8 = text.dup.force_encoding(Encoding::UTF_8)
      utf8 = utf8.unicode_normalize(:nfc) unless utf8.unicode_normalized?(:nfc)

      Accents::CHARS.each { |from, to| utf8 = utf8.gsub(from, to) }
      utf8
    end

    # wp-includes/formatting.php:1996 — "Assume ISO-8859-1 if not UTF-8."
    LATIN1_IN = "\x80\x83\x8a\x8e\x9a\x9e\x9f\xa2\xa5\xb5\xc0\xc1\xc2\xc3\xc4\xc5\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd1\xd2\xd3\xd4\xd5\xd6\xd8\xd9\xda\xdb\xdc\xdd\xe0\xe1\xe2\xe3\xe4\xe5\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf1\xf2\xf3\xf4\xf5\xf6\xf8\xf9\xfa\xfb\xfc\xfd\xff".b
    LATIN1_OUT = 'EfSZszYcYuAAAAAACEEEEIIIINOOOOOOUUUUYaaaaaaceeeeiiiinoooooouuuuyy'.b
    LATIN1_DOUBLE = {
      "\x8c".b => 'OE'.b, "\x9c".b => 'oe'.b, "\xc6".b => 'AE'.b, "\xd0".b => 'DH'.b,
      "\xde".b => 'TH'.b, "\xdf".b => 'ss'.b, "\xe6".b => 'ae'.b, "\xf0".b => 'dh'.b,
      "\xfe".b => 'th'.b
    }.freeze

    def remove_accents_latin1(text)
      out = +''.b
      text.each_byte do |b|
        idx = LATIN1_IN.index(b.chr)
        out << (idx ? LATIN1_OUT[idx] : b.chr)
      end
      LATIN1_DOUBLE.each { |from, to| out = out.gsub(from, to) }
      out
    end

    # Legacy: utf8_uri_encode(), wp-includes/formatting.php:1160.
    def utf8_uri_encode(utf8_string, length = 0, encode_ascii_characters = false)
      utf8_string = Bytes.binary(utf8_string)
      unicode = +''.b
      values = []
      num_octets = 1
      unicode_length = 0

      utf8_string.each_byte do |value|
        if value < 128
          char = value.chr
          encoded_char = encode_ascii_characters ? rawurlencode(char) : char
          break if length.positive? && (unicode_length + encoded_char.bytesize) > length

          unicode << encoded_char
          unicode_length += encoded_char.bytesize
        else
          if values.empty?
            num_octets = if value < 224 then 2 elsif value < 240 then 3 else 4 end
          end

          values << value

          break if length.positive? && (unicode_length + (num_octets * 3)) > length

          if values.length == num_octets
            num_octets.times { |j| unicode << format('%%%s', values[j].to_s(16)).b }
            unicode_length += num_octets * 3
            values = []
            num_octets = 1
          end
        end
      end

      unicode
    end

    # ── wpautop / wptexturize ───────────────────────────────────────────────
    # BR-MIGRATE-294 (BR-FMT-03): these run on rendered output, never on stored
    # content, which is why the database holds plain newlines.

    # BR-MIGRATE-295 (BR-FMT-04, ⚠️ override) — replaces double line breaks with
    # paragraph elements. Legacy: wpautop(), wp-includes/formatting.php:446.
    def wpautop(text, br = true)
      text = Bytes.binary(text)
      pre_tags = {}

      return '' if Kses.php_trim(text).empty?

      text = text + "\n".b

      if text.include?('<pre'.b)
        text_parts = text.split('</pre>'.b, -1)
        last_part = text_parts.pop
        text = +''.b
        i = 0

        text_parts.each do |text_part|
          start = text_part.index('<pre'.b)

          if start.nil?
            text << text_part
            next
          end

          name = "<pre wp-pre-tag-#{i}></pre>".b
          pre_tags[name] = text_part[start..] + '</pre>'.b
          text << text_part[0, start] << name
          i += 1
        end

        text << last_part
      end

      text = text.gsub(/<br\s*\/?>\s*<br\s*\/?>/n, "\n\n".b)
      text = text.gsub(/(<#{ALL_BLOCKS}[\s\/>])/n) { "\n\n#{Regexp.last_match(1)}".b }
      text = text.gsub(/(<\/#{ALL_BLOCKS}>)/n) { "#{Regexp.last_match(1)}\n\n".b }
      text = text.gsub(/(<hr\s*?\/?>)/n) { "#{Regexp.last_match(1)}\n\n".b }
      text = text.gsub("\r\n".b, "\n".b).gsub("\r".b, "\n".b)
      text = wp_replace_in_html_tags(text, "\n".b => ' <!-- wpnl --> '.b)

      if text.include?('<option'.b)
        text = text.gsub(/\s*<option/n, '<option'.b)
        text = text.gsub(/<\/option>\s*/n, '</option>'.b)
      end

      if text.include?('</object>'.b)
        text = text.gsub(/(<object[^>]*>)\s*/n) { Regexp.last_match(1) }
        text = text.gsub(/\s*<\/object>/n, '</object>'.b)
        text = text.gsub(/\s*(<\/?(?:param|embed)[^>]*>)\s*/n) { Regexp.last_match(1) }
      end

      if text.include?('<source'.b) || text.include?('<track'.b)
        text = text.gsub(/([<\[](?:audio|video)[^>\]]*[>\]])\s*/n) { Regexp.last_match(1) }
        text = text.gsub(/\s*([<\[]\/(?:audio|video)[>\]])/n) { Regexp.last_match(1) }
        text = text.gsub(/\s*(<(?:source|track)[^>]*>)\s*/n) { Regexp.last_match(1) }
      end

      if text.include?('<figcaption'.b)
        text = text.gsub(/\s*(<figcaption[^>]*>)/n) { Regexp.last_match(1) }
        text = text.gsub(/<\/figcaption>\s*/n, '</figcaption>'.b)
      end

      text = text.gsub(/\n\n+/n, "\n\n".b)

      paragraphs = text.split(/\n\s*\n/n, -1).reject(&:empty?)

      text = +''.b
      paragraphs.each { |paragraph| text << '<p>'.b << paragraph.gsub(/\A\n+|\n+\z/n, ''.b) << "</p>\n".b }

      text = text.gsub(/<p>\s*<\/p>/n, ''.b)
      text = text.gsub(/<p>([^<]+)<\/(div|address|form)>/n) { "<p>#{Regexp.last_match(1)}</p></#{Regexp.last_match(2)}>".b }
      text = text.gsub(/<p>\s*(<\/?#{ALL_BLOCKS}[^>]*>)\s*<\/p>/n) { Regexp.last_match(1) }
      text = text.gsub(/<p>(<li.+?)<\/p>/n) { Regexp.last_match(1) }
      text = text.gsub(/<p><blockquote([^>]*)>/in) { "<blockquote#{Regexp.last_match(1)}><p>".b }
      text = text.gsub('</blockquote></p>'.b, '</p></blockquote>'.b)
      text = text.gsub(/<p>\s*(<\/?#{ALL_BLOCKS}[^>]*>)/n) { Regexp.last_match(1) }
      text = text.gsub(/(<\/?#{ALL_BLOCKS}[^>]*>)\s*<\/p>/n) { Regexp.last_match(1) }

      if br
        # PCRE `/s` (dot matches newline) is Ruby's `/m` — one of the four
        # modifier translations handoff.md names.
        text = text.gsub(/<(script|style|svg|math).*?<\/\1>/mn) { |m| m.gsub("\n".b, '<WPPreserveNewline />'.b) }
        text = text.gsub('<br>'.b, '<br />'.b).gsub('<br/>'.b, '<br />'.b)
        text = text.gsub(/(?<!<br \/>)\s*\n/n, "<br />\n".b)
        text = text.gsub('<WPPreserveNewline />'.b, "\n".b)
      end

      text = text.gsub(/(<\/?#{ALL_BLOCKS}[^>]*>)\s*<br \/>/n) { Regexp.last_match(1) }
      text = text.gsub(/<br \/>(\s*<\/?(?:p|li|div|dl|dd|dt|th|pre|td|ul|ol)[^>]*>)/n) { Regexp.last_match(1) }
      text = text.sub(Bytes.regexp("\\n</p>#{EOS}"), '</p>'.b)

      pre_tags.each { |name, original| text = text.gsub(name, original) } unless pre_tags.empty?

      if text.include?('<!-- wpnl -->'.b)
        text = text.gsub(' <!-- wpnl --> '.b, "\n".b).gsub('<!-- wpnl -->'.b, "\n".b)
      end

      Bytes.utf8(text)
    end

    # Legacy: wp_html_split(), wp-includes/formatting.php:610.
    def wp_html_split(input)
      php_preg_split_delim_capture(HTML_SPLIT_REGEX, Bytes.binary(input))
    end

    # Legacy: wp_replace_in_html_tags(), wp-includes/formatting.php:757.
    def wp_replace_in_html_tags(haystack, replace_pairs)
      textarr = wp_html_split(haystack)
      changed = false

      i = 1
      while i < textarr.length
        replace_pairs.each do |needle, replacement|
          next unless textarr[i].include?(needle)

          textarr[i] = textarr[i].gsub(needle, replacement)
          changed = true
        end
        i += 2
      end

      changed ? textarr.join : Bytes.binary(haystack)
    end

    # ── helpers ─────────────────────────────────────────────────────────────

    # PHP strip_tags(). Legacy call site: sanitize_title_with_dashes(),
    # wp-includes/formatting.php:2283.
    #
    # ⚠️ This is NOT a regex in the legacy — it is php_strip_tags_ex(), a byte
    # state machine in ext/standard/string.c. A regex port such as
    # `<[^>]*>` diverges on three inputs the corpus contains: `a < b` (PHP keeps
    # a `<` followed by whitespace as text), `<b class="unterminated>x</b>`
    # (PHP tracks quotes inside the tag, so the `>` does not close it) and
    # `<!-- c <b>x</b> -->` (PHP drops the whole comment). PHP also drops NUL
    # bytes outright, which shifts utf8_uri_encode()'s 200-byte budget.
    # See README, "strip_tags".
    def strip_tags(text)
      bytes = Bytes.binary(text)
      out = +''.b
      state = 0 # 0 text, 1 tag, 2 markup declaration `<!`, 3 comment `<!--`
      in_q = nil
      depth = 0
      i = 0
      len = bytes.bytesize

      while i < len
        c = bytes[i]
        prev = i.positive? ? bytes[i - 1] : nil
        prev2 = i > 1 ? bytes[i - 2] : nil

        if c == "\x00".b
          # `case '\0': break;` — NUL never reaches the output buffer. This
          # matters: it shifts utf8_uri_encode()'s 200-byte budget downstream.
          i += 1
          next
        end

        case c
        when '<'.b
          nxt = bytes[i + 1]
          if in_q
            # inside a quoted attribute value: not a token
          elsif !nxt.nil? && WHITESPACE_BYTES.include?(nxt)
            # `isspace(*(p+1))` — `a < b` keeps its `<`. At the end of the buffer
            # that byte is the NUL terminator, which is not whitespace, so a
            # trailing `<` opens a tag: strip_tags('<') === ''.
            out << c if state.zero?
          elsif state.zero?
            state = 1
          elsif state == 1
            depth += 1
          end
        when '>'.b
          if depth.positive?
            depth -= 1
          elsif in_q
            # not a token
          elsif state == 1 || state == 2
            state = 0
          elsif state == 3
            state = 0 if prev == '-'.b && prev2 == '-'.b
          else
            out << c
          end
        when '"'.b, "'".b
          if state == 3
            # quotes are inert inside a comment
          elsif state.zero?
            out << c
          elsif in_q == c
            in_q = nil
          elsif in_q.nil?
            in_q = c
          end
        when '!'.b
          if state == 1 && prev == '<'.b
            state = 2
          elsif state.zero?
            out << c
          end
        when '-'.b
          if state == 2 && prev == '-'.b && prev2 == '!'.b
            state = 3
          elsif state.zero?
            out << c
          end
        when 'E'.b, 'e'.b
          # PHP's literal comment: `/* !DOCTYPE exception */`. On the final `E`
          # of `<!DOCTYPE`, the markup-declaration state reverts to the ordinary
          # tag state, so `<!DOCTYPE</x>y` keeps consuming past the `>`.
          if state == 2 && i >= 6 && bytes[(i - 6)..i].to_s.downcase == 'doctype'.b
            state = 1
          elsif state.zero?
            out << c
          end
        else
          out << c if state.zero?
        end

        i += 1
      end

      out
    end

    WHITESPACE_BYTES = " \t\n\r\v\f".b

    def php_str_replace(search, replace, subject)
      subject = Bytes.binary(subject)
      Array(search).each { |needle| subject = subject.gsub(Bytes.binary(needle), Bytes.binary(replace)) }
      subject
    end

    def php_stripslashes(str)
      out = +''.b
      i = 0
      bytes = Bytes.binary(str)
      len = bytes.bytesize
      while i < len
        if bytes[i] == '\\'.b
          # php_stripslashes() (PHP ext/standard/string.c) consumes the slash
          # first and only then looks for a character to preserve, so a lone
          # trailing backslash is dropped, not kept: stripslashes("a\\") === "a".
          i += 1
          break if i >= len

          out << (bytes[i] == '0'.b ? "\0".b : bytes[i])
        else
          out << bytes[i]
        end
        i += 1
      end
      out
    end

    def php_addslashes(str)
      Bytes.binary(str).gsub(/(['"\\\x00])/n) do
        c = Regexp.last_match(1)
        c == "\0".b ? '\\0'.b : ('\\'.b + c)
      end
    end

    def rawurlencode(str)
      Bytes.binary(str).gsub(/[^A-Za-z0-9\-_.~]/n) { |c| format('%%%02X', c.ord).b }
    end

    # PHP preg_split(..., PREG_SPLIT_DELIM_CAPTURE): text and delimiters
    # alternate, starting with text (possibly empty).
    def php_preg_split_delim_capture(regex, subject)
      out = []
      pos = 0
      while (m = regex.match(subject, pos))
        out << subject[pos...m.begin(0)]
        out << m[0]
        pos = m.end(0)
        pos += 1 if m.end(0) == m.begin(0)
      end
      out << subject[pos..].to_s
      out
    end

    # Legacy: the `[`/`]` branch of esc_url(), wp-includes/formatting.php:4602.
    #
    # The legacy rebuilds the "front" of the URL from wp_parse_url() (PHP's
    # parse_url()) and percent-encodes brackets only in what is left. When
    # parse_url() *fails* — it returns false for a malformed authority such as
    # `//host:notaport/` — every component is missing and the whole URL gets
    # encoded. That failure path is reachable from user input, so it is ported
    # rather than approximated.
    def percent_encode_brackets(url)
      parsed = php_parse_url(url)
      front = +''.b

      if parsed && parsed[:scheme]
        front << parsed[:scheme] << '://'.b
      elsif url[0] == '/'.b
        front << '//'.b
      end

      if parsed
        front << parsed[:user] if parsed[:user]
        front << ':'.b << parsed[:pass] if parsed[:pass]
        front << '@'.b if parsed[:user] || parsed[:pass]
        front << parsed[:host] if parsed[:host]
        front << ':'.b << parsed[:port] if parsed[:port]
      end

      end_dirty = php_str_replace_all(front, ''.b, url)
      end_clean = end_dirty.gsub('['.b, '%5B'.b).gsub(']'.b, '%5D'.b)
      php_str_replace_all(end_dirty, end_clean, url)
    end

    # PHP str_replace(): an empty search leaves the subject untouched, where
    # Ruby's gsub would splice the replacement between every character.
    def php_str_replace_all(search, replace, subject)
      return subject if search.empty?

      subject.gsub(search, replace)
    end

    # PHP parse_url(), reduced to the components esc_url() reads. Returns nil
    # where PHP returns false.
    def php_parse_url(url)
      rest = url
      scheme = nil

      if (m = /\A([a-zA-Z][a-zA-Z0-9+.\-]*):/n.match(rest))
        scheme = m[1]
        rest = rest[m.end(0)..].to_s
      end

      return { scheme: scheme } unless rest.start_with?('//'.b)

      authority_end = rest.index(/[\/?#]/n, 2) || rest.bytesize
      authority = rest[2...authority_end].to_s

      user = pass = host = port = nil

      if (at = authority.rindex('@'.b))
        userinfo = authority[0, at]
        authority = authority[(at + 1)..].to_s
        if (colon = userinfo.index(':'.b))
          user = userinfo[0, colon]
          pass = userinfo[(colon + 1)..].to_s
        else
          user = userinfo
        end
        user = nil if user.nil? || user.empty?
      end

      # PHP does not validate the inside of a bracketed host: parse_url() reports
      # `ex[1].com` and `[CDATA[raw]]` as hosts verbatim. Only the *last* `]`
      # closes it, and only a `:digits` tail may follow.
      close = authority.start_with?('['.b) ? authority.rindex(']'.b) : nil
      remainder = close ? authority[(close + 1)..].to_s : nil

      if close && (remainder.empty? || /\A:[0-9]+\z/n.match?(remainder))
        host = authority[0..close]
        port = remainder[1..] unless remainder.empty?
      elsif (colon = authority.rindex(':'.b))
        host = authority[0, colon]
        port = authority[(colon + 1)..].to_s
        # PHP rejects the whole URL when the port is not a run of digits.
        return nil unless /\A[0-9]+\z/n.match?(port)
      else
        host = authority
      end

      host = nil if host.nil? || host.empty?

      { scheme: scheme, user: user, pass: pass, host: host, port: port }
    end
  end
end
