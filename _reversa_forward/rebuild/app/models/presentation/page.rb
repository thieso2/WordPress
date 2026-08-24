# frozen_string_literal: true

module Presentation
  # `wp-includes/template-canvas.php` — the file a block theme actually renders.
  #
  # Its shape is the whole of this class:
  #
  #     $template_html = get_the_block_template_html();   // BEFORE <head>
  #     <!DOCTYPE html><html …><head><meta charset><?php wp_head(); ?></head>
  #     <body <?php body_class(); ?>> … $template_html … <?php wp_footer(); ?>
  #
  # ⚠️ The comment on line 8 of template-canvas.php is load-bearing: "This needs to run
  # before <head> so that blocks can add scripts and styles in wp_head()." The template is
  # rendered FIRST, and the head is assembled afterwards from what the render collected.
  # Doing it the other way round produces a `<head>` with no block stylesheets in it —
  # 39% of the page's bytes, silently missing.
  class Page
    def initialize(screen:, site_url:, query: nil, theme_slug: nil,
                   request_path: nil, request_params: nil)
      @screen = screen
      @query = query
      @site = site_url.to_s.chomp("/")
      @theme = theme_slug || Theme.active.pick(:slug)
      # $_SERVER['REQUEST_URI'] and $_GET, which four query-loop callbacks and
      # get_pagenum_link() read in the legacy. They travel on the RenderContext as the
      # Symbol keys Composition::Renderers::QueryBlocks documents (query_blocks.rb:28) —
      # Symbols on purpose, so a block-provided String context key can never collide.
      @request_path = (request_path || "/").to_s
      @request_params = (request_params || {}).to_h
    end

    def resolution
      @resolution ||= begin
        TemplateResolver.assert_theme_loaded!
        TemplateResolver.new(theme_slug: @theme).resolve(@screen)
      end
    end

    def to_html
      body = template_html # first: it fills the style collector
      head = Head.new(screen: @screen, resolution: resolution, styles: context.styles,
                      site_url: @site, global_styles: global_styles,
                      enqueued_script_modules: context.script_modules.used,
                      block_supports_css: block_supports_css,
                      # Per-instance block style variation CSS the render generated
                      # (block-supports/block-style-variations.php:193) — read AFTER
                      # template_html for the same reason the collectors are.
                      style_variation_css:
                        Composition::Renderers::CommentBlocks::StyleVariations.css(context)).to_html
      footer = Footer.new(site_url: @site, theme_slug: @theme,
                          enqueued_script_modules: context.script_modules.used,
                          enqueued_scripts: context.scripts.used).to_html

      <<~HTML
        <!DOCTYPE html>
        <html lang="en-US">
        <head>
        #{head}
        </head>

        <body class="#{BodyClass.new(@screen, theme_slug: @theme).to_s}">

        #{body}

        #{footer}
        </body>
        </html>
      HTML
    end

    # The RenderContext every block in this page shares. paradigm_decision.md
    # implication 1: the current post and the query travel HERE, explicitly, instead of in
    # the `$post` global and `$wp_query`.
    #
    # ⚠️ `query` is the MAIN query, the one a `core/query` block with `inherit: true`
    # loops over (query_blocks.rb:279). It is nil on singular screens, which is correct
    # and not a shortcut: twentytwentyfive's `single`, `page` and `404` templates contain
    # no `core/query` block at all — the very omission block-template.php:265 comments on
    # — so nothing on those screens can inherit a main query. Retrieval::PostQuery has no
    # var that selects a single post by slug, so inventing one here would be inventing a
    # query the target cannot express.
    def context
      @context ||= Composition::RenderContext.new(
        # `query` is wrapped so it answers the conditional tags TOO — see
        # Presentation::MainQuery: the legacy's is_*() and get_queried_object() are
        # reads of the same global the loop runs on, and blocks nested under a
        # navigation (whose child context faithfully REPLACES block context) can only
        # reach them through the query.
        post: @screen.post, query: @query && MainQuery.new(@query, @screen),
        # The dependency-inversion seam — see Presentation::MenuSource. Composition asks
        # the context for a menu; Presentation is what answers.
        context: { "menuSource" => MenuSource.new }.merge(screen_facts).merge(default_block_context)
      )
    end

    # The legacy's conditional tags (`is_front_page()`, `is_archive()`, …,
    # wp-includes/query.php) are reads of the global `$wp_query`; with no global they
    # travel as the String context keys Composition::Renderers::PostBlocks::Screen names
    # (post_blocks.rb:52). This is what puts `aria-current="page"` on the front page's
    # site title (site-title.php:34) and feeds `core/query-title` on archives. The two
    # Symbol keys stand in for $_SERVER['REQUEST_URI'] and $_GET, which
    # get_pagenum_link() and four query-loop callbacks read (query_blocks.rb:28);
    # Symbols on purpose so a block-provided String key can never collide.
    def screen_facts
      {
        "isArchive" => @screen.archive?, "isSearch" => @screen.search?,
        "isFrontPage" => @screen.front_page?, "isHome" => @screen.home?,
        "isPaged" => @screen.paged?, "isSingular" => @screen.singular?,
        "queriedObject" => queried_object,
        "searchQuery" => @screen.search_query.to_s,
        request_path: @request_path, request_params: @request_params
      }
    end

    # `get_queried_object()` for a DATE archive is null in the legacy; what
    # get_the_archive_title() (general-template.php:1808) actually reads is
    # `get_query_var('year'/'monthnum'/'day')`. The renderers take those three facts as
    # one Hash (post_blocks.rb:71's documented shape), which is what turns
    # `Year: <span>2026</span>` / `Month: <span>March 2026</span>` on /2026/ and
    # /2026/03/.
    def queried_object
      return @screen.queried_object unless @screen.date?

      { "year" => @screen.year, "monthnum" => @screen.month, "day" => @screen.day }
    end

    # `render_block()`, wp-includes/blocks.php:2475-2486: when the global `$post` is set,
    # every top-level block receives `postId` / `postType` as DEFAULT context. On a
    # singular screen the main loop has set that global before the template renders, so
    # `core/comments`, `core/comment-template` and `core/post-comments-form` — whose
    # schemas name `postId` in `usesContext` — resolve the rendered post through it.
    #
    # `isSingular` is the same fact for the conditional tags: `core/post-navigation-link`
    # bails on `! is_singular()` (blocks/post-navigation-link.php:22), and with no
    # `$wp_query` global the flag has to travel in the context
    # (paradigm_decision.md implication 1). Only singular screens set the global `$post`
    # this way, so none of these keys exist on archive/search/404 screens — matching the
    # legacy, where the loop has not run when the template renders.
    def default_block_context
      return {} unless @screen.singular? && @screen.post

      { "postId" => @screen.post.id,
        "postType" => @screen.post.is_a?(Publishing::Page) ? "page" : "post",
        "isSingular" => true }
    end

    private

    # `get_the_block_template_html()`, wp-includes/block-template.php:249.
    def template_html
      template = resolution.template
      return "" if template.nil?

      content = Composition::Renderer.render(template.content, context)
      # :297 — four transformations applied to the WHOLE template output. `do_shortcode`
      # and `$wp_embed->autoembed` (:259) are shortcode/oEmbed machinery that AD-03 and
      # the syndication wave own; `wp_filter_content_tags` (:299) is the media family's
      # lazy-loading/srcset pass. Neither is invented here.
      content = Sanitizing::Texturize.wptexturize(content)
      content = content.gsub("]]>", "]]&gt;")
      # :304 — the wrapper that makes `.wp-site-blocks > *` addressable.
      add_skip_link(%(<div class="wp-site-blocks">#{content}</div>))
    end

    # `_block_template_add_skip_link()`, block-template.php:350. The legacy walks to the
    # first `DIV.wp-site-blocks`, bookmarks it, gives the first `MAIN` an id if it has
    # none, and inserts the link before the bookmark. Here the bookmark is the first byte
    # of the string by construction, so only the `MAIN` half needs a tag processor —
    # and the `markup` pack has the same one the legacy uses.
    SKIP_LINK_TARGET = "wp--skip-link--target"

    def add_skip_link(html)
      processor = Markup::TagProcessor.new(html)
      return html unless processor.next_tag("MAIN")

      target = processor.get_attribute("id")
      if target.nil? || target.to_s.empty?
        target = SKIP_LINK_TARGET
        processor.set_attribute("id", target)
      end
      # :391 — `screen-reader-text` second, `skip-link` first, and the label is not
      # translatable here (single locale).
      link = %(<a class="skip-link screen-reader-text" id="wp-skip-link" href="##{target}">Skip to content</a>)
      "#{link}#{processor.get_updated_html}"
    end

    # `wp_enqueue_global_styles()` → WP_Theme_JSON::get_stylesheet(). The `styling`
    # pack now ports the stylesheet GENERATOR as well as the four-origin cascade
    # (Styling::Stylesheet, Styling::GlobalStylesheet), so there is something to call.
    #
    # ⚠️ `context.styles.used` is read here and not earlier for the same reason
    # template-canvas.php:8 gives: the template must render first, because which
    # blocks are on the page decides which per-block global styles are appended
    # (global-styles-and-settings.php:311).
    def global_styles
      GlobalStylesheet.new(theme_slug: @theme).css(used_blocks: context.styles.used)
    end

    # `wp_enqueue_stored_styles()`, wp-includes/script-loader.php:3307 — the rules the
    # block supports wrote into the 'block-supports' store while the template rendered.
    # BR-MIGRATE-216/217/218.
    #
    # ⚠️ Order is load-bearing, not cosmetic: `to_html` renders the template FIRST (see the
    # class comment), so by the time this runs the store attached to THIS render's
    # `StyleCollector` holds every rule the layout and elements supports emitted. Reading it
    # before `template_html` yields an empty store and drops the element silently — which is
    # exactly what the previous implementation did, by reaching for a process-global
    # registry that paradigm_decision.md implication 1 removed.
    #
    # ⚠️ :3334 calls `wp_style_engine_get_stylesheet_from_context( $style_key, $options )`
    # with `$options = array()` — the action is registered bare (default-filters.php:655) —
    # so BOTH `optimize` and `prettify` are false. Optimizing here would merge and reorder
    # declarations the oracle prints as it collected them.
    def block_supports_css
      Composition::Renderers::LayoutBlocks.block_supports_css(context).presence
    end
  end
end
