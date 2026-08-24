# frozen_string_literal: true

module Presentation
  # `get_body_class()`, wp-includes/post-template.php:639.
  #
  # AD-01: the `body_class` filter is gone, so this list IS the body's class attribute.
  # Nothing appends to it afterwards.
  #
  # ⚠️ The parity harness SORTS class tokens (spec/parity/harness/normalizer.rb:133), so
  # the ORDER below cannot be checked by the screen diff. It is kept in the legacy's order
  # anyway — the normalization exists to hide block-supports concatenation order, not to
  # license a different list.
  class BodyClass
    # Branches the legacy has that no corpus screen can reach are marked; each is left out
    # deliberately rather than forgotten:
    #   * `rtl`             — is_rtl(), the corpus locale is en_US (post-template.php:644)
    #   * `attachment*`     — attachment pages 301-redirect, see Screen#attachment?
    #   * `post-type-archive*` — no post type declares has_archive
    #   * `logged-in` / `admin-bar` — the read path is anonymous (post-template.php:794)
    #   * `custom-background` / `wp-custom-logo` — twentytwentyfive supports neither
    #   * `wp-child-theme-*` — twentytwentyfive is not a child theme
    def initialize(screen, theme_slug: nil, stylesheet_slug: nil)
      @screen = screen
      @theme = theme_slug || Theme.active.pick(:slug)
      @stylesheet = stylesheet_slug || @theme
    end

    def to_a
      classes = []
      s = @screen

      classes << "home" if s.front_page?
      classes << "blog" if s.home?
      classes << "privacy-policy" if s.privacy_policy?
      classes << "archive" if s.archive?
      classes << "date" if s.date?
      if s.search?
        classes << "search"
        # post-template.php:665 — the branch reads `$wp_query->posts`, i.e. THIS PAGE's
        # posts, not found_posts.
        classes << (s.found_posts.positive? ? "search-results" : "search-no-results")
      end
      classes << "paged" if s.paged?
      classes << "error404" if s.not_found?

      if s.singular?
        classes.concat(singular_classes)
      elsif s.archive?
        classes.concat(archive_classes)
      end

      # twentytwentyfive declares `add_theme_support( 'responsive-embeds' )`.
      classes << "wp-embed-responsive"

      classes.concat(paged_classes)
      classes << "wp-theme-#{sanitize_html_class(@theme)}"
      classes.map { |c| sanitize_html_class(c, c) }.reject(&:empty?).uniq
    end

    def to_s = to_a.join(" ")

    private

    # post-template.php:677.
    def singular_classes
      post = @screen.post
      type = PostType.legacy_name(post)
      classes = ["wp-singular"]

      template_slug = post.respond_to?(:template_slug) ? post.template_slug.to_s : ""
      # `is_page_template()` is false for the sentinel 'default' (post-template.php:684).
      if template_slug.present? && template_slug != "default"
        classes << "#{type}-template"
        # post-template.php:690 — one class per PATH SEGMENT with its extension stripped,
        # then one more for the whole slug with '.' replaced by '-'. For
        # `templates/full-width.php` that is `page-template-templates`,
        # `page-template-full-width` and `page-template-templatesfull-width-php`
        # (the '/' does not survive sanitize_html_class).
        template_slug.split("/").each do |part|
          classes << "#{type}-template-#{sanitize_html_class(File.basename(part, ".php").tr("./", "--"))}"
        end
        classes << "#{type}-template-#{sanitize_html_class(template_slug.tr(".", "-"))}"
      else
        classes << "#{type}-template-default"
      end

      if @screen.single?
        classes << "single"
        classes << "single-#{sanitize_html_class(type, post.id)}"
        classes << "postid-#{post.id}"
        # `post_type_supports( 'post', 'post-formats' )` is true. AD-03 dropped the
        # `post_format` taxonomy, and the corpus assigns none, so the else arm of
        # post-template.php:708 is the only reachable one.
        classes << "single-format-standard"
      elsif @screen.page?
        classes << "page"
        classes << "page-id-#{post.id}"
        classes << "page-parent" if Publishing::Page.where(parent_id: post.id).exists?
        if post.parent_id
          classes << "page-child"
          classes << "parent-pageid-#{post.parent_id}"
        end
      end
      classes
    end

    # post-template.php:740.
    def archive_classes
      s = @screen
      if s.author? && s.author
        ["author", "author-#{sanitize_html_class(s.author.login, s.author.id)}",
         "author-#{s.author.id}"]
      elsif s.category? && s.term
        ["category", "category-#{term_class(s.term)}", "category-#{s.term.id}"]
      elsif s.tag? && s.term
        ["tag", "tag-#{term_class(s.term)}", "tag-#{s.term.id}"]
      elsif s.tax? && s.term
        ["tax-#{sanitize_html_class(s.term.taxonomy.name)}",
         "term-#{term_class(s.term)}", "term-#{s.term.id}"]
      else
        []
      end
    end

    # post-template.php:759 — a slug that sanitizes to a number, or to nothing but
    # hyphens, falls back to the term id so the class cannot start with a digit.
    def term_class(term)
      value = sanitize_html_class(term.slug, term.id)
      return term.id.to_s if value.match?(/\A-?\d+(\.\d+)?\z/) || value.delete("-").empty?

      value
    end

    # post-template.php:816.
    def paged_classes
      s = @screen
      page = s.page < 2 ? s.paged : s.page
      return [] unless page > 1 && !s.not_found?

      classes = ["paged-#{page}"]
      suffix = if s.single? then "single"
               elsif s.page? then "page"
               elsif s.category? then "category"
               elsif s.tag? then "tag"
               elsif s.date? then "date"
               elsif s.author? then "author"
               elsif s.search? then "search"
               end
      classes << "#{suffix}-paged-#{page}" if suffix
      classes
    end

    # `sanitize_html_class()`, wp-includes/formatting.php:2340.
    def sanitize_html_class(value, fallback = "")
      sanitized = value.to_s.gsub(/%[a-f0-9]{2}/i, "").gsub(/[^A-Za-z0-9_-]/, "")
      sanitized.empty? ? fallback.to_s : sanitized
    end
  end
end
