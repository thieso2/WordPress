# frozen_string_literal: true

module Presentation
  # The template hierarchy: which of the theme's documents renders this request.
  #
  # Two legacy files, in this order:
  #
  #  1. wp-includes/template-loader.php:67 — the `$tag_templates` table. Seventeen
  #     conditional tags are tried IN A FIXED ORDER; the first one that both HOLDS and
  #     yields a template wins, and `index` is the fallback (template-loader.php:103).
  #  2. wp-includes/template.php — one `get_*_template()` per tag, each building a list of
  #     candidate FILENAMES in descending specificity, and
  #     wp-includes/block-template.php:150 `resolve_block_template()`, which maps those
  #     filenames onto block templates by slug after `_strip_template_file_suffix()`.
  #
  # ⚠️ The subtlety that makes this table-driven rather than a case statement: a tag can
  # HOLD and still yield nothing. `is_front_page()` is true for the oracle's `/`, but
  # twentytwentyfive ships no `front-page.html`, so `get_front_page_template()` returns ''
  # and THE LOOP CONTINUES to `is_home()`. Six of the eighteen screens depend on that
  # fall-through — every archive screen reaches `archive` only because `category`, `tag`,
  # `author` and `date` produced nothing first. Verified screen by screen against the
  # oracle (spec/models/presentation/template_resolver_spec.rb).
  #
  # AD-01: `{$type}_template_hierarchy` and `{$type}_template` are both filters. Neither
  # exists here; the hierarchy each tag produces is final.
  class TemplateResolver
    # ⚠️ An EMPTY theme is not a resolution outcome, it is a broken install.
    #
    # `oracle:seed` truncates `templates`, `patterns` and `themes` — the corpus's
    # machinery post types (wp_template, wp_template_part, wp_block) share those tables —
    # so forgetting `theme:sync` afterwards leaves nothing to resolve. The resolver then
    # returns `template: nil`, the page renders a bare <head>, and the front end looks
    # 80% short for what appears to be a renderer reason. That has cost two debugging
    # cycles; it now says so instead.
    class ThemeNotLoaded < StandardError; end

    def self.assert_theme_loaded!
      return if Theme.exists?(active: true) && Composition::Template.where(kind: "template").exists?

      raise ThemeNotLoaded, <<~MSG
        No active theme with templates is loaded.

        The rebuild renders block templates out of the database. Load them with:

            bin/rails theme:sync        # ⚠️ AFTER bin/rails oracle:seed, never before —
                                        # seeding truncates templates/patterns/themes.

        themes(active): #{Theme.where(active: true).count}   \
        templates: #{Composition::Template.where(kind: "template").count}   \
        parts: #{Composition::Template.where(kind: "part").count}
      MSG
    end

    # The `$tag_templates` table, verbatim, as [conditional, template type].
    # The type is the `$type` argument `get_query_template()` receives — note that
    # is_post_type_archive maps to 'archive', not to a type of its own (template.php:283).
    TAGS = [
      # is_embed is handled before this table — see #resolve.
      [:not_found?, :"404"],
      [:search?, :search],
      [:front_page?, :frontpage],
      [:home?, :home],
      [:privacy_policy?, :privacypolicy],
      [:post_type_archive?, :archive],
      [:tax?, :taxonomy],
      [:attachment?, :attachment],
      [:single?, :single],
      [:page?, :page],
      [:singular?, :singular],
      [:category?, :category],
      [:tag?, :tag],
      [:author?, :author],
      [:date?, :date],
      [:archive?, :archive],
    ].freeze

    # What resolution decided, and how. `hierarchy` is kept because a resolver that
    # cannot show its working cannot be checked against the oracle.
    Resolution = Struct.new(:type, :hierarchy, :template, :fell_back, :theme_compat,
                            keyword_init: true) do
      def slug = template&.slug
      # The legacy's `$_wp_current_template_id`, block-template.php:93.
      def id = template && "#{template.theme_slug}//#{template.slug}"
      # True when the request renders a wp-includes/theme-compat/*.php file instead of a
      # block template — the embed screen, and only the embed screen.
      def block_template? = !template.nil?
    end

    def initialize(theme_slug: nil)
      @theme_slug = theme_slug || Theme.active.pick(:slug)
    end

    # @param screen [Presentation::Screen]
    # @return [Resolution]
    def resolve(screen)
      # ⚠️ The one tag that can never fall through. `locate_template()` searches the theme
      # AND `wp-includes/theme-compat/` (template.php:742), and core ships
      # `theme-compat/embed.php`, so `get_embed_template()` ALWAYS returns a file and the
      # loop always breaks at `is_embed` — never reaching `is_single`, which is also true
      # for an `/embed/` URL. Verified against the oracle: /2026/03/hello-world/embed/
      # loads wp-includes/theme-compat/embed.php with `$_wp_current_template_id` empty.
      # web.embed is therefore NOT a block-template screen at all.
      if screen.embed?
        return Resolution.new(type: :embed, hierarchy: hierarchy_for(:embed, screen),
                              template: nil, fell_back: false, theme_compat: "embed")
      end

      TAGS.each do |conditional, type|
        next unless screen.public_send(conditional)

        hierarchy = hierarchy_for(type, screen)
        template = first_match(hierarchy)
        next if template.nil?

        return Resolution.new(type: type, hierarchy: hierarchy, template: template,
                              fell_back: false)
      end

      # template-loader.php:103 — `if ( ! $template ) { $template = get_index_template(); }`
      Resolution.new(type: :index, hierarchy: ["index"],
                     template: first_match(["index"]), fell_back: true)
    end

    # The candidate slugs for one template type, in descending specificity.
    # `_strip_template_file_suffix()` (block-template.php:160) removes the extension, so
    # the lists below are the legacy's arrays with `.php` already dropped.
    def hierarchy_for(type, screen)
      case type
      when :embed then embed_hierarchy(screen)          # template.php:518
      when :"404" then ["404"]                          # template.php:133
      when :search then ["search"]                      # template.php:497
      when :frontpage then ["front-page"]               # template.php:453
      when :home then %w[home index]                    # template.php:447
      when :privacypolicy then ["privacy-policy"]       # template.php:459
      when :taxonomy then taxonomy_hierarchy(screen)    # template.php:238
      when :attachment then ["attachment"]              # template.php:—, unreachable
      when :single then single_hierarchy(screen)        # template.php:501
      when :page then page_hierarchy(screen)            # template.php:470
      when :singular then ["singular"]                  # template.php:532
      when :category then category_hierarchy(screen)    # template.php:210
      when :tag then tag_hierarchy(screen)              # template.php:224
      when :author then author_hierarchy(screen)        # template.php:200
      when :date then ["date"]                          # template.php:443
      when :archive then ["archive"]                    # template.php:148
      when :index then ["index"]
      else [type.to_s]
      end
    end

    private

    # `get_block_templates( array( 'slug__in' => $slugs ) )` then a usort by the slug's
    # position in the hierarchy (block-template.php:170). Expressed directly: the first
    # slug in the hierarchy that the active theme has a template for.
    #
    # ⚠️ Scoped to the ACTIVE theme. The oracle's two seeded `wp_template` rows carry no
    # `wp_theme` term, so `get_block_templates()` never returns them — confirmed by asking
    # the oracle, which reports `source: theme` for `twentytwentyfive//single`, i.e. the
    # FILE, not the database row.
    def first_match(slugs)
      candidates = Composition::Template.where(theme_slug: @theme_slug, kind: "template",
                                               slug: slugs).index_by(&:slug)
      slugs.filter_map { |slug| candidates[slug] }.first
    end

    def author_hierarchy(screen)
      author = screen.author
      list = []
      list << "author-#{author.login}" << "author-#{author.id}" if author
      list << "author"
    end

    def category_hierarchy(screen)
      term_hierarchy(screen.term, "category")
    end

    def tag_hierarchy(screen)
      term_hierarchy(screen.term, "tag")
    end

    def term_hierarchy(term, prefix)
      list = []
      if term && term.slug.present?
        decoded = CGI.unescape(term.slug)
        list << "#{prefix}-#{decoded}" if decoded != term.slug
        list << "#{prefix}-#{term.slug}" << "#{prefix}-#{term.id}"
      end
      list << prefix
    end

    def taxonomy_hierarchy(screen)
      term = screen.term
      list = []
      if term && term.slug.present?
        taxonomy = term.taxonomy.name
        decoded = CGI.unescape(term.slug)
        list << "taxonomy-#{taxonomy}-#{decoded}" if decoded != term.slug
        list << "taxonomy-#{taxonomy}-#{term.slug}" << "taxonomy-#{taxonomy}-#{term.id}"
        list << "taxonomy-#{taxonomy}"
      end
      list << "taxonomy"
    end

    def single_hierarchy(screen)
      post = screen.post
      list = []
      if post
        type = legacy_post_type(post)
        list << strip_suffix(post.template_slug) if custom_template?(post.template_slug)
        decoded = CGI.unescape(post.slug.to_s)
        list << "single-#{type}-#{decoded}" if decoded != post.slug
        list << "single-#{type}-#{post.slug}" << "single-#{type}"
      end
      list << "single"
    end

    def page_hierarchy(screen)
      post = screen.post
      list = []
      if post
        list << strip_suffix(post.template_slug) if custom_template?(post.template_slug)
        decoded = CGI.unescape(post.slug.to_s)
        list << "page-#{decoded}" if decoded != post.slug
        list << "page-#{post.slug}" << "page-#{post.id}"
      end
      list << "page"
    end

    def embed_hierarchy(screen)
      post = screen.post
      list = []
      list << "embed-#{legacy_post_type(post)}" if post
      list << "embed"
    end

    # `get_page_template_slug()` returns '' for the sentinel 'default', and
    # `validate_file()` rejects a path containing '..' or a drive letter
    # (functions.php:5361). Both are what keep a stored value from addressing a file
    # outside the theme.
    def custom_template?(slug)
      value = slug.to_s
      return false if value.empty? || value == "default"

      !value.include?("..") && !value.start_with?("/") && value !~ %r{\A[A-Za-z]:}
    end

    # `_strip_template_file_suffix()`, block-template.php:160.
    def strip_suffix(name) = name.to_s.sub(/\.(php|html)\z/, "")

    # AD-02 split `wp_posts` by type; the hierarchy still speaks the legacy's post-type
    # vocabulary because that is what the template SLUGS are named after.
    def legacy_post_type(post) = PostType.legacy_name(post)
  end
end
