# frozen_string_literal: true

module Presentation
  # web.embed — the `/embed/` variant of a singular URL.
  #
  # This is NOT the block-theme render path. `template-loader.php:53` short-circuits on
  # `is_embed()` into `wp-includes/theme-compat/embed.php` (twentytwentyfive ships no
  # `embed.php` of its own), which composes header-embed.php → embed-content.php →
  # footer-embed.php: a fixed standalone document, no theme templates, no wp_head().
  # So this class IS that template trio, section by section, each carrying its legacy
  # citation. AD-01: `embed_head` / `embed_content_meta` / `embed_footer` are actions and
  # are gone — the fixed sequence core registers in default-filters.php:740-763 is the
  # specification.
  #
  # ⚠️ Whitespace inside text runs is load-bearing: the parity normalizer collapses
  # whitespace BETWEEN tags only, so the tabs the PHP templates leave around `the_title()`
  # and the share-dialog strings must be reproduced byte for byte.
  class EmbedPage
    # `wp_embed_defaults()`, embed.php:141 — the share dialog's iframe is 600×400.
    EMBED_WIDTH = 600
    EMBED_HEIGHT = 400

    Text = Composition::Renderers::PostBlocks::Text
    Links = Composition::Renderers::PostBlocks::Links
    Site = Composition::Renderers::PostBlocks::Site

    def initialize(post:, site_url:, theme_slug: nil)
      @post = post
      @site = site_url.to_s.chomp("/")
      @theme = theme_slug || Theme.active.pick(:slug)
      # `print_embed_sharing_dialog()`, embed.php:1204 — `get_the_ID() . '-' . wp_rand()`.
      # wp_rand() (pluggable.php:3009) is a 32-bit draw; the parity normalizer masks the
      # value (`wp-embed-share-…-<UID>`) but its PATTERN requires 6+ digits, so the floor
      # here keeps the rebuild inside the shape the oracle exhibits.
      @dialog_suffix = "#{post.id}-#{SecureRandom.random_number(100_000..4_294_967_295)}"
      # `get_post_embed_html()`, embed.php:497 — `wp_generate_password( 10, false )`,
      # i.e. 10 chars of [a-zA-Z0-9]. Per-request; the normalizer masks it as <NONCE>.
      @secret = SecureRandom.alphanumeric(10)
    end

    def to_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en-US" class="no-js">
        <head>
        \t<title>#{document_title}</title>
        \t<meta http-equiv="X-UA-Compatible" content="IE=edge">
        \t<meta name='robots' content='noindex, follow, max-image-preview:large' />
        <link rel="canonical" href="#{permalink}" />
        #{Assets.style_tag("wp-emoji-styles", site_url: @site)}
        #{Assets.style_tag("wp-embed-template", site_url: @site)}
        </head>
        <body class="#{BodyClass.new(screen, theme_slug: @theme)}">
        \t<div class="#{post_classes.join(" ")}">
        \t\t<p class="wp-embed-heading">
        \t\t\t<a href="#{permalink}" target="_top">
        \t\t\t\t#{title}\t\t\t</a>
        \t\t</p>

        \t\t<div class="wp-embed-excerpt">#{excerpt_html}</div>

        \t\t<div class="wp-embed-footer">
        \t\t\t#{site_title_html}
        \t\t\t<div class="wp-embed-meta">
        #{comments_button}#{sharing_button}\t\t\t</div>
        \t\t</div>
        \t</div>
        #{sharing_dialog}
        #{embed_template_script}
        #{late_style_links}
        #{footer_helper.emoji_settings}
        #{footer_helper.emoji_loader}
        </body>
        </html>
      HTML
    end

    private

    attr_reader :post

    # The conditional facts of this request: is_embed() plus is_single() for a post or
    # is_page() for a page — the `embed` endpoint is registered for both permastructs
    # (class-wp-rewrite.php:1010, :1100), and the body classes (post-template.php:677)
    # and document title follow the singular kind.
    def screen
      @screen ||= Screen.new(kind: page? ? :page : :single, post: post, embed: true)
    end

    # The legacy `post_type` string — 'post' or 'page' (Presentation::PostType).
    def legacy_type = @legacy_type ||= PostType.legacy_name(post)
    def page? = legacy_type == "page"

    # The excerpt renders the post content through the block renderer, which is what
    # collects the used-block list for the late stylesheet links — same reason
    # Presentation::Page renders the template before assembling the head.
    def context
      @context ||= Composition::RenderContext.new(post: post)
    end

    def footer_helper = @footer_helper ||= Footer.new(site_url: @site, theme_slug: @theme)

    # ── head ─────────────────────────────────────────────────────────────────────────

    # `wp_get_document_title()` — is_embed() takes the same single-post branch as
    # web.single (general-template.php:1385), so the title matches golden-web-single's.
    def document_title = DocumentTitle.new(screen).to_s

    # `rel_canonical()` / `the_permalink()` — the post's permalink, trailing slash and all.
    def permalink = @permalink ||= Links.permalink(post)

    # get_the_title() through the `the_title` default chain.
    def title = @title ||= Text.the_title(post)

    def blog_name_raw = Configuration::Setting["blogname"].to_s

    # ── embed-content.php ────────────────────────────────────────────────────────────

    # `post_class( 'wp-embed' )`, theme-compat/embed-content.php:14 →
    # `get_post_class()`, wp-includes/post-template.php:494. The reachable branches for
    # this corpus mirror Composition::Renderers::QueryBlocks (query_blocks.rb:422):
    # no sticky (not is_home), format-standard always ('post' supports formats, no
    # post_format terms exist under AD-03).
    STATUS_NAMES = {
      "auto_draft" => "auto-draft", "draft" => "draft", "pending" => "pending",
      "scheduled" => "future", "published" => "publish", "private" => "private",
      "trashed" => "trash",
    }.freeze

    def post_classes
      # post-template.php:513-518 — `post-ID`, the post type, `type-<post_type>`, status.
      classes = ["wp-embed", "post-#{post.id}", legacy_type, "type-#{legacy_type}",
                 "status-#{STATUS_NAMES.fetch(post.status.to_s, post.status.to_s)}"]
      # post-template.php:521 — `post_type_supports( $post->post_type, 'post-formats' )`:
      # only 'post' declares the support (post.php:50, create_initial_post_types), so a
      # page embed carries no `format-*` class. Oracle: `wp-embed post-23 page type-page
      # status-publish hentry` for /parent-page/embed/.
      classes << "format-standard" unless page?
      password_required = post.password_digest.present?
      classes << "post-password-required" if password_required
      classes << "has-post-thumbnail" if post.featured_asset_id.present? && !password_required
      classes << "hentry"
      # post-template.php:575 — `is_object_in_taxonomy( $post->post_type, $taxonomy )`:
      # category / post_tag / post_format are registered to 'post' only.
      classes.concat(taxonomy_classes) unless page?
      classes.uniq
    end

    # post-template.php:576 — public taxonomies in registration order, terms by name ASC,
    # 'post_tag' spelled 'tag-'. Same query Composition::Renderers::QueryBlocks uses.
    PUBLIC_TAXONOMIES = %w[category post_tag post_format].freeze

    def taxonomy_classes
      terms = Classification::Term
              .joins(:taxonomy, :assignments)
              .where(term_assignments: { classifiable_type: "Publishing::Post",
                                         classifiable_id: post.id })
              .where(taxonomies: { name: PUBLIC_TAXONOMIES })
              .select("terms.*, taxonomies.name AS taxonomy_name")
              .order("terms.name ASC")
      grouped = terms.group_by { |term| term.attributes["taxonomy_name"] }
      PUBLIC_TAXONOMIES.flat_map do |taxonomy|
        Array(grouped[taxonomy]).filter_map do |term|
          next if term.slug.blank?

          term_class = sanitize_html_class(term.slug, term.id.to_s)
          term_class = term.id.to_s if term_class.match?(/\A[0-9]+\z/) || term_class.gsub("-", "").empty?
          taxonomy == "post_tag" ? "tag-#{term_class}" : sanitize_html_class("#{taxonomy}-#{term_class}", "#{taxonomy}-#{term.id}")
        end
      end
    end

    # `sanitize_html_class()`, wp-includes/formatting.php:2340.
    def sanitize_html_class(value, fallback = "")
      sanitized = value.to_s.gsub(/%[a-f0-9]{2}/i, "").gsub(/[^A-Za-z0-9_-]/, "")
      sanitized.empty? ? fallback.to_s : sanitized
    end

    # `the_excerpt_embed()`, embed.php:1032 — get_the_excerpt() through the
    # `the_excerpt_embed` chain default-filters.php:759 installs: wptexturize,
    # convert_chars, wpautop. (shortcode_unautop: no shortcode is registered;
    # wp_embed_excerpt_attachment: attachment URLs 301-redirect, is_attachment() is
    # unreachable — see Screen#attachment?.)
    def excerpt_html
      Text.wpautop(Text.convert_chars(Text.wptexturize(excerpt_text)))
    end

    # get_the_excerpt()'s protected-post sentence, the same literal
    # Syndication::FeedText::PROTECTED_EXCERPT carries.
    PROTECTED_EXCERPT = "There is no excerpt because this is a protected post."

    # `wp_trim_excerpt()`, wp-includes/formatting.php:4029 — the stored excerpt verbatim,
    # else the rendered content trimmed to 55 words. Same shape as
    # Composition::Renderers::PostBlocks::PostExcerpt#the_excerpt, with the embed's own
    # `excerpt_more`.
    def excerpt_text
      # get_the_excerpt(), wp-includes/post-template.php:423 — the password gate runs
      # BEFORE the stored excerpt is even read, and returns the literal sentence, which
      # the `the_excerpt_embed` chain then wpautop()s. PostBlocks::PostExcerpt (:1671)
      # and Syndication::FeedText (PROTECTED_EXCERPT) both had it; this renderer did not,
      # so /…/password-protected/embed/ printed the protected post's real excerpt.
      # Found by the corpus-widening pass — no golden covered a protected post's embed.
      return PROTECTED_EXCERPT if post.password_digest.present?

      stored = post.excerpt.to_s
      return stored unless stored.strip.empty?

      rendered = Text.the_content(post, context)
      return "" if rendered.empty?

      Text.trim_words(rendered, 55, embed_excerpt_more)
    end

    # `wp_embed_excerpt_more()`, embed.php:1011 — appended only when the excerpt was
    # actually trimmed (wp_trim_words appends `$more` only past the word limit).
    def embed_excerpt_more
      %( &hellip; <a href="#{Text.esc_url(permalink)}" class="wp-embed-more" target="_top">) +
        %(Continue reading <span class="screen-reader-text">#{title}</span></a>)
    end

    # `the_embed_site_title()`, embed.php:1236. No site icon exists in this corpus, so
    # `get_site_icon_url( 32, $fallback )` returns the fallback
    # `includes_url( 'images/w-logo-gray-white-bg.svg' )` — and because the 64px lookup
    # falls back to the SAME url, no srcset is printed (:1244).
    def site_title_html
      icon = Text.esc_url("#{@site}/wp-includes/images/w-logo-gray-white-bg.svg")
      icon_img = %(<img src="#{icon}" width="32" height="32" alt="" class="wp-embed-site-icon" />)
      link = %(<a href="#{Text.esc_url(Site.home_url)}" target="_top">#{icon_img}<span>#{Text.esc_html(blog_name_raw)}</span></a>)
      %(<div class="wp-embed-site-title">#{link}</div>)
    end

    # ── embed_content_meta, default-filters.php:751 ──────────────────────────────────

    # `print_embed_comments_button()`, embed.php:1138. `get_comments_number()` is the
    # post's comment_count cache (comment-template.php:915), which the migration carried
    # over; `comments_link()` is the permalink plus `#comments` (no comment paging in
    # this corpus).
    def comments_button
      open = post.comment_status.to_s == "open"
      count = post.comment_count.to_i
      return "" unless count.positive? || open

      label = count == 1 ? "Comment" : "Comments"
      # get_comments_link(), comment-template.php:1073: `$hash = get_comments_number() ?
      # '#comments' : '#respond'`. The fragment was hard-coded to `#comments` here, which
      # is right for every post that HAS a comment and wrong for the open-but-empty case
      # — the corpus's only embed golden was Hello World, which has one.
      hash = count.positive? ? "#comments" : "#respond"
      <<~HTML
        \t<div class="wp-embed-comments">
        \t\t<a href="#{permalink}#{hash}" target="_top">
        \t\t\t<span class="dashicons dashicons-admin-comments"></span>
        \t\t\t#{number_format_i18n(count)} <span class="screen-reader-text">#{label}</span>\t\t</a>
        \t</div>
      HTML
    end

    # `print_embed_sharing_button()`, embed.php:1167.
    def sharing_button
      <<~HTML
        \t<div class="wp-embed-share">
        \t\t<button type="button" class="wp-embed-share-dialog-open" aria-label="Open sharing dialog">
        \t\t\t<span class="dashicons dashicons-share"></span>
        \t\t</button>
        \t</div>
      HTML
    end

    # `number_format_i18n()`, functions.php — en_US grouping.
    def number_format_i18n(number)
      number.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')
    end

    # ── embed_footer, default-filters.php:754 ────────────────────────────────────────

    # `print_embed_sharing_dialog()`, embed.php:1185.
    def sharing_dialog
      wp_id = "wp-embed-share-tab-wordpress-#{@dialog_suffix}"
      html_id = "wp-embed-share-tab-html-#{@dialog_suffix}"
      wp_desc = "wp-embed-share-description-wordpress-#{@dialog_suffix}"
      html_desc = "wp-embed-share-description-html-#{@dialog_suffix}"
      <<~HTML.chomp
        \t<div class="wp-embed-share-dialog hidden" role="dialog" aria-label="Sharing options">
        \t\t<div class="wp-embed-share-dialog-content">
        \t\t\t<div class="wp-embed-share-dialog-text">
        \t\t\t\t<ul class="wp-embed-share-tabs" role="tablist">
        \t\t\t\t\t<li class="wp-embed-share-tab-button wp-embed-share-tab-button-wordpress" role="presentation">
        \t\t\t\t\t\t<button type="button" role="tab" aria-controls="#{wp_id}" aria-selected="true" tabindex="0">WordPress Embed</button>
        \t\t\t\t\t</li>
        \t\t\t\t\t<li class="wp-embed-share-tab-button wp-embed-share-tab-button-html" role="presentation">
        \t\t\t\t\t\t<button type="button" role="tab" aria-controls="#{html_id}" aria-selected="false" tabindex="-1">HTML Embed</button>
        \t\t\t\t\t</li>
        \t\t\t\t</ul>
        \t\t\t\t<div id="#{wp_id}" class="wp-embed-share-tab" role="tabpanel" aria-hidden="false">
        \t\t\t\t\t<input type="text" value="#{Text.esc_url(permalink)}" class="wp-embed-share-input" aria-label="URL" aria-describedby="#{wp_desc}" tabindex="0" readonly/>

        \t\t\t\t\t<p class="wp-embed-share-description" id="#{wp_desc}">
        \t\t\t\t\t\tCopy and paste this URL into your WordPress site to embed\t\t\t\t\t</p>
        \t\t\t\t</div>
        \t\t\t\t<div id="#{html_id}" class="wp-embed-share-tab" role="tabpanel" aria-hidden="true">
        \t\t\t\t\t<textarea class="wp-embed-share-input" aria-label="HTML" aria-describedby="#{html_desc}" tabindex="0" readonly>#{Sanitizing::Formatting.esc_textarea(post_embed_html)}</textarea>

        \t\t\t\t\t<p class="wp-embed-share-description" id="#{html_desc}">
        \t\t\t\t\t\tCopy and paste this code into your site to embed\t\t\t\t\t</p>
        \t\t\t\t</div>
        \t\t\t</div>

        \t\t\t<button type="button" class="wp-embed-share-dialog-close" aria-label="Close sharing dialog">
        \t\t\t\t<span class="dashicons dashicons-no"></span>
        \t\t\t</button>
        \t\t</div>
        \t</div>
      HTML
    end

    # `get_post_embed_html( 600, 400 )`, embed.php:490 — blockquote, iframe, then
    # wp-embed.min.js inline (the script must come last, :532 explains the regex quirk).
    def post_embed_html
      embed_src = "#{permalink}embed/#?secret=#{@secret}"
      # /* translators */ '&#8220;%1$s&#8221; &#8212; %2$s' — post title, site title.
      iframe_title = Text.esc_attr("&#8220;#{title}&#8221; &#8212; #{blog_name_raw}")
      %(<blockquote class="wp-embedded-content" data-secret="#{@secret}">) +
        %(<a href="#{Text.esc_url(permalink)}">#{title}</a></blockquote>) +
        %(<iframe sandbox="allow-scripts" security="restricted" src="#{Text.esc_url(embed_src)}" ) +
        %(width="#{EMBED_WIDTH}" height="#{EMBED_HEIGHT}" title="#{iframe_title}" data-secret="#{@secret}" ) +
        %(frameborder="0" marginwidth="0" marginheight="0" scrolling="no" class="wp-embedded-content"></iframe>) +
        inline_script_tag("wp-embed-js")
    end

    # `print_embed_scripts()`, embed.php:1107.
    def embed_template_script = inline_script_tag("wp-embed-template-js").chomp

    # `wp_get_inline_script_tag()`, script-loader.php — `<script>\n{trim(js)}\n</script>\n`,
    # with the sourceURL trailer embed.php appends to the file's contents first.
    def inline_script_tag(handle)
      asset = Assets[handle]
      url = asset["source_url"].sub("{site}", @site)
      "<script>\n#{asset["js"].strip}\n//# sourceURL=#{url}\n</script>\n"
    end

    # `print_late_styles()` via `wp_print_footer_scripts` (embed_footer:20) — the
    # stylesheets the excerpt's block render enqueued AFTER `wp_print_styles` already ran
    # in the head, printed as links. Same element shape as Presentation::Head's
    # `stylesheet_link` (WP_Styles::do_item — single quotes, media='all').
    def late_style_links
      context.styles.used.map do |name|
        short = name.sub(%r{\Acore/}, "")
        %(<link rel='stylesheet' id='wp-block-#{short}-css' ) +
          %(href='#{@site}/wp-includes/blocks/#{short}/style.min.css?ver=#{Head::GENERATOR_VERSION}' media='all' />)
      end.join("\n")
    end
  end
end
