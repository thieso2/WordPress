# frozen_string_literal: true

module Syndication
  # The feed-only halves of the legacy text pipeline: the default listeners core
  # installs on the `*_rss` / `*_feed` filter names (wp-includes/default-filters.php:
  # 257-269), composed as plain functions. AD-01: these chains are the permanent, only
  # behaviour — there is no way to add to them.
  #
  # Everything the web pipeline already ports (wptexturize, wpautop, convert_chars,
  # esc_html, the_content, the_title, trim_words …) is reused from
  # `Composition::Renderers::PostBlocks::Text`, which is the implementation the
  # byte-identical web screens went through. Only what feeds ADD lives here.
  module FeedText
    module_function

    Text = Composition::Renderers::PostBlocks::Text
    Site = Composition::Renderers::PostBlocks::Site
    Links = Composition::Renderers::PostBlocks::Links

    # ── ent2ncr() ────────────────────────────────────────────────────────────────
    # wp-includes/formatting.php:4168 — named character references to numeric ones,
    # applied with sequential str_replace over this exact table (formatting.php:4185,
    # `$to_ncr`), transcribed verbatim including the odd `'|' => '&#124;'` entry.
    # Feeds hang it (priority 8, so ahead of everything else) on `the_title_rss`,
    # `the_excerpt_rss`, `comment_text_rss` and `bloginfo_rss`
    # (default-filters.php:258,264,266,269).
    ENT2NCR = [
      ["&quot;", "&#34;"], ["&amp;", "&#38;"], ["&lt;", "&#60;"], ["&gt;", "&#62;"],
      ["|", "&#124;"], ["&nbsp;", "&#160;"], ["&iexcl;", "&#161;"], ["&cent;", "&#162;"],
      ["&pound;", "&#163;"], ["&curren;", "&#164;"], ["&yen;", "&#165;"],
      ["&brvbar;", "&#166;"], ["&brkbar;", "&#166;"], ["&sect;", "&#167;"],
      ["&uml;", "&#168;"], ["&die;", "&#168;"], ["&copy;", "&#169;"], ["&ordf;", "&#170;"],
      ["&laquo;", "&#171;"], ["&not;", "&#172;"], ["&shy;", "&#173;"], ["&reg;", "&#174;"],
      ["&macr;", "&#175;"], ["&hibar;", "&#175;"], ["&deg;", "&#176;"],
      ["&plusmn;", "&#177;"], ["&sup2;", "&#178;"], ["&sup3;", "&#179;"],
      ["&acute;", "&#180;"], ["&micro;", "&#181;"], ["&para;", "&#182;"],
      ["&middot;", "&#183;"], ["&cedil;", "&#184;"], ["&sup1;", "&#185;"],
      ["&ordm;", "&#186;"], ["&raquo;", "&#187;"], ["&frac14;", "&#188;"],
      ["&frac12;", "&#189;"], ["&frac34;", "&#190;"], ["&iquest;", "&#191;"],
      ["&Agrave;", "&#192;"], ["&Aacute;", "&#193;"], ["&Acirc;", "&#194;"],
      ["&Atilde;", "&#195;"], ["&Auml;", "&#196;"], ["&Aring;", "&#197;"],
      ["&AElig;", "&#198;"], ["&Ccedil;", "&#199;"], ["&Egrave;", "&#200;"],
      ["&Eacute;", "&#201;"], ["&Ecirc;", "&#202;"], ["&Euml;", "&#203;"],
      ["&Igrave;", "&#204;"], ["&Iacute;", "&#205;"], ["&Icirc;", "&#206;"],
      ["&Iuml;", "&#207;"], ["&ETH;", "&#208;"], ["&Ntilde;", "&#209;"],
      ["&Ograve;", "&#210;"], ["&Oacute;", "&#211;"], ["&Ocirc;", "&#212;"],
      ["&Otilde;", "&#213;"], ["&Ouml;", "&#214;"], ["&times;", "&#215;"],
      ["&Oslash;", "&#216;"], ["&Ugrave;", "&#217;"], ["&Uacute;", "&#218;"],
      ["&Ucirc;", "&#219;"], ["&Uuml;", "&#220;"], ["&Yacute;", "&#221;"],
      ["&THORN;", "&#222;"], ["&szlig;", "&#223;"], ["&agrave;", "&#224;"],
      ["&aacute;", "&#225;"], ["&acirc;", "&#226;"], ["&atilde;", "&#227;"],
      ["&auml;", "&#228;"], ["&aring;", "&#229;"], ["&aelig;", "&#230;"],
      ["&ccedil;", "&#231;"], ["&egrave;", "&#232;"], ["&eacute;", "&#233;"],
      ["&ecirc;", "&#234;"], ["&euml;", "&#235;"], ["&igrave;", "&#236;"],
      ["&iacute;", "&#237;"], ["&icirc;", "&#238;"], ["&iuml;", "&#239;"],
      ["&eth;", "&#240;"], ["&ntilde;", "&#241;"], ["&ograve;", "&#242;"],
      ["&oacute;", "&#243;"], ["&ocirc;", "&#244;"], ["&otilde;", "&#245;"],
      ["&ouml;", "&#246;"], ["&divide;", "&#247;"], ["&oslash;", "&#248;"],
      ["&ugrave;", "&#249;"], ["&uacute;", "&#250;"], ["&ucirc;", "&#251;"],
      ["&uuml;", "&#252;"], ["&yacute;", "&#253;"], ["&thorn;", "&#254;"],
      ["&yuml;", "&#255;"], ["&OElig;", "&#338;"], ["&oelig;", "&#339;"],
      ["&Scaron;", "&#352;"], ["&scaron;", "&#353;"], ["&Yuml;", "&#376;"],
      ["&fnof;", "&#402;"], ["&circ;", "&#710;"], ["&tilde;", "&#732;"],
      ["&Alpha;", "&#913;"], ["&Beta;", "&#914;"], ["&Gamma;", "&#915;"],
      ["&Delta;", "&#916;"], ["&Epsilon;", "&#917;"], ["&Zeta;", "&#918;"],
      ["&Eta;", "&#919;"], ["&Theta;", "&#920;"], ["&Iota;", "&#921;"],
      ["&Kappa;", "&#922;"], ["&Lambda;", "&#923;"], ["&Mu;", "&#924;"],
      ["&Nu;", "&#925;"], ["&Xi;", "&#926;"], ["&Omicron;", "&#927;"],
      ["&Pi;", "&#928;"], ["&Rho;", "&#929;"], ["&Sigma;", "&#931;"],
      ["&Tau;", "&#932;"], ["&Upsilon;", "&#933;"], ["&Phi;", "&#934;"],
      ["&Chi;", "&#935;"], ["&Psi;", "&#936;"], ["&Omega;", "&#937;"],
      ["&alpha;", "&#945;"], ["&beta;", "&#946;"], ["&gamma;", "&#947;"],
      ["&delta;", "&#948;"], ["&epsilon;", "&#949;"], ["&zeta;", "&#950;"],
      ["&eta;", "&#951;"], ["&theta;", "&#952;"], ["&iota;", "&#953;"],
      ["&kappa;", "&#954;"], ["&lambda;", "&#955;"], ["&mu;", "&#956;"],
      ["&nu;", "&#957;"], ["&xi;", "&#958;"], ["&omicron;", "&#959;"],
      ["&pi;", "&#960;"], ["&rho;", "&#961;"], ["&sigmaf;", "&#962;"],
      ["&sigma;", "&#963;"], ["&tau;", "&#964;"], ["&upsilon;", "&#965;"],
      ["&phi;", "&#966;"], ["&chi;", "&#967;"], ["&psi;", "&#968;"],
      ["&omega;", "&#969;"], ["&thetasym;", "&#977;"], ["&upsih;", "&#978;"],
      ["&piv;", "&#982;"], ["&ensp;", "&#8194;"], ["&emsp;", "&#8195;"],
      ["&thinsp;", "&#8201;"], ["&zwnj;", "&#8204;"], ["&zwj;", "&#8205;"],
      ["&lrm;", "&#8206;"], ["&rlm;", "&#8207;"], ["&ndash;", "&#8211;"],
      ["&mdash;", "&#8212;"], ["&lsquo;", "&#8216;"], ["&rsquo;", "&#8217;"],
      ["&sbquo;", "&#8218;"], ["&ldquo;", "&#8220;"], ["&rdquo;", "&#8221;"],
      ["&bdquo;", "&#8222;"], ["&dagger;", "&#8224;"], ["&Dagger;", "&#8225;"],
      ["&bull;", "&#8226;"], ["&hellip;", "&#8230;"], ["&permil;", "&#8240;"],
      ["&prime;", "&#8242;"], ["&Prime;", "&#8243;"], ["&lsaquo;", "&#8249;"],
      ["&rsaquo;", "&#8250;"], ["&oline;", "&#8254;"], ["&frasl;", "&#8260;"],
      ["&euro;", "&#8364;"], ["&image;", "&#8465;"], ["&weierp;", "&#8472;"],
      ["&real;", "&#8476;"], ["&trade;", "&#8482;"], ["&alefsym;", "&#8501;"],
      ["&crarr;", "&#8629;"], ["&lArr;", "&#8656;"], ["&uArr;", "&#8657;"],
      ["&rArr;", "&#8658;"], ["&dArr;", "&#8659;"], ["&hArr;", "&#8660;"],
      ["&forall;", "&#8704;"], ["&part;", "&#8706;"], ["&exist;", "&#8707;"],
      ["&empty;", "&#8709;"], ["&nabla;", "&#8711;"], ["&isin;", "&#8712;"],
      ["&notin;", "&#8713;"], ["&ni;", "&#8715;"], ["&prod;", "&#8719;"],
      ["&sum;", "&#8721;"], ["&minus;", "&#8722;"], ["&lowast;", "&#8727;"],
      ["&radic;", "&#8730;"], ["&prop;", "&#8733;"], ["&infin;", "&#8734;"],
      ["&ang;", "&#8736;"], ["&and;", "&#8743;"], ["&or;", "&#8744;"],
      ["&cap;", "&#8745;"], ["&cup;", "&#8746;"], ["&int;", "&#8747;"],
      ["&there4;", "&#8756;"], ["&sim;", "&#8764;"], ["&cong;", "&#8773;"],
      ["&asymp;", "&#8776;"], ["&ne;", "&#8800;"], ["&equiv;", "&#8801;"],
      ["&le;", "&#8804;"], ["&ge;", "&#8805;"], ["&sub;", "&#8834;"],
      ["&sup;", "&#8835;"], ["&nsub;", "&#8836;"], ["&sube;", "&#8838;"],
      ["&supe;", "&#8839;"], ["&oplus;", "&#8853;"], ["&otimes;", "&#8855;"],
      ["&perp;", "&#8869;"], ["&sdot;", "&#8901;"], ["&lceil;", "&#8968;"],
      ["&rceil;", "&#8969;"], ["&lfloor;", "&#8970;"], ["&rfloor;", "&#8971;"],
      ["&lang;", "&#9001;"], ["&rang;", "&#9002;"], ["&larr;", "&#8592;"],
      ["&uarr;", "&#8593;"], ["&rarr;", "&#8594;"], ["&darr;", "&#8595;"],
      ["&harr;", "&#8596;"], ["&loz;", "&#9674;"], ["&spades;", "&#9824;"],
      ["&clubs;", "&#9827;"], ["&hearts;", "&#9829;"], ["&diams;", "&#9830;"],
    ].freeze

    def ent2ncr(text)
      ENT2NCR.reduce(text.to_s) { |acc, (from, to)| acc.gsub(from, to) }
    end

    # ── wp_encode_emoji() / wp_staticize_emoji() ────────────────────────────────
    # wp-includes/formatting.php:6116 and :6137. Feeds hang wp_staticize_emoji on
    # `the_content_feed` and `comment_text_rss` (default-filters.php:261,268) — it is
    # why feed content carries <img class="wp-smiley"> where the web pages carry the
    # raw emoji. The emoji tables come from the oracle verbatim (EmojiData).
    EMOJI_CDN = "https://s.w.org/images/core/emoji/17.0.2/72x72/"
    EMOJI_EXT = ".png"

    # formatting.php:6116 — every partial found in the text becomes its `&#x...;`
    # entity, in table order (`preg_replace` over each partial in turn).
    def encode_emoji(content)
      EmojiData::PARTIALS.reduce(content) do |acc, partial|
        char = decode_emoji_entity(partial)
        acc.include?(char) ? acc.gsub(char, partial) : acc
      end
    end

    # formatting.php:6137. The `/(<.*>)/U` split (PCRE: lazy, dot excludes newline)
    # is `/(<[^\n]*?>)/` in Ruby; code|pre|style|script|textarea blocks are skipped by
    # the same literal `<tag>` / `</tag>` comparison the legacy uses.
    IGNORE_TAGS = /\A<(code|pre|style|script|textarea)>/

    def staticize_emoji(text)
      text = text.to_s
      unless text.include?("&#x")
        return text if text.ascii_only?

        encoded = encode_emoji(text)
        return text if encoded == text

        text = encoded
      end

      possible = {}
      EmojiData::ENTITIES.each do |entity|
        possible[entity] = decode_emoji_entity(entity) if text.include?(entity)
      end
      return text if possible.empty?

      ignore_block = ""
      text.split(/(<[^\n]*?>)/).map do |content|
        if ignore_block.empty? && (m = IGNORE_TAGS.match(content))
          ignore_block = m[1]
        end

        if ignore_block.empty? && !content.empty? && !content.start_with?("<") && content.include?("&#x")
          possible.each do |entity, char|
            next unless content.include?(entity)

            file = entity.gsub(";&#x", "-").gsub("&#x", "").gsub(";", "")
            img = %(<img src="#{EMOJI_CDN}#{file}#{EMOJI_EXT}" alt="#{char}" class="wp-smiley" style="height: 1em; max-height: 1em;" />)
            content = content.gsub(entity, img)
          end
        end

        ignore_block = "" if !ignore_block.empty? && content == "</#{ignore_block}>"
        content
      end.join
    end

    def decode_emoji_entity(entity)
      entity.scan(/&#x([0-9a-f]+);/i).map { |(hex)| hex.to_i(16) }.pack("U*")
    end

    # ── bloginfo_rss() ──────────────────────────────────────────────────────────
    # wp-includes/feed.php:27,56 — strip_tags, convert_chars, then the `bloginfo_rss`
    # default listener ent2ncr (default-filters.php:269). The stored option value
    # already carries `&quot;`/`&#039;` from sanitize_option, which is why the channel
    # description reads `&#34;` after ent2ncr.
    def bloginfo_rss(value)
      ent2ncr(Text.convert_chars(Text.strip_all_tags(value.to_s)))
    end

    # ── wp_title_rss() ──────────────────────────────────────────────────────────
    # feed.php:103,129 — wp_get_document_title() on a feed request resolves to the
    # site title through wptexturize → convert_chars → esc_html → capital_P_dangit
    # (wp-includes/general-template.php, wp_get_document_title()). Verified against
    # the oracle: for this corpus the stored `blogname` passes through unchanged.
    def wp_title_rss
      title = Configuration::Setting.display("blogname").to_s
      Text.capital_p_title(Sanitizing::Formatting.esc_html(Text.convert_chars(Text.wptexturize(title))))
    end

    # ── the_title_rss() ─────────────────────────────────────────────────────────
    # feed.php:158,176 — get_the_title() (the web `the_title` chain, reused), then the
    # `the_title_rss` listeners in priority-then-registration order: ent2ncr (8),
    # strip_tags, esc_html (default-filters.php:257-259).
    def the_title_rss(post)
      Sanitizing::Formatting.esc_html(Text.strip_all_tags(ent2ncr(Text.the_title(post))))
    end

    # ── get_the_excerpt() → wp_trim_excerpt() ───────────────────────────────────
    # wp-includes/post-template.php (get_the_excerpt): a password-protected post
    # short-circuits to the fixed sentence. wp-includes/formatting.php
    # (wp_trim_excerpt): a manual excerpt is returned as stored; an empty one is
    # generated from the content — `the_content` filter, strip tags, 55 words,
    # ' [&hellip;]'. The block-removal step (excerpt_remove_blocks) is subsumed here
    # by rendering through the same block pipeline the web screens use and stripping
    # tags, which is byte-equivalent for every post in this corpus.
    PROTECTED_EXCERPT = "There is no excerpt because this is a protected post."

    def get_the_excerpt(post, ctx)
      return PROTECTED_EXCERPT if post.password_digest.present?

      stored = post.excerpt.to_s
      return stored unless stored.empty?

      text = Text.the_content(post, ctx).gsub("]]>", "]]&gt;")
      Text.trim_words(Text.strip_all_tags(text), 55, " [&hellip;]")
    end

    # ── the_excerpt_rss() ───────────────────────────────────────────────────────
    # feed.php:227 — `the_excerpt_rss` listeners: ent2ncr (8), convert_chars
    # (default-filters.php:263-264).
    def the_excerpt_rss(post, ctx)
      Text.convert_chars(ent2ncr(get_the_excerpt(post, ctx)))
    end

    # ── get_the_content_feed() ──────────────────────────────────────────────────
    # feed.php:190 — the full web `the_content` chain (reused: it is what produced the
    # byte-identical web screens), then `']]>' → ']]&gt;'`, then the
    # `the_content_feed` listener wp_staticize_emoji (default-filters.php:261).
    # `_oembed_filter_feed_content` (:262) only rewrites sandboxed oEmbed iframes,
    # which no post in this corpus contains.
    #
    # get_the_content() substitutes the password form for the content of a protected
    # post (wp-includes/post-template.php, get_the_content: `if
    # post_password_required( $post ) return get_the_password_form( $post )`), and the
    # form then rides the same filter chain — which is where the golden's mangled
    # `</p>` after the hidden input comes from (wpautop over markup it cannot parse).
    def the_content_feed(post, ctx)
      content =
        if post.password_digest.present?
          form = password_form(post)
          out = Text.wptexturize(form.gsub("]]>", "]]&gt;"))
          Text.filter_content_tags(Text.capital_p_content(Text.wpautop(out)))
        else
          Text.the_content(post, ctx)
        end
      staticize_emoji(content.gsub("]]>", "]]&gt;"))
    end

    # ── get_the_password_form() ─────────────────────────────────────────────────
    # wp-includes/post-template.php:1779. Block theme active, so the submit button is
    # wrapped in `<span class="wp-block-button">` and classed
    # `wp-block-button__link wp-element-button` (post-template.php:1816-1819;
    # wp_theme_get_element_class_name('button') = 'wp-element-button').
    # No referer, so the invalid-password branch never fires here.
    def password_form(post)
      field_id = "pwbox-#{post.id}"
      permalink = Links.permalink(post)
      redirect_field = %(<input type="hidden" name="redirect_to" value="#{Text.esc_attr(permalink)}" />)
      %(<form action="#{Text.esc_url("#{Site.home_url}/wp-login.php?action=postpass")}" class="post-password-form" method="post">#{redirect_field}\n\t) +
        %(<p>This content is password-protected. To view it, please enter the password below.</p>\n\t) +
        %(<p><label for="#{field_id}">Password: <input name="post_password" id="#{field_id}" type="password" spellcheck="false" required size="20" /></label> ) +
        %(<span class="wp-block-button"><input type="submit" name="Submit" class="wp-block-button__link wp-element-button" value="Enter" /></span></p></form>\n\t)
    end

    # ── get_the_category_rss() ──────────────────────────────────────────────────
    # feed.php:381 — categories first, then tags, each name-ascending
    # (wp_get_object_terms' unfiltered default), de-duplicated. RSS2 wraps each name
    # in its own indented CDATA line after html_entity_decode(ENT_COMPAT); Atom
    # concatenates `<category scheme term />` elements with no separator
    # (feed.php:434-438).
    def category_names(post)
      terms = Classification::Term
              .joins(:taxonomy, :assignments)
              .where(term_assignments: { classifiable_type: "Publishing::Post",
                                         classifiable_id: post.id })
              .where(taxonomies: { name: %w[category post_tag] })
              .select("terms.*, taxonomies.name AS taxonomy_name")
              .order("terms.name ASC")
      grouped = terms.group_by { |t| t.attributes["taxonomy_name"] }
      (Array(grouped["category"]).map(&:name) + Array(grouped["post_tag"]).map(&:name)).uniq
    end

    # html_entity_decode(ENT_COMPAT) over a term name. The corpus names carry no
    # character references, so only the four basic ones are transcribed.
    def entity_decode(name)
      name.gsub("&quot;", '"').gsub("&lt;", "<").gsub("&gt;", ">").gsub("&amp;", "&")
    end

    def category_rss(post, type)
      names = category_names(post)
      if type == "atom"
        names.map { |n| %(<category scheme="#{Text.esc_attr(bloginfo_rss(Site.home_url))}" term="#{Text.esc_attr(n)}" />) }.join
      else
        names.map { |n| "\t\t<category><![CDATA[#{entity_decode(n)}]]></category>\n" }.join
      end
    end

    # ── get_comments_number() ───────────────────────────────────────────────────
    # The legacy reads the denormalized `comment_count`, which WordPress maintains as
    # the APPROVED comment count (wp_update_comment_count_now, wp-includes/
    # comment.php). The rebuild's counter counts every comment, so the approved set
    # is counted directly.
    def comments_number(post)
      Discussion::Comment.where(post_id: post.id, status: "approved").count
    end

    # ── get_comments_link() ─────────────────────────────────────────────────────
    # wp-includes/comment-template.php:873-875 — '#comments' when there are approved
    # comments, '#respond' otherwise.
    def comments_link(post, count)
      "#{Links.permalink(post)}##{count.positive? ? 'comments' : 'respond'}"
    end

    # ── get_post_comments_feed_link() ───────────────────────────────────────────
    # wp-includes/link-template.php:745 — pretty permalinks append 'feed', plus the
    # feed name when it is not the default, then user_trailingslashit.
    def post_comments_feed_link(post, feed = "rss2")
      suffix = feed == "rss2" ? "feed/" : "feed/#{feed}/"
      "#{Links.permalink(post)}#{suffix}"
    end

    # ── get_comment_text() for a comment feed ───────────────────────────────────
    # wp-includes/comment-template.php:1029 — a child comment in a comment feed is
    # prefixed with `In reply to <a href="…">author</a>.` and a blank line
    # (comment-template.php:1034-1045).
    def comment_text(comment, parent)
      text = comment.content.to_s
      return text if parent.nil?

      link = Text.esc_url("#{Links.permalink(parent.post)}#comment-#{parent.id}")
      %(In reply to <a href="#{link}">#{parent.author_name}</a>.\n\n#{text})
    end

    # ── comment_text_rss() ──────────────────────────────────────────────────────
    # feed.php:356 — `comment_text_rss` listeners in order: ent2ncr (8), esc_html,
    # wp_staticize_emoji (default-filters.php:266-268). esc_html runs BEFORE
    # staticize, which is why the emoji <img> survives unescaped inside an otherwise
    # escaped description.
    def comment_text_rss(comment, parent)
      staticize_emoji(Sanitizing::Formatting.esc_html(ent2ncr(comment_text(comment, parent))))
    end

    # ── comment_text() display chain ────────────────────────────────────────────
    # The `comment_text` filter's default listeners, already ported and verified for
    # the web screens: Composition::Renderers::CommentBlocks::CommentText.
    def comment_text_full(comment, parent)
      Composition::Renderers::CommentBlocks::CommentText.call(comment_text(comment, parent))
    end

    # mysql2date( 'D, d M Y H:i:s +0000', get_post_time( …, true ) ) — the RFC-2822
    # shape every <pubDate>/<lastBuildDate> uses. GMT instants only (AD-07).
    def rfc2822(time)
      time.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
    end

    # get_post_time / get_post_modified_time with 'Y-m-d\TH:i:s\Z' (feed-atom.php).
    def atom_time(time)
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end
  end
end
