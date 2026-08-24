# frozen_string_literal: true

module Presentation
  # The facts a request has established about WHAT is being viewed, before anything has
  # been decided about HOW.
  #
  # In the legacy these facts live on the `$wp_query` global and are read through 20
  # conditional-tag functions (`is_home()`, `is_single()`, …, wp-includes/query.php).
  # Three separate subsystems consume them — the template hierarchy
  # (template-loader.php:67), the body classes (post-template.php:639) and the document
  # title (general-template.php:1385) — and each reads them from the global.
  #
  # ⚠️ paradigm_decision.md implication 1: no global mutable state. So the conditional tags
  # become methods on a value object that the controller CONSTRUCTS and passes down. The
  # three consumers take it as an argument; none of them can ask "what is being viewed"
  # without being told.
  #
  # AD-01: there is no `pre_get_posts`, so nothing can change these facts after the
  # controller has stated them.
  class Screen
    KINDS = %i[home single page archive category tag taxonomy author date search
               not_found].freeze

    attr_reader :kind, :post, :term, :author, :year, :month, :day, :search_query,
                :paged, :page, :found_posts

    # @param kind [Symbol] one of KINDS
    # @param embed [Boolean] the `/embed/` variant of a singular URL (is_embed)
    # @param found_posts [Integer] how many posts the query matched — is_search() needs it
    #   for the `search-results` / `search-no-results` body class (post-template.php:665)
    def initialize(kind:, post: nil, term: nil, author: nil, year: nil, month: nil,
                   day: nil, search_query: nil, paged: 1, page: 1, found_posts: 0,
                   embed: false)
      raise ArgumentError, "unknown screen kind #{kind.inspect}" unless KINDS.include?(kind)

      @kind = kind
      @post = post
      @term = term
      @author = author
      @year = year
      @month = month
      @day = day
      @search_query = search_query
      @paged = [paged.to_i, 1].max
      @page = [page.to_i, 1].max
      @found_posts = found_posts.to_i
      @embed = embed
      freeze
    end

    # ── the conditional tags, in wp-includes/query.php order ────────────────────────

    def embed? = @embed
    def not_found? = kind == :not_found
    def search? = kind == :search
    def home? = kind == :home

    # query.php:181 — with `show_on_front` = 'posts' the front page IS the blog index.
    # The oracle's setting is 'posts', so the second arm never fires there; it is kept
    # because the setting is data, not a constant.
    def front_page?
      if Configuration::Setting["show_on_front"].to_s == "page"
        page? && post && post.id.to_s == Configuration::Setting["page_on_front"].to_s
      else
        home?
      end
    end

    # query.php:214.
    def privacy_policy?
      page? && post && post.id.to_s == Configuration::Setting["wp_page_for_privacy_policy"].to_s
    end

    # The corpus registers no custom taxonomy, so is_tax() is false for every one of the
    # 18 screens — verified against the oracle, which reports `is_category` (never
    # `is_tax`) for /category/top-category/middle-category/, the screen the manifest calls
    # `web.taxonomy`. Built-in taxonomies have their own conditionals; query.php:672
    # excludes them.
    def tax? = kind == :taxonomy

    # BR-MIGRATE-045's other half: `wp_attachment_pages_enabled` is '0' on the oracle and
    # canonical.php:553 301-redirects every attachment URL, so no attachment screen is
    # ever rendered. See spec/parity/corpus/requests.yml:62.
    def attachment? = false

    def single? = kind == :single
    def page? = kind == :page
    def singular? = single? || page? || attachment?
    def category? = kind == :category
    def tag? = kind == :tag
    def author? = kind == :author
    def date? = kind == :date
    def year? = date? && !year.nil?
    def month? = date? && !month.nil?
    def day? = date? && !day.nil?

    # `archive` is the umbrella: query.php:129.
    def archive? = kind == :archive || category? || tag? || tax? || author? || date?

    # No post type in the corpus declares `has_archive`, so get_post_type_archive_template()
    # returns '' unconditionally (template.php:283).
    def post_type_archive? = false

    def paged? = paged > 1

    # get_queried_object() — one of post / term / author, or nothing.
    def queried_object = post || term || author
  end
end
