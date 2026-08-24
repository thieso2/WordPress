# frozen_string_literal: true

module Web
  # web.embed — the `/embed/` endpoint: `/:year/:monthnum/:slug/embed/` for a post and
  # `/<page path>/embed/` for a page. The endpoint is registered with
  # EP_PERMALINK | EP_PAGES | EP_ATTACHMENT (class-wp-rewrite.php:892, :1010, :1100); the
  # attachment arm never renders — it 301s to the file (Web::AttachmentsController).
  #
  # template-loader.php:53: `is_embed()` is checked FIRST, before the block-template
  # hierarchy, and routes into wp-includes/theme-compat/embed.php. So this is a separate
  # controller and a separate renderer (Presentation::EmbedPage), not a variant of
  # Web::SingularController's block-theme path.
  class EmbedsController < ApplicationController
    def show
      post = Publishing::Article.where(status: %w[published private])
                                .find_by(slug: params[:slug])
      return not_found if post.nil?

      render_embed(post)
    end

    # `/parent-page/child-page/embed/`. The page resolves exactly as Web::PagesController
    # resolves `/parent-page/child-page/` — one (parent, slug) step per segment, the scope
    # BR-MIGRATE-033's unique index enforces — and then takes the embed template instead
    # of the block template. Verified against the oracle for every corpus page, nested
    # ones included (spec/requests/web/embeds_spec.rb).
    def page
      segments = params[:path].to_s.split("/").reject(&:empty?)
      return not_found if segments.empty?

      post = walk(segments)
      return not_found if post.nil?

      render_embed(post)
    end

    private

    def render_embed(post)
      # header-embed.php:14 — the one header the embed template sets.
      response.set_header("X-WP-embed", "true")
      page = Presentation::EmbedPage.new(post: post, site_url: site_url)
      render html: page.to_html.html_safe, layout: false # rubocop:disable Rails/OutputSafety
    end

    # Same walk as Web::PagesController#walk: `get_page_by_path()` semantics, one
    # (parent_id, slug) lookup per segment.
    def walk(segments)
      parent_id = nil
      node = nil
      segments.each do |segment|
        node = Publishing::Page.where(status: %w[published private], parent_id: parent_id)
                               .find_by(slug: segment)
        return nil if node.nil?

        parent_id = node.id
      end
      node
    end

    # ⚠️ Reported deviation, deliberately out of corpus: the legacy renders
    # theme-compat/embed-404.php (with the embed chrome) for an unknown slug under
    # `/embed/`. No corpus request reaches it; until one does, this returns the standard
    # 404 screen rather than inventing an unverified page.
    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
