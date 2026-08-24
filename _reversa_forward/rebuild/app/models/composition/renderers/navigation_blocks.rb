# frozen_string_literal: true

module Composition
  module Renderers
    # ═══════════════════════════════════════════════════════════════════════════════
    # navigation + search + media
    #
    #   core/template-part   wp-includes/blocks/template-part.php:19
    #   core/pattern         wp-includes/blocks/pattern.php:33
    #   core/navigation      wp-includes/blocks/navigation.php:87  (WP_Navigation_Block_Renderer)
    #   core/navigation-link wp-includes/blocks/navigation-link.php:180
    #   core/navigation-submenu wp-includes/blocks/navigation-submenu.php:76
    #   core/page-list       wp-includes/blocks/page-list.php:257
    #   core/page-list-item  wp-includes/blocks/page-list-item.php  (NO render callback —
    #                        deliberately left to Renderers::Base, BR-MIGRATE-203)
    #   core/search          wp-includes/blocks/search.php:17
    #   core/image           wp-includes/blocks/image.php:20
    #   core/gallery         wp-includes/blocks/gallery.php:309
    #
    # ── AD-01, applied here ────────────────────────────────────────────────────────
    # Four `apply_filters` sites live in these callbacks and all four are gone, with the
    # legacy's own default taken as the specification:
    #
    #   * `block_core_navigation_listable_blocks` — the list of blocks that get an <li>
    #     wrapper is the hard-coded triple (site-title, site-logo, social-links).
    #   * `block_core_navigation_render_inner_blocks` — identity.
    #   * `block_core_navigation_render_fallback` — the page-list fallback as built.
    #   * `render_block_core_navigation_link_allowed_post_status` — exactly ['publish'].
    #
    # Two `render_block` filters that WordPress core registers on ITS OWN blocks are NOT
    # extension points but core behaviour (the same carve-out `Sanitizing::Formatting`
    # records at its head), so they are folded into the renderers that own them:
    # `block_core_navigation_add_directives_to_submenu` (navigation.php:1217) and
    # `block_core_navigation_add_support_classes_to_container` (navigation.php:1615).
    #
    # ── implication 1 (no global mutable state) ────────────────────────────────────
    # These callbacks lean on FIVE request-scoped PHP statics, and every one of them is
    # observable in the golden files:
    #
    #   wp_unique_id()'s counter  → id="modal-1", id="wp-block-search__input-2"
    #   $seen_menu_names          → aria-label=" 2" on the second nav of a page
    #   $has_submenus             → sticky across every nav in one request
    #   $seen_ids / $seen_refs    → template-part and pattern recursion guards
    #
    # ⚠️ REPORTED, NOT SOLVED. The right home for these is `RenderContext` — one
    # per-render scratchpad, handed to renderers explicitly, exactly as `post` and
    # `query` already are. RenderContext is shared contract and this agent may not
    # change it, so `RenderScope` below keys the state off `ctx.styles`, which is the
    # one object identity-shared across a whole render and freshly built for each one.
    # It is deliberately a weak map, so a finished render's counters are collectable.
    # This is a seam, not a design: see the hand-off note in the report.
    module NavigationBlocks
      # ── Request-scoped counters ───────────────────────────────────────────────────
      class RenderScope
        attr_accessor :id_counter, :has_submenus

        attr_reader :seen_menu_names, :seen_template_parts, :seen_patterns

        def initialize
          @id_counter = 0
          @has_submenus = false
          @seen_menu_names = Hash.new(0)
          @seen_template_parts = {}
          @seen_patterns = {}
        end

        # wp-includes/functions.php:8177 — ONE counter shared by every prefix. That is
        # why the 404 screen's search input is `wp-block-search__input-2`: the header's
        # navigation took `modal-1` first.
        def unique_id(prefix = "")
          @id_counter += 1
          "#{prefix}#{@id_counter}"
        end
      end

      SCOPES = ObjectSpace::WeakKeyMap.new

      def self.scope(ctx)
        SCOPES[ctx.styles] ||= RenderScope.new
      end

      # ── PHP-faithful escaping ─────────────────────────────────────────────────────
      # Ruby's ERB::Util.html_escape emits `&#39;` where PHP's ENT_QUOTES emits
      # `&#039;`. One byte, and it appears on every screen that renders an apostrophe.
      module Php
        module_function

        def esc_attr(text) = Sanitizing::Formatting.esc_attr(text.to_s)
        def esc_html(text) = Sanitizing::Formatting.esc_html(text.to_s)
        def esc_url(url) = Sanitizing::Formatting.esc_url(url.to_s)
        def kses_post(html) = Sanitizing::Kses.wp_kses_post(html.to_s)
        def safecss(css) = Sanitizing::Css.safecss_filter_attr(css.to_s)

        # wp-includes/formatting.php:5836 — wp_strip_all_tags(): script and style
        # ELEMENTS lose their contents too, then all tags go, then trim.
        def strip_all_tags(text, remove_breaks: false)
          out = text.to_s.gsub(%r{<script[^>]*?>.*?</script>}mi, "")
                    .gsub(%r{<style[^>]*?>.*?</style>}mi, "")
          out = Sanitizing::Formatting.strip_tags(out)
          out = out.gsub(/[\r\n\t ]+/, " ") if remove_breaks
          out.strip
        end

        # wp-includes/interactivity-api/interactivity-api.php:104.
        def data_wp_context(context)
          "data-wp-context='#{php_json(context)}'"
        end

        # PHP's json_encode with JSON_HEX_TAG|JSON_HEX_APOS|JSON_HEX_QUOT|JSON_HEX_AMP
        # and WITHOUT JSON_UNESCAPED_SLASHES / JSON_UNESCAPED_UNICODE. Ruby's
        # JSON.generate matches none of that, so the encoder is written out:
        #   * `/` escapes to `\/`;
        #   * the five flagged characters escape to the UPPERCASE forms PHP hard-codes
        #     (`\u003C`, `\u003E`, `\u0026`, `\u0027`, `\u0022`);
        #   * every other non-ASCII character escapes to LOWERCASE `\uXXXX`, surrogate
        #     pair by surrogate pair. The case difference is PHP's, not a typo.
        def php_json(value)
          case value
          when Hash   then "{#{value.map { |k, v| "#{php_json(k.to_s)}:#{php_json(v)}" }.join(",")}}"
          when Array  then "[#{value.map { |v| php_json(v) }.join(",")}]"
          when String then %("#{php_json_string(value)}")
          when nil    then "null"
          when true, false, Numeric then value.to_s
          else php_json(value.to_s)
          end
        end

        JSON_ESCAPES = {
          '"' => '\u0022', "'" => '\u0027', "<" => '\u003C', ">" => '\u003E',
          "&" => '\u0026', "\\" => '\\\\', "/" => '\/', "\b" => '\b', "\f" => '\f',
          "\n" => '\n', "\r" => '\r', "\t" => '\t'
        }.freeze

        def php_json_string(string)
          string.each_char.map do |ch|
            next JSON_ESCAPES[ch] if JSON_ESCAPES.key?(ch)

            code = ch.ord
            next format('\\u%04x', code) if code < 0x20
            next ch if code < 0x80

            ch.encode(Encoding::UTF_16BE).unpack("n*").map { |u| format('\\u%04x', u) }.join
          end.join
        end
      end

      # ── get_block_wrapper_attributes(), wp-includes/class-wp-block-supports.php:203 ──
      #
      # The full port already exists: `PostBlocks::Supports.wrapper_attributes`, which
      # wires the eleven `wp-includes/block-supports/*.php` apply callbacks into
      # `Styling::BlockSupports` (the packs/styling port of WP_Block_Supports) and then
      # runs the four hard-coded merge callbacks. Delegating to it is what makes THIS
      # family's dynamic blocks emit the colour, typography, border, spacing, dimensions
      # and shadow halves of the wrapper.
      #
      # ⚠️ Do NOT re-port it here. An earlier revision of this file carried a reduced
      # copy that implemented only align / custom-classname / generated-classname /
      # anchor, and the four supports it left out are observable:
      #
      #   <!-- wp:navigation {"style":{"typography":{"fontStyle":"italic"}}} -->
      #     oracle:  <nav style="font-style:italic" class="…">…<ul style="font-style:italic" …>
      #     reduced: <nav class="…">…<ul …>            ← the style attribute vanished
      #   <!-- wp:page-list {"fontSize":"small","textColor":"accent-1"} /-->
      #     oracle:  <ul class="wp-block-page-list has-text-color has-accent-1-color has-small-font-size">
      #     reduced: <ul class="wp-block-page-list">
      #
      # `twentytwentyfive/footer-social` and `hidden-sidebar` both ship the first shape,
      # so it is theme content, not a synthetic case.
      #
      # The `layout` support is NOT part of get_block_wrapper_attributes() in the legacy
      # either — layout.php:1336 adds its classes afterwards from a `render_block`
      # listener, and `Supports.apply` below is where the rebuild does that.
      #
      # The reduced-supports branch is kept for ONE case: BR-MIGRATE-200, an unregistered
      # block type, where `type` is nil and there is no name to look up.
      module Wrapper
        module_function

        def attributes(type, attrs, extra = {})
          return PostBlocks::Supports.wrapper_attributes(type.name, attrs, extra) unless type.nil?

          supports = block_supports(type, attrs)
          return "" if supports.empty? && extra.empty?

          out = {}
          merge(out, "style", supports, extra) { |s, e| join_styles(s, e) }
          merge(out, "class", supports, extra) { |s, e| join_classes(s, e) }
          merge(out, "id", supports, extra) { |s, e| e.empty? ? s : e }
          merge(out, "aria-label", supports, extra) { |s, e| e.empty? ? s : e }

          extra.each do |name, value|
            next if %w[style class id aria-label].include?(name)
            next unless scalar?(value)

            out[name] = value.to_s
          end
          return "" if out.empty?

          out.map { |k, v| %(#{k}="#{Php.esc_attr(v)}") }.join(" ")
        end

        def merge(out, name, supports, extra)
          from_supports = scalar?(supports[name]) ? supports[name].to_s : ""
          from_extra = scalar?(extra[name]) ? extra[name].to_s : ""
          return if from_supports.empty? && from_extra.empty?

          out[name] = yield(from_supports, from_extra)
        end

        def scalar?(value) = value.is_a?(String) || value.is_a?(Numeric)

        def join_classes(from_supports, from_extra)
          (from_extra.split(/\s+/) + from_supports.split(/\s+/)).reject(&:empty?).uniq.join(" ")
        end

        def join_styles(from_supports, from_extra)
          Php.safecss([from_supports, from_extra].map { |s| s.strip.sub(/;\z/, "") }
                                                 .reject(&:empty?).join(";"))
        end

        # BR-MIGRATE-200: an unregistered block type gets NOTHING.
        def block_supports(type, attrs)
          return {} if type.nil?

          classes = []
          # block-supports/align.php — `align` support is opt-in (default false).
          if type.supports.key?("align") && type.supports["align"] != false && !blank?(attrs["align"])
            classes << "align#{attrs["align"]}"
          end
          # block-supports/custom-classname.php — opt-out (default true).
          if type.supports.fetch("customClassName", true) != false && !blank?(attrs["className"])
            classes << attrs["className"].to_s
          end
          # block-supports/generated-classname.php — opt-out (default true).
          if type.supports.fetch("className", true) != false
            classes << default_classname(type.name)
          end

          out = {}
          out["class"] = classes.join(" ") unless classes.empty?
          # block-supports/anchor.php.
          out["id"] = attrs["anchor"].to_s if type.supports["anchor"] && !blank?(attrs["anchor"])
          # block-supports/aria-label.php:45 — opt-in, and keyed on PRESENCE, so an
          # explicit empty ariaLabel still emits `aria-label=""`. This one is easy to
          # miss: the navigation block passes its own aria-label as an EXTRA attribute on
          # the <nav>, where the caller's value wins, but the inner <ul> gets it only
          # through the support.
          out["aria-label"] = attrs["ariaLabel"].to_s if type.supports["ariaLabel"] && attrs.key?("ariaLabel")
          out
        end

        def blank?(value) = value.nil? || value == "" || value == false

        # wp-includes/blocks.php — wp_get_block_default_classname().
        def default_classname(name)
          "wp-block-#{name.to_s.sub(%r{\Acore/}, "").tr("/", "-")}"
        end
      end

      # ── The active theme's file-based patterns and template parts ─────────────────
      #
      # `db/theme_content/<theme>.json`, produced by `rake composition:generate_theme_content`.
      # See that task for WHY the theme's pattern PHP is evaluated once at generation
      # time instead of at render time. Nothing here evaluates anything.
      class ThemeContent
        DATA = Rails.root.join("db", "theme_content")

        class << self
          def for(theme)
            @cache ||= {}
            @cache[theme.to_s] ||= begin
              path = DATA.join("#{theme}.json")
              new(File.exist?(path) ? JSON.parse(File.read(path)) : { "patterns" => {}, "parts" => {} })
            end
          end

          def reset! = @cache = nil

          # The active stylesheet, `get_stylesheet()`. ⚠️ Read from the `stylesheet`
          # SETTING, not from Presentation::Theme: topology_decision.md forbids
          # Composition -> Presentation, and Composition -> Configuration already exists.
          # `rake theme:load` keeps the themes row and this setting describing the same
          # theme.
          def active_theme
            Configuration::Setting["stylesheet"].presence || "twentytwentyfive"
          end
        end

        def initialize(data)
          @patterns = data["patterns"] || {}
          @parts = data["parts"] || {}
        end

        def pattern(slug) = @patterns[slug.to_s]
        def part(slug) = @parts[slug.to_s]
        def pattern?(slug) = @patterns.key?(slug.to_s)

        # The generator tokenizes the oracle's own host out of the asset; the target
        # substitutes its own `home` so the asset carries no foreign hostname.
        def self.expand(content)
          content.to_s.gsub("{{SITE_URL}}", SiteUrl.home)
        end
      end

      module SiteUrl
        module_function

        # wp-includes/link-template.php — home_url() without a trailing slash.
        def home = Configuration::Setting["home"].to_s.sub(%r{/\z}, "")
        def home_slash = "#{home}/"
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/template-part — wp-includes/blocks/template-part.php:19
      # ═══════════════════════════════════════════════════════════════════════════════
      class TemplatePart < Base
        handles "core/template-part"

        # block-template-utils.php:70 — the allowed areas and the tag each one implies.
        AREA_TAGS = {
          "uncategorized" => "div", "header" => "header",
          "footer" => "footer", "navigation-overlay" => "div"
        }.freeze
        UNCATEGORIZED = "uncategorized"

        def render
          slug = attrs["slug"]
          theme = attrs["theme"].presence || ThemeContent.active_theme
          return "" if slug.blank? || theme != ThemeContent.active_theme

          part_id = "#{theme}//#{slug}"
          content, area = resolve(theme, slug)
          # :118 — WP_DEBUG is off, so a missing part renders as nothing at all.
          return "" if content.nil?
          # :130 — the recursion guard. Same shape as pattern.php's $seen_refs.
          return "" if NavigationBlocks.scope(ctx).seen_template_parts[part_id]

          area = UNCATEGORIZED unless AREA_TAGS.key?(area)
          inner = with_seen(part_id) { content_filters(content, area) }

          tag = tag_name_for(area)
          wrapper = Wrapper.attributes(type, attrs)
          # :166 — `]]>` is neutralised so the part cannot close an enclosing CDATA.
          Supports.apply("<#{tag} #{wrapper}>#{inner.gsub("]]>", "]]&gt;")}</#{tag}>", block, ctx)
        end

        private

        # :155 — an explicit tagName wins, but only if it survives tag_escape().
        def tag_name_for(area)
          supplied = attrs["tagName"].to_s
          return AREA_TAGS.fetch(area, "div") if supplied.empty? || tag_escape(supplied) != supplied

          Php.esc_attr(supplied)
        end

        # wp-includes/formatting.php — tag_escape(): lowercase, strip all but [a-z0-9_:].
        def tag_escape(tag) = tag.downcase.gsub(/[^a-z0-9_:]/, "")

        # :27 — the DATABASE copy wins over the theme file. That order is why a
        # customized header replaces the theme's, and it is checked before the file is
        # ever looked at.
        def resolve(theme, slug)
          row = Composition::Template.parts.find_by(theme_slug: theme, slug: slug)
          return [row.content, row.area.presence || UNCATEGORIZED] if row

          file = ThemeContent.for(theme).part(slug)
          return [nil, UNCATEGORIZED] if file.nil?

          [ThemeContent.expand(file["content"]), file["area"] || UNCATEGORIZED]
        end

        def with_seen(part_id)
          seen = NavigationBlocks.scope(ctx).seen_template_parts
          seen[part_id] = true
          begin
            yield
          ensure
            seen.delete(part_id)
          end
        end

        # :153 — _wp_apply_block_content_filters(), wp-includes/blocks.php:2648.
        #
        # shortcode_unautop + do_shortcode are the identity here: AD-01 removes the
        # shortcode registry along with the rest of the extension surface, and core
        # registers no shortcodes of its own on the front end.
        # convert_smilies and wp_filter_content_tags are identity too, and that is a
        # KNOWN GAP rather than a decision — see the report.
        def content_filters(content, _area)
          Sanitizing::Texturize.wptexturize(Renderer.render(Parser.parse(content), ctx))
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/pattern — wp-includes/blocks/pattern.php:33
      # ═══════════════════════════════════════════════════════════════════════════════
      class Pattern < Base
        handles "core/pattern"

        def render
          slug = attrs["slug"]
          return "" if slug.blank?

          theme_content = ThemeContent.for(ThemeContent.active_theme)
          # :43 — an unregistered slug renders as nothing, not as an error.
          return "" unless theme_content.pattern?(slug)
          # :47 — the recursion guard, with WP_DEBUG off.
          seen = NavigationBlocks.scope(ctx).seen_patterns
          return "" if seen[slug]

          content = ThemeContent.expand(theme_content.pattern(slug)["content"])
          seen[slug] = true
          begin
            # :62 — do_blocks(). The `$wp_embed->autoembed()` on :65 is NOT applied:
            # see the report.
            Supports.apply(Renderer.render(Parser.parse(content), ctx), block, ctx)
          ensure
            seen.delete(slug)
          end
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/navigation — wp-includes/blocks/navigation.php:87
      # ═══════════════════════════════════════════════════════════════════════════════
      class Navigation < Base
        handles "core/navigation"

        SUBMENU_ICON = '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" ' \
                       'viewBox="0 0 12 12" fill="none" aria-hidden="true" focusable="false">' \
                       '<path d="M1.50002 4L6.00002 8L10.5 4" stroke-width="1.5"></path></svg>'
        OPEN_ICON = '<svg width="24" height="24" xmlns="http://www.w3.org/2000/svg" ' \
                    'viewBox="0 0 24 24" aria-hidden="true" focusable="false">' \
                    '<path d="M4 7.5h16v1.5H4z"></path><path d="M4 15h16v1.5H4z"></path></svg>'
        MENU_ICON = '<svg width="24" height="24" xmlns="http://www.w3.org/2000/svg" ' \
                    'viewBox="0 0 24 24"><path d="M5 5v1.5h14V5H5z"></path>' \
                    '<path d="M5 12.8h14v-1.5H5v1.5z"></path>' \
                    '<path d="M5 19h14v-1.5H5V19z"></path></svg>'
        CLOSE_ICON = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" ' \
                     'height="24" aria-hidden="true" focusable="false">' \
                     '<path d="m13.06 12 6.47-6.47-1.06-1.06L12 10.94 5.53 4.47 4.47 5.53 10.94 ' \
                     '12l-6.47 6.47 1.06 1.06L12 13.06l6.47 6.47 1.06-1.06L13.06 12Z"></path></svg>'

        # :98 — the hard-coded list. AD-01 drops `block_core_navigation_listable_blocks`,
        # so this triple IS the specification.
        NEEDS_LIST_ITEM_WRAPPER = %w[core/site-title core/site-logo core/social-links].freeze

        # The directive blobs are copied byte-for-byte out of :783-:816, leading newline
        # and tab runs included: they land inside an HTML tag and the golden files are
        # compared byte-for-byte, so the whitespace is output, not formatting.
        OPEN_BUTTON_DIRECTIVES = "\n\t\t\t\tdata-wp-on--click=\"actions.openMenuOnClick\"\n" \
                                 "\t\t\t\tdata-wp-on--keydown=\"actions.handleMenuKeydown\"\n\t\t\t"
        CONTAINER_DIRECTIVES = "\n\t\t\t\tdata-wp-class--has-modal-open=\"state.isMenuOpen\"\n" \
                               "\t\t\t\tdata-wp-class--is-menu-open=\"state.isMenuOpen\"\n" \
                               "\t\t\t\tdata-wp-watch=\"callbacks.initMenu\"\n" \
                               "\t\t\t\tdata-wp-on--keydown=\"actions.handleMenuKeydown\"\n" \
                               "\t\t\t\tdata-wp-on--focusout=\"actions.handleMenuFocusout\"\n" \
                               "\t\t\t\ttabindex=\"-1\"\n\t\t\t"
        DIALOG_DIRECTIVES = "\n\t\t\t\tdata-wp-bind--aria-modal=\"state.ariaModal\"\n" \
                            "\t\t\t\tdata-wp-bind--aria-label=\"state.ariaLabel\"\n" \
                            "\t\t\t\tdata-wp-bind--role=\"state.roleAttribute\"\n\t\t\t"
        CLOSE_BUTTON_DIRECTIVES = "\n\t\t\t\tdata-wp-on--click=\"actions.closeMenuOnClick\"\n\t\t\t"
        CONTENT_DIRECTIVES = "\n\t\t\t\tdata-wp-watch=\"callbacks.focusFirstElement\"\n\t\t\t"

        RESPONSIVE_TEMPLATE = <<~HTML.chomp
          <button aria-haspopup="dialog" %<aria_open>s class="%<open_classes>s" %<open_directives>s>%<toggle>s</button>
          \t\t\t\t<div class="%<container_classes>s" %<overlay_styles>s id="%<modal>s" %<container_directives>s>
          \t\t\t\t\t<div class="wp-block-navigation__responsive-close" tabindex="-1">
          \t\t\t\t\t\t<div class="wp-block-navigation__responsive-dialog" %<dialog_directives>s>
          \t\t\t\t\t\t\t%<close_button>s
          \t\t\t\t\t\t\t<div class="wp-block-navigation__responsive-container-content" %<content_directives>s id="%<modal>s-content">
          \t\t\t\t\t\t\t\t%<inner>s
          \t\t\t\t\t\t\t\t%<custom_overlay>s
          \t\t\t\t\t\t\t</div>
          \t\t\t\t\t\t</div>
          \t\t\t\t\t</div>
          \t\t\t\t</div>
        HTML

        def render
          nav_attrs = deprecated_colors(attrs)
          inner_blocks = resolve_inner_blocks(nav_attrs)
          # :1017 — a navigation that contains a navigation renders as nothing.
          return "" if tree_has_navigation?(inner_blocks)

          # :953 `handle_view_script_module_loading` — the view module is enqueued only
          # when the menu is genuinely interactive, not for every navigation block.
          ctx.script_modules.use("@wordpress/block-library/navigation/view") if interactive?(nav_attrs, inner_blocks)

          markup = format("<nav %s>%s</nav>",
                          nav_attributes(nav_attrs, inner_blocks),
                          inner_block_markup(nav_attrs, inner_blocks))
          # The layout filter runs at priority 10, the navigation container pass at 11.
          # class-wp-block.php:736 — navigation is a root interactive block, so the
          # directive pass runs over its finished subtree.
          Interactivity.process(add_support_classes_to_container(Supports.apply(markup, block, ctx)))
        end

        private

        # :988 — rgbTextColor / rgbBackgroundColor move to their custom* successors and
        # are then unset, so `array_key_exists` downstream cannot see them.
        def deprecated_colors(source)
          out = source.dup
          out["customTextColor"] = out["rgbTextColor"] if out.key?("rgbTextColor") && blank?(out["textColor"])
          if out.key?("rgbBackgroundColor") && blank?(out["backgroundColor"])
            out["customBackgroundColor"] = out["rgbBackgroundColor"]
          end
          out.delete("rgbTextColor")
          out.delete("rgbBackgroundColor")
          out
        end

        # :519 — `ref` first, fallback second. There is no `wp_navigation` post type in
        # the target (AD-02 dissolved it), so a `ref` resolves through Presentation::Menu,
        # which is the aggregate that replaced it.
        def resolve_inner_blocks(nav_attrs)
          blocks = block.inner_blocks.reject(&:freeform?)
          ref = nav_attrs["navigationMenuId"] || nav_attrs["ref"]
          blocks = menu_blocks(ref) if ref.present?
          blocks = fallback_blocks if blocks.empty?
          blocks
        end

        # :1479 — block_core_navigation_get_fallback_blocks(). The chain, in the
        # legacy's order (class-wp-navigation-fallback.php:70):
        #
        #   1. the most recently published `wp_navigation` post — parse_blocks() of its
        #      content (:530 in get_inner_blocks_from_navigation_post has the same
        #      parse-and-filter shape). AD-02 pivots those posts into
        #      `Composition::Template` kind "navigation" (the corpus's is the seeded
        #      `block-navigation` document, `<!-- wp:navigation-link {"label":"Home"} /-->`);
        #   2. else convert the classic menu — a WRITE in the legacy; read-only here, the
        #      menuSource seam's `default` answers it (nil today: the corpus's classic
        #      menu is never converted because step 1 answers first);
        #   3. else the bare page-list, only if `core/page-list` is registered (:1490).
        def fallback_blocks
          from_document = navigation_document_blocks
          return from_document unless from_document.empty?

          menu = menu_source&.default
          from_menu = menu ? menu_blocks_for(menu) : []
          return from_menu unless from_menu.empty?
          return [] unless Registry.registered?("core/page-list")

          [Parser::Block.new(block_name: "core/page-list", attrs: {}, inner_blocks: [],
                             inner_html: "", inner_content: [])]
        end

        # class-wp-navigation-fallback.php:110 — get_most_recently_published_navigation():
        # ONE post, newest first, and if ITS content filters down to nothing the page-list
        # wins — older navigation posts are never consulted. The legacy orders by
        # post_date; the pivot keeps only post_modified (templates.updated_at), which for
        # this corpus names the same row. `filter_out_empty_blocks` (:1407) drops the
        # nameless whitespace blocks parse_blocks invents, i.e. exactly `freeform?`.
        def navigation_document_blocks
          document = Composition::Template.navigations
                                          .order(updated_at: :desc, id: :desc).first
          return [] if document.nil?

          Parser.parse(document.content).reject(&:freeform?)
        end

        def menu_blocks(ref)
          menu = menu_source&.find(ref)
          menu ? menu_blocks_for(menu) : []
        end

        # ⚠️ AGG-Menu lives in Presentation, and Composition may not depend on
        # Presentation (bin/check_cycles). The menu therefore arrives through
        # RenderContext#context under `menuSource` — the same mechanism the block
        # schemas' `usesContext` describes — so this renderer names no namespace it is
        # not allowed to name. Nil is a valid answer: with no menu the legacy also falls
        # through to the page-list fallback.
        def menu_source = ctx.context["menuSource"]

        # navigation.php:1573 — block_core_navigation_parse_blocks_from_menu_items().
        # An item with children becomes a submenu; everything else becomes a link.
        def menu_blocks_for(menu, items = nil)
          items ||= menu.roots
          items.map do |item|
            children = item.children.order(:position)
            Parser::Block.new(
              block_name: children.any? ? "core/navigation-submenu" : "core/navigation-link",
              attrs: menu_item_attrs(item),
              inner_blocks: children.any? ? menu_blocks_for(menu, children) : [],
              inner_html: "", inner_content: []
            )
          end
        end

        # navigation.php:1584 — the nine attributes a menu item becomes. T-04 pivoted the
        # legacy's nine `_menu_item_*` postmeta keys into real columns, so each line here
        # reads a column instead of a meta lookup. Two legacy fields have NO column and
        # therefore no value: the item description, and `target` (`_blank`) — so
        # `opensInNewTab` is always false. Reported.
        KINDS = { "Publishing::Post" => "post-type", "Publishing::Page" => "post-type",
                  "Publishing::Article" => "post-type",
                  "Classification::Term" => "taxonomy" }.freeze
        TYPES = { "Publishing::Article" => "post", "Publishing::Page" => "page" }.freeze

        def menu_item_attrs(item)
          {
            "className" => Array(item.css_classes).join(" ").presence,
            "id" => item.target_id,
            "kind" => KINDS.fetch(item.target_type, "custom"),
            "label" => item.label.presence || item.title,
            "opensInNewTab" => false,
            "rel" => item.xfn.presence,
            "title" => item.title.presence,
            "type" => TYPES[item.target_type],
            "url" => item.url.presence || permalink_for_target(item)
          }.compact
        end

        def permalink_for_target(item)
          item.target ? "#{SiteUrl.home}#{ctx.permalink_for(item.target)}" : nil
        end


        def tree_has_navigation?(blocks)
          blocks.any? do |b|
            b.block_name == "core/navigation" || tree_has_navigation?(b.inner_blocks)
          end
        end

        # ── the flags, :125-:189 ────────────────────────────────────────────────────
        def responsive?(nav_attrs)
          old = nav_attrs["isResponsive"]
          (nav_attrs.key?("overlayMenu") && nav_attrs["overlayMenu"] != "never") || old == true
        end

        # :143 — ⚠️ `static::$has_submenus` is never reset within a request, so a page
        # whose FIRST navigation has submenus makes every later navigation interactive
        # too. Reproduced deliberately: the golden files were captured with that leak.
        def has_submenus?(blocks)
          scope = NavigationBlocks.scope(ctx)
          return true if scope.has_submenus

          blocks.each do |inner|
            if inner.block_name == "core/page-list" && PageList.any_page_has_children?
              scope.has_submenus = true
            end
            if inner.block_name == "core/navigation-submenu"
              scope.has_submenus = true
              break
            end
          end
          scope.has_submenus
        end

        def interactive?(nav_attrs, blocks)
          open_on_click = submenu_visibility(nav_attrs) == "click"
          show_icon = !blank?(nav_attrs["showSubmenuIcon"])
          (has_submenus?(blocks) && (open_on_click || show_icon)) || responsive?(nav_attrs)
        end

        # :24 — the legacy `openSubmenusOnClick` boolean still wins when present.
        def submenu_visibility(nav_attrs)
          legacy = nav_attrs["openSubmenusOnClick"]
          return blank?(legacy) ? "hover" : "click" unless legacy.nil?

          nav_attrs["submenuVisibility"] || "hover"
        end

        # ── classes and styles, :599-:673 ──────────────────────────────────────────
        def layout_class(nav_attrs)
          layout = nav_attrs["layout"] || {}
          justification = { "left" => "items-justified-left", "right" => "items-justified-right",
                            "center" => "items-justified-center",
                            "space-between" => "items-justified-space-between" }
          out = +""
          out << justification[layout["justifyContent"]].to_s if justification.key?(layout["justifyContent"])
          out << " is-vertical" if layout["orientation"] == "vertical"
          out << " no-wrap" if layout["flexWrap"] == "nowrap"
          out
        end

        def classes(nav_attrs)
          colors = self.class.css_colors(nav_attrs)
          fonts = self.class.css_font_sizes(nav_attrs)
          text_decoration = nav_attrs.dig("style", "typography", "textDecoration")
          layout = layout_class(nav_attrs)
          (colors[:css_classes] + fonts[:css_classes] +
            (responsive?(nav_attrs) ? ["is-responsive"] : []) +
            (layout.empty? ? [] : [layout]) +
            (blank?(text_decoration) ? [] : ["has-text-decoration-#{text_decoration}"])).join(" ")
        end

        def styles(nav_attrs)
          colors = self.class.css_colors(nav_attrs)
          fonts = self.class.css_font_sizes(nav_attrs)
          # :662 — `$attributes['styles']` (plural) is not a registered attribute; it is
          # always the empty string. Carried over rather than dropped, because dropping
          # it would silently change what a third-party attribute could do — and there
          # are no third parties left to do it (AD-01).
          "#{nav_attrs["styles"]}#{colors[:inline_styles]}#{fonts[:inline_styles]}"
        end

        # :1282 — block_core_navigation_build_css_colors(). Presence is tested with
        # array_key_exists, so an explicit null still counts as "has a colour".
        def self.css_colors(nav_attrs)
          out = { css_classes: [], inline_styles: +"", overlay_css_classes: [], overlay_inline_styles: +"" }
          pairs = [
            [:css_classes, :inline_styles, "textColor", "customTextColor", "has-text-color", "has-%s-color", "color: %s;"],
            [:css_classes, :inline_styles, "backgroundColor", "customBackgroundColor", "has-background", "has-%s-background-color", "background-color: %s;"],
            [:overlay_css_classes, :overlay_inline_styles, "overlayTextColor", "customOverlayTextColor", "has-text-color", "has-%s-color", "color: %s;"],
            [:overlay_css_classes, :overlay_inline_styles, "overlayBackgroundColor", "customOverlayBackgroundColor", "has-background", "has-%s-background-color", "background-color: %s;"]
          ]
          pairs.each do |classes_key, styles_key, named, custom, flag, class_format, style_format|
            has_named = nav_attrs.key?(named)
            has_custom = nav_attrs.key?(custom)
            out[classes_key] << flag if has_named || has_custom
            if has_named
              out[classes_key] << format(class_format, nav_attrs[named])
            elsif has_custom
              out[styles_key] << format(style_format, nav_attrs[custom])
            end
          end
          out
        end

        # :1375 — block_core_navigation_build_css_font_sizes().
        def self.css_font_sizes(nav_attrs)
          return { css_classes: ["has-#{nav_attrs["fontSize"]}-font-size"], inline_styles: "" } if nav_attrs.key?("fontSize")
          return { css_classes: [], inline_styles: "font-size: #{nav_attrs["customFontSize"]}px;" } if nav_attrs.key?("customFontSize")

          { css_classes: [], inline_styles: "" }
        end

        # ── the <nav> attributes, :875 ─────────────────────────────────────────────
        def nav_attributes(nav_attrs, blocks)
          extra = { "class" => classes(nav_attrs), "style" => styles(nav_attrs) }
          name = unique_navigation_name(nav_attrs)
          extra["aria-label"] = name unless blank?(name)
          out = Wrapper.attributes(type, nav_attrs, extra)
          return out unless responsive?(nav_attrs)

          "#{out} #{nav_element_directives(interactive?(nav_attrs, blocks))}"
        end

        # :915 — the directives blob, verbatim including the leading newline and the
        # single space before `data-wp-interactive`.
        def nav_element_directives(is_interactive)
          return "" unless is_interactive

          context = { "overlayOpenedBy" => { "click" => false, "hover" => false, "focus" => false },
                      "type" => "overlay", "roleAttribute" => "", "ariaLabel" => "Menu" }
          "\n\t\t data-wp-interactive=\"core/navigation\" #{Php.data_wp_context(context)}"
        end

        # :962 — the SECOND navigation with the same name gets " 2" appended, the third
        # " 3". With no ariaLabel and no ref the name is the empty string, so the first
        # navigation on a page carries no aria-label at all and the next two carry
        # `aria-label=" 2"` and `aria-label=" 3"` — leading space included.
        def unique_navigation_name(nav_attrs)
          name = navigation_name(nav_attrs)
          seen = NavigationBlocks.scope(ctx).seen_menu_names
          seen[name] += 1
          seen[name] > 1 ? "#{name} #{seen[name]}" : name
        end

        def navigation_name(nav_attrs)
          label = nav_attrs["ariaLabel"].to_s
          return label unless label.empty?

          ref = nav_attrs["navigationMenuId"] || nav_attrs["ref"]
          return "" if ref.blank?

          menu_source&.find(ref)&.name.to_s
        end

        # ── inner markup, :934 and :247 ────────────────────────────────────────────
        def inner_block_markup(nav_attrs, blocks)
          html = inner_blocks_html(nav_attrs, blocks)
          return html unless responsive?(nav_attrs)

          responsive_container_markup(nav_attrs, blocks, html)
        end

        def inner_blocks_html(nav_attrs, blocks)
          child_ctx = child_context(nav_attrs)
          container = Wrapper.attributes(
            type, nav_attrs,
            { "class" => "wp-block-navigation__container #{classes(nav_attrs)}",
              "style" => styles(nav_attrs) }
          )

          html = +""
          list_open = false
          blocks.each do |inner|
            markup = markup_for_inner_block(inner, child_ctx)
            # :262 — "does this markup contain an LI anywhere" decides whether the run
            # belongs inside the <ul>, so a block that renders nothing closes the list.
            is_list_item = Markup::TagProcessor.new(markup).next_tag("LI")

            if is_list_item && !list_open
              list_open = true
              html << "<ul #{container}>"
            elsif !is_list_item && list_open
              list_open = false
              html << "</ul>"
            end
            html << markup
          end
          html << "</ul>" if list_open

          return html unless has_submenus?(blocks) && interactive?(nav_attrs, blocks)

          self.class.add_directives_to_submenu(Markup::TagProcessor.new(html), nav_attrs)
        end

        # WP_Block_List's `$available_context` for navigation children is the navigation's
        # PREPARED ATTRIBUTES, not the surrounding context — so it REPLACES what the
        # parent tree supplied rather than merging with it. A fresh RenderContext is the
        # only faithful way to say that; `ctx.with` merges by design.
        def child_context(nav_attrs)
          RenderContext.new(post: ctx.post, query: ctx.query, styles: ctx.styles,
                            context: nav_attrs, depth: ctx.depth + 1)
        end

        def markup_for_inner_block(inner, child_ctx)
          html = Renderer.render_block(inner, child_ctx)
          return html if html.to_s.empty?
          return html unless NEEDS_LIST_ITEM_WRAPPER.include?(inner.block_name)

          %(<li class="wp-block-navigation-item">#{html}</li>)
        end

        # :1217 — a `render_block` listener registered by core on its own block, folded
        # into the renderer that owns it (see the AD-01 note at the head of this file).
        def self.add_directives_to_submenu(tags, nav_attrs)
          open_on_hover = submenu_visibility_for(nav_attrs) == "hover"
          while tags.next_tag({ tag_name: "LI", class_name: "has-child" })
            tags.set_attribute("data-wp-interactive", "core/navigation")
            tags.set_attribute("data-wp-context",
                               '{ "submenuOpenedBy": { "click": false, "hover": false, ' \
                               '"focus": false }, "type": "submenu", "modal": null, ' \
                               '"previousFocus": null }')
            tags.set_attribute("data-wp-watch", "callbacks.initMenu")
            tags.set_attribute("data-wp-on--focusout", "actions.handleMenuFocusout")
            tags.set_attribute("data-wp-on--keydown", "actions.handleMenuKeydown")
            # :1233 — the Safari focus workaround, kept because removing it changes
            # rendered bytes.
            tags.set_attribute("tabindex", "-1")

            if open_on_hover
              tags.set_attribute("data-wp-on--pointerenter", "actions.openMenuOnHover")
              tags.set_attribute("data-wp-on--pointerleave", "actions.closeMenuOnHover")
            end

            if tags.next_tag({ tag_name: "BUTTON", class_name: "wp-block-navigation-submenu__toggle" })
              tags.set_attribute("data-wp-on--click", "actions.toggleMenuOnClick")
              tags.set_attribute("data-wp-bind--aria-expanded", "state.isSubmenuOpen")
            end
            if tags.next_tag({ tag_name: "UL", class_name: "wp-block-navigation__submenu-container" })
              tags.set_attribute("data-wp-on--focus", "actions.openMenuOnFocus")
            end
          end
          tags.get_updated_html
        end

        def self.submenu_visibility_for(nav_attrs)
          legacy = nav_attrs["openSubmenusOnClick"]
          unless legacy.nil?
            return (legacy.nil? || legacy == false || legacy == "" || legacy == 0) ? "hover" : "click"
          end

          nav_attrs["submenuVisibility"] || "hover"
        end

        # :723 — the responsive overlay.
        def responsive_container_markup(nav_attrs, blocks, inner_html)
          is_interactive = interactive?(nav_attrs, blocks)
          colors = self.class.css_colors(nav_attrs)
          modal = NavigationBlocks.scope(ctx).unique_id("modal-")
          hidden_by_default = nav_attrs["overlayMenu"] == "always"

          # ⚠️ NOT IMPLEMENTED, and the omission is visible here rather than hidden in the
          # report alone: `attrs["overlay"]` names a NAVIGATION-OVERLAY TEMPLATE PART
          # (navigation.php:734), which the block renders in place of the default overlay
          # and which then suppresses the overlay colour classes, adds
          # `disable-default-overlay`, may replace the close button with its own
          # `wp-block-navigation-overlay-close`, and forces fetchpriority="low" on its
          # images. No screen in the corpus sets it — the theme's header pattern does not —
          # so rather than write five branches that nothing can check against the oracle,
          # `has_custom_overlay` is fixed at false and this comment says so. The moment a
          # navigation carries `overlay`, this output is wrong.
          has_custom_overlay = false
          container_classes = ["wp-block-navigation__responsive-container"]
          container_classes << "disable-default-overlay" if has_custom_overlay
          container_classes << "hidden-by-default" if hidden_by_default
          container_classes << colors[:overlay_css_classes].join(" ") unless has_custom_overlay

          show_icon_label = nav_attrs["hasIcon"] == true
          toggle_icon = nav_attrs["icon"] == "menu" ? MENU_ICON : OPEN_ICON
          toggle = show_icon_label ? toggle_icon : "Menu"
          close_content = show_icon_label ? CLOSE_ICON : "Close"
          aria_open = show_icon_label ? %(aria-label="Open menu") : ""
          aria_close = show_icon_label ? %(aria-label="Close menu") : ""

          overlay_styles = Php.esc_attr(Php.safecss(colors[:overlay_inline_styles]))
          overlay_styles = overlay_styles.empty? ? "" : %(style="#{overlay_styles}")

          close_button = format('<button %1$s class="wp-block-navigation__responsive-container-close" %2$s>%3$s</button>',
                                aria_close, is_interactive ? CLOSE_BUTTON_DIRECTIVES : "", close_content)

          format(RESPONSIVE_TEMPLATE,
                 aria_open: aria_open,
                 open_classes: Php.esc_attr(["wp-block-navigation__responsive-container-open",
                                             hidden_by_default ? "always-shown" : ""].join(" ").strip),
                 open_directives: is_interactive ? OPEN_BUTTON_DIRECTIVES : "",
                 toggle: toggle,
                 container_classes: Php.esc_attr(container_classes.join(" ").strip),
                 overlay_styles: overlay_styles,
                 modal: Php.esc_attr(modal),
                 container_directives: is_interactive ? CONTAINER_DIRECTIVES : "",
                 dialog_directives: is_interactive ? DIALOG_DIRECTIVES : "",
                 close_button: close_button,
                 content_directives: is_interactive ? CONTENT_DIRECTIVES : "",
                 inner: inner_html,
                 custom_overlay: "")
        end

        # :1615 — block_core_navigation_add_support_classes_to_container(). With no
        # `wp-states-*` class on the wrapper (the `states` support is not built) and no
        # viewport layouts in theme.json, both branches are empty and the function
        # returns its input untouched. Written out so the SHAPE of the rule survives:
        # if either input ever appears, this is where it belongs.
        def add_support_classes_to_container(markup) = markup

        def blank?(value) = value.nil? || value == "" || value == false || value == 0
      end

      # ── usesContext, honoured literally ──────────────────────────────────────────
      # WP_Block::__construct copies from `$available_context` ONLY the keys the block
      # type declares in `usesContext`, and every one of these callbacks then tests
      # `array_key_exists` on the result. Slicing here is what makes those tests mean
      # the same thing.
      module Context
        module_function

        def for(type, ctx)
          return {} if type.nil?

          ctx.context.slice(*Array(type.uses_context))
        end
      end

      # ── the Interactivity API's server pass ──────────────────────────────────────
      # wp-includes/class-wp-block.php:736. The FIRST block whose type declares
      # `supports.interactivity === true` becomes the "root interactive block"; when its
      # whole subtree has rendered, `wp_interactivity_process_directives()` runs once over
      # the combined HTML. Three of this family's blocks are such roots — navigation,
      # search and image — and one of them changes bytes because of it:
      #
      #     <button … aria-expanded="false" data-wp-bind--aria-expanded="state.isSubmenuOpen">
      #
      # `state.isSubmenuOpen` is CLIENT state. No PHP calls `wp_interactivity_state()` for
      # `core/navigation`, so the server store is empty, the reference evaluates to null,
      # and class-wp-interactivity-api.php:1222 REMOVES the bound attribute. Every submenu
      # toggle in the golden files is missing its `aria-expanded` for exactly that reason.
      # Skipping this pass leaves an attribute the oracle does not emit.
      #
      # ⚠️ WHAT IS AND IS NOT IMPLEMENTED. `data-wp-bind--*` and `data-wp-class--*` are
      # evaluated against an EMPTY state store, which is the true store for every block in
      # this family. A `context.*` reference would need the `data-wp-context` stack that
      # WP_Interactivity_API_Directives_Processor maintains across balanced tags; it is
      # NOT built, and such a reference is therefore left untouched rather than guessed at.
      # The only markup in this family that carries one is the search block's `button-only`
      # variant, which no screen in the corpus uses. `data-wp-style--*`, `data-wp-text` and
      # `data-wp-each` are not implemented; no block here emits them. All reported.
      module Interactivity
        module_function

        def process(html)
          return html if html.to_s.empty? || !html.include?("data-wp-")

          tags = Markup::TagProcessor.new(html)
          while tags.next_tag
            bind(tags)
            classes(tags)
          end
          tags.get_updated_html
        end

        # class-wp-interactivity-api.php:1108 `data_wp_bind_processor()`.
        def bind(tags)
          Array(tags.get_attribute_names_with_prefix("data-wp-bind--")).each do |name|
            suffix = name.delete_prefix("data-wp-bind--")
            # :1112 — an empty suffix, or a `--<unique id>` variant, is skipped; :1117 —
            # so is an event handler, which must use data-wp-on-- instead.
            next if suffix.empty? || suffix.include?("--") || suffix.start_with?("on")
            next unless null_reference?(tags.get_attribute(name))

            tags.remove_attribute(suffix)
          end
        end

        # class-wp-interactivity-api.php `data_wp_class_processor()` — a falsy result
        # removes the class.
        def classes(tags)
          Array(tags.get_attribute_names_with_prefix("data-wp-class--")).each do |name|
            suffix = name.delete_prefix("data-wp-class--")
            next if suffix.empty? || suffix.include?("--")
            next unless null_reference?(tags.get_attribute(name))

            tags.remove_class(suffix)
          end
        end

        # True when the reference resolves to null against an empty server store, i.e.
        # when it reads `state`. A `context.` reference is deliberately NOT claimed.
        def null_reference?(reference)
          return false unless reference.is_a?(String)

          path = reference.sub(/\A[!]+/, "")
          path = path.split("::").last.to_s
          path == "state" || path.start_with?("state.")
        end
      end

      # ── the `render_block` filter chain ──────────────────────────────────────────
      # WordPress applies the block-supports RENDER filters (typography → settings →
      # elements → layout → dimensions → block-style-variations) to EVERY block's output,
      # not only to the ones whose own callback is static. That chain is what puts
      # `is-layout-flex`, `is-content-justification-right` and
      # `wp-container-core-navigation-is-layout-<hash>` on the <nav>.
      #
      # It is cross-family infrastructure and it already exists, ported by the `layout`
      # agent in `Renderers::LayoutBlocks`. Calling it here rather than re-porting it is
      # the whole point: two copies of the layout hash would drift, and the hash is
      # load-bearing (it names the CSS rule the styling layer emits).
      #
      # ⚠️ Structurally this belongs in `Renderer.render_block`, so that every block gets
      # it once and no family can forget. Reported; `Renderer` is shared contract.
      module Supports
        module_function

        def apply(html, block, ctx)
          return html if html.to_s.empty?

          elements_class = LayoutBlocks::ElementsSupport.prepare(block, ctx)
          LayoutBlocks.apply_supports(html, block, ctx, elements_class)
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/navigation-link — wp-includes/blocks/navigation-link.php:180
      # ═══════════════════════════════════════════════════════════════════════════════
      class NavigationLink < Base
        handles "core/navigation-link"

        def render
          return "" unless NavigationItem.should_render?(attrs)
          return "" if attrs["label"].to_s.empty?

          # :195 — inner blocks render FIRST, because whether this item has a submenu is
          # decided by whether they produced anything.
          inner_html = block.inner_blocks.map { |b| Renderer.render_block(b, ctx) }.join
          has_submenu = !inner_html.strip.empty?
          is_active = NavigationItem.active?(attrs, ctx)
          context = Context.for(type, ctx)

          # :210 — `$css_classes . ' wp-block-navigation-item'` with $css_classes always
          # empty, so the value starts with a space. It is split on whitespace by the
          # wrapper merge, so the space is harmless — and reproducing it costs nothing.
          klass = +" wp-block-navigation-item"
          klass << " has-child" if has_submenu
          klass << " current-menu-item" if is_active

          html = +"<li #{Wrapper.attributes(type, attrs, { "class" => klass })}>"
          html << %(<a class="wp-block-navigation-item__content" )
          html << %( href="#{Php.esc_url(NavigationItem.maybe_urldecode(attrs["url"]))}") if attrs.key?("url")
          html << %( aria-current="page") if is_active
          html << %( target="_blank"  ) if attrs["opensInNewTab"] == true
          if attrs.key?("rel")
            html << %( rel="#{Php.esc_attr(attrs["rel"])}")
          elsif attrs["nofollow"]
            html << %( rel="nofollow")
          end
          html << %( title="#{Php.esc_attr(attrs["title"])}") if attrs.key?("title")
          html << ">"
          html << %(<span class="wp-block-navigation-item__label">)
          html << Php.kses_post(attrs["label"]) if attrs.key?("label")
          html << "</span>"
          unless attrs["description"].to_s.empty?
            html << %(<span class="wp-block-navigation-item__description">#{Php.kses_post(attrs["description"])}</span>)
          end
          html << "</a>"

          if context["showSubmenuIcon"] && has_submenu
            html << %(<span class="wp-block-navigation__submenu-icon">#{Navigation::SUBMENU_ICON}</span>)
          end
          html << %(<ul class="wp-block-navigation__submenu-container">#{inner_html}</ul>) if has_submenu
          html << "</li>"
          Supports.apply(html, block, ctx)
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/navigation-submenu — wp-includes/blocks/navigation-submenu.php:76
      # ═══════════════════════════════════════════════════════════════════════════════
      class NavigationSubmenu < Base
        handles "core/navigation-submenu"

        def render
          return "" unless NavigationItem.should_render?(attrs)
          return "" if attrs["label"].to_s.empty?

          context = Context.for(type, ctx)
          # providesContext: isParentSubmenu → core/isInsideSubmenu.
          child_ctx = ctx.with(context: { "core/isInsideSubmenu" => attrs["isParentSubmenu"] },
                               depth: ctx.depth + 1)
          inner_html = block.inner_blocks.map { |b| Renderer.render_block(b, child_ctx) }.join
          has_submenu = !inner_html.strip.empty?
          is_active = NavigationItem.active?(attrs, ctx)

          show_indicators = context["showSubmenuIcon"] ? true : false
          visibility = NavigationItem.submenu_visibility(context)
          open_on_click = visibility == "click"
          open_on_hover_and_click = visibility == "hover" && show_indicators

          classes = ["wp-block-navigation-item"]
          classes << "has-child" if has_submenu
          classes << "open-on-click" if open_on_click
          classes << "open-on-hover-click" if open_on_hover_and_click
          classes << "open-always" if visibility == "always"
          classes << "current-menu-item" if is_active

          label = attrs.key?("label") ? Php.kses_post(attrs["label"]) : ""
          aria_label = "#{Php.strip_all_tags(label)} submenu"

          html = +"<li #{Wrapper.attributes(type, attrs, { "class" => classes.join(" ") })}>"
          if open_on_click
            html << %(<button aria-label="#{Php.esc_attr(aria_label)}" class="wp-block-navigation-item__content wp-block-navigation-submenu__toggle" aria-expanded="false">)
            html << %(<span class="wp-block-navigation-item__label">#{label}</span>)
            unless attrs["description"].to_s.empty?
              html << %(<span class="wp-block-navigation-item__description">#{Php.kses_post(attrs["description"])}</span>)
            end
            html << "</button>"
            html << %(<span class="wp-block-navigation__submenu-icon">#{Navigation::SUBMENU_ICON}</span>) if has_submenu
          else
            html << %(<a class="wp-block-navigation-item__content")
            html << %( href="#{Php.esc_url(attrs["url"])}") unless attrs["url"].to_s.empty?
            html << %( aria-current="page") if is_active
            html << %( target="_blank"  ) if attrs["opensInNewTab"] == true
            if attrs.key?("rel")
              html << %( rel="#{Php.esc_attr(attrs["rel"])}")
            elsif attrs["nofollow"]
              html << %( rel="nofollow")
            end
            html << %( title="#{Php.esc_attr(attrs["title"])}") if attrs.key?("title")
            html << ">"
            html << %(<span class="wp-block-navigation-item__label">#{label}</span>)
            unless attrs["description"].to_s.empty?
              html << %(<span class="wp-block-navigation-item__description">#{Php.kses_post(attrs["description"])}</span>)
            end
            html << "</a>"
            if show_indicators && has_submenu
              html << %(<button aria-label="#{Php.esc_attr(aria_label)}" class="wp-block-navigation__submenu-icon wp-block-navigation-submenu__toggle" aria-expanded="false">#{Navigation::SUBMENU_ICON}</button>)
            end
          end

          if has_submenu
            # :262 — the overlay colours are copied down onto THIS block's attributes so
            # that the colour support can answer for the submenu <ul>. That is a mutation
            # of the block's own attribute array in the legacy; here it is a local copy.
            sub_attrs = attrs.dup
            sub_attrs["textColor"] = context["overlayTextColor"] if context.key?("overlayTextColor")
            sub_attrs["backgroundColor"] = context["overlayBackgroundColor"] if context.key?("overlayBackgroundColor")
            if context.key?("customOverlayTextColor")
              sub_attrs["style"] = deep_color(sub_attrs["style"], "text", context["customOverlayTextColor"])
            end
            if context.key?("customOverlayBackgroundColor")
              sub_attrs["style"] = deep_color(sub_attrs["style"], "background", context["customOverlayBackgroundColor"])
            end

            # :275 — `$block->block_type->supports['color'] = true` is set FIRST, so the
            # colour support answers for a block type whose schema does not declare it.
            # A local hash stands in for that mutation of the registered type.
            colors = self.class.colors_support(sub_attrs)
            css_classes = ["wp-block-navigation__submenu-container", colors["class"]]
                          .reject { |c| c.to_s.empty? }.join(" ")

            # :286 — an inner `current-menu-item` promotes every enclosing nav item to
            # `current-menu-ancestor`, and it is done with the tag processor because the
            # markup has already been built.
            if inner_html.include?("current-menu-item")
              tp = Markup::TagProcessor.new(html)
              tp.add_class("current-menu-ancestor") while tp.next_tag({ class_name: "wp-block-navigation-item" })
              html = +tp.get_updated_html
            end

            html << format('<ul %s>%s</ul>',
                           Wrapper.attributes(type, sub_attrs,
                                              { "class" => css_classes, "style" => colors["style"].to_s }),
                           inner_html)
          end
          html << "</li>"
          Supports.apply(html, block, ctx)
        end

        # block-supports/colors.php:83 `wp_apply_colors_support()`, for a block type whose
        # `color` support has just been forced to `true` — so text and background are both
        # on and gradients are off. A PRESET wins over a custom value, and the style engine
        # is asked to convert `var:preset|color|x` into the `has-x-color` class rather than
        # a declaration, which is what `convert_vars_to_classnames` means.
        def self.colors_support(attributes)
          color_styles = {}
          color_styles["text"] =
            attributes.key?("textColor") ? "var:preset|color|#{attributes["textColor"]}" : attributes.dig("style", "color", "text")
          color_styles["background"] =
            attributes.key?("backgroundColor") ? "var:preset|color|#{attributes["backgroundColor"]}" : attributes.dig("style", "color", "background")

          styles = Styling::StyleEngine.get_styles({ "color" => color_styles },
                                                   convert_vars_to_classnames: true)
          out = {}
          out["class"] = styles["classnames"] unless styles["classnames"].to_s.empty?
          out["style"] = styles["css"] unless styles["css"].to_s.empty?
          out
        end

        private

        def deep_color(style, key, value)
          out = (style || {}).deep_dup
          out["color"] ||= {}
          out["color"][key] = value
          out
        end
      end

      # ── shared between navigation-link and navigation-submenu ────────────────────
      module NavigationItem
        module_function

        # navigation-link/shared/item-should-render.php:17. AD-01 removes
        # `render_block_core_navigation_link_allowed_post_status`, so the allowed set is
        # exactly ['publish'] and there is no way to widen it.
        def should_render?(attrs)
          has_id = attrs["id"].is_a?(Numeric) || attrs["id"].to_s.match?(/\A-?\d+(\.\d+)?\z/)
          is_post_type = attrs["kind"] == "post-type" || %w[post page].include?(attrs["type"])
          return true unless is_post_type && has_id

          record = Publishing::Post.find_by(id: attrs["id"].to_i)
          !record.nil? && record.status == "published"
        end

        # navigation-link.php:205 — active when the queried object IS this item's target.
        # `is_post_type_archive()` has no counterpart in the corpus's screens and is not
        # implemented; see the report.
        def active?(attrs, ctx)
          return false if attrs["id"].to_s.empty?

          ctx.post.present? && ctx.post.id == attrs["id"].to_i
        end

        def submenu_visibility(context)
          legacy = context["openSubmenusOnClick"]
          return (legacy == false || legacy.nil? || legacy == "" ? "hover" : "click") unless legacy.nil?

          context["submenuVisibility"] || "hover"
        end

        # navigation-link.php:145 — block_core_navigation_link_maybe_urldecode().
        #
        # ⚠️ The subtlety that makes this rule almost invisible: `wp_parse_args($query)`
        # runs PHP's parse_str, which ALREADY percent-decodes each value. The test
        # `rawurldecode($v) !== $v` therefore fires only on a value that survives one
        # decode still encoded — i.e. a DOUBLE-encoded one. `?q=%C3%A9` decodes to `é`,
        # decodes again to `é`, and the URL is returned untouched; `?q=%2520` does not.
        # Comparing the raw parameter instead would decode every ordinary escape and
        # break `?q=%C3%A9`.
        def maybe_urldecode(url)
          return url if url.to_s.empty?

          query = url.to_s.split("?", 2)[1]
          return url if query.nil?

          encoded = query.split("&").any? do |pair|
            raw = pair.split("=", 2)[1].to_s
            next false if raw.empty?

            once = CGI.unescape(raw)
            !once.empty? && CGI.unescape(once) != once
          rescue ArgumentError
            false
          end
          encoded ? CGI.unescape(url.to_s) : url
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/page-list — wp-includes/blocks/page-list.php:257
      # ═══════════════════════════════════════════════════════════════════════════════
      class PageList < Base
        handles "core/page-list"

        Page = Struct.new(:page_id, :title, :link, :is_active, :children, keyword_init: true)

        class << self
          # get_pages( sort_column: 'menu_order,post_title', order: 'asc' ). Two steps,
          # and the second one is the part a naive port loses: get_pages() sorts FLAT by
          # (menu_order, post_title) and then, because `hierarchical` defaults to true,
          # re-threads the result depth-first through get_page_children(). The observable
          # difference is that a child sorts under its parent no matter what its own
          # menu_order is — verified against the oracle's own get_pages() output.
          def ordered_pages
            flat = Publishing::Page.where(status: "published")
                                   .order(Arel.sql("menu_order ASC, title ASC")).to_a
            by_parent = flat.group_by(&:parent_id)
            depth_first(by_parent, nil, [])
          end

          def depth_first(by_parent, parent_id, out)
            (by_parent[parent_id] || []).each do |page|
              out << page
              depth_first(by_parent, page.id, out)
            end
            out
          end

          def any_page_has_children?
            Publishing::Page.where(status: "published").where.not(parent_id: nil).exists?
          end

          # get_permalink() for a hierarchical page: home + '/' + get_page_uri() + '/'.
          def permalink(page, index)
            segments = []
            node = page
            seen = {}
            while node && !seen[node.id]
              seen[node.id] = true
              segments.unshift(node.slug)
              node = node.parent_id ? index[node.parent_id] : nil
            end
            "#{SiteUrl.home}/#{segments.join("/")}/"
          end
        end

        def render
          context = Context.for(type, ctx)
          all_pages = self.class.ordered_pages
          return "" if all_pages.empty?

          index = all_pages.index_by(&:id)
          active_id = queried_object_id
          ancestor_ids = ancestors_of(index, active_id)

          top_level = {}
          with_children = {}
          all_pages.each do |page|
            entry = Page.new(page_id: page.id, title: page.title,
                             link: self.class.permalink(page, index),
                             is_active: !page.id.nil? && page.id == active_id)
            if page.parent_id
              (with_children[page.parent_id] ||= {})[page.id] = entry
            else
              top_level[page.id] = entry
            end
          end

          colors = self.class.css_colors(context)
          nested = nest(top_level, with_children)

          parent_page_id = attrs["parentPageID"].to_i
          unless parent_page_id.zero?
            return "" unless with_children.key?(parent_page_id)

            nested = nest(with_children[parent_page_id], with_children)
          end

          is_nested = !blank?(context["core/isInsideSubmenu"])
          is_navigation_child = context.key?("showSubmenuIcon")
          visibility = is_navigation_child ? NavigationItem.submenu_visibility(context) : "hover"
          show_icons = is_navigation_child ? context["showSubmenuIcon"] : false

          items = render_nested(visibility, show_icons, is_navigation_child, nested,
                                is_nested, ancestor_ids, colors, 0)
          return Supports.apply(items, block, ctx) if is_nested

          wrapper = Wrapper.attributes(type, attrs,
                                       { "class" => colors[:css_classes].join(" ").strip,
                                         "style" => colors[:inline_styles] })
          Supports.apply("<ul #{wrapper}>#{items}</ul>", block, ctx)
        end

        private

        # get_queried_object_id() as page-list.php:283 uses it: compared RAW against
        # every page's ID, with no check of what KIND of object is queried. On a term
        # archive the id is the TERM id — and the corpus's data makes that observable:
        # term 2 (`top-category`) collides with page 2 (`sample-page`), so the oracle's
        # /category/top-category/ marks Sample Page `current-menu-item` in the page
        # list. A legacy id-collision bug, reproduced rather than corrected (the
        # navigation-link block guards against it with `! empty( get_queried_object()
        # ->$kind )`, navigation-link.php:213; page-list does not).
        # `queriedObject` is the main query's object (Presentation::Page#screen_facts);
        # on singular screens it is the post itself, so `ctx.post` is only a fallback.
        def queried_object_id
          queried = ctx.context["queriedObject"]
          # Inside a navigation, `child_context` REPLACED the block context (WP_Block_List
          # semantics), so the main query — which survives on `ctx.query` — answers, the
          # way the legacy's global does. A date archive's Hash has no id: `(int) null`
          # is 0 there, no page id here.
          queried = ctx.query.queried_object if queried.nil? && ctx.query.respond_to?(:queried_object)
          return queried.id if queried.respond_to?(:id) && !queried.is_a?(Hash)

          ctx.post&.id
        end

        def ancestors_of(index, page_id)
          return [] if page_id.nil?

          out = []
          node = index[page_id]
          while node&.parent_id
            out << node.parent_id
            node = index[node.parent_id]
          end
          out
        end

        # :234 — block_core_page_list_nest_pages().
        def nest(level, children)
          return nil if level.nil? || level.empty?

          level.each do |id, entry|
            entry.children = nest(children[id], children) if children.key?(id)
          end
          level
        end

        # :142 — block_core_page_list_render_nested_page_list().
        def render_nested(visibility, show_icons, is_navigation_child, pages, is_nested,
                          ancestor_ids, colors, depth)
          return "" if pages.nil? || pages.empty?

          # `page_on_front` is 0 in the corpus, so no item ever takes `menu-item-home`;
          # the comparison is kept so a front page would still get it.
          front_page_id = Configuration::Setting["page_on_front"].to_i
          open_on_click = visibility == "click"
          open_on_hover = visibility == "hover"
          open_always = visibility == "always"

          pages.each_value.map do |page|
            css_class = +(page.is_active ? " current-menu-item" : "")
            aria_current = page.is_active ? %( aria-current="page") : ""
            style_attribute = ""

            css_class << " current-menu-ancestor" if ancestor_ids.include?(page.page_id)
            css_class << " has-child" if page.children

            if is_navigation_child
              css_class << " wp-block-navigation-item"
              # :169 — elseif, so open-on-hover-click and open-on-click are exclusive.
              if open_on_click
                css_class << " open-on-click"
              elsif open_on_hover && show_icons
                css_class << " open-on-hover-click"
              elsif open_always
                css_class << " open-always"
              end
            end

            content_class = is_navigation_child ? " wp-block-navigation-item__content" : ""

            # :181 — the first level of SUBMENUS carries the overlay colours.
            if (depth.positive? && !is_nested) || is_nested
              css_class << " #{colors[:overlay_css_classes].join(" ").strip}"
              unless colors[:overlay_inline_styles].empty?
                style_attribute = %( style="#{Php.esc_attr(colors[:overlay_inline_styles])}")
              end
            end

            css_class << " menu-item-home" if page.page_id == front_page_id

            title = page.title.presence || "(no title)"
            aria_label = "#{Php.strip_all_tags(title)} submenu"

            markup = +%(<li class="wp-block-pages-list__item#{Php.esc_attr(css_class)}"#{style_attribute}>)

            if page.children && is_navigation_child && open_on_click
              markup << %(<button aria-label="#{Php.esc_attr(aria_label)}" class="#{Php.esc_attr(content_class)} wp-block-navigation-submenu__toggle" aria-expanded="false">#{Php.kses_post(title)}</button>)
              markup << %(<span class="wp-block-page-list__submenu-icon wp-block-navigation__submenu-icon">#{Navigation::SUBMENU_ICON}</span>)
            else
              markup << %(<a class="wp-block-pages-list__item__link#{Php.esc_attr(content_class)}" href="#{Php.esc_url(page.link)}"#{aria_current}>#{Php.kses_post(title)}</a>)
            end

            if page.children
              if is_navigation_child && show_icons && !open_on_click
                markup << %(<button aria-label="#{Php.esc_attr(aria_label)}" class="wp-block-navigation__submenu-icon wp-block-navigation-submenu__toggle" aria-expanded="false">)
                markup << Navigation::SUBMENU_ICON
                markup << "</button>"
              end
              markup << %(<ul class="wp-block-navigation__submenu-container">)
              markup << render_nested(visibility, show_icons, is_navigation_child, page.children,
                                      is_nested, ancestor_ids, colors, depth + 1)
              markup << "</ul>"
            end
            markup << "</li>"
            markup
          end.join
        end

        def blank?(value) = value.nil? || value == "" || value == false || value == 0

        # :43 — block_core_page_list_build_css_colors(). Unlike navigation's version this
        # one also reads `style.color.*` from the context, and it kebab-cases the slug.
        def self.css_colors(context)
          out = { css_classes: [], inline_styles: +"", overlay_css_classes: [], overlay_inline_styles: +"" }
          [["textColor", "customTextColor", "text", "has-text-color", "has-%s-color", "color: %s;"],
           ["backgroundColor", "customBackgroundColor", "background", "has-background",
            "has-%s-background-color", "background-color: %s;"]].each do |named, picked, path, flag, class_format, style_format|
            has_named = context.key?(named)
            has_picked = context.key?(picked)
            has_custom = !context.dig("style", "color", path).nil?
            out[:css_classes] << flag if has_named || has_picked || has_custom
            if has_named
              out[:css_classes] << format(class_format, kebab(context[named]))
            elsif has_picked
              out[:inline_styles] << format(style_format, context[picked])
            elsif has_custom
              out[:inline_styles] << format(style_format, context.dig("style", "color", path))
            end
          end

          [["overlayTextColor", "customOverlayTextColor", "has-text-color", "has-%s-color", "color: %s;"],
           ["overlayBackgroundColor", "customOverlayBackgroundColor", "has-background",
            "has-%s-background-color", "background-color: %s;"]].each do |named, picked, flag, class_format, style_format|
            has_named = context.key?(named)
            has_picked = context.key?(picked)
            out[:overlay_css_classes] << flag if has_named || has_picked
            if has_named
              out[:overlay_css_classes] << format(class_format, kebab(context[named]))
            elsif has_picked
              out[:overlay_inline_styles] << format(style_format, context[picked])
            end
          end
          out
        end

        # wp-includes/functions.php — _wp_to_kebab_case().
        def self.kebab(value)
          value.to_s.gsub(/(?<=[a-z0-9])([A-Z])/) { "-#{Regexp.last_match(1)}" }
               .gsub(/(?<=[0-9])(?=[a-zA-Z])|(?<=[a-zA-Z])(?=[0-9])/, "-")
               .downcase
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/search — wp-includes/blocks/search.php:17
      # ═══════════════════════════════════════════════════════════════════════════════
      class Search < Base
        handles "core/search"

        SEARCH_ICON = "<svg class=\"search-icon\" viewBox=\"0 0 24 24\" width=\"24\" height=\"24\">\n" \
                      "\t\t\t\t\t<path d=\"M13 5c-3.3 0-6 2.7-6 6 0 1.4.5 2.7 1.3 3.7l-3.8 3.8 1.1 1.1 " \
                      "3.8-3.8c1 .8 2.3 1.3 3.7 1.3 3.3 0 6-2.7 6-6S16.3 5 13 5zm0 10.5c-2.5 0-4.5-2-4.5-4.5s2-4.5 " \
                      "4.5-4.5 4.5 2 4.5 4.5-2 4.5-4.5 4.5z\"></path>\n\t\t\t\t</svg>"

        def render
          # :21 — `<!-- wp:search /-->` with no attributes at all still says "Search"
          # twice, because wp_parse_args fills label and buttonText.
          a = attrs.dup
          a["label"] = "Search" unless a.key?("label")
          a["buttonText"] = "Search" unless a.key?("buttonText")

          input_id = NavigationBlocks.scope(ctx).unique_id("wp-block-search__input-")
          show_label = !blank?(a["showLabel"])
          use_icon_button = !blank?(a["buttonUseIcon"])
          show_button = a["buttonPosition"].to_s != "no-button" || blank?(a["buttonPosition"])
          show_button = false if !blank?(a["buttonPosition"]) && a["buttonPosition"] == "no-button"
          button_position = show_button ? a["buttonPosition"] : nil
          inline = styles(a)
          color_classes = self.class.color_classes(a)
          typography_classes = self.class.typography_classes(a)
          is_button_inside = !blank?(a["buttonPosition"]) && a["buttonPosition"] == "button-inside"
          border_color_classes = self.class.border_color_classes(a)
          is_expandable = button_position == "button-only"

          label_inner = a["label"].to_s.empty? ? "Search" : Php.kses_post(a["label"])
          label = Markup::TagProcessor.new(format('<label %1$s>%2$s</label>', inline[:label], label_inner))
          if label.next_tag
            label.set_attribute("for", input_id)
            label.add_class("wp-block-search__label")
            if show_label && !a["label"].to_s.empty?
              label.add_class(typography_classes) unless typography_classes.empty?
            else
              label.add_class("screen-reader-text")
            end
          end

          input = Markup::TagProcessor.new(format('<input type="search" name="s" required %s/>', inline[:input]))
          input_classes = ["wp-block-search__input"]
          input_classes << border_color_classes if !is_button_inside && !border_color_classes.empty?
          input_classes << typography_classes unless typography_classes.empty?
          input_classes << color_classes if !show_button && !color_classes.empty?
          if input.next_tag
            input.add_class(input_classes.join(" "))
            input.set_attribute("id", input_id)
            input.set_attribute("value", search_query)
            input.set_attribute("placeholder", a["placeholder"].to_s)
            if is_expandable
              input.set_attribute("data-wp-bind--aria-hidden", "!context.isSearchInputVisible")
              input.set_attribute("data-wp-bind--tabindex", "state.tabindex")
              input.set_attribute("aria-hidden", "true")
              input.set_attribute("tabindex", "-1")
            end
          end

          query_params_markup = (a["query"] || {}).map do |param, value|
            format('<input type="hidden" name="%s" value="%s" />', Php.esc_attr(param), Php.esc_attr(value))
          end.join

          button = ""
          if show_button
            button_classes = ["wp-block-search__button"]
            button_classes << color_classes unless color_classes.empty?
            button_classes << typography_classes unless typography_classes.empty?
            button_classes << border_color_classes if !is_button_inside && !border_color_classes.empty?
            if use_icon_button
              button_classes << "has-icon"
              internal = SEARCH_ICON
            else
              internal = a["buttonText"].to_s.empty? ? "" : Php.kses_post(a["buttonText"])
            end
            # wp_theme_get_element_class_name('button') — WP_Theme_JSON's fixed map.
            button_classes << "wp-element-button"

            tp = Markup::TagProcessor.new(format('<button type="submit" %s>%s</button>', inline[:button], internal))
            if tp.next_tag
              tp.add_class(button_classes.join(" "))
              if a["buttonPosition"] == "button-only"
                tp.set_attribute("data-wp-bind--aria-label", "state.ariaLabel")
                tp.set_attribute("data-wp-bind--aria-controls", "state.ariaControls")
                tp.set_attribute("data-wp-bind--aria-expanded", "context.isSearchInputVisible")
                tp.set_attribute("data-wp-bind--type", "state.type")
                tp.set_attribute("data-wp-on--click", "actions.openSearchInput")
                tp.set_attribute("aria-label", "Expand search field")
                tp.set_attribute("aria-controls", "wp-block-search__input-#{input_id}")
                tp.set_attribute("aria-expanded", "false")
                tp.set_attribute("type", "button")
              else
                tp.set_attribute("aria-label", Php.strip_all_tags(a["buttonText"]))
              end
            end
            button = tp.get_updated_html
          end

          field_classes = ["wp-block-search__inside-wrapper"]
          field_classes << border_color_classes if is_button_inside && !border_color_classes.empty?
          field_markup = format('<div class="%s" %s>%s</div>',
                                Php.esc_attr(field_classes.join(" ")), inline[:wrapper],
                                "#{input.get_updated_html}#{query_params_markup}#{button}")

          wrapper = Wrapper.attributes(type, a, { "class" => self.class.classnames(a) })
          directives = is_expandable ? expandable_directives(input_id) : ""

          # :199 — the <search> landmark is opt-in through html5 theme support, which
          # Twenty Twenty-Five does not declare, so the classic <form role="search">
          # branch is the one the corpus exercises. Both are implemented.
          use_search_element = a["tagName"].to_s == "search"
          markup = if use_search_element
            format('<search %2$s %3$s><form method="get" action="%1$s">%4$s</form></search>',
                   Php.esc_url(SiteUrl.home_slash), wrapper, directives,
                   "#{label.get_updated_html}#{field_markup}")
          else
            format('<form role="search" method="get" action="%1$s" %2$s %3$s>%4$s</form>',
                   Php.esc_url(SiteUrl.home_slash), wrapper, directives,
                   "#{label.get_updated_html}#{field_markup}")
          end
          # class-wp-block.php:736 — search is a root interactive block too.
          Interactivity.process(Supports.apply(markup, block, ctx))
        end

        private

        def blank?(value) = value.nil? || value == "" || value == false || value == 0

        # get_search_query( false ) — the raw `s` query var.
        # get_the_search_query() → get_query_var('s'): the MAIN query's search term,
        # which Presentation::Page states as `searchQuery` on the context — this is what
        # refills the search box with the term on /?s=… (golden-web-search.html:190).
        def search_query
          value = ctx.context["searchQuery"]
          return value.to_s unless value.nil?

          q = ctx.query
          value = q.is_a?(Hash) ? (q["s"] || q[:s]) : nil
          value.to_s
        end

        def expandable_directives(input_id)
          context = { "isSearchInputVisible" => false, "inputId" => input_id,
                      "ariaLabelExpanded" => "Submit Search",
                      "ariaLabelCollapsed" => "Expand search field" }
          "\n\t\t data-wp-interactive=\"core/search\"\n\t\t " \
            "#{Php.data_wp_context(context)}\n\t\t " \
            "data-wp-class--wp-block-search__searchfield-hidden=\"!context.isSearchInputVisible\"\n\t\t " \
            "data-wp-on--keydown=\"actions.handleSearchKeydown\"\n\t\t " \
            "data-wp-on--focusout=\"actions.handleSearchFocusout\"\n\t\t"
        end

        # :247 — classnames_for_block_core_search().
        def self.classnames(a)
          names = []
          unless a["buttonPosition"].to_s.empty?
            case a["buttonPosition"]
            when "button-inside" then names << "wp-block-search__button-inside"
            when "button-outside" then names << "wp-block-search__button-outside"
            when "no-button" then names << "wp-block-search__no-button"
            when "button-only" then names << "wp-block-search__button-only wp-block-search__searchfield-hidden"
            end
          end
          if a.key?("buttonUseIcon") && !a["buttonPosition"].to_s.empty? && a["buttonPosition"] != "no-button"
            names << (a["buttonUseIcon"] ? "wp-block-search__icon-button" : "wp-block-search__text-button")
          end
          names.join(" ")
        end

        # :639 — get_border_color_classes_for_block_core_search().
        def self.border_color_classes(a)
          names = []
          has_custom = !a.dig("style", "border", "color").to_s.empty?
          has_named = !a["borderColor"].to_s.empty?
          names << "has-border-color" if has_custom || has_named
          names << "has-#{Php.esc_attr(a["borderColor"])}-border-color" if has_named
          names.join(" ")
        end

        # :666 — get_color_classes_for_block_core_search().
        def self.color_classes(a)
          names = []
          if !a["textColor"].to_s.empty?
            names << "has-text-color has-#{a["textColor"]}-color"
          elsif !a.dig("style", "color", "text").to_s.empty?
            names << "has-text-color"
          end
          has_bg = !a["backgroundColor"].to_s.empty? || !a.dig("style", "color", "background").to_s.empty? ||
                   !a["gradient"].to_s.empty? || !a.dig("style", "color", "gradient").to_s.empty?
          names << "has-background" if has_bg
          names << "has-#{a["backgroundColor"]}-background-color" unless a["backgroundColor"].to_s.empty?
          names << "has-#{a["gradient"]}-gradient-background" unless a["gradient"].to_s.empty?
          names.join(" ")
        end

        # :531 — get_typography_classes_for_block_core_search().
        def self.typography_classes(a)
          names = []
          names << "has-#{Php.esc_attr(a["fontSize"])}-font-size" unless a["fontSize"].to_s.empty?
          names << "has-#{Php.esc_attr(a["fontFamily"])}-font-family" unless a["fontFamily"].to_s.empty?
          names.join(" ")
        end

        # :556 — get_typography_styles_for_block_core_search().
        # `wp_get_typography_font_size_value()` resolves FLUID typography out of
        # theme.json — `20px` becomes `clamp(14px, 0.875rem + …, 20px)`. It is the `layout`
        # agent's port that owns that resolution, and calling it is the point: a second
        # copy of the clamp arithmetic would drift from the one the golden files were
        # captured against.
        def self.typography_styles(a)
          t = a["style"].is_a?(Hash) ? (a["style"]["typography"] || {}) : {}
          out = +""
          unless t["fontSize"].to_s.empty?
            out << "font-size: #{LayoutBlocks::TypographySupport.font_size_value(t["fontSize"])};"
          end
          out << "font-family: #{t["fontFamily"]};" unless t["fontFamily"].to_s.empty?
          out << "letter-spacing: #{t["letterSpacing"]};" unless t["letterSpacing"].to_s.empty?
          out << "font-weight: #{t["fontWeight"]};" unless t["fontWeight"].to_s.empty?
          out << "font-style: #{t["fontStyle"]};" unless t["fontStyle"].to_s.empty?
          out << "line-height: #{t["lineHeight"]};" unless t["lineHeight"].to_s.empty?
          out << "text-transform: #{t["textTransform"]};" unless t["textTransform"].to_s.empty?
          out
        end

        # :360 — styles_for_block_core_search().
        def styles(a)
          wrapper = []
          button = []
          input = []
          label = []
          is_button_inside = !blank?(a["buttonPosition"]) && a["buttonPosition"] == "button-inside"
          show_label = a.key?("showLabel") && a["showLabel"] != false

          if !blank?(a["width"]) && !blank?(a["widthUnit"])
            wrapper << "width: #{a["width"].to_i}#{Php.esc_attr(a["widthUnit"])};"
          end

          %w[width color style].each do |property|
            [nil, "top", "right", "bottom", "left"].each do |side|
              border_style(a, property, side, wrapper, button, input, is_button_inside)
            end
          end
          border_radius(a, wrapper, button, input, is_button_inside)

          use_input = !blank?(a["buttonPosition"]) && a["buttonPosition"] == "no-button"
          { "text" => "color: %s;", "background" => "background-color: %s;",
            "gradient" => "background: %s;" }.each do |key, template|
            value = a.dig("style", "color", key)
            next if value.to_s.empty?

            (use_input ? input : button) << format(template, value)
          end

          typography = Php.esc_attr(self.class.typography_styles(a))
          unless typography.empty?
            label << typography
            button << typography
            input << typography
          end
          decoration = a.dig("style", "typography", "textDecoration")
          unless decoration.to_s.empty?
            button << "text-decoration: #{Php.esc_attr(decoration)};"
            label << "text-decoration: #{Php.esc_attr(decoration)};" if show_label
          end

          { input: style_attribute(input), button: style_attribute(button),
            wrapper: style_attribute(wrapper), label: style_attribute(label) }
        end

        def style_attribute(parts)
          return "" if parts.empty?

          %( style="#{Php.esc_attr(Php.safecss(parts.join(" ")))}")
        end

        def border_style(a, property, side, wrapper, button, input, is_button_inside)
          path = side ? ["style", "border", side, property] : ["style", "border", property]
          value = a.dig(*path)
          return if value.nil? || value == "" || value == false

          if property == "color" && side && value.to_s.include?("var:preset|color|")
            value = "var(--wp--preset--color--#{value.to_s.split("|").last})"
          end
          suffix = side ? "#{side}-#{property}" : property
          if is_button_inside
            wrapper << "border-#{suffix}: #{Php.esc_attr(value)};"
          else
            button << "border-#{suffix}: #{Php.esc_attr(value)};"
            input << "border-#{suffix}: #{Php.esc_attr(value)};"
          end
        end

        def border_radius(a, wrapper, button, input, is_button_inside)
          radius = a.dig("style", "border", "radius")
          return if radius.nil? || radius == "" || radius == false

          if radius.is_a?(Hash)
            radius.each do |key, value|
              if value.is_a?(String) && value.include?("var:preset|border-radius|")
                value = "var(--wp--preset--border-radius--#{PageList.kebab(value.split("|").last)})"
              end
              next if value.nil?

              name = key.to_s.gsub(/(?<!\A)[A-Z]/) { "-#{Regexp.last_match(0)}" }.downcase
              declaration = "border-#{Php.esc_attr(name)}-radius: #{Php.esc_attr(value)};"
              input << declaration
              button << declaration
              if is_button_inside && (value.to_i != 0 || value.to_s.include?("var(--wp--preset--border-radius--"))
                wrapper << "border-#{Php.esc_attr(name)}-radius: calc(#{Php.esc_attr(value)} + 4px);"
              end
            end
          else
            radius = "#{radius}px" if radius.is_a?(Numeric) || radius.to_s.match?(/\A-?\d+(\.\d+)?\z/)
            if radius.to_s.include?("var:preset|border-radius|")
              radius = "var(--wp--preset--border-radius--#{PageList.kebab(radius.to_s.split("|").last)})"
            end
            declaration = "border-radius: #{Php.esc_attr(radius)};"
            input << declaration
            button << declaration
            wrapper << "border-radius: calc(#{Php.esc_attr(radius)} + 4px);" if is_button_inside && radius.to_i != 0
          end
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/image — wp-includes/blocks/image.php:20
      # ═══════════════════════════════════════════════════════════════════════════════
      #
      # The image block is a STATIC block with a render callback that edits its own saved
      # markup. Three edits, and nothing else: the `wp-image-<id>` class when the id came
      # from a block binding, the `data-id` back-compat attribute a gallery stamps on, and
      # the removal of an empty `<figcaption>`.
      class Image < Base
        handles "core/image"

        # :92 — "empty" tolerates comments between the tags, and nothing else.
        EMPTY_FIGCAPTION = %r{<figcaption\b[^>]*>(?:<!--.*?-->|[\s]*)*</figcaption>}m

        def render
          content = super
          return "" unless content.downcase.include?("<img")

          processor = Markup::TagProcessor.new(content)
          return "" unless processor.next_tag("img") && processor.get_attribute("src")

          has_id_binding = !attrs.dig("metadata", "bindings", "id").nil? && !attrs["id"].nil?
          if has_id_binding
            classnames = processor.get_attribute("class")
            wanted = "wp-image-#{attrs["id"]}"
            if classnames.is_a?(String) && !classnames.include?(wanted)
              processor.set_attribute("class", classnames.gsub(/wp-image-(\d+)/, wanted))
            end
          end

          # :78 — `data-id` is only ever set by core/gallery's back-compat pass.
          if attrs.key?("data-id")
            processor.set_attribute("data-id", (has_id_binding ? attrs["id"] : attrs["data-id"]).to_s)
          end

          output = processor.get_updated_html
          # :124 — the lightbox branch is a `render_block_core/image` filter that adds
          # interactivity markup. `lightbox` is unset in the corpus and the branch is not
          # implemented; see the report.
          output = output.sub(EMPTY_FIGCAPTION, "") if attrs["caption"].to_s.empty?
          Interactivity.process(Supports.apply(output, block, ctx))
        end
      end

      # ═══════════════════════════════════════════════════════════════════════════════
      # core/gallery — wp-includes/blocks/gallery.php:309
      # ═══════════════════════════════════════════════════════════════════════════════
      #
      # ⚠️ PARTIAL, and it is the weakest block in this family. What IS implemented is the
      # markup path: the per-instance `wp-block-gallery-N` class, and the dynamic-content
      # wrapper. What is NOT is the `--wp--style--unstable-gallery-gap` custom property,
      # because that is written into WP_Style_Engine's block-supports store and printed by
      # the styling layer, which does not exist yet in the rebuild. `randomOrder` is
      # deliberately left unshuffled — see the note at its branch.
      class Gallery < Base
        handles "core/gallery"

        def render
          content = saved_markup_with_data_ids
          content = dynamic_wrapper(content) unless attrs["dynamicContent"].to_s.empty?

          unique = NavigationBlocks.scope(ctx).unique_id("wp-block-gallery-")
          processor = Markup::TagProcessor.new(content)
          processor.next_tag
          processor.add_class(unique)
          # :419 — wp_style_engine_get_stylesheet_from_css_rules() registers
          #   .wp-block-gallery.<unique> { --wp--style--unstable-gallery-gap: <gap> }
          # into the block-supports CSS store. NOT DONE: there is no store to write to.
          Supports.apply(processor.get_updated_html, block, ctx)
        end

        private

        # :21 — block_core_gallery_data_id_backcompatibility(), a `render_block_data`
        # filter: every inner core/image gets a `data-id` copied from its `id`, which
        # core/image's own callback then writes onto the <img>. The legacy MUTATES the
        # parsed block to do it; here the copy is local, because the parsed tree is shared
        # and a renderer that edits it changes what a later render sees.
        def saved_markup_with_data_ids
          return block.inner_html if block.inner_blocks.empty?

          index = -1
          block.inner_content.map do |chunk|
            next chunk unless chunk.nil?

            index += 1
            Renderer.render_block(with_data_id(block.inner_blocks[index]), ctx)
          end.join
        end

        def with_data_id(inner)
          return inner if inner.nil? || inner.block_name != "core/image"

          supplied = inner.attrs || {}
          return inner if supplied.key?("data-id") || !supplied.key?("id")

          copy = inner.dup
          copy.attrs = supplied.merge("data-id" => Php.esc_attr(supplied["id"]))
          copy
        end

        # :319 — dynamic galleries resolve their images from a source query at render
        # time. `dynamicContent` is unset everywhere in the corpus, and resolving it needs
        # the attachment-query surface that `Library` owns, so this renders nothing rather
        # than guessing. Stated, not silently approximated.
        def dynamic_wrapper(_content) = ""

        # :488 — `randomOrder` shuffles the figures with PHP's shuffle(), i.e. with a
        # per-request RNG. A parity harness cannot compare that, and `bin/parity
        # determinism` exists precisely to keep the corpus reproducible, so the ordering
        # is left alone and the divergence is reported instead of being invented.
      end
    end
  end
end
