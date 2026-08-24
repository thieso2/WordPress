# frozen_string_literal: true

module Composition
  module Renderers
    # The post + site block family: the fifteen server-rendered blocks that read the
    # record in `ctx.post` (or the term / author / comment in `ctx.context`).
    #
    # BR-MIGRATE-199 (BR-BLIB-06, `wp-includes/blocks/post-title.php` and 29 sibling
    # files): "Post-context blocks read from the current QUERY CONTEXT rather than from
    # attributes." The legacy carries that context in the `$post` global plus
    # `WP_Block::$context`; paradigm_decision.md implication 1 forbids both, so it
    # arrives here through `RenderContext` and nothing reaches for ambient state.
    #
    # ⚠️ Zeitwerk: this file owns exactly one top-level constant, `PostBlocks`, and every
    # renderer is nested inside it. Referencing `Composition::Renderers::PostBlocks` is
    # what loads the file and therefore what runs `handles` for all fifteen names; under
    # `config.eager_load` that happens at boot. With lazy loading (development, and `test`
    # unless CI=1) nothing references it, so the names are unregistered until something
    # does — see the report.
    #
    # ── What this family CANNOT reproduce ────────────────────────────────────────
    # Verified case by case against the live oracle by
    # spec/models/composition/post_blocks_differential_spec.rb, which fails if the list
    # of known divergences grows OR shrinks. All 178 of its cases — the oracle rendering
    # each through `render_block()`'s two filter passes — are byte-identical. The layout
    # container hash, the child-layout `wp-container-content-<hash>` and the fluid
    # typography clamp() that used to be listed here are the `render_block` chain's, and
    # `SupportChain` below delegates them to the shared port in `LayoutBlocks`.
    #
    # One divergence is DATA, not rendering, and is called out at its site: the local
    # wall clock (AD-07 keeps only the GMT instant, and this corpus's oracle rows have
    # post_date == post_date_gmt, so their own local column contradicts their own GMT
    # column).
    module PostBlocks
      # ── The context this family reads ────────────────────────────────────────────
      #
      # The legacy's conditional tags (`is_archive()`, `is_search()`, `is_front_page()`,
      # `is_paged()`, `get_queried_object()`) are reads of one global `WP_Query`. There
      # is no global here, so the same facts travel explicitly. `Screen` accepts them in
      # either of the two shapes a caller may already have:
      #
      #   * `ctx.query` responding to `archive?` / `search?` / `front_page?` / `home?` /
      #     `paged?` / `singular?` / `queried_object` / `search_query`; or
      #   * plain keys in `ctx.context`, which is the mechanism the block schemas
      #     themselves use (`usesContext`).
      #
      # Absent both, every predicate is false — which is the legacy's own answer outside
      # a query, and it is why a bare `render_block()` of `core/query-title` returns ''.
      class Screen
        KEYS = {
          archive?: "isArchive", search?: "isSearch", front_page?: "isFrontPage",
          home?: "isHome", paged?: "isPaged", singular?: "isSingular"
        }.freeze

        def initialize(ctx)
          @query = ctx.query
          @context = ctx.context || {}
        end

        KEYS.each do |predicate, key|
          define_method(predicate) do
            return !!@query.public_send(predicate) if @query.respond_to?(predicate)

            !!@context[key]
          end
        end

        # `get_queried_object()`: a Classification::Term, an Identity::User, or a Hash
        # describing a date archive (`{"year" => 2026, "monthnum" => 3, "day" => nil}`).
        def queried_object
          return @query.queried_object if @query.respond_to?(:queried_object)

          @context["queriedObject"]
        end

        # `get_search_query()`. The legacy passes it through `esc_attr()` at the call
        # site in query-title, so this is the raw term.
        def search_query
          return @query.search_query if @query.respond_to?(:search_query)

          @context["searchQuery"].to_s
        end
      end

      # ── Site-wide URLs and settings ─────────────────────────────────────────────
      module Site
        module_function

        # `home_url()`, wp-includes/link-template.php:3486 — no trailing slash.
        # BR-MIGRATE-012 (BR-OPT-12) already makes `home` fall back to `siteurl`.
        def home_url = Configuration::Setting["home"].to_s.chomp("/")

        # `site_url()`, wp-includes/link-template.php:3555 — the `siteurl` option, no
        # trailing slash. The password form posts here, not to `home`.
        def site_url = presence(Configuration::Setting["siteurl"]) || home_url

        # `get_option('date_format')`. Settings::Setting#[] answers `false` for a missing
        # row; the legacy's own default for this option is 'F j, Y'.
        def date_format = presence(Configuration::Setting["date_format"]) || "F j, Y"

        def timezone
          name = presence(Configuration::Setting["timezone_string"])
          return ActiveSupport::TimeZone[name] || Time.find_zone("UTC") if name

          # Settings::Setting#[] answers false for a missing row; PHP's
          # `(float) get_option('gmt_offset')` reads that as 0.0.
          raw_offset = Configuration::Setting["gmt_offset"]
          offset = raw_offset == false ? 0.0 : raw_offset.to_f
          ActiveSupport::TimeZone[offset * 3600] || Time.find_zone("UTC")
        end

        # `get_option('avatar_default', 'mystery')` maps 'mystery' onto Gravatar's 'mm'.
        def avatar_default
          value = presence(Configuration::Setting["avatar_default"]) || "mystery"
          value == "mystery" ? "mm" : value
        end

        # get_avatar_data(), wp-includes/link-template.php:4475 — `strtolower()`. The
        # option is stored as 'G'.
        def avatar_rating = (presence(Configuration::Setting["avatar_rating"]) || "g").downcase

        def presence(value)
          return nil if value == false || value.nil?

          s = value.to_s
          s.empty? ? nil : s
        end
      end

      # ── Permalinks ──────────────────────────────────────────────────────────────
      #
      # `get_permalink()` / `get_author_posts_url()` / `get_term_link()`, all resolved
      # against Routing::PermalinkStructure's `/%year%/%monthnum%/%postname%/`.
      #
      # ⚠️ Absolute, and with the trailing slash the structure ends in. `RenderContext#
      # permalink_for` returns a host-relative path without one; both properties are
      # observable in the golden files, so this family builds its own.
      module Links
        module_function

        def permalink(record)
          return "" if record.nil?
          return page_permalink(record) if record.is_a?(Publishing::Page)
          return "" if record.slug.blank? || record.published_at.nil?

          local = record.published_at.in_time_zone(Site.timezone)
          "#{Site.home_url}/#{local.strftime("%Y/%m")}/#{record.slug}/"
        end

        # BR-MIGRATE-033: hierarchical types allocate slugs unique within (type, parent),
        # so the path is the ancestor chain.
        def page_permalink(page)
          segments = []
          node = page
          seen = Set.new
          while node && !seen.include?(node.id)
            seen << node.id
            segments.unshift(node.slug)
            node = node.parent
          end
          "#{Site.home_url}/#{segments.compact.join("/")}/"
        end

        def author_posts_url(user)
          return "" if user.nil?

          "#{Site.home_url}/author/#{user.nicename}/"
        end

        # `get_term_link()`. The category permastruct is hierarchical, so a child term's
        # URL carries its ancestors; `post_tag` is flat.
        def term_link(term)
          return "" if term.nil?

          taxonomy = term.taxonomy&.name.to_s
          case taxonomy
          when "category"
            path = (term.ancestors.reverse.map(&:slug) + [term.slug]).join("/")
            "#{Site.home_url}/category/#{path}/"
          when "post_tag"
            "#{Site.home_url}/tag/#{term.slug}/"
          else
            "#{Site.home_url}/#{taxonomy}/#{term.slug}/"
          end
        end
      end

      # ── Formatting ──────────────────────────────────────────────────────────────
      #
      # Thin, cited wrappers over `packs/sanitizing`, plus the three `wp-includes/
      # formatting.php` helpers the pack does not carry. AD-01: `the_title`,
      # `the_content`, `get_the_excerpt` and `term_description` are filter names in the
      # legacy; the chains below are the DEFAULT LISTENERS core itself installs in
      # `wp-includes/default-filters.php`, which is core behaviour rather than
      # extension — so the composed function is the specification and there is no way to
      # add to it.
      module Text
        module_function

        def esc_html(text) = Sanitizing::Formatting.esc_html(text.to_s)
        def esc_attr(text) = Sanitizing::Formatting.esc_attr(text.to_s)
        def esc_url(url) = Sanitizing::Formatting.esc_url(url.to_s)
        def wptexturize(text) = Sanitizing::Texturize.wptexturize(text.to_s)
        def kses_post(html) = Sanitizing::Kses.wp_kses_post(html.to_s)
        def wpautop(text, br = true) = Sanitizing::Formatting.wpautop(text.to_s, br)

        # convert_chars(), wp-includes/formatting.php:2492 — a bare `&` becomes the
        # numeric reference; one already opening a character reference is left alone.
        def convert_chars(content)
          text = content.to_s
          return text unless text.include?("&")

          text.gsub(/&([^#])(?![a-z1-4]{1,8};)/i) { "&#038;#{Regexp.last_match(1)}" }
        end

        # capital_P_dangit(), wp-includes/formatting.php:5783. TWO behaviours, chosen by
        # which filter is running: `the_title` gets the blunt replacement, everything
        # else the judicious one. Ported as two methods because there is no
        # `current_filter()` here to ask.
        def capital_p_title(text) = text.to_s.gsub("Wordpress", "WordPress")

        CAPITAL_P_CONTEXTS = [" ", "&#8216;", "&#8220;", ">", "("].freeze

        def capital_p_content(text)
          CAPITAL_P_CONTEXTS.inject(text.to_s) do |acc, prefix|
            acc.gsub("#{prefix}Wordpress", "#{prefix}WordPress")
          end
        end

        # wp_strip_all_tags(), wp-includes/formatting.php:5610.
        def strip_all_tags(text, remove_breaks: false)
          stripped = text.to_s.gsub(%r{<(script|style)[^>]*?>.*?</\1>}mi, "")
          # The pack works on binary strings by design (packs/sanitizing/…/bytes.rb); the
          # bytes are UTF-8 and only the tag needs restoring. Transcoding here would turn
          # one emoji into four U+FFFD — the exact RISK-014 failure the harness's own
          # normalizer warns about.
          stripped = Sanitizing::Formatting.strip_tags(stripped).dup.force_encoding(Encoding::UTF_8)
          stripped = stripped.gsub(/[\r\n\t ]+/, " ") if remove_breaks
          stripped.strip
        end

        # wp_trim_words(), wp-includes/formatting.php:4120. `blog_charset` is UTF-8 and
        # `wp_get_word_count_type()` is 'words' for en_US, so only the word branch is
        # reachable; the character branch is recorded here and not implemented because
        # nothing in this corpus can enter it.
        def trim_words(text, num_words = 55, more = "&hellip;")
          stripped = strip_all_tags(text)
          count = num_words.to_i
          # PHP's preg_split with a limit puts the remainder in the last element; only
          # its EXISTENCE is used (to decide whether to append `$more`), so splitting
          # fully and comparing lengths is equivalent.
          words = stripped.split(/[\n\r\t ]+/).reject(&:empty?)
          return words.join(" ") if words.length <= count

          "#{words.first(count).join(" ")}#{more}"
        end

        # get_the_title(), wp-includes/post-template.php:130 — the two title formats and
        # then the `the_title` chain: wptexturize, convert_chars, trim, capital_P_dangit.
        #
        # BR-MIGRATE-199's context rule is why the password/private prefixes live here
        # and not in a view: they are part of the title the block renders.
        def the_title(post)
          return "" if post.nil?

          title = post.title.to_s
          title = format("Protected: %s", title) if post.password_digest.present?
          title = format("Private: %s", title) if post.password_digest.blank? && post.status.to_s == "private"
          capital_p_title(convert_chars(wptexturize(title)).strip)
        end

        # the_content, wp-includes/default-filters.php:201-210, in priority then
        # registration order. `do_blocks()` (priority 9) removes `wpautop` from the chain
        # whenever the content HAS BLOCKS — wp-includes/blocks.php, do_blocks() — which
        # is every post in this corpus, so the paragraphs come from the paragraph block
        # and never from wpautop.
        #
        # ⚠️ NOT IMPLEMENTED, each verified inert for this corpus by the differential
        # spec rather than assumed: shortcode_unautop and do_shortcode (no shortcode is
        # registered), prepend_attachment (attachment post type only),
        # wp_replace_insecure_home_url (the home URL is http), wp_filter_content_tags
        # (no <img> survives into rendered content here) and convert_smilies.
        def the_content(post, ctx)
          return "" if post.nil?

          # get_the_content(), wp-includes/post-template.php:319 — "If post password
          # required and it doesn't match the cookie", the PASSWORD FORM is the content.
          # There is no cookie until the postpass endpoint lands in Wave 3, so a
          # protected post always takes this branch. The form then travels the SAME
          # `the_content` chain the real content would (post-content.php:50 applies the
          # filter to whatever get_the_content returned): the form has no `<!-- wp:`, so
          # do_blocks leaves wpautop in place and the golden files show the form
          # wpautop-mangled — a stray `</p>` after the hidden input included.
          if post.password_digest.present?
            raw = password_form(post, ctx)
            rendered = raw
          else
            raw = post.content.to_s
            rendered = Renderer.render(Parser.parse(raw), ctx)
          end
          out = wptexturize(rendered.gsub("]]>", "]]&gt;"))
          # do_blocks(), wp-includes/blocks.php: wpautop is removed from the chain ONLY
          # when the content HAS BLOCKS — tested on the PRE-RENDER string, which still
          # carries its `<!-- wp:` delimiters. Classic (block-less) content still gets
          # it, and this corpus contains both kinds — the revision bodies are classic,
          # and the password form above is block-less by construction.
          out = wpautop(out) unless has_blocks?(raw)
          filter_content_tags(capital_p_content(out))
        end

        # get_the_password_form(), wp-includes/post-template.php:1779, transcribed for
        # the arms this corpus can reach:
        #   * the invalid-password branch (:1789) needs the postpass endpoint's referer
        #     plus the `wp-postpass_` cookie — neither exists before Wave 3, so
        #     `$invalid_password_html`, `$aria` and `$class` stay ''.
        #   * `wp_is_block_theme()` is true (twentytwentyfive), so the submit input gets
        #     `wp-block-button__link` + `wp_theme_get_element_class_name('button')`
        #     (= 'wp-element-button', class-wp-theme-json.php) inside a
        #     `<span class="wp-block-button">`, and :1822 enqueues the registered
        #     `wp-block-button` style — which is why the button stylesheet appears in
        #     `<head>` on every screen whose loop contains the protected post.
        # The action posts to `site_url('wp-login.php?action=postpass','login_post')`;
        # there is no submission endpoint until Wave 3, and that is correct.
        # Whitespace is the legacy's own, verbatim — wpautop feeds on the newlines.
        def password_form(post, ctx)
          ctx.styles.use("core/button")
          field_id = "pwbox-#{post.id}"
          redirect_field = format('<input type="hidden" name="redirect_to" value="%s" />',
                                  esc_attr(Links.permalink(post)))
          action = Sanitizing::Formatting.esc_url("#{Site.site_url}/wp-login.php?action=postpass")
          "<form action=\"#{action}\" class=\"post-password-form\" method=\"post\">#{redirect_field}\n" \
            "\t<p>This content is password-protected. To view it, please enter the password below.</p>\n" \
            "\t<p><label for=\"#{field_id}\">Password: " \
            "<input name=\"post_password\" id=\"#{field_id}\" type=\"password\" spellcheck=\"false\" required size=\"20\" /></label> " \
            "<span class=\"wp-block-button\"><input type=\"submit\" name=\"Submit\" " \
            "class=\"wp-block-button__link wp-element-button\" value=\"Enter\" /></span></p></form>\n\t"
        end

        # has_blocks(), wp-includes/blocks.php — a literal substring test, not a parse.
        def has_blocks?(content) = content.to_s.include?("<!-- wp:")

        # wp_filter_content_tags(), wp-includes/media.php, priority 12 on `the_content`.
        # Only the `decoding` half is reachable for this corpus: the srcset/sizes half
        # needs a `wp-image-<id>` class on the tag, which no content image here carries.
        # `wp_img_tag_add_decoding_attr()` does a str_replace on the OPENING `<img `,
        # which is why `decoding` lands first rather than last.
        def filter_content_tags(content)
          return content unless content.include?("<img")

          content.gsub(/<img\s[^>]*>/) do |tag|
            next tag if tag.match?(/\sdecoding\s*=/)

            tag.sub("<img ", '<img decoding="async" ')
          end
        end

        # term_description(), wp-includes/category-template.php — the `term_description`
        # filter's default listeners are wptexturize, convert_chars, wpautop,
        # shortcode_unautop, wp_replace_insecure_home_url.
        def term_description(term)
          return "" if term.nil?

          wpautop(convert_chars(wptexturize(term.description.to_s)))
        end
      end

      # ── Block supports on the wrapper ───────────────────────────────────────────
      #
      # `get_block_wrapper_attributes()`, wp-includes/class-wp-block-supports.php:203.
      # Every render callback in this family ends by calling it, so it is not optional
      # scaffolding — it is 39% of what these blocks emit.
      #
      # BR-MIGRATE-200…205 are ALREADY PORTED, in `packs/styling`
      # (`Styling::BlockSupports`), and that port is the one covered by the styling
      # pack's differential spec. This module therefore supplies only the two halves the
      # pack deliberately leaves out: the eleven `apply` callbacks from
      # `wp-includes/block-supports/*.php`, and the attribute-merge step of
      # `get_block_wrapper_attributes()` itself.
      #
      # ⚠️ SCOPE. This is a private helper for the post + site family, nested inside it
      # so that it cannot collide with another renderer file. Every server-rendered block
      # in WordPress needs it, so it is a candidate for extraction into a shared
      # `Composition::Supports` once the other families land — see the report.
      module Supports
        module_function

        # wp-settings.php:415-434 fixes the registration order, and BR-MIGRATE-201
        # ("the first support to write an attribute takes the slot; later ones append")
        # makes that order observable. Supports registered WITHOUT an `apply` callable
        # (elements, layout, position, background, duotone, block-style-variation,
        # custom-css) contribute nothing here — BR-MIGRATE-203.
        REGISTRATION_ORDER = %w[
          align custom-classname generated-classname colors typography border
          spacing dimensions shadow aria-label anchor
        ].freeze

        # block_has_support(), wp-includes/blocks.php.
        def block_has_support?(type, feature, default_value = false)
          feature = Array(feature)
          support = if feature.length == 1
                      type.supports.key?(feature.first) ? type.supports[feature.first] : default_value
                    else
                      Styling::PhpCompat.array_get(type.supports, feature, default_value)
                    end
          support == true || support.is_a?(Hash) || support.is_a?(Array)
        end

        # wp_should_skip_block_supports_serialization(), wp-includes/blocks.php.
        def skip_serialization?(type, feature_set, feature = nil)
          return false if type.nil?

          skip = Styling::PhpCompat.array_get(type.supports, [feature_set, "__experimentalSkipSerialization"], false)
          return skip.include?(feature) if skip.is_a?(Array)

          skip == true
        end

        def dig(attrs, *path) = Styling::PhpCompat.array_get(attrs, path.map(&:to_s), nil)

        def style_engine(styles, convert_vars_to_classnames: false)
          Styling::StyleEngine.get_styles(styles, convert_vars_to_classnames: convert_vars_to_classnames)
        end

        # wp-includes/block-supports/align.php:44.
        def apply_align(type, attrs)
          return {} unless block_has_support?(type, "align", false)
          return {} unless attrs.key?("align")

          { "class" => "align#{attrs["align"]}" }
        end

        # wp-includes/block-supports/custom-classname.php:43.
        def apply_custom_classname(type, attrs)
          return {} unless block_has_support?(type, "customClassName", true)
          return {} unless attrs.key?("className")

          { "class" => attrs["className"] }
        end

        # wp-includes/block-supports/generated-classname.php:51 and
        # wp_get_block_default_classname(): `core/` is dropped, every other `/` becomes
        # `-`.
        def apply_generated_classname(type, _attrs)
          return {} unless block_has_support?(type, "className", true)

          { "class" => "wp-block-#{type.name.tr("/", "-").sub(/\Acore-/, "")}" }
        end

        # wp-includes/block-supports/colors.php:83.
        def apply_colors(type, attrs)
          support = type.supports["color"] || false
          return {} if support.is_a?(Hash) && skip_serialization?(type, "color")

          has_text = support == true || (support.is_a?(Hash) && (support["text"] || !support.key?("text")))
          has_background = support == true ||
                           (support.is_a?(Hash) && (support["background"] || !support.key?("background")))
          has_gradients = support.is_a?(Hash) ? support["gradients"] : false

          styles = {}
          if has_text && !skip_serialization?(type, "color", "text")
            preset = attrs.key?("textColor") ? "var:preset|color|#{attrs["textColor"]}" : nil
            styles["text"] = preset || dig(attrs, "style", "color", "text")
          end
          if has_background && !skip_serialization?(type, "color", "background")
            preset = attrs.key?("backgroundColor") ? "var:preset|color|#{attrs["backgroundColor"]}" : nil
            styles["background"] = preset || dig(attrs, "style", "color", "background")
          end
          # colors.php:117-127 — `color.gradient` is suppressed when the block also
          # supports `background.gradient` AND a value is set, because background.php
          # owns the CSS in that case.
          bg_gradient_support = block_has_support?(type, %w[background gradient], false)
          bg_gradient_value = !Styling::PhpCompat.php_empty?(dig(attrs, "style", "background", "gradient"))
          if has_gradients && !skip_serialization?(type, "color", "gradients") &&
             !(bg_gradient_support && bg_gradient_value)
            preset = attrs.key?("gradient") ? "var:preset|gradient|#{attrs["gradient"]}" : nil
            styles["gradient"] = preset || dig(attrs, "style", "color", "gradient")
          end

          from_style_engine(style_engine({ "color" => styles }, convert_vars_to_classnames: true))
        end

        # wp-includes/block-supports/typography.php:93. The `__experimental*` flags are
        # verbatim from the block.json files this repo generates db/blocks/types.json
        # from, so they are read verbatim here too.
        TYPOGRAPHY_FEATURES = {
          "fontFamily" => "__experimentalFontFamily", "fontSize" => "fontSize",
          "fontStyle" => "__experimentalFontStyle", "fontWeight" => "__experimentalFontWeight",
          "letterSpacing" => "__experimentalLetterSpacing", "lineHeight" => "lineHeight",
          "textAlign" => "textAlign", "textColumns" => "textColumns",
          "textDecoration" => "__experimentalTextDecoration",
          "textTransform" => "__experimentalTextTransform", "textIndent" => "textIndent",
          "writingMode" => "__experimentalWritingMode"
        }.freeze

        # typography.php:277 — a value that is not a `var:preset|<property>|…` string is
        # returned unchanged; a preset one becomes the CSS variable.
        def preset_inline_style_value(value, css_property)
          return value if value.nil? || value.to_s.empty?
          return value unless value.to_s.include?("var:preset|#{css_property}|")

          slug = Styling::PhpCompat.to_kebab_case(value.to_s.split("|").last)
          "var(--wp--preset--#{css_property}--#{slug})"
        end

        def apply_typography(type, attrs) # rubocop:disable Metrics/AbcSize
          supports = type.supports["typography"] || false
          return {} unless supports
          return {} if skip_serialization?(type, "typography")

          has = ->(feature) { !!supports[TYPOGRAPHY_FEATURES.fetch(feature)] }
          skip = ->(feature) { skip_serialization?(type, "typography", feature) }
          styles = {}

          if has.call("fontSize") && !skip.call("fontSize")
            preset = attrs.key?("fontSize") ? "var:preset|font-size|#{attrs["fontSize"]}" : nil
            # ⚠️ `wp_get_typography_font_size_value()` is NOT ported: it turns a custom
            # size into a fluid clamp() using wp_get_global_settings(), which this family
            # has no access to. A CUSTOM (non-preset) font size therefore renders
            # unfluid. No block in the 18 golden screens carries one; the ones that do
            # live in patterns. Recorded in the report rather than approximated silently.
            styles["fontSize"] = preset || dig(attrs, "style", "typography", "fontSize")
          end
          if has.call("fontFamily") && !skip.call("fontFamily")
            preset = attrs.key?("fontFamily") ? "var:preset|font-family|#{attrs["fontFamily"]}" : nil
            custom = dig(attrs, "style", "typography", "fontFamily")
            styles["fontFamily"] = preset || (custom && preset_inline_style_value(custom, "font-family"))
          end
          { "fontStyle" => "font-style", "fontWeight" => "font-weight",
            "textDecoration" => "text-decoration", "textTransform" => "text-transform",
            "letterSpacing" => "letter-spacing" }.each do |feature, property|
            next unless has.call(feature) && !skip.call(feature)

            value = dig(attrs, "style", "typography", feature)
            styles[feature] = preset_inline_style_value(value, property) unless value.nil?
          end
          styles["lineHeight"] = dig(attrs, "style", "typography", "lineHeight") if has.call("lineHeight") && !skip.call("lineHeight")
          styles["textAlign"] = dig(attrs, "style", "typography", "textAlign") if has.call("textAlign") && !skip.call("textAlign")
          %w[textColumns writingMode textIndent].each do |feature|
            next unless has.call(feature) && !skip.call(feature)

            value = dig(attrs, "style", "typography", feature)
            styles[feature] = value unless value.nil?
          end

          result = from_style_engine(style_engine({ "typography" => styles }, convert_vars_to_classnames: true))
          # typography.php:246 — the alignment CLASS is appended after the style engine's
          # own classnames, and only for `style.typography.textAlign`.
          if has.call("textAlign") && !skip.call("textAlign") && !dig(attrs, "style", "typography", "textAlign").nil?
            extra = "has-text-align-#{dig(attrs, "style", "typography", "textAlign")}"
            result["class"] = result["class"] ? "#{result["class"]} #{extra}" : extra
          end
          result
        end

        # wp-includes/block-supports/border.php:50. Note the asymmetry the legacy has
        # and this keeps: the whole-support skip check reads `border`, the per-feature
        # ones read `__experimentalBorder`.
        def border_feature?(type, feature)
          return true if type.supports["__experimentalBorder"] == true

          block_has_support?(type, ["__experimentalBorder", feature], false)
        end

        def apply_border(type, attrs) # rubocop:disable Metrics/AbcSize
          return {} if skip_serialization?(type, "border")

          styles = {}
          radius = dig(attrs, "style", "border", "radius")
          if border_feature?(type, "radius") && !radius.nil? &&
             !skip_serialization?(type, "__experimentalBorder", "radius")
            styles["radius"] = radius.is_a?(Numeric) ? "#{radius}px" : radius
          end
          border_style = dig(attrs, "style", "border", "style")
          if border_feature?(type, "style") && !border_style.nil? &&
             !skip_serialization?(type, "__experimentalBorder", "style")
            styles["style"] = border_style
          end
          has_width = border_feature?(type, "width")
          width = dig(attrs, "style", "border", "width")
          if has_width && !width.nil? && !skip_serialization?(type, "__experimentalBorder", "width")
            styles["width"] = width.is_a?(Numeric) ? "#{width}px" : width
          end
          has_color = border_feature?(type, "color")
          if has_color && !skip_serialization?(type, "__experimentalBorder", "color")
            preset = attrs.key?("borderColor") ? "var:preset|color|#{attrs["borderColor"]}" : nil
            styles["color"] = preset || dig(attrs, "style", "border", "color")
          end
          if has_color || has_width
            %w[top right bottom left].each do |side|
              side_values = dig(attrs, "style", "border", side)
              styles[side] = {
                "width" => side_value(side_values, "width", skip_serialization?(type, "__experimentalBorder", "width")),
                "color" => side_value(side_values, "color", skip_serialization?(type, "__experimentalBorder", "color")),
                "style" => side_value(side_values, "style", skip_serialization?(type, "__experimentalBorder", "style"))
              }
            end
          end

          from_style_engine(style_engine({ "border" => styles }))
        end

        def side_value(side_values, key, skipped)
          return nil if skipped || !side_values.is_a?(Hash)

          side_values[key]
        end

        # wp-includes/block-supports/spacing.php:47.
        def apply_spacing(type, attrs)
          return {} if skip_serialization?(type, "spacing")

          block_styles = attrs["style"]
          return {} if Styling::PhpCompat.php_empty?(block_styles)

          styles = { "padding" => nil, "margin" => nil }
          if block_has_support?(type, %w[spacing padding], false) && !skip_serialization?(type, "spacing", "padding")
            styles["padding"] = dig(attrs, "style", "spacing", "padding")
          end
          if block_has_support?(type, %w[spacing margin], false) && !skip_serialization?(type, "spacing", "margin")
            styles["margin"] = dig(attrs, "style", "spacing", "margin")
          end

          from_style_engine(style_engine({ "spacing" => styles }), classnames: false)
        end

        # wp-includes/block-supports/dimensions.php:53.
        def apply_dimensions(type, attrs)
          return {} if skip_serialization?(type, "dimensions")
          return {} if Styling::PhpCompat.php_empty?(attrs["style"])

          styles = %w[minHeight minWidth height width].each_with_object({}) do |feature, out|
            out[feature] = nil
            next unless block_has_support?(type, ["dimensions", feature], false)
            next if skip_serialization?(type, "dimensions", feature)

            out[feature] = dig(attrs, "style", "dimensions", feature)
          end

          from_style_engine(style_engine({ "dimensions" => styles }), classnames: false)
        end

        # wp-includes/block-supports/shadow.php:53.
        def apply_shadow(type, attrs)
          return {} unless block_has_support?(type, "shadow", false)
          return {} if skip_serialization?(type, "shadow")

          from_style_engine(style_engine({ "shadow" => dig(attrs, "style", "shadow") }), classnames: false)
        end

        # wp-includes/block-supports/aria-label.php:45.
        def apply_aria_label(type, attrs)
          return {} if Styling::PhpCompat.php_empty?(attrs)
          return {} unless block_has_support?(type, ["ariaLabel"], false)
          return {} if skip_serialization?(type, "ariaLabel")
          return {} unless attrs.key?("ariaLabel")

          { "aria-label" => attrs["ariaLabel"] }
        end

        # wp-includes/block-supports/anchor.php.
        def apply_anchor(type, attrs)
          return {} if Styling::PhpCompat.php_empty?(attrs)
          return {} unless block_has_support?(type, "anchor", false)
          return {} unless attrs.key?("anchor")

          { "id" => attrs["anchor"] }
        end

        def from_style_engine(styles, classnames: true)
          out = {}
          out["class"] = styles["classnames"] if classnames && !Styling::PhpCompat.php_empty?(styles["classnames"])
          out["style"] = styles["css"] unless Styling::PhpCompat.php_empty?(styles["css"])
          out
        end

        APPLIERS = {
          "align" => :apply_align, "custom-classname" => :apply_custom_classname,
          "generated-classname" => :apply_generated_classname, "colors" => :apply_colors,
          "typography" => :apply_typography, "border" => :apply_border,
          "spacing" => :apply_spacing, "dimensions" => :apply_dimensions,
          "shadow" => :apply_shadow, "aria-label" => :apply_aria_label, "anchor" => :apply_anchor
        }.freeze

        # The `packs/styling` port of WP_Block_Supports, wired with the eleven callbacks
        # above and with a BlockTypeRegistry projected from db/blocks/types.json. Built
        # once; nothing mutates it, so there is no registration hook to reach for
        # (AD-01).
        def engine
          @engine ||= begin
            supports = Styling::BlockSupports.new
            REGISTRATION_ORDER.each do |name|
              method_name = APPLIERS.fetch(name)
              supports.register(name, apply: ->(type, attributes) { public_send(method_name, type, attributes) })
            end
            supports
          end
        end

        def registry
          @registry ||= Composition::Registry.types.values.each_with_object(Styling::BlockTypeRegistry.new) do |type, reg|
            reg.register(Styling::BlockType.new(type.name, attributes: type.attributes, supports: type.supports))
          end
        end

        def reset!
          @engine = nil
          @registry = nil
        end

        # get_block_wrapper_attributes(), class-wp-block-supports.php:203. The attribute
        # ORDER of the output is the order of this table — style, class, id, aria-label,
        # then any extra the caller passed — and it is observable: post-terms renders
        # `<div style="font-weight:300" class="taxonomy-category wp-block-post-terms">`.
        MERGE_ORDER = %w[style class id aria-label].freeze

        # Only the `apply` supports are merged here. The `layout` support's classes are
        # NOT: the legacy adds those after the callback, through
        # WP_HTML_Tag_Processor::add_class() in a `render_block` filter (layout.php:1336),
        # and `SupportChain` runs that filter over the finished markup.
        def wrapper_attributes(block_name, raw_attrs, extra = {})
          new_attributes = engine.apply_block_supports(
            { "blockName" => block_name, "attrs" => raw_attrs || {} }, registry
          )
          return "" if new_attributes.empty? && extra.empty?

          attributes = {}
          MERGE_ORDER.each do |name|
            fresh = scalar_string(new_attributes[name])
            supplied = scalar_string(extra[name])
            next if fresh == "" && supplied == ""

            attributes[name] = merge(name, fresh, supplied)
          end
          extra.each do |name, value|
            next if MERGE_ORDER.include?(name)
            next unless Styling::PhpCompat.php_scalar?(value) && value != true && value != false

            attributes[name] = value.to_s
          end
          return "" if attributes.empty?

          attributes.map { |name, value| %(#{name}="#{Text.esc_attr(value)}") }.join(" ")
        end

        def scalar_string(value)
          return "" unless Styling::PhpCompat.php_scalar?(value)
          return "" if value == true || value == false

          Styling::PhpCompat.to_php_string(value)
        end

        # The four hardcoded merge callbacks, class-wp-block-supports.php:212-235.
        def merge(name, fresh, supplied)
          case name
          when "style"
            Styling::CssSafety.safecss_filter_attr(
              [fresh.strip.sub(/;+\z/, ""), supplied.strip.sub(/;+\z/, "")].reject(&:empty?).join(";")
            )
          when "class"
            # ⚠️ EXTRA classes first, then the supports' own. The screen diff sorts class
            # tokens (spec/parity/harness/normalizer.rb) so it cannot see this, which is
            # exactly why it is asserted by a unit spec instead.
            (supplied.split(/\s+/).reject(&:empty?) + fresh.split(/\s+/).reject(&:empty?)).uniq.join(" ")
          else
            supplied == "" ? fresh : supplied
          end
        end
      end

      # ── Images ──────────────────────────────────────────────────────────────────
      #
      # `wp_get_attachment_image()`, wp-includes/media.php:1169, and the two helpers it
      # calls to build `srcset` / `sizes`. Only the paths `core/post-featured-image` and
      # `core/site-logo` can reach are ported.
      module Images
        module_function

        UPLOADS_PATH = "/wp-content/uploads"

        # `wp_get_upload_dir()['baseurl']`.
        def uploads_baseurl = "#{Site.home_url}#{UPLOADS_PATH}"

        # AD-03: `_wp_attachment_metadata['file']` is `assets.metadata['file']`.
        def relative_file(asset) = asset.metadata.is_a?(Hash) ? asset.metadata["file"].to_s : ""

        def full_url(asset)
          file = relative_file(asset)
          return "" if file.empty?

          "#{uploads_baseurl}/#{file}"
        end

        # wp_image_matches_ratio(), wp-includes/media.php — the larger image is
        # constrained to the smaller and the two are compared with a 1px tolerance
        # (wp_fuzzy_number_match). It is what keeps a CROPPED thumbnail (150x150 of a
        # 1600x1200 original) out of the srcset.
        def matches_ratio?(source_w, source_h, target_w, target_h)
          if source_w > target_w
            constrained = constrain(source_w, source_h, target_w)
            expected = [target_w, target_h]
          else
            constrained = constrain(target_w, target_h, source_w)
            expected = [source_w, source_h]
          end
          (constrained[0] - expected[0]).abs <= 1 && (constrained[1] - expected[1]).abs <= 1
        end

        # wp_constrain_dimensions() with only a max width, which is the only call shape
        # matches_ratio? makes.
        def constrain(width, height, max_width)
          return [width, height] if max_width <= 0 || width <= 0

          ratio = max_width.to_f / width
          [max_width, [1, (height * ratio).round].max]
        end

        # `wp_calculate_image_srcset()` builds each candidate URL from
        # `_wp_attachment_metadata['sizes'][<name>]['file']`. AD-03 promoted that nested
        # array to `Library::Variant` rows, but `asset_variants` carries only
        # (size_name, width, height, mime_type) — no filename. The name therefore rides
        # in `assets.metadata['sizes']`, which target_data_model.md:349 already provides
        # for, and lib/seeding/pipeline.rb keeps it there.
        #
        # The canonical `<base>-<w>x<h>.<ext>` below is the fallback for an asset whose
        # metadata carries no `sizes` entry. It is what WordPress itself would have named
        # the file, so it is right for a default install and wrong for any size that was
        # renamed — this corpus's are `med-…` / `large-…`, which is exactly why the
        # filename has to be carried rather than guessed.
        def variant_file(asset, variant)
          from_metadata = Styling::PhpCompat.array_get(
            asset.metadata, ["sizes", variant.size_name.to_s, "file"], nil
          )
          return from_metadata.to_s if from_metadata.is_a?(String) && !from_metadata.empty?

          base = File.basename(relative_file(asset))
          ext = File.extname(base)
          "#{File.basename(base, ext)}-#{variant.width}x#{variant.height}#{ext}"
        end

        # wp_calculate_image_srcset(), wp-includes/media.php:1460.
        MAX_SRCSET_IMAGE_WIDTH = 2048

        def srcset(asset, src_url, width, height)
          return nil if width.to_i < 1 || asset.width.to_i < 1 || asset.height.to_i < 1

          dirname = File.dirname(relative_file(asset))
          baseurl = dirname == "." ? "#{uploads_baseurl}/" : "#{uploads_baseurl}/#{dirname}/"

          candidates = asset.variants.map do |variant|
            { file: variant_file(asset, variant), width: variant.width, height: variant.height }
          end
          # media.php:1485 — the FULL size is appended to the candidate list.
          candidates << { file: File.basename(relative_file(asset)), width: asset.width, height: asset.height }

          sources = {}
          src_matched = false
          candidates.each do |candidate|
            is_src = false
            if !src_matched && src_url.include?("#{baseurl}#{candidate[:file]}")
              src_matched = true
              is_src = true
            end
            next if candidate[:width] > MAX_SRCSET_IMAGE_WIDTH && !is_src
            next unless matches_ratio?(width, height, candidate[:width], candidate[:height])

            source = "#{baseurl}#{candidate[:file]}".gsub(" ", "%20") + " #{candidate[:width]}w"
            # media.php:1597 — "The 'src' image has to be the first in the 'srcset',
            # because of a bug in iOS8." That is why the full size leads here even though
            # it is the last candidate considered.
            sources = { candidate[:width] => source }.merge(sources) if is_src
            sources[candidate[:width]] = source unless is_src
          end
          return nil if !src_matched || sources.length < 2

          sources.values.join(", ")
        end

        # wp_calculate_image_sizes(), wp-includes/media.php.
        def sizes_attribute(width) = format("(max-width: %<w>dpx) 100vw, %<w>dpx", w: width.to_i)

        # wp_get_loading_optimization_attributes(), wp-includes/media.php.
        #
        # ⚠️ APPROXIMATED, deliberately and visibly. The legacy decides `loading` and
        # `fetchpriority` from a PAGE-SCOPED COUNTER (`wp_increase_content_media_count()`,
        # a function-static) plus `wp_omit_loading_img_threshold()`. That counter is
        # global mutable state, which paradigm_decision.md implication 1 forbids, and the
        # only page-scoped object a renderer is handed — `ctx.styles` — is not mine to
        # extend. See the report: this needs a counter on `RenderContext`.
        #
        # What is implemented is the size half of the rule, which is what decides the
        # outcome for all 18 golden screens (each carries exactly one featured image and
        # at most three avatars, so the counter never reaches the threshold):
        # `wp_maybe_add_fetchpriority_high_attr()` requires width*height >= 50000.
        FETCHPRIORITY_MIN_AREA = 50_000

        def loading_optimization(width, height)
          attributes = { "decoding" => "async" }
          return attributes if width.to_i <= 0 || height.to_i <= 0
          return attributes if width.to_i * height.to_i < FETCHPRIORITY_MIN_AREA

          attributes["fetchpriority"] = "high"
          attributes
        end

        # image_hwstring(), wp-includes/media.php.
        def hwstring(width, height)
          out = +""
          out << %(width="#{width.to_i}" ) if width.to_i.positive?
          out << %(height="#{height.to_i}" ) if height.to_i.positive?
          out
        end

        # wp_get_attachment_image(), wp-includes/media.php:1169. `size` is only ever
        # 'post-thumbnail' or 'full' here, and neither resolves to an intermediate file
        # for this corpus, so the full-size source is the one path implemented.
        def attachment_image(asset, size:, attr: {}, dimensions: nil)
          return "" if asset.nil?

          src = full_url(asset)
          return "" if src.empty?

          width = asset.width.to_i
          height = asset.height.to_i
          # `wp_get_attachment_image_src` is filtered by core's OWN callback in
          # site-logo.php:18 — the block installs and removes it itself, so it is the
          # block's behaviour, not an extension point (AD-01). It rewrites $image[1] and
          # $image[2], which then drive image_hwstring(), wp_calculate_image_srcset(),
          # wp_calculate_image_sizes() and the loading optimization alike.
          width, height = dimensions if dimensions
          size_class = size.to_s

          attributes = {
            "src" => src,
            "class" => "attachment-#{size_class} size-#{size_class}",
            "alt" => Text.strip_all_tags(asset.alt_text.to_s)
          }
          # wp_parse_args($attr, $default_attr): the CALLER's values win, and any key the
          # defaults do not carry is appended in the caller's order.
          attr.each { |name, value| attributes[name.to_s] = value }

          attributes.merge!(loading_optimization(width, height))
          attributes.delete("decoding") unless %w[async sync auto].include?(attributes["decoding"])

          if Styling::PhpCompat.php_empty?(attributes["srcset"])
            set = srcset(asset, src, width, height)
            sizes = sizes_attribute(width)
            if set && (sizes || !Styling::PhpCompat.php_empty?(attributes["sizes"]))
              attributes["srcset"] = set
              attributes["sizes"] = sizes if Styling::PhpCompat.php_empty?(attributes["sizes"])
            end
          end

          body = attributes.map { |name, value| %( #{name}="#{Text.esc_attr(value)}") }.join
          "<img #{hwstring(width, height)}".rstrip + body + " />"
        end

        # get_the_post_thumbnail(), wp-includes/post-thumbnail-template.php:165, plus
        # `_wp_post_thumbnail_class_filter()` (media.php:2525) which is core's own
        # listener and therefore behaviour, not extension (AD-01).
        def post_thumbnail(asset, size:, attr: {})
          merged = attr.dup
          base_class = "attachment-#{size} size-#{size}"
          merged["class"] = merged.key?("class") ? "#{merged["class"]} wp-post-image" : "#{base_class} wp-post-image"
          attachment_image(asset, size: size, attr: merged)
        end
      end

      # ── Avatars ─────────────────────────────────────────────────────────────────
      #
      # `get_avatar()` / `get_avatar_data()`, wp-includes/link-template.php &
      # pluggable.php. WordPress 7.x hashes the address with SHA-256.
      module Avatars
        module_function

        BASE_URL = "https://secure.gravatar.com/avatar/"

        def hash_for(email)
          Digest::SHA256.hexdigest(email.to_s.strip.downcase)
        end

        def url(email, size)
          "#{BASE_URL}#{hash_for(email)}?s=#{size.to_i}&d=#{Site.avatar_default}&r=#{Site.avatar_rating}"
        end

        # get_avatar(), wp-includes/pluggable.php. The attribute ORDER is fixed by the
        # sprintf() there — alt, src, srcset, class, height, width, extra — and so are
        # the SINGLE quotes, which is why the golden files show `alt='…'` beside the
        # double-quoted attributes of every other block.
        def img(email:, size:, alt:, image_class:, extra_attr: "")
          size = size.to_i
          classes = ["avatar", "avatar-#{size}", "photo"]
          classes << image_class unless image_class.to_s.empty?
          # get_avatar(), wp-includes/pluggable.php: `loading`, `fetchpriority` and
          # `decoding` are APPENDED to `extra_attr`, separated by a single space only
          # when extra_attr is non-empty. `extra_attr` itself already carries a LEADING
          # space (avatar.php:32 sprintf(' style="%s"')), which is why the golden files
          # show two spaces before `style` and one before `decoding`.
          #
          # ⚠️ Same page-scoped-counter approximation as Images.loading_optimization: an
          # avatar is far below the fetchpriority area threshold and inside the
          # media-count threshold on every golden screen, so it carries `decoding` alone.
          attributes = extra_attr.to_s
          attributes += " " unless attributes.empty?
          attributes += "decoding='async'"
          format(
            "<img alt='%<alt>s' src='%<src>s' srcset='%<srcset>s' class='%<class>s' " \
            "height='%<height>d' width='%<width>d' %<extra>s/>",
            alt: Text.esc_attr(alt), src: Text.esc_url(url(email, size)),
            srcset: "#{Text.esc_url(url(email, size * 2))} 2x",
            class: Text.esc_attr(classes.join(" ")),
            height: size, width: size, extra: attributes
          )
        end
      end

      # ── The filter chain around every callback ──────────────────────────────────
      #
      # `render_block()` (wp-includes/blocks.php) wraps EVERY block's callback in two
      # filter passes core registers unconditionally, and a page renders every block
      # through it (the root via render_block(), the rest via class-wp-block.php:614):
      #
      #   * `render_block_data`, BEFORE the callback — `wp_render_elements_support_styles`
      #     (elements.php:308) allocates `wp-elements-<n>` with wp_unique_prefixed_id(),
      #     stores the element CSS, and APPENDS the class to `attrs.className`
      #     (elements.php:186-188). That is why it lands through the custom-classname
      #     support, BETWEEN the callback's own classes and the generated `wp-block-…`:
      #     `class="has-link-color wp-elements-1 wp-block-post-date has-text-color …"`.
      #   * `render_block`, AFTER — typography (fluid font size), settings, elements
      #     class name, layout (`is-layout-*` + `wp-container-*-<hash>` and its rule),
      #     dimensions, block-style variation class name.
      #
      # Both halves are the shared port in `Renderers::LayoutBlocks`; this module only
      # delegates, exactly as `QueryBlocks::SupportChain` does and for the same reason —
      # a second copy of the layout hash would drift, and the hash names the CSS rule.
      #
      # Verified against the oracle rather than assumed: with `render_block_data` applied
      # to the root block, post_blocks_oracle.php emits `wp-elements-1…6` for the six
      # cases carrying `style.elements.link.color`, and without it none — see
      # spec/models/composition/post_blocks_differential_spec.rb.
      #
      # ⚠️ The legacy mutates `$parsed_block` — its per-request copy. The parsed block
      # here may be shared (a template is parsed once and rendered per request), so the
      # renderer swaps in a COPY carrying the merged className and never writes through.
      module SupportChain
        def render
          elements_class = LayoutBlocks::ElementsSupport.prepare(block, ctx)
          if elements_class
            raw = block.attrs.is_a?(Hash) ? block.attrs : {}
            merged = [raw["className"].to_s, elements_class].reject(&:empty?).join(" ")
            @block = Parser::Block.new(
              block_name: block.block_name, attrs: raw.merge("className" => merged),
              inner_blocks: block.inner_blocks, inner_html: block.inner_html,
              inner_content: block.inner_content
            )
            @attrs = type ? type.prepare_attributes(@block.attrs) : @block.attrs
          end

          html = super.to_s
          return html if html.strip.empty?

          LayoutBlocks.apply_supports(html, block, ctx, elements_class)
        end
      end

      # ── The family's shared renderer base ───────────────────────────────────────
      class Block < Renderers::Base
        # Every concrete renderer defines its own `render` without calling super, so the
        # chain must sit in front of EACH subclass (a module prepended to `Block` alone
        # would be shadowed by the subclass's method). Same effect as the seven explicit
        # `prepend SupportChain` lines in query_blocks.rb, stated once.
        def self.inherited(subclass)
          super
          subclass.prepend(SupportChain)
        end

        private

        # Every render callback in this family ends with
        # `get_block_wrapper_attributes( array( 'class' => … ) )`. The RAW attrs go in,
        # exactly as `WP_Block_Supports::apply_block_supports()` receives them
        # (BR-MIGRATE-204 re-applies the schema defaults inside).
        def wrapper(extra = {}) = Supports.wrapper_attributes(block.block_name, block.attrs, extra)

        def screen = @screen ||= Screen.new(ctx)

        # `isset( $block->context['postId'] )`. `ctx.post` is that context here
        # (paradigm_decision.md implication 1); `ctx.context["postId"]` is honoured too
        # because the block schemas name it.
        def context_post
          return ctx.post if ctx.post

          id = ctx.context["postId"]
          id && Publishing::Post.find_by(id: id)
        end

        # The two class fragments every one of these callbacks builds by hand, before
        # the supports get a say.
        def text_align_class(classes)
          classes << "has-text-align-#{attrs["textAlign"]}" if attrs.key?("textAlign")
          classes
        end

        def link_color_class(classes)
          classes << "has-link-color" if Supports.dig(attrs, "style", "elements", "link", "color", "text")
          classes
        end

        def align_and_link_classes(*seed)
          link_color_class(text_align_class(seed))
        end

        # `0 === $attributes['level'] ? 'p' : 'h' . (int) $attributes['level']`.
        def heading_tag(level) = level.to_i.zero? ? "p" : "h#{level.to_i}"
      end

      # ── core/site-title ─────────────────────────────────────────────────────────
      # wp-includes/blocks/site-title.php:17.
      class SiteTitle < Block
        handles "core/site-title"

        def render
          # `get_bloginfo( 'name' )` with the DEFAULT filter argument, which is 'raw' —
          # so the `bloginfo` display chain (wptexturize/convert_chars/esc_html) does NOT
          # run. BR-MIGRATE-014: the value is already HTML-escaped at rest, which is why
          # `Configuration::Setting.display` exists and why esc_html below leaves
          # `&quot;` alone (`_wp_specialchars` does not double-encode).
          site_title = Configuration::Setting.display("blogname").to_s
          return "" if site_title.strip.empty?

          classes = attrs["textAlign"].to_s.empty? ? +"" : +"has-text-align-#{attrs["textAlign"]}"
          classes << " has-link-color" if Supports.dig(attrs, "style", "elements", "link", "color", "text")
          tag = attrs.key?("level") ? heading_tag(attrs["level"]) : "h1"

          body = if attrs["isLink"]
                   %(<a href="#{Text.esc_url(Site.home_url)}" target="#{Text.esc_attr(link_target)}" ) +
                     %(rel="home"#{aria_current}>#{Text.esc_html(site_title)}</a>)
                 else
                   Text.esc_html(site_title)
                 end

          "<#{tag} #{wrapper("class" => classes.strip)}>#{body}</#{tag}>"
        end

        private

        def link_target = attrs["linkTarget"].to_s.empty? ? "_self" : attrs["linkTarget"]

        # site-title.php:34. `! is_paged() && ( is_front_page() || is_home() && the blog
        # page is not a static page )`. The `page_for_posts` half is inert here: AD-06
        # keeps that setting, and with no static posts page configured the comparison is
        # always true.
        def aria_current
          return "" if screen.paged?
          return "" unless screen.front_page? || screen.home?

          ' aria-current="page"'
        end
      end

      # ── core/site-tagline ───────────────────────────────────────────────────────
      # wp-includes/blocks/site-tagline.php:17. Note the tagline is NOT escaped by the
      # callback: it is printed exactly as stored (already sanitized on write,
      # BR-MIGRATE-014).
      class SiteTagline < Block
        handles "core/site-tagline"

        def render
          tagline = Configuration::Setting.display("blogdescription").to_s
          # `return;` — PHP's null, which render_block concatenates as ''.
          return "" if tagline.empty?

          align_class = attrs["textAlign"].to_s.empty? ? "" : "has-text-align-#{attrs["textAlign"]}"
          attributes = wrapper("class" => align_class)
          tag = attrs.key?("level") && attrs["level"].to_i != 0 ? "h#{attrs["level"].to_i}" : "p"

          "<#{tag} #{attributes}>#{tagline}</#{tag}>"
        end
      end

      # ── core/site-logo ──────────────────────────────────────────────────────────
      # wp-includes/blocks/site-logo.php:17 and `get_custom_logo()`
      # (wp-includes/general-template.php).
      #
      # `_override_custom_logo_theme_mod()` makes the `site_logo` OPTION the source of
      # truth over the theme mod, so the option is the only input modelled — AD-01 leaves
      # no way for a theme mod to win, and AD-06 keeps the option.
      class SiteLogo < Block
        handles "core/site-logo"

        HOME_LINK_NEW_TAB_LABEL = "(Home link, opens in a new tab)"

        def render
          logo = custom_logo
          # "Return early if no custom logo is set, avoiding extraneous wrapper div."
          return "" if logo.empty?

          # site-logo.php:37 — `#<a.*?>(.*?)</a>#i`. PHP's `.` does NOT cross a newline
          # without the `s` modifier, so this is `/i` only, never `/im`.
          logo = logo.gsub(%r{<a.*?>(.*?)</a>}i) { Regexp.last_match(1) } unless attrs["isLink"]
          logo = open_home_link_in_new_tab(logo) if attrs["isLink"] && attrs["linkTarget"] == "_blank"
          classnames = Styling::PhpCompat.php_empty?(attrs["width"]) ? "is-default-size" : ""
          "<div #{wrapper("class" => classnames)}>#{logo}</div>"
        end

        private

        # site-logo.php:41-51 — "Add the link target after the rel=\"home\"." The tag
        # processor inserts a newly set attribute directly after the tag name, which is
        # why `aria-label` and `target` precede `href` in the output.
        def open_home_link_in_new_tab(logo)
          processor = Markup::TagProcessor.new(logo)
          processor.next_tag("a")
          if processor.get_attribute("rel") == "home"
            processor.set_attribute("aria-label", HOME_LINK_NEW_TAB_LABEL)
            processor.set_attribute("target", attrs["linkTarget"])
          end
          processor.get_updated_html
        end

        def custom_logo
          asset = logo_asset
          return "" if asset.nil?

          attr = { "class" => "custom-logo" }
          attr["alt"] = Configuration::Setting.display("blogname").to_s if asset.alt_text.to_s.empty?
          image = Images.attachment_image(asset, size: "full", attr: attr, dimensions: scaled_dimensions(asset))
          %(<a href="#{Text.esc_url("#{Site.home_url}/")}" class="custom-logo-link" rel="home">#{image}</a>)
        end

        # site-logo.php:18-24, the `$adjust_width_height_filter` closure the callback
        # installs around its own `get_custom_logo()` call:
        #   $height = (float) $attributes['width'] / ( (float) $image[1] / (float) $image[2] );
        #   return array( $image[0], (int) $attributes['width'], (int) $height );
        # `(int)` truncates toward zero, and the guard is PHP `empty()` so width 0 is no
        # override at all.
        def scaled_dimensions(asset)
          width = attrs["width"]
          return nil if Styling::PhpCompat.php_empty?(width)
          return nil if asset.width.to_i.zero? || asset.height.to_i.zero?

          [width.to_i, (width.to_f / (asset.width.to_f / asset.height.to_f)).to_i]
        end

        def logo_asset
          id = Configuration::Setting["site_logo"]
          return nil if id == false || id.to_s.empty?

          Library::Asset.find_by(id: id)
        end
      end

      # ── Dates ───────────────────────────────────────────────────────────────────
      #
      # `wp_date()` / `get_the_date()`, wp-includes/functions.php & general-template.php.
      # AD-07 collapsed the legacy's paired local/GMT columns into ONE `timestamptz`, so
      # the local wall clock is derived here from `timezone_string` rather than stored.
      module Dates
        module_function

        # PHP's date() format characters, in the subset WordPress's own default formats
        # and this theme's block attributes can produce. `\` escapes the next character,
        # exactly as PHP does.
        def php_date(format, time)
          out = +""
          escaped = false
          format.to_s.each_char do |char|
            if escaped
              out << char
              escaped = false
            elsif char == "\\"
              escaped = true
            else
              out << token(char, time)
            end
          end
          out
        end

        DAY_SUFFIXES = { 1 => "st", 21 => "st", 31 => "st", 2 => "nd", 22 => "nd", 3 => "rd", 23 => "rd" }.freeze

        def token(char, time) # rubocop:disable Metrics/CyclomaticComplexity
          case char
          when "d" then format("%02d", time.day)
          when "j" then time.day.to_s
          when "S" then DAY_SUFFIXES.fetch(time.day, "th")
          when "D" then time.strftime("%a")
          when "l" then time.strftime("%A")
          when "N" then (time.wday.zero? ? 7 : time.wday).to_s
          when "w" then time.wday.to_s
          when "z" then (time.yday - 1).to_s
          when "W" then time.strftime("%V")
          when "F" then time.strftime("%B")
          when "M" then time.strftime("%b")
          when "m" then format("%02d", time.month)
          when "n" then time.month.to_s
          when "t" then Date.new(time.year, time.month, -1).day.to_s
          when "L" then (Date.leap?(time.year) ? "1" : "0")
          when "Y" then time.year.to_s
          when "y" then format("%02d", time.year % 100)
          when "a" then time.hour < 12 ? "am" : "pm"
          when "A" then time.hour < 12 ? "AM" : "PM"
          when "g" then ((time.hour % 12).zero? ? 12 : time.hour % 12).to_s
          when "G" then time.hour.to_s
          when "h" then format("%02d", (time.hour % 12).zero? ? 12 : time.hour % 12)
          when "H" then format("%02d", time.hour)
          when "i" then format("%02d", time.min)
          when "s" then format("%02d", time.sec)
          when "e" then time.time_zone.respond_to?(:tzinfo) ? time.time_zone.tzinfo.name : time.zone.to_s
          when "T" then time.strftime("%Z")
          when "P" then time.strftime("%:z")
          when "O" then time.strftime("%z")
          when "Z" then time.utc_offset.to_s
          when "U" then time.to_i.to_s
          when "c" then time.strftime("%Y-%m-%dT%H:%M:%S%:z")
          when "r" then time.strftime("%a, %d %b %Y %H:%M:%S %z")
          else char
          end
        end

        def in_site_zone(instant) = instant&.in_time_zone(Site.timezone)

        # get_the_date( $format, $post ).
        def the_date(post, format = nil)
          local = in_site_zone(post&.published_at)
          return "" if local.nil?

          php_date(format.presence || Site.date_format, local)
        end

        def the_modified_date(post, format = nil)
          local = in_site_zone(post&.modified_at)
          return "" if local.nil?

          php_date(format.presence || Site.date_format, local)
        end

        # human_time_diff(), wp-includes/formatting.php:4046 — the unfiltered strings.
        def human_time_diff(from, to = Time.current)
          diff = (to.to_i - from.to_i).abs
          if diff < 3600
            mins = [(diff / 60.0).round, 1].max
            mins <= 1 ? "1 min" : "#{mins} mins"
          elsif diff < 86_400
            hours = [(diff / 3600.0).round, 1].max
            hours <= 1 ? "1 hour" : "#{hours} hours"
          elsif diff < 604_800
            days = [(diff / 86_400.0).round, 1].max
            days <= 1 ? "1 day" : "#{days} days"
          elsif diff < 2_629_746
            weeks = [(diff / 604_800.0).round, 1].max
            weeks <= 1 ? "1 week" : "#{weeks} weeks"
          elsif diff < 31_556_952
            months = [(diff / 2_629_746.0).round, 1].max
            months <= 1 ? "1 month" : "#{months} months"
          else
            years = [(diff / 31_556_952.0).round, 1].max
            years <= 1 ? "1 year" : "#{years} years"
          end
        end
      end

      # ── core/post-title ─────────────────────────────────────────────────────────
      # wp-includes/blocks/post-title.php:19. BR-MIGRATE-199.
      class PostTitle < Block
        handles "core/post-title"

        def render
          post = context_post
          return "" if post.nil?

          title = Text.the_title(post)
          return "" if title.empty?

          tag = attrs.key?("level") ? heading_tag(attrs["level"]) : "h2"

          if attrs["isLink"]
            rel = attrs["rel"].to_s.empty? ? "" : %(rel="#{Text.esc_attr(attrs["rel"])}")
            # The trailing space before `>` is the sprintf's, and it survives into the
            # golden files whenever `rel` is empty: `target="_self" >`.
            title = %(<a href="#{Text.esc_url(Links.permalink(post))}" ) +
                    %(target="#{Text.esc_attr(attrs["linkTarget"])}" #{rel}>#{title}</a>)
          end

          "<#{tag} #{wrapper("class" => align_and_link_classes.join(" "))}>#{title}</#{tag}>"
        end
      end

      # ── core/post-date ──────────────────────────────────────────────────────────
      # wp-includes/blocks/post-date.php:19, and the `core/post-data` block-bindings
      # source it delegates to (wp-includes/block-bindings/post-data.php:21).
      class PostDate < Block
        handles "core/post-date"

        def render
          post = context_post
          classes = []
          datetime = attrs["datetime"]

          unless attrs.key?("datetime")
            # post-date.php:28 — "the legacy version of the block that didn't have the
            # `datetime` attribute", kept for back-compat and taken by every block in
            # this theme.
            field = attrs["displayType"] == "modified" ? "modified" : "date"
            classes << "wp-block-post-date__modified-date" if field == "modified"
            datetime = post_data_value(field, post)
          end
          return "" if datetime.to_s.empty?

          formatted = formatted_date(datetime)
          text_align_class(classes)
          link_color_class(classes)

          time_tag = %(<time datetime="#{Text.esc_attr(datetime)}">#{Text.esc_html(formatted)}</time>)
          if attrs["isLink"] && post
            time_tag = %(<a href="#{Text.esc_url(Links.permalink(post))}">#{time_tag}</a>)
          end

          "<div #{wrapper("class" => classes.join(" "))}>#{time_tag}</div>"
        end

        private

        # post-data.php:57 — the binding refuses to leak a post that is not publicly
        # viewable, or one behind a password. That is why the password-protected article
        # renders its title but NO date in every golden archive screen.
        def post_data_value(field, post)
          return nil if post.nil?
          return nil unless post.status.to_s == "published"
          return nil if post.password_digest.present?

          case field
          when "date" then Text.esc_attr(Dates.the_date(post, "c"))
          when "modified"
            return "" unless post.modified_at && post.published_at && post.modified_at > post.published_at

            Text.esc_attr(Dates.the_modified_date(post, "c"))
          end
        end

        def formatted_date(datetime)
          instant = Time.zone.parse(datetime.to_s)
          return "" if instant.nil?

          if attrs["format"] == "human-diff"
            local = instant.in_time_zone(Site.timezone)
            return format("%s from now", Dates.human_time_diff(local)) if local > Time.current

            format("%s ago", Dates.human_time_diff(local))
          else
            format_string = attrs["format"].to_s.empty? ? Site.date_format : attrs["format"]
            Dates.php_date(format_string, instant.in_time_zone(Site.timezone))
          end
        end
      end

      # ── core/post-author-name ───────────────────────────────────────────────────
      # wp-includes/blocks/post-author-name.php:18.
      class PostAuthorName < Block
        handles "core/post-author-name"

        def render
          author = resolve_author
          return "" if author.nil?

          name = author.display_name.to_s
          if attrs["isLink"]
            name = %(<a href="#{Text.esc_url(Links.author_posts_url(author))}" ) +
                   %(target="#{Text.esc_attr(attrs["linkTarget"])}" class="wp-block-post-author-name__link">#{name}</a>)
          end

          "<div #{wrapper("class" => align_and_link_classes.join(" "))}>#{name}</div>"
        end

        private

        # post-author-name.php:19-27 — the post's author, or `get_query_var('author')`
        # outside a post. The `post_type_supports( …, 'author' )` guard at line 29 is
        # inert: AD-02 keeps only `post` and `page`, and both support authors.
        def resolve_author
          post = context_post
          return post.author if post

          queried = screen.queried_object
          queried.is_a?(Identity::User) ? queried : nil
        end
      end

      # ── core/post-author ────────────────────────────────────────────────────────
      # wp-includes/blocks/post-author.php:18.
      class PostAuthor < Block
        handles "core/post-author"

        def render
          author = resolve_author
          return "" if author.nil?

          name = author.display_name.to_s
          # ⚠️ post-author.php:40 — `! empty( $attributes['isLink'] && ! empty(
          # $attributes['linkTarget'] ) )`. The parenthesis is misplaced IN THE LEGACY:
          # `empty()` is applied to the whole `&&` expression, so the condition is
          # "isLink AND linkTarget non-empty". Reproduced, not corrected.
          if attrs["isLink"] && !attrs["linkTarget"].to_s.empty?
            name = %(<a href="#{Text.esc_url(Links.author_posts_url(author))}" ) +
                   %(target="#{Text.esc_attr(attrs["linkTarget"])}">#{name}</a>)
          end

          classes = []
          classes << "items-justified-#{attrs["itemsJustification"]}" if attrs.key?("itemsJustification")
          text_align_class(classes)
          link_color_class(classes)

          avatar = attrs["avatarSize"].to_i.positive? ? avatar_for(author) : nil
          byline = attrs["byline"].to_s

          out = +"<div #{wrapper("class" => classes.join(" "))}>"
          out << %(<div class="wp-block-post-author__avatar">#{avatar}</div>) if attrs["showAvatar"]
          out << '<div class="wp-block-post-author__content">'
          out << %(<p class="wp-block-post-author__byline">#{Text.kses_post(byline)}</p>) unless byline.empty?
          out << %(<p class="wp-block-post-author__name">#{name}</p>)
          # ⚠️ `get_the_author_meta( 'user_description', … )`. AD-03 promoted the core-owned
          # usermeta keys to columns, but `user_description` did NOT get one — see the
          # report. The paragraph is emitted regardless, exactly as the legacy does when
          # the description is empty, so only the TEXT is missing, never the element.
          out << %(<p class="wp-block-post-author__bio">#{author_bio(author)}</p>) if attrs["showBio"]
          out << "</div></div>"
        end

        private

        def resolve_author
          post = context_post
          return post.author if post

          queried = screen.queried_object
          queried.is_a?(Identity::User) ? queried : nil
        end

        def author_bio(author) = author.respond_to?(:description) ? author.description.to_s : ""

        # `get_avatar( $author_id, $size )` with no class and no alt.
        def avatar_for(author)
          Avatars.img(email: author.email, size: attrs["avatarSize"], alt: "", image_class: "")
        end
      end

      # ── core/post-terms ─────────────────────────────────────────────────────────
      # wp-includes/blocks/post-terms.php:18 and `get_the_term_list()`.
      class PostTerms < Block
        handles "core/post-terms"

        def render
          post = context_post
          return "" if post.nil? || attrs["term"].to_s.empty?
          # `is_taxonomy_viewable()`: the two built-in taxonomies are public.
          return "" unless %w[category post_tag].include?(attrs["term"])

          classes = align_and_link_classes("taxonomy-#{attrs["term"]}")
          # post-terms.php:35/40/45 use PHP `empty()` and PHP truthiness, for which the
          # string "0" is FALSE. `separator: "0"` therefore falls back to " ", and a
          # prefix or suffix of "0" emits no span at all. `String#empty?` disagrees.
          separator = Styling::PhpCompat.php_empty?(attrs["separator"]) ? " " : attrs["separator"]

          prefix = +"<div #{wrapper("class" => classes.join(" "))}>"
          unless Styling::PhpCompat.php_empty?(attrs["prefix"])
            prefix << %(<span class="wp-block-post-terms__prefix">#{attrs["prefix"]}</span>)
          end
          suffix = +"</div>"
          unless Styling::PhpCompat.php_empty?(attrs["suffix"])
            suffix = %(<span class="wp-block-post-terms__suffix">#{attrs["suffix"]}</span>) + suffix
          end

          terms = terms_for(post)
          return "" if terms.empty?

          links = terms.map { |term| %(<a href="#{Text.esc_url(Links.term_link(term))}" rel="tag">#{term.name}</a>) }
          joiner = %(<span class="wp-block-post-terms__separator">#{Text.esc_html(separator)}</span>)
          Text.kses_post(prefix) + links.join(joiner) + Text.kses_post(suffix)
        end

        private

        # `get_the_terms()` -> `wp_get_object_terms()`, whose unfiltered default ordering
        # is name ASC.
        def terms_for(post)
          Classification::Assignment
            .where(classifiable_type: "Publishing::Post", classifiable_id: post.id)
            .includes(term: :taxonomy)
            .map(&:term)
            .select { |term| term.taxonomy&.name == attrs["term"] }
            .sort_by(&:name)
        end
      end

      # ── core/post-content ───────────────────────────────────────────────────────
      # wp-includes/blocks/post-content.php:18.
      class PostContent < Block
        handles "core/post-content"

        ALLOWED_TAG_NAMES = %w[div main section article].freeze
        SEEN_KEY = "postContentSeenIds"

        def render
          post = context_post
          return "" if post.nil?

          # post-content.php:19/27 — a `static $seen_ids` guard against a post whose
          # content embeds itself. A function-static is global mutable state
          # (paradigm_decision.md implication 1), so the set travels down the child
          # context instead: identical protection, no ambient state, and re-entrant.
          seen = Array(ctx.context[SEEN_KEY])
          # WP_DEBUG is off in the oracle, so the halted-render message is never the
          # value; the empty string is.
          return "" if seen.include?(post.id)

          inner = ctx.with(post: post, context: { SEEN_KEY => seen + [post.id] })
          content = Text.the_content(post, inner)
          return "" if content.empty?

          supplied = attrs["tagName"]
          tag = supplied.is_a?(String) && ALLOWED_TAG_NAMES.include?(supplied.downcase) ? supplied.downcase : "div"

          # post-content.php:62 — `get_block_wrapper_attributes( array( 'class' =>
          # 'entry-content' ) )` and nothing else. The `is-layout-*`, `has-global-padding`
          # and `wp-container-core-post-content-is-layout-<hash>` classes the golden files
          # show on this element are the layout support's (layout.php:984, a
          # `render_block` filter), added AFTER the callback by `SupportChain`.
          "<#{tag} #{wrapper("class" => "entry-content")}>#{content}</#{tag}>"
        end
      end

      # ── core/post-excerpt ───────────────────────────────────────────────────────
      # wp-includes/blocks/post-excerpt.php:18.
      class PostExcerpt < Block
        handles "core/post-excerpt"

        def render
          post = context_post
          return "" if post.nil?

          more_text = if attrs["moreText"].to_s.empty?
                        ""
                      else
                        %(<a class="wp-block-post-excerpt__more-link" href="#{Text.esc_url(Links.permalink(post))}">) +
                          "#{Text.kses_post(attrs["moreText"])}</a>"
                      end

          excerpt = the_excerpt(post, more_text)
          excerpt = Text.trim_words(excerpt, attrs["excerptLength"]) if attrs.key?("excerptLength")

          content = +%(<p class="wp-block-post-excerpt__excerpt">#{excerpt})
          show_on_new_line = !attrs.key?("showMoreOnNewLine") || attrs["showMoreOnNewLine"]
          if show_on_new_line && !more_text.empty?
            content << %(</p><p class="wp-block-post-excerpt__more-text">#{more_text}</p>)
          else
            content << " #{more_text}</p>"
          end

          "<div #{wrapper("class" => align_and_link_classes.join(" "))}>#{content}</div>"
        end

        private

        # get_the_excerpt() -> wp_trim_excerpt(), wp-includes/formatting.php. The
        # `excerpt_more` override at post-excerpt.php:24 is the block deciding that its
        # OWN more-link replaces the default ' […]' — under AD-01 that is expressed as
        # the argument it is, not as a filter installed and removed around a call.
        def the_excerpt(post, more_text)
          # get_the_excerpt(), wp-includes/post-template.php:423 — a protected post's
          # excerpt is this fixed sentence, before the stored excerpt is even looked at.
          # No cookie can clear post_password_required() until Wave 3.
          return "There is no excerpt because this is a protected post." if post.password_digest.present?

          stored = post.excerpt.to_s
          return stored unless stored.strip.empty?

          rendered = Text.the_content(post, ctx.with(post: post))
          return "" if rendered.empty?

          excerpt_more = more_text.empty? ? " [&hellip;]" : ""
          # post-excerpt.php:52 — excerpt_length is temporarily raised to 101 so that
          # wp_trim_words below, not wp_trim_excerpt, applies the block's own length.
          Text.trim_words(rendered, 101, excerpt_more)
        end
      end

      # ── core/post-featured-image ────────────────────────────────────────────────
      # wp-includes/blocks/post-featured-image.php:18.
      #
      # AD-03 promoted `_thumbnail_id` postmeta to a real FK, so `get_post_thumbnail_id()`
      # is `post.featured_asset`.
      class PostFeaturedImage < Block
        handles "core/post-featured-image"

        def render
          post = context_post
          return "" if post.nil?

          is_link = attrs["isLink"]
          size_slug = attrs["sizeSlug"].to_s.empty? ? "post-thumbnail" : attrs["sizeSlug"]
          attr = Borders.attributes(block.attrs)
          overlay = overlay_markup

          if is_link
            title = Text.the_title(post)
            attr["alt"] = title.empty? ? format("Untitled post %d", post.id) : Text.strip_all_tags(title).strip
          end

          extra = extra_styles
          attr["style"] = attr["style"].to_s.empty? ? extra : "#{attr["style"]}#{extra}" unless extra.empty?

          image = post.featured_asset ? Images.post_thumbnail(post.featured_asset, size: size_slug, attr: attr) : ""
          return "" if image.empty?

          image = if is_link
                    rel = attrs["rel"].to_s.empty? ? "" : %(rel="#{Text.esc_attr(attrs["rel"])}")
                    %(<a href="#{Text.esc_url(Links.permalink(post))}" ) +
                      %(target="#{Text.esc_attr(attrs["linkTarget"])}" #{rel}>#{image}#{overlay}</a>)
                  else
                    "#{image}#{overlay}"
                  end

          "<figure #{wrapper}>#{image}</figure>"
        end

        private

        # post-featured-image.php:42-77, in that exact order: aspect ratio, then height
        # or an implied `height:auto`, then width, then object-fit, then shadow.
        def extra_styles
          styles = +""
          has_width = attrs.key?("width") && !attrs["width"].nil? && attrs["width"] != ""
          has_height = attrs.key?("height") && !attrs["height"].nil? && attrs["height"] != ""

          unless attrs["aspectRatio"].to_s.empty?
            unless attrs["aspectRatio"] == "auto"
              styles << "#{Text.esc_attr(safe_css("aspect-ratio:#{attrs["aspectRatio"]}"))};"
            end
            styles << "width:100%;"
          end
          if has_height
            styles << "#{Text.esc_attr(safe_css("height:#{attrs["height"]}"))};"
          elsif has_width
            styles << "height:auto;"
          end
          styles << "#{Text.esc_attr(safe_css("width:#{attrs["width"]}"))};" if has_width
          styles << "#{Text.esc_attr(safe_css("object-fit:#{attrs["scale"]}"))};" unless attrs["scale"].to_s.empty?
          unless Styling::PhpCompat.php_empty?(Supports.dig(block.attrs, "style", "shadow"))
            shadow = Styling::StyleEngine.get_styles({ "shadow" => Supports.dig(block.attrs, "style", "shadow") })
            styles << shadow["css"].to_s unless Styling::PhpCompat.php_empty?(shadow["css"])
          end
          styles
        end

        def safe_css(css) = Styling::CssSafety.safecss_filter_attr(css)

        # post-featured-image.php:149.
        def overlay_markup
          return "" unless attrs["dimRatio"] && attrs["dimRatio"] != 0

          class_names = ["wp-block-post-featured-image__overlay"]
          styles = []
          border = Borders.attributes(block.attrs)
          class_names << border["class"] unless border["class"].to_s.empty?
          styles << border["style"] unless border["style"].to_s.empty?
          class_names << "has-background-dim"
          class_names << "has-background-dim-#{attrs["dimRatio"]}"
          class_names << "has-#{attrs["overlayColor"]}-background-color" unless attrs["overlayColor"].to_s.empty?
          has_gradient = !attrs["gradient"].to_s.empty?
          has_custom_gradient = !attrs["customGradient"].to_s.empty?
          class_names << "has-background-gradient" if has_gradient || has_custom_gradient
          class_names << "has-#{attrs["gradient"]}-gradient-background" if has_gradient
          styles << "background-image: #{attrs["customGradient"]};" if has_custom_gradient
          styles << "background-color: #{attrs["customOverlayColor"]};" unless attrs["customOverlayColor"].to_s.empty?

          %(<span class="#{Text.esc_attr(class_names.join(" "))}" ) +
            %(style="#{Text.esc_attr(safe_css(styles.join(" ")))}" aria-hidden="true"></span>)
        end
      end

      # ── Border attributes for the two blocks that skip border serialization ─────
      #
      # `get_block_core_post_featured_image_border_attributes()`
      # (post-featured-image.php:214) and `get_block_core_avatar_border_attributes()`
      # (avatar.php:108) are the SAME function, duplicated in the legacy. Both blocks
      # declare `__experimentalSkipSerialization` so the border support contributes
      # nothing to the wrapper; the block applies it to the inner element instead.
      module Borders
        module_function

        def attributes(attrs)
          styles = {}
          %w[radius style width].each do |key|
            value = Styling::PhpCompat.array_get(attrs, ["style", "border", key], nil)
            styles[key] = value unless value.nil?
          end
          preset = attrs.key?("borderColor") ? "var:preset|color|#{attrs["borderColor"]}" : nil
          styles["color"] = preset || Styling::PhpCompat.array_get(attrs, %w[style border color], nil)
          %w[top right bottom left].each do |side|
            border = Styling::PhpCompat.array_get(attrs, ["style", "border", side], nil)
            border = {} unless border.is_a?(Hash)
            styles[side] = { "color" => border["color"], "style" => border["style"], "width" => border["width"] }
          end

          engine = Styling::StyleEngine.get_styles({ "border" => styles })
          out = {}
          out["class"] = engine["classnames"] unless Styling::PhpCompat.php_empty?(engine["classnames"])
          out["style"] = engine["css"] unless Styling::PhpCompat.php_empty?(engine["css"])
          out
        end
      end

      # ── core/post-navigation-link ───────────────────────────────────────────────
      # wp-includes/blocks/post-navigation-link.php:18 and `get_adjacent_post_link()`.
      class PostNavigationLink < Block
        handles "core/post-navigation-link"

        ARROWS = {
          "none" => {},
          "arrow" => { "next" => "→", "previous" => "←" },
          "chevron" => { "next" => "»", "previous" => "«" }
        }.freeze

        def render
          return "" unless screen.singular?

          navigation_type = attrs["type"].to_s.empty? ? "next" : attrs["type"]
          return "" unless %w[next previous].include?(navigation_type)

          classes = +"post-navigation-link-#{navigation_type}"
          classes << " has-text-align-#{attrs["textAlign"]}" if attrs.key?("textAlign")
          attributes = wrapper("class" => classes)

          template = "%link"
          link = navigation_type == "next" ? "Next" : "Previous"
          label = attrs["label"].to_s

          unless label.empty?
            link = label
          end

          if attrs["showTitle"]
            if !attrs["linkLabel"]
              template = %(<span class="post-navigation-link__label">#{Text.kses_post(label)}</span> %link) unless label.empty?
              link = "%title"
            elsif label.empty?
              label = navigation_type == "next" ? "Next:" : "Previous:"
              link = %(<span class="post-navigation-link__label">#{Text.kses_post(label)}</span> ) +
                     %(<span class="post-navigation-link__title">%title</span>)
            else
              link = %(<span class="post-navigation-link__label">#{Text.kses_post(label)}</span> ) +
                     %(<span class="post-navigation-link__title">%title</span>)
            end
          end

          arrow = attrs["arrow"].to_s
          if !arrow.empty? && arrow != "none" && ARROWS.key?(arrow)
            glyph = ARROWS[arrow][navigation_type]
            template = if navigation_type == "next"
                         %(%link<span class="wp-block-post-navigation-link__arrow-next is-arrow-#{arrow}" aria-hidden="true">#{glyph}</span>)
                       else
                         %(<span class="wp-block-post-navigation-link__arrow-previous is-arrow-#{arrow}" aria-hidden="true">#{glyph}</span>%link)
                       end
          end

          "<div #{attributes}>#{adjacent_link(navigation_type, template, link)}</div>"
        end

        private

        # get_adjacent_post_link(), wp-includes/link-template.php:2011. Note the href is
        # NOT passed through esc_url there, and the title IS passed through the `the_title`
        # chain.
        def adjacent_link(navigation_type, template, link)
          adjacent = adjacent_post(navigation_type)
          return "" if adjacent.nil?

          title = adjacent.title.to_s.empty? ? (navigation_type == "next" ? "Next Post" : "Previous Post") : nil
          title ||= adjacent.title.to_s
          title = Text.capital_p_title(Text.convert_chars(Text.wptexturize(title)).strip)
          date = Dates.the_date(adjacent, Site.date_format)
          rel = navigation_type == "next" ? "next" : "prev"

          inner = link.gsub("%title", title).gsub("%date", date)
          inner = %(<a href="#{Links.permalink(adjacent)}" rel="#{rel}">#{inner}</a>)
          template.gsub("%link", inner)
        end

        # get_adjacent_post(), wp-includes/link-template.php:1734 — strictly earlier or
        # later `post_date`, the same post type, and post_status = 'publish' only, which
        # is why the private article between the two published ones is skipped.
        def adjacent_post(navigation_type)
          post = context_post
          return nil if post.nil? || post.published_at.nil?

          scope = Publishing::Post.where(type: post.type, status: "published")
          if navigation_type == "previous"
            scope.where(published_at: ...post.published_at).order(published_at: :desc).first
          else
            scope.where("published_at > ?", post.published_at).order(published_at: :asc).first
          end
        end
      end

      # ── core/query-title ────────────────────────────────────────────────────────
      # wp-includes/blocks/query-title.php:21 and `get_the_archive_title()`
      # (wp-includes/general-template.php).
      class QueryTitle < Block
        handles "core/query-title"

        def render
          kind = attrs["type"]
          is_archive = screen.archive?
          is_search = screen.search?
          post_type = Supports.dig(block.attrs, "context", "query", "postType") ||
                      Styling::PhpCompat.array_get(ctx.context, %w[query postType], nil) ||
                      current_post_type

          return "" if kind.to_s.empty?
          return "" if kind == "archive" && !is_archive
          return "" if kind == "search" && !is_search
          return "" if kind == "post-type" && post_type.to_s.empty?

          title = +""
          title = archive_title if is_archive
          if is_search
            title = if attrs["showSearchTerm"]
                      format("Search results for: &#8220;%s&#8221;", Text.esc_attr(screen.search_query))
                    else
                      +"Search results"
                    end
          end
          if kind == "post-type"
            singular = post_type.to_s == "page" ? "Page" : "Post"
            title = attrs["showPrefix"] ? format("Post Type: &#8220;%s&#8221;", singular) : +singular
          end

          tag = heading_tag(attrs["level"].to_i)
          align_class = attrs["textAlign"].to_s.empty? ? "" : "has-text-align-#{attrs["textAlign"]}"
          "<#{tag} #{wrapper("class" => align_class)}>#{title}</#{tag}>"
        end

        private

        def current_post_type
          post = ctx.post
          return nil if post.nil?

          post.is_a?(Publishing::Page) ? "page" : "post"
        end

        # get_the_archive_title(). The prefixes are verbatim; `%1$s %2$s` is the
        # 'archive title' format and the title itself is wrapped in a <span>.
        #
        # ⚠️ NOT texturized here, and that is correct: the whole template output goes
        # through wptexturize() once in get_the_block_template_html()
        # (wp-includes/block-template.php:297), which is a page-level concern, not this
        # block's. The golden files show the texturized form because they are pages.
        def archive_title
          queried = screen.queried_object
          prefix, title =
            case queried
            when Classification::Term
              case queried.taxonomy&.name
              when "category" then ["Category:", queried.name.to_s]
              when "post_tag" then ["Tag:", queried.name.to_s]
              else [queried.taxonomy&.name.to_s, queried.name.to_s]
              end
            when Identity::User
              ["Author:", queried.display_name.to_s]
            when Hash
              date_archive_title(queried)
            else
              [nil, "Archives"]
            end

          return +title.to_s if prefix.nil? || prefix.to_s.empty?
          return +title.to_s unless attrs["showPrefix"]

          "#{prefix} <span>#{title}</span>"
        end

        # is_year() / is_month() / is_day() with the 'Y', 'F Y' and 'F j, Y' archive
        # formats. The queried object for a date archive is the date itself.
        def date_archive_title(queried)
          year = queried["year"] || queried[:year]
          month = queried["monthnum"] || queried[:monthnum]
          day = queried["day"] || queried[:day]
          local = Time.new(year.to_i, (month || 1).to_i, (day || 1).to_i, 0, 0, 0, Site.timezone.formatted_offset)
          return ["Day:", Dates.php_date("F j, Y", local.in_time_zone(Site.timezone))] if day
          return ["Month:", Dates.php_date("F Y", local.in_time_zone(Site.timezone))] if month

          ["Year:", Dates.php_date("Y", local.in_time_zone(Site.timezone))]
        end
      end

      # ── core/term-description ───────────────────────────────────────────────────
      # wp-includes/blocks/term-description.php:19.
      class TermDescription < Block
        handles "core/term-description"

        def render
          description = resolve_description
          return "" if description.to_s.empty?

          "<div #{wrapper("class" => align_and_link_classes.join(" "))}>#{description}</div>"
        end

        private

        # term-description.php:23 — the block schema's `usesContext: [termId, taxonomy]`
        # first, then the queried term. Note the CONTEXT branch returns the RAW
        # description while the query branch returns `term_description()`, which is the
        # filtered one. The legacy's asymmetry, reproduced.
        def resolve_description
          term_id = ctx.context["termId"]
          taxonomy = ctx.context["taxonomy"]
          if term_id && taxonomy
            term = Classification::Term.joins(:taxonomy).find_by(id: term_id, taxonomies: { name: taxonomy })
            return term&.description.to_s
          end

          queried = screen.queried_object
          return "" unless queried.is_a?(Classification::Term)

          Text.term_description(queried)
        end
      end

      # ── core/avatar ─────────────────────────────────────────────────────────────
      # wp-includes/blocks/avatar.php:18.
      class Avatar < Block
        handles "core/avatar"

        def render
          size = attrs.key?("size") ? attrs["size"] : 96
          attributes = wrapper
          border = Borders.attributes(block.attrs)
          image_class = border["class"].to_s.empty? ? "wp-block-avatar__image" : "wp-block-avatar__image #{border["class"]}"
          # avatar.php:28 — "Unlike class, `get_avatar` doesn't filter the styles via
          # `esc_attr`", so the style engine's output goes through esc_attr HERE.
          image_styles = border["style"].to_s.empty? ? "" : %( style="#{Text.esc_attr(border["style"])}")

          comment_id = ctx.context["commentId"]
          return render_for_comment(comment_id, size, attributes, image_class, image_styles) if comment_id

          author = resolve_author
          return "" if author.nil?

          avatar = Avatars.img(email: author.email, size: size,
                               alt: format("%s Avatar", author.display_name),
                               image_class: image_class, extra_attr: image_styles)
          if attrs["isLink"]
            label = if attrs["linkTarget"] == "_blank"
                      %(aria-label="#{Text.esc_attr(format("(%s author archive, opens in a new tab)", author.display_name))}")
                    else
                      ""
                    end
            avatar = %(<a href="#{Text.esc_url(Links.author_posts_url(author))}" ) +
                     %(target="#{Text.esc_attr(attrs["linkTarget"])}" #{label} class="wp-block-avatar__link">#{avatar}</a>)
          end
          "<div #{attributes}>#{avatar}</div>"
        end

        private

        def resolve_author
          return Identity::User.find_by(id: attrs["userId"]) if attrs.key?("userId")

          post = context_post
          return post.author if post

          queried = screen.queried_object
          queried.is_a?(Identity::User) ? queried : nil
        end

        def render_for_comment(comment_id, size, attributes, image_class, image_styles)
          comment = Discussion::Comment.find_by(id: comment_id)
          return "" if comment.nil?

          email = comment.user&.email || comment.author_email
          avatar = Avatars.img(email: email, size: size,
                               alt: format("%s Avatar", comment.author_name),
                               image_class: image_class, extra_attr: image_styles)
          if attrs["isLink"] && comment.author_url.to_s != ""
            label = if attrs["linkTarget"] == "_blank"
                      %(aria-label="#{Text.esc_attr(format("(%s website link, opens in a new tab)", comment.author_name))}")
                    else
                      ""
                    end
            avatar = %(<a href="#{Text.esc_url(comment.author_url)}" ) +
                     %(target="#{Text.esc_attr(attrs["linkTarget"])}" #{label} class="wp-block-avatar__link">#{avatar}</a>)
          end
          "<div #{attributes}>#{avatar}</div>"
        end
      end
    end
  end
end
