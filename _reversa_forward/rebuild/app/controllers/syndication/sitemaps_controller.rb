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
        next unless taxonomy.terms.where("count > 0").exists?

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
      render_with_legacy_content_type "syndication/sitemaps/urlset", formats: [:xml], content_type: CONTENT_TYPE
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
  end
end
