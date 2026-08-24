# frozen_string_literal: true

module Presentation
  # `wp_get_document_title()`, wp-includes/general-template.php:1385, printed by
  # `_block_template_render_title_tag()` (block-template.php:232) — which, for a block
  # theme, replaces `_wp_render_title_tag` unconditionally (block-template.php:129).
  #
  # ⚠️ AD-01, read precisely. `pre_get_document_title`, `document_title_separator` and
  # `document_title_parts` are EXTENSION POINTS and are gone: nothing can substitute a
  # title, change the separator or add a part. But `document_title` also carries four
  # callbacks that WordPress itself registers in default-filters.php:162 —
  # `wptexturize`, `convert_chars`, `esc_html`, `capital_P_dangit` — and those are not
  # extension, they are how core formats a title for display. The oracle proves the
  # distinction is real: with the separator left as the literal '-' the title would read
  # `Reversa … - He said …`, and every golden file shows `&#8211;`, which only
  # wptexturize produces. So the chain is implemented and the hooks are not.
  class DocumentTitle
    SEPARATOR = "-" # general-template.php:1476, the unfiltered default.

    def initialize(screen)
      @screen = screen
    end

    def to_s
      parts = [title_part, page_part, context_part].compact.reject(&:empty?)
      formatted(parts.join(" #{SEPARATOR} "))
    end

    private

    def title_part
      s = @screen
      if s.not_found?
        "Page not found"
      elsif s.search?
        # general-template.php:1415. The curly quotes are in the string itself.
        "Search Results for &#8220;#{search_query}&#8221;"
      elsif s.front_page?
        blog_info("name")
      elsif s.tax?
        single_term_title
      elsif s.home? || s.singular?
        single_post_title
      elsif s.category? || s.tag?
        single_term_title
      elsif s.author?
        s.author&.display_name.to_s
      elsif s.year? && !s.month?
        s.year.to_s
      elsif s.month? && !s.day?
        "#{Date::MONTHNAMES[s.month.to_i]} #{s.year}"
      elsif s.day?
        Date.new(s.year.to_i, s.month.to_i, s.day.to_i).strftime("%B %-d, %Y")
      end
    end

    # general-template.php:1457.
    def page_part
      s = @screen
      page = [s.paged, s.page].max
      return nil unless page >= 2 && !s.not_found?

      "Page #{page}"
    end

    # general-template.php:1463.
    def context_part
      @screen.front_page? ? blog_info("description") : blog_info("name")
    end

    # `get_bloginfo( $show, 'display' )` runs the value through the `bloginfo` filter,
    # which default-filters.php:162 gives the same wptexturize/convert_chars/esc_html
    # chain. ⚠️ BR-MIGRATE-014: these two option values are ALREADY html-escaped at rest
    # (Configuration::Setting::SANITIZED_ON_WRITE), and esc_html does not double-encode,
    # which is why `&quot;` survives as `&quot;`.
    def blog_info(key)
      raw = Configuration::Setting[key == "name" ? "blogname" : "blogdescription"].to_s
      formatted(raw)
    end

    # `single_post_title()` / `single_term_title()` are filtered through
    # `single_post_title` / `single_cat_title` etc., which default-filters.php:175 gives
    # wptexturize + strip_tags. The outer `document_title` chain then runs over the joined
    # string, so applying it once at the end is equivalent for these inputs and is what
    # the goldens show.
    def single_post_title = @screen.post&.title.to_s
    def single_term_title = @screen.term&.name.to_s
    def search_query = @screen.search_query.to_s

    def formatted(text)
      text = Sanitizing::Texturize.wptexturize(text)
      text = convert_chars(text)
      text = Sanitizing::Formatting.esc_html(text)
      capital_p_dangit(text)
    end

    # `convert_chars()`, wp-includes/formatting.php:2492 — everything but the bare
    # ampersand rule was deprecated away.
    def convert_chars(content)
      return content unless content.include?("&")

      content.gsub(/&([^#])(?![a-z1-4]{1,8};)/i) { "&#038;#{Regexp.last_match(1)}" }
    end

    # `capital_P_dangit()`, wp-includes/formatting.php:5783. `current_filter()` is
    # 'document_title' here, so the judicious replacement applies, not the simple one.
    def capital_p_dangit(text)
      text.gsub(" Wordpress", " WordPress")
          .gsub("&#8216;Wordpress", "&#8216;WordPress")
          .gsub("&#8220;Wordpress", "&#8220;WordPress")
          .gsub(">Wordpress", ">WordPress")
          .gsub("(Wordpress", "(WordPress")
    end
  end
end
