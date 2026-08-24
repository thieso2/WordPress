# frozen_string_literal: true

module Discussion
  # The `pre_comment_*` save filters, inlined as one fixed pipeline per field.
  #
  # wp_filter_comment() (wp-includes/comment.php:2251) runs every field of a new comment
  # through a `pre_comment_<field>` filter before wp_insert_comment(). AD-01: the filters
  # are gone. What core itself registered on them is the only behaviour, and it is written
  # out here in registration/priority order:
  #
  #   pre_comment_author_name   default-filters.php:32-36   sanitize_text_field (10),
  #                                                         wp_filter_kses (10),
  #                                                         _wp_specialchars (30)
  #   pre_comment_author_email  default-filters.php:62-66   trim, sanitize_email, wp_filter_kses
  #   pre_comment_author_url    default-filters.php:77-88   wp_strip_all_tags, sanitize_url,
  #                                                         wp_filter_kses
  #   pre_comment_content       default-filters.php:157-160 convert_invalid_entities (10),
  #                                                         balanceTags (50)
  #                             kses.php:2545-2553          wp_filter_kses (10) — unless the
  #                                                         actor holds unfiltered_html
  #                             default-filters.php:317     _wp_kses_sanitize_note_mention_classes (11)
  #                             default-filters.php:312     wp_rel_ugc (15)
  #   pre_comment_user_ip / pre_comment_user_agent / pre_user_id — nothing registered.
  #
  # ⚠️ RISK-008. Every callback above is a "pre-save filter, so text is already escaped"
  # (formatting.php:3363): wp_filter_kses() is addslashes(wp_kses(stripslashes())) and
  # wp_rel_ugc() is wp_slash(…(stripslashes())). The slashes are put on by
  # wp_handle_comment_submission (`wp_new_comment( wp_slash( $commentdata ) )`,
  # comment.php:4148) and taken off again by wp_insert_comment (`wp_unslash`, :2159), so
  # the net transform applied to the VALUE is the unslashed pipeline. Rails params are
  # raw; nothing here slashes or unslashes, and the differential spec compares against
  # `wp_unslash(apply_filters('pre_comment_*', wp_slash($raw)))`.
  module FieldFilters
    F = Sanitizing::Formatting
    K = Sanitizing::Kses

    # wp_kses_allowed_html('pre_comment_content') is the $allowedtags set
    # (kses.php:1063, default branch) as modified by `_wp_kses_allow_note_mention_span`
    # (kses.php:1157) — `span.class` is allowed for that one context.
    COMMENT_ALLOWED_TAGS = Sanitizing::Tables::ALLOWED_TAGS.merge("span" => { "class" => true }).freeze

    # The other two kses'd fields run in their own filter context and get $allowedtags
    # unmodified.
    FIELD_ALLOWED_TAGS = Sanitizing::Tables::ALLOWED_TAGS

    # PHP trim()'s default character list.
    TRIM_CHARS = " \t\n\r\0\x0B"

    # convert_invalid_entities(), formatting.php:2512. Windows-1252 numeric entities in
    # the 128-159 range are mapped to their Unicode equivalents; 129, 141, 143, 144 and
    # 157 are removed.
    WIN_UNI = {
      "&#128;" => "&#8364;", "&#129;" => "", "&#130;" => "&#8218;", "&#131;" => "&#402;",
      "&#132;" => "&#8222;", "&#133;" => "&#8230;", "&#134;" => "&#8224;", "&#135;" => "&#8225;",
      "&#136;" => "&#710;", "&#137;" => "&#8240;", "&#138;" => "&#352;", "&#139;" => "&#8249;",
      "&#140;" => "&#338;", "&#141;" => "", "&#142;" => "&#381;", "&#143;" => "", "&#144;" => "",
      "&#145;" => "&#8216;", "&#146;" => "&#8217;", "&#147;" => "&#8220;", "&#148;" => "&#8221;",
      "&#149;" => "&#8226;", "&#150;" => "&#8211;", "&#151;" => "&#8212;", "&#152;" => "&#732;",
      "&#153;" => "&#8482;", "&#154;" => "&#353;", "&#155;" => "&#8250;", "&#156;" => "&#339;",
      "&#157;" => "", "&#158;" => "&#382;", "&#159;" => "&#376;"
    }.freeze

    module_function

    # ── the four field pipelines ─────────────────────────────────────────────────

    # `pre_comment_author_name`.
    def author_name(raw)
      s = sanitize_text_field(raw)
      s = K.wp_kses(s, FIELD_ALLOWED_TAGS)
      # _wp_specialchars() with its defaults: ENT_NOQUOTES, no double encoding
      # (formatting.php:945) — so `&` becomes `&amp;` and quotes are left alone.
      utf8(F._wp_specialchars(s))
    end

    # `pre_comment_author_email`.
    def author_email(raw)
      s = php_trim(raw.to_s)
      s = sanitize_email(s)
      utf8(K.wp_kses(s, FIELD_ALLOWED_TAGS))
    end

    # `pre_comment_author_url`.
    def author_url(raw)
      s = wp_strip_all_tags(raw.to_s)
      s = F.sanitize_url(s)
      utf8(K.wp_kses(s, FIELD_ALLOWED_TAGS))
    end

    # `pre_comment_content`. `html_filter` is the kses level the submitting actor gets
    # (kses_init(), kses.php:2605, and comment.php:4061-4071):
    #   :restricted — everyone without `unfiltered_html`, AND an `unfiltered_html` holder
    #                 whose `_wp_unfiltered_html_comment` nonce is absent or invalid
    #   :none       — an `unfiltered_html` holder with a valid nonce: no kses at all.
    def content(raw, html_filter: :restricted)
      s = convert_invalid_entities(raw.to_s)
      if html_filter == :restricted
        s = K.wp_kses(s, COMMENT_ALLOWED_TAGS)
        # kses.php:1196 — runs only while wp_filter_kses is on pre_comment_content.
        s = sanitize_note_mention_classes(s)
      end
      s = wp_rel_ugc(s)
      # balanceTags (priority 50, formatting.php:2529) is `force_balance_tags()` only when
      # `use_balanceTags` is '1'; the setting is '0' on the oracle and force_balance_tags
      # is not ported. See the report.
      utf8(s)
    end

    # ── formatting.php ports the `sanitizing` pack does not carry ─────────────────

    # sanitize_text_field() → _sanitize_text_fields($str, false), formatting.php:5718.
    def sanitize_text_field(str)
      s = F.wp_check_invalid_utf8(str.to_s)
      if s.include?("<".b)
        s = F.wp_pre_kses_less_than(s)
        # "This will strip extra whitespace for us."
        s = wp_strip_all_tags(s, false)
        s = s.gsub("<\n".b, "&lt;\n".b)
      end
      s = s.gsub(/[\r\n\t ]+/n, " ".b)
      s = php_trim(s)

      # Remove percent-encoded characters — str_replace of each match, repeated.
      found = false
      while (m = s.match(/%[a-f0-9]{2}/in))
        s = s.gsub(m[0], "".b)
        found = true
      end
      s = php_trim(s.gsub(/ +/n, " ".b)) if found
      utf8(s)
    end

    # wp_strip_all_tags(), formatting.php:5610.
    def wp_strip_all_tags(text, remove_breaks = false)
      s = Sanitizing::Bytes.binary(text.to_s)
      s = s.gsub(%r{<(script|style)[^>]*?>.*?</\1>}imn, "".b)
      s = F.strip_tags(s)
      s = s.gsub(/[\r\n\t ]+/n, " ".b) if remove_breaks
      utf8(php_trim(s))
    end

    # convert_invalid_entities(), formatting.php:2512.
    def convert_invalid_entities(content)
      return content unless content.include?("&#1")

      content.gsub(/&#1[2-5][0-9];/) { |e| WIN_UNI.fetch(e, e) }
    end

    # is_email(), formatting.php:3613. Boolean here; the legacy returns the email itself
    # on success, and the one caller on this path only tests truthiness.
    def is_email?(email) # rubocop:disable Naming/PredicatePrefix
      email = email.to_s.b
      return false if email.bytesize < 6
      return false if email.index("@".b, 1).nil?

      local, domain = email.split("@".b, 2)
      # PCRE `$` without /D also matches before a string-final newline.
      return false unless local.match?(%r{\A[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]+\n?\z}n)
      return false if domain.match?(/\.{2,}/n)
      return false if php_trim(domain, "#{TRIM_CHARS}.") != domain

      subs = domain.split(".".b, -1)
      return false if subs.length < 2

      subs.all? do |sub|
        php_trim(sub, "#{TRIM_CHARS}-") == sub && sub.match?(/\A[a-z0-9-]+\n?\z/in)
      end
    end

    # sanitize_email(), formatting.php:3831.
    def sanitize_email(email)
      email = email.to_s.b
      return "" if email.bytesize < 6
      return "" if email.index("@".b, 1).nil?

      local, domain = email.split("@".b, 2)
      local = local.gsub(%r{[^a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]}n, "".b)
      return "" if local.empty?

      domain = domain.gsub(/\.{2,}/n, "".b)
      return "" if domain.empty?

      domain = php_trim(domain, "#{TRIM_CHARS}.")
      return "" if domain.empty?

      subs = domain.split(".".b, -1)
      return "" if subs.length < 2

      new_subs = subs.map { |sub| php_trim(sub, "#{TRIM_CHARS}-").gsub(/[^a-z0-9-]+/in, "".b) }
                     .reject(&:empty?)
      return "" if new_subs.length < 2

      utf8("#{local}@#{new_subs.join(".")}")
    end

    # wp_rel_ugc(), formatting.php:3364: every `<a …>` gets rel="nofollow ugc", merged
    # with any rel it already carries; internal links get "ugc" alone.
    def wp_rel_ugc(text)
      text.gsub(/<a (.+?)>/i) { wp_rel_callback(Regexp.last_match(1), "nofollow ugc") }
    end

    # wp_rel_callback(), formatting.php:3291.
    def wp_rel_callback(attr_text, rel)
      text = attr_text
      atts = {}
      K.wp_kses_hair(attr_text, Sanitizing::Tables::ALLOWED_PROTOCOLS).each do |a|
        atts[utf8(a[:name])] = { value: utf8(a[:value]), vless: a[:vless] }
      end

      if atts["href"] && !atts["href"][:value].empty? && internal_link?(atts["href"][:value])
        rel = rel.sub("nofollow", "").strip
      end

      if atts["rel"] && !atts["rel"][:value].empty?
        parts = atts["rel"][:value].split(/ /, -1).map(&:strip)
        parts = (parts + rel.split(/ /, -1).map(&:strip)).uniq
        rel = parts.join(" ")
        atts.delete("rel")

        html = +""
        atts.each do |name, value|
          html << (value[:vless] == "y" ? "#{name} " : %(#{name}="#{F.esc_attr(value[:value])}" ))
        end
        text = html.strip
      end

      rel_attr = rel.empty? ? "" : %( rel="#{F.esc_attr(rel)}")
      "<a #{text}#{rel_attr}>"
    end

    # wp_is_internal_link(), link-template.php:4898: an allowed scheme and the home host.
    def internal_link?(link)
      link = link.downcase
      parsed = F.php_parse_url(link.b)
      return false if parsed.nil?
      return false unless Sanitizing::Tables::ALLOWED_PROTOCOLS.include?(parsed[:scheme].to_s)

      internal_hosts.include?(parsed[:host].to_s)
    end

    # wp_internal_hosts(), link-template.php:4863: the host of home_url(), lowercased.
    def internal_hosts
      home = Configuration::Setting["home"].to_s
      host = F.php_parse_url(home.b)&.dig(:host).to_s.downcase
      host.empty? ? [] : [host]
    end

    # _wp_kses_sanitize_note_mention_classes(), kses.php:1196: on every <span>, only the
    # classes `wp-note-mention` and `user-<n>` survive; removing the last one removes the
    # attribute. The legacy walks the tags with WP_HTML_Tag_Processor; after wp_kses the
    # attribute is always in the normalized `class="…"` form, which is what is matched.
    #
    # Observed on the oracle, and reproduced: the attribute is rewritten only when a class
    # was actually removed (an untouched `class="a  b"` keeps its double space); when the
    # last class goes the attribute goes but the whitespace before it stays (`<span >`).
    def sanitize_note_mention_classes(content)
      content.gsub(/<span\b[^>]*>/i) do |tag|
        tag.sub(/(\s+)class=(?:"([^"]*)"|'([^']*)')/i) do
          space = Regexp.last_match(1)
          tokens = (Regexp.last_match(2) || Regexp.last_match(3)).to_s.split(/[\t\n\f\r ]+/).reject(&:empty?)
          keep = ->(c) { c == "wp-note-mention" || c.match?(/\Auser-[1-9][0-9]*\z/) }
          next Regexp.last_match(0) if tokens.all?(&keep)

          kept = tokens.select(&keep).uniq
          kept.empty? ? space : %(#{space}class="#{kept.join(" ")}")
        end
      end
    end

    # ── PHP primitives ─────────────────────────────────────────────────────────────

    def php_trim(str, chars = TRIM_CHARS)
      set = Regexp.escape(chars.b)
      str.b.sub(/\A[#{set}]+/n, "".b).sub(/[#{set}]+\z/n, "".b)
    end

    def utf8(str) = Sanitizing::Bytes.utf8(str)
  end
end
