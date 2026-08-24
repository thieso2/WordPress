# frozen_string_literal: true

module Syndication
  # Wave 1. Terminal module, zero dependents (F-SIM-06), no write path.
  #
  # The XML shape mirrors WP_Sitemaps_Renderer (wp-includes/sitemaps/
  # class-wp-sitemaps-renderer.php:146-160): an XML declaration, the
  # `<?xml-stylesheet ?>` processing instruction (renderer.php:43-52), and one
  # unindented element line — SimpleXML's asXML() emits no whitespace between
  # elements.
  class SitemapsController < ApplicationController
    include LegacyHeaders

    # class-wp-sitemaps-renderer.php:126 (index) and :190 (sitemap) — a literal header.
    CONTENT_TYPE = "application/xml; charset=UTF-8"
    # wp_sitemaps_get_max_urls(), wp-includes/sitemaps.php — 2000 per page.
    PER_PAGE = 2000

    def index
      # WP_Sitemaps_Registry order: posts (per subtype), taxonomies (per taxonomy),
      # users — wp-includes/sitemaps/class-wp-sitemaps.php:64-76 registration order.
      @sections = []
      @sections << "/wp-sitemap-posts-post-1.xml" if Publishing::Article.published.exists?
      @sections << "/wp-sitemap-posts-page-1.xml" if Publishing::Page.published.exists?
      Classification::Taxonomy.order(:name).each do |taxonomy|
        # `hide_empty => true` against the LEGACY's raw count — see
        # Classification::Term.with_direct_published_posts for why that is not `count > 0`.
        next unless taxonomy.terms.with_direct_published_posts.exists?

        @sections << "/wp-sitemap-taxonomies-#{taxonomy.name}-1.xml"
      end
      @sections << "/wp-sitemap-users-1.xml"
      render_with_legacy_content_type "syndication/sitemaps/index", formats: [:xml], content_type: CONTENT_TYPE
    end

    def posts
      klass = params[:type] == "page" ? Publishing::Page : Publishing::Article
      # class-wp-sitemaps-posts.php:239-240 — 'orderby' => 'ID', 'order' => 'ASC'.
      # Each entry carries loc + lastmod (post_modified_gmt, DATE_W3C) —
      # class-wp-sitemaps-posts.php:149-152.
      @entries = klass.published.order(:id)
                      .offset(([params[:page].to_i, 1].max - 1) * PER_PAGE).limit(PER_PAGE)
      # ⚠️ class-wp-sitemaps-posts.php:118-155 — "Add a URL for the homepage in the pages
      # sitemap. Shows only on the first page if the reading settings are set to display
      # latest posts." Its `lastmod` is NOT the home page's own (there is no such post):
      # it is the newest `post_modified_gmt` among the posts the home loop would show.
      # The rebuild omitted the entry entirely, so its page sitemap advertised six URLs
      # where the oracle advertises seven — the site's own front page was missing from
      # its sitemap. Found by the corpus-widening pass; only the POST sitemap was in the
      # corpus.
      @home_entry = home_sitemap_entry if params[:type] == "page" && [params[:page].to_i, 1].max == 1
      render_with_legacy_content_type "syndication/sitemaps/urlset", formats: [:xml], content_type: CONTENT_TYPE
    end

    # ⚠️ The sitemap INDEX already advertised these URLs (see `index` above) and the
    # rebuild answered them with a 404 — a dead entry in a document the corpus does
    # compare. class-wp-sitemaps-taxonomies.php:106-147: `hide_empty => true`,
    # `orderby => 'term_order'` (get_terms() maps that to `t.term_id ASC`), entries are
    # loc-only — no lastmod, because a term has no modified date.
    def taxonomies
      taxonomy = Classification::Taxonomy.find_by(name: params[:taxonomy])
      return head(:not_found) if taxonomy.nil?

      @terms = taxonomy.terms.with_direct_published_posts.order(:id)
                       .offset(([params[:page].to_i, 1].max - 1) * PER_PAGE).limit(PER_PAGE)
      render_with_legacy_content_type "syndication/sitemaps/taxonomies", formats: [:xml], content_type: CONTENT_TYPE
    end

    def users
      # class-wp-sitemaps-users.php:132-146 — WP_User_Query with
      # 'has_published_posts' over the public post types MINUS attachment and page
      # ("We're not supporting sitemaps for author pages for attachments and pages",
      # users.php:140-141) — so authors of published ARTICLES only. Default user
      # ordering (login ASC). Entries are loc-only (users.php:68-70).
      author_ids = Publishing::Article.published.distinct.pluck(:author_id).compact
      @users = Identity::User.where(id: author_ids).order(:login)
      render_with_legacy_content_type "syndication/sitemaps/users", formats: [:xml], content_type: CONTENT_TYPE
    end

    private

    # `'posts' === get_option('show_on_front')` is the gate; the corpus runs the default.
    def home_sitemap_entry
      return nil unless Configuration::Setting["show_on_front"].to_s.presence.nil? ||
                        Configuration::Setting["show_on_front"].to_s == "posts"

      latest = Publishing::Article.published.order(published_at: :desc)
                                  .limit(Configuration::Setting["posts_per_page"].to_i.positive? ? Configuration::Setting["posts_per_page"].to_i : 10)
      { loc: "#{Composition::Renderers::PostBlocks::Site.home_url}/",
        lastmod: latest.map(&:modified_at).compact.max }
    end
  end
end
