# frozen_string_literal: true

module Presentation
  # `wp_head()` for a block theme, wp-includes/general-template.php:3050 plus the
  # actions default-filters.php:390 registers on it.
  #
  # ⚠️ The ORDER is not decoration: 39% of each golden screen's bytes are the `<style>`
  # elements this assembles, so a section in the wrong place fails the diff for the whole
  # page. The order below is the order the goldens show, and each entry names the legacy
  # function that produced it.
  #
  # AD-01: `wp_head` is an ACTION, and it is gone. What is left is the fixed sequence
  # WordPress itself registers — nothing can be added to it, removed from it or reordered.
  class Head
    # `_block_template_viewport_meta_tag()`, block-template.php:410 — for a block theme
    # this is hooked at priority 0, i.e. before the title.
    VIEWPORT = %(<meta name="viewport" content="width=device-width, initial-scale=1" />)
    # `wp_robots()`, robots-template.php. Two directives are reachable here:
    # `wp_robots_max_image_preview_large()` always, and `wp_robots_noindex_search()`
    # (:118), which adds `noindex, follow` on a search screen — visible in
    # golden-web-search.html:6 and in no other golden.
    # ⚠️ single quotes: the legacy prints this attribute with them.
    ROBOTS = %(<meta name='robots' content='max-image-preview:large' />)
    ROBOTS_SEARCH = %(<meta name='robots' content='noindex, follow, max-image-preview:large' />)
    # `wp_generator()`, general-template.php.
    GENERATOR_VERSION = "7.2-alpha-63330"
    # `feed_links()` / `feed_links_extra()`, general-template.php:3455 and :3520.
    FEED_SEPARATOR = "&raquo;"
    # `wp_maybe_inline_styles()`, wp-includes/script-loader.php:3098 — `$total_inline_limit
    # = 40000` (raised from 20K in 6.9.0). AD-01: `styles_inline_size_limit` is a filter
    # and is gone, so 40000 is the specification.
    TOTAL_INLINE_LIMIT = 40_000

    # ⚠️ `resolution` is accepted but deliberately unused, and that is a FACT about the
    # legacy rather than an oversight: `wp_head()` never learns which template rendered
    # the page. Everything here is derived from the QUERY (Presentation::Screen) and from
    # what the render enqueued (`styles`). Taking it as an argument keeps that visible.
    def initialize(screen:, styles:, site_url:, enqueued_script_modules: [], resolution: nil, global_styles: nil,
                   block_supports_css: nil, style_variation_css: nil)
      @screen = screen
      @resolution = resolution
      @styles = styles
      @enqueued_script_modules = enqueued_script_modules
      @site = site_url.to_s.chomp("/")
      @global_styles = global_styles
      @block_supports_css = block_supports_css
      @style_variation_css = style_variation_css
    end

    def to_html
      lines = []
      lines << %(<meta charset="UTF-8" />)
      lines << VIEWPORT
      lines << (@screen.search? ? ROBOTS_SEARCH : ROBOTS)
      lines << "<title>#{DocumentTitle.new(@screen)}</title>"
      lines.concat(feed_links)
      lines.concat(style_elements)
      lines << rest_and_rsd_links
      lines << %(<meta name="generator" content="WordPress #{GENERATOR_VERSION}" />)
      lines.concat(canonical_links)
      lines.concat(script_modules)
      lines << font_faces
      lines.compact.reject(&:empty?).join("\n")
    end

    private

    def site_name = Configuration::Setting["blogname"].to_s

    # ── styles ─────────────────────────────────────────────────────────────────────

    # The observed sequence, with the block stylesheets in FIRST-USE order in the middle.
    #
    # ⚠️ `wp-emoji-styles` MOVES when a block style variation registered during the
    # render, and that is WP_Dependencies resolving an edge, not caprice. The handle
    # `block-style-variation-styles` is registered with deps
    # `['wp-block-library', 'global-styles']` (block-supports/block-style-variations.php
    # :192) and enqueued on `wp_enqueue_scripts` at priority 1 (:267) — BEFORE
    # `wp_enqueue_emoji_styles` at priority 10 (default-filters.php:378). `do_items()`
    # therefore pulls wp-block-library and global-styles forward to print before the
    # variation handle, and emoji follows them. On a screen with no variation the handle
    # is enqueued but never registered, prints nothing and pulls nothing — emoji stays
    # ahead of wp-block-library, which is the order the other fifteen goldens show.
    def style_elements
      # ⚠️ `wp-img-auto-sizes-contain` and `wp-emoji-styles` are registered from STRING
      # LITERALS (media.php:2212, formatting.php:5979) — no `path`, so `wp_maybe_inline_styles()`
      # never sees them and they can never become a `<link>`. `Assets#source` is what
      # records the difference: a `/`-rooted path for a file, `file.php:line` for a literal.
      elements = [Assets.style_tag("wp-img-auto-sizes-contain", site_url: @site)]
      elements.concat(block_style_elements)
      if @style_variation_css.blank?
        elements << Assets.style_tag("wp-emoji-styles", site_url: @site)
        elements << asset_style_element("wp-block-library")
        elements << global_styles_element
      else
        elements << asset_style_element("wp-block-library")
        elements << global_styles_element
        elements << Assets.inline("block-style-variation-styles", @style_variation_css,
                                  "block-style-variation-styles-inline-css")
        elements << Assets.style_tag("wp-emoji-styles", site_url: @site)
      end
      elements << block_supports_element
      elements << asset_style_element("wp-block-template-skip-link")
      elements << asset_style_element("#{Assets.meta["slug"]}-style")
      elements.compact
    end

    # `wp_maybe_inline_styles()`, wp-includes/script-loader.php:3095.
    #
    # ⚠️ The rule is a BUDGET, not a per-file threshold, and it is what decides between
    # `<style id="X-inline-css">` and `<link rel='stylesheet' id='X-css'>`. Only styles
    # registered with a `path` are candidates (:3111); they are sorted ASCENDING by the
    # file's byte size (:3144) and inlined until the running total would exceed
    # TOTAL_INLINE_LIMIT, at which point the loop BREAKS (:3164) — so the largest styles
    # stay external, and whether a given one does depends on what ELSE the screen enqueued.
    #
    # Measured against the goldens, screen by screen: `/` totals 37,564 path bytes and
    # inlines everything; `/definitely-not-a-real-url/` totals 41,854, so the largest
    # candidate — `wp-block-navigation` at 20,776 — is left as a `<link>`. Four of the
    # eighteen screens (single, singular, comments, 404) turn on this.
    def linked_handles
      @linked_handles ||= begin
        total = 0
        path_styles.sort_by { |style| style[:size] }.drop_while do |style|
          total += style[:size]
          total <= TOTAL_INLINE_LIMIT
        end.map { |style| style[:handle] }.to_set
      end
    end

    # The `$wp_styles->queue` entries that have `path` data, as { handle, src, size }.
    def path_styles
      styles = @styles.used.filter_map do |name|
        css = Composition::Registry.style_for(name)
        next unless css

        short = name.sub(%r{\Acore/}, "")
        { handle: "wp-block-#{short}", size: css.bytesize,
          src: "/wp-includes/blocks/#{short}/style.min.css" }
      end
      styles + ["wp-block-library", "wp-block-template-skip-link",
                "#{Assets.meta["slug"]}-style"].filter_map { |handle| asset_path_style(handle) }
    end

    def asset_path_style(handle)
      asset = Assets[handle]
      return nil unless asset && asset["source"].to_s.start_with?("/")

      { handle: handle, size: asset["css"].bytesize, src: asset["source"] }
    end

    def asset_style_element(handle)
      return Assets.style_tag(handle, site_url: @site) unless linked_handles.include?(handle)

      stylesheet_link(handle, Assets[handle]["source"])
    end

    # `WP_Styles::do_item()`, class-wp-styles.php — ⚠️ single quotes, and `media='all'`.
    def stylesheet_link(handle, src)
      %(<link rel='stylesheet' id='#{handle}-css' ) +
        %(href='#{@site}#{src}?ver=#{GENERATOR_VERSION}' media='all' />)
    end

    # ⚠️ FINDING, not a workaround. Composition::StyleCollector#to_html emits
    #   <style id="wp-block-X-inline-css">\n{css}\n</style>
    # with NO `/*# sourceURL=… */` trailer, but every golden file carries one for every
    # block stylesheet (`<SITE>/wp-includes/blocks/X/style.min.css`). StyleCollector is
    # shared contract and this family may not edit it, so the head reads the collector's
    # `used` list — its ORDER is the part that matters and is unchanged — and wraps each
    # entry itself. The two renderings will disagree until StyleCollector#to_html is
    # corrected; see the report.
    def block_style_elements
      @styles.used.map do |name|
        short = name.sub(%r{\Acore/}, "")
        src = "/wp-includes/blocks/#{short}/style.min.css"
        next stylesheet_link("wp-block-#{short}", src) if linked_handles.include?("wp-block-#{short}")

        Assets.inline("wp-block-#{short}", Composition::Registry.style_for(name), "#{@site}#{src}")
      end
    end

    # `wp_enqueue_global_styles()` → WP_Theme_JSON::get_stylesheet().
    def global_styles_element
      return nil if @global_styles.blank?

      Assets.inline("global-styles", @global_styles, "global-styles-inline-css")
    end

    # `wp_enqueue_stored_styles()` — the layout/spacing rules the block supports emitted
    # into the 'block-supports' CSS rules store while the template rendered.
    def block_supports_element
      return nil if @block_supports_css.blank?

      Assets.inline("core-block-supports", @block_supports_css, "core-block-supports-inline-css")
    end

    # ── links ──────────────────────────────────────────────────────────────────────

    def feed_links
      links = [
        feed_link("#{site_name} #{FEED_SEPARATOR} Feed", "#{@site}/feed/"),
        feed_link("#{site_name} #{FEED_SEPARATOR} Comments Feed", "#{@site}/comments/feed/"),
      ]
      extra = extra_feed_link
      links << extra if extra
      links.concat(oembed_discovery_links)
    end

    # `wp_oembed_add_discovery_links()`, wp-includes/embed.php — singular screens only.
    #
    # ⚠️ The `url` parameter is the page's own permalink, PERCENT-ENCODED. The parity
    # normalizer maps `http://127.0.0.1:<port>` to `<SITE>` (normalizer.rb:115) but its
    # pattern cannot see through `%3A%2F%2F`, so the oracle's golden keeps a literal
    # `127.0.0.1%3A8099` here and this line can never compare equal however correct it is.
    # It is emitted anyway — the alternative is a page that is wrong in order to make a
    # diff look better — and the missing normalization rule is reported.
    def oembed_discovery_links
      return [] unless @screen.singular? && @screen.post

      permalink = "#{@site}#{permalink(@screen.post)}"
      endpoint = "#{@site}/wp-json/oembed/1.0/embed?url=#{CGI.escape(permalink)}"
      [%(<link rel="alternate" title="oEmbed (JSON)" type="application/json+oembed" href="#{endpoint}" />),
       %(<link rel="alternate" title="oEmbed (XML)" type="text/xml+oembed" href="#{endpoint}&#038;format=xml" />)]
    end

    # general-template.php:3520. One extra link at most, and only for the shapes the
    # corpus reaches.
    def extra_feed_link
      s = @screen
      if s.singular? && s.post
        # :3577 — printed when comments are open, pings are open, OR the post already has
        # comments. The corpus's pages satisfy the third arm.
        return nil unless comments_feed?(s.post)

        feed_link("#{site_name} #{FEED_SEPARATOR} #{title_attribute(s.post)} Comments Feed",
                  "#{@site}#{permalink(s.post)}feed/")
      elsif s.category? && s.term
        feed_link("#{site_name} #{FEED_SEPARATOR} #{esc_attr(s.term.name)} Category Feed",
                  "#{@site}#{term_path(s.term)}feed/")
      elsif s.tag? && s.term
        feed_link("#{site_name} #{FEED_SEPARATOR} #{esc_attr(s.term.name)} Tag Feed",
                  "#{@site}#{term_path(s.term)}feed/")
      elsif s.author? && s.author
        feed_link("#{site_name} #{FEED_SEPARATOR} Posts by #{esc_attr(s.author.display_name)} Feed",
                  "#{@site}/author/#{s.author.login}/feed/")
      elsif s.search?
        feed_link("#{site_name} #{FEED_SEPARATOR} Search Results for &#8220;#{esc_attr(s.search_query)}&#8221; Feed",
                  "#{@site}/search/#{CGI.escape(s.search_query.to_s)}/feed/rss2/")
      end
    end

    def feed_link(title, href)
      %(<link rel="alternate" type="application/rss+xml" title="#{title}" href="#{href}" />)
    end

    # `the_title_attribute()`, wp-includes/post-template.php:81 — `esc_attr( strip_tags(
    # get_the_title( $post ) ) )` (:90, :97), which is what :3582 feeds into the feed
    # link's title. `get_the_title()` (:118) prepends `Protected: %s` when the post has a
    # password (:128, :143), else `Private: %s` when its status is private (:147, :162),
    # and then runs the `the_title` chain core registers: wptexturize, convert_chars, trim
    # (default-filters.php:197-199) and capital_P_dangit at priority 11 (:170, whose
    # `the_title` branch is a plain str_replace, formatting.php:5786). AD-01: a fixed
    # pipeline. ⚠️ The raw title is NOT enough, and two corpus posts prove it: the
    # password-protected one reads `Protected: Password protected Comments Feed`, and the
    # backslash-title one reaches the attribute with `\&#8221;` — texturize runs before
    # esc_attr, and esc_attr does not double-encode (BR-MIGRATE-014), so the curly quote
    # survives as its entity where the raw title would have given `\&quot;`.
    def title_attribute(post)
      title = post.title.to_s
      if post.password_digest.present?
        title = "Protected: #{title}"
      elsif post.status.to_s == "private"
        title = "Private: #{title}"
      end
      title = Sanitizing::Texturize.wptexturize(title)
      title = convert_chars(title).strip.gsub("Wordpress", "WordPress")
      esc_attr(Sanitizing::Formatting.strip_tags(title))
    end

    # convert_chars(), wp-includes/formatting.php:2492 — a bare `&` that does not open an
    # entity becomes `&#038;` (:2497-2498). Nothing else.
    def convert_chars(text)
      return text unless text.include?("&")

      text.gsub(/&([^#])(?![a-z1-4]{1,8};)/i, '&#038;\1')
    end

    # general-template.php:3577 — `comments_open($post) || pings_open($post) ||
    # (int) $post->comment_count > 0`.
    #
    # `pings_open()` reads `ping_status`, a column AD-03's data model dropped — and the
    # oracle's `privacy-policy` page reaches this link through it ALONE
    # (comment_status=closed, comment_count=0, ping_status=OPEN). The seeding pipeline
    # therefore parks the legacy column in the residual bucket
    # (lib/seeding/pipeline.rb, load_posts) instead of losing it, and `pings_open()`
    # is this read. A post loaded outside the pipeline has no such key, and no key means
    # pings are not open — matching the legacy default only by accident, so the fact is
    # stated: `default_ping_status` is 'open' in the oracle, but a ping status is a
    # per-post fact and only seeded rows carry one.
    def comments_feed?(post)
      post.comment_status.to_s == "open" ||
        post.residual_attributes["ping_status"].to_s == "open" ||
        post.comment_count.to_i.positive?
    end

    # `rest_output_link_wp_head()` and `rsd_link()`. ⚠️ The legacy prints these with NO
    # separating whitespace, which the harness's `>\s+<` collapse cannot restore, so they
    # are emitted glued exactly as the goldens show them.
    def rest_and_rsd_links
      parts = [%(<link rel="https://api.w.org/" href="#{@site}/wp-json/" />)]
      route = rest_route
      parts << %(<link rel="alternate" title="JSON" type="application/json" href="#{@site}/wp-json/#{route}" />) if route
      parts << %(<link rel="EditURI" type="application/rsd+xml" title="RSD" href="#{@site}/xmlrpc.php?rsd" />)
      parts.join
    end

    def rest_route
      s = @screen
      if s.single? && s.post then "wp/v2/posts/#{s.post.id}"
      elsif s.page? && s.post then "wp/v2/pages/#{s.post.id}"
      elsif s.category? && s.term then "wp/v2/categories/#{s.term.id}"
      elsif s.tag? && s.term then "wp/v2/tags/#{s.term.id}"
      elsif s.author? && s.author then "wp/v2/users/#{s.author.id}"
      end
    end

    # `rel_canonical()` and `wp_shortlink_wp_head()` — singular only.
    # ⚠️ the shortlink is printed with SINGLE quotes in the legacy.
    def canonical_links
      s = @screen
      return [] unless s.singular? && s.post

      [%(<link rel="canonical" href="#{@site}#{permalink(s.post)}" />),
       %(<link rel='shortlink' href='#{@site}/?p=#{s.post.id}' />)]
    end

    # `wp_print_import_map()` and `wp_print_script_module_preloads()`,
    # wp-includes/class-wp-script-modules.php.
    # ⚠️ Driven by what the render actually ENQUEUED, not by the manifest.
    #
    # `print_script_module_preloads()` (class-wp-script-modules.php) walks the static
    # dependencies of the queue and skips anything that is itself queued — "Don't preload
    # if it's marked for enqueue" — because an enqueued module gets a real `<script>` tag
    # in the footer instead. So the import map and the preloads carry the DEPENDENCIES of
    # what rendered, and the footer carries the modules themselves.
    #
    # Emitting the whole manifest here happened to match while exactly one module existed;
    # it stops matching the moment a second block enqueues anything.
    def script_modules
      queue = Array(@enqueued_script_modules)
      dependencies = Assets.script_module_dependencies(queue) - queue
      return [] if dependencies.empty?

      catalogue = Assets.script_modules
      imports = dependencies.to_h { |id| [id, module_src(catalogue[id])] }
      preloads = dependencies.map do |id|
        %(<link rel="modulepreload" href="#{module_src(catalogue[id])}" id="#{id}-js-modulepreload" fetchpriority="low">)
      end
      [%(<script id="wp-importmap" type="importmap">),
       JSON.generate({ "imports" => imports }),
       "</script>", *preloads]
    end

    def module_src(entry) = "#{@site}#{entry["src"]}?ver=#{entry["version"]}"

    # `WP_Font_Face::generate_and_print()`, wp-includes/fonts/class-wp-font-face.php.
    # The source is the merged theme.json's `settings.typography.fontFamilies[].fontFace`.
    def font_faces
      families = Assets.theme_json.dig("settings", "typography", "fontFamilies") || []
      faces = families.flat_map { |family| Array(family["fontFace"]) }
      return "" if faces.empty?

      rules = faces.map { |face| font_face_rule(face) }
      "<style class=\"wp-fonts-local\">\n#{rules.join("\n")}\n</style>"
    end

    # The legacy prints the properties in a fixed order and quotes a family name only when
    # it contains a space (class-wp-font-face.php).
    def font_face_rule(face)
      family = face["fontFamily"].to_s
      family = %("#{family}") if family.include?(" ") && !family.start_with?('"')
      src = Array(face["src"]).map do |path|
        url = path.to_s.sub(%r{\Afile:\./}, "#{@site}/wp-content/themes/#{Assets.meta["slug"]}/")
        "url('#{url}') format('#{font_format(url)}')"
      end.join(", ")
      declarations = ["font-family:#{family}"]
      declarations << "font-style:#{face["fontStyle"]}" if face["fontStyle"]
      declarations << "font-weight:#{face["fontWeight"]}" if face["fontWeight"]
      declarations << "font-display:#{face["fontDisplay"] || "fallback"}"
      declarations << "src:#{src}"
      "@font-face{#{declarations.join(";")};}"
    end

    def font_format(url)
      case File.extname(URI.parse(url).path)
      when ".woff2" then "woff2"
      when ".woff" then "woff"
      when ".ttf" then "truetype"
      when ".otf" then "opentype"
      else "woff2"
      end
    end

    # ── shared bits ────────────────────────────────────────────────────────────────

    # ⚠️ Both of these walk ANCESTORS, and both would look right in a spot check without
    # it. A page's permalink is its whole path — BR-MIGRATE-033 scopes a page slug to
    # (type, parent), so `child-page` is only unique under its parent — and a hierarchical
    # term's archive is likewise the whole path: the oracle's feed link for
    # `middle-category` is `/category/top-category/middle-category/feed/`, not
    # `/category/middle-category/feed/`.
    def permalink(post)
      return "/#{page_path(post).join("/")}/" if post.is_a?(Publishing::Page)

      "/#{post.published_at.strftime("%Y/%m")}/#{post.slug}/"
    end

    def page_path(page, seen = [])
      return [page.slug] if page.parent_id.nil? || seen.include?(page.id)

      parent = Publishing::Page.find_by(id: page.parent_id)
      return [page.slug] if parent.nil?

      page_path(parent, seen + [page.id]) + [page.slug]
    end

    def term_path(term)
      prefix = term.taxonomy.name == "category" ? "category" : "tag"
      "/#{prefix}/#{term_path_segments(term).join("/")}/"
    end

    # Only a HIERARCHICAL taxonomy nests its archive path; `post_tag` is flat, which is
    # why `/tag/flat-tag-one/` has no ancestors even when the term has a parent column.
    def term_path_segments(term, seen = [])
      return [term.slug] unless term.taxonomy.hierarchical?
      return [term.slug] if term.parent_id.nil? || seen.include?(term.id)

      parent = Classification::Term.find_by(id: term.parent_id)
      return [term.slug] if parent.nil?

      term_path_segments(parent, seen + [term.id]) + [term.slug]
    end

    # `esc_attr()` — ⚠️ does NOT double-encode, which is why the already-escaped option
    # values survive as `&quot;` (BR-MIGRATE-014).
    def esc_attr(text) = Sanitizing::Formatting.esc_attr(text.to_s)
  end
end
