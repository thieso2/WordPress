# frozen_string_literal: true

module Web
  # web.index / web.home / web.archive / web.category / web.tag / web.author / web.date /
  # web.search / web.not_found_404 -- nine of the eighteen literal screens.
  #
  # Every listing goes through Retrieval::PostQuery, which is where BR-MIGRATE-041 lives:
  # private query vars can never be set from the URL. That is the boundary that keeps
  # drafts private, so the surface never builds a scope of its own.
  #
  # Wave 2 adds the second half: having decided WHAT is queried, the controller states
  # those facts as a Presentation::Screen and hands them to the template hierarchy. It
  # does NOT choose a template — template-loader.php's rules are not controller logic.
  class ArchivesController < ApplicationController
    def index
      @query = Retrieval::PostQuery.from_request(request.query_parameters.merge(paged: params[:paged]))
      screen = if params[:s].present?
                 build_screen(:search, search_query: params[:s])
               else
                 build_screen(:home)
               end
      render_archive(screen)
    end

    def year
      @query = build(year: params[:year])
      render_archive(build_screen(:date, year: params[:year].to_i))
    end

    def month
      @query = build(year: params[:year], monthnum: params[:monthnum])
      render_archive(build_screen(:date, year: params[:year].to_i, month: params[:monthnum].to_i))
    end

    # The DAY arm of the date permastruct. `get_date_permastruct()` emits
    # `%year%/%monthnum%/%day%` and class-wp-rewrite.php registers it ahead of the post
    # permastruct, so a three-segment all-numeric path is a day archive. Presentation
    # already knew how to title one ("Day: March 15, 2026",
    # composition/renderers/post_blocks.rb:1989 date_archive_title) and PostQuery already
    # bounded the range on `day` -- only the route and this action were missing.
    def day
      @query = build(year: params[:year], monthnum: params[:monthnum], day: params[:day])
      render_archive(build_screen(:date, year: params[:year].to_i, month: params[:monthnum].to_i,
                                         day: params[:day].to_i))
    end

    def category
      # A hierarchical path: /category/top-category/middle-category/ addresses the LEAF.
      slug = encoded(params[:path].to_s.split("/").last)
      term = find_term(slug, "category")
      return not_found unless term

      @query = build(category_name: slug)
      render_archive(build_screen(:category, term: term))
    end

    def tag
      # BR-MIGRATE-033's sibling for terms: `slug` is stored the way sanitize_title() wrote
      # it -- non-ASCII percent-encoded in LOWERCASE hex (utf8_uri_encode(),
      # wp-includes/formatting.php:1160) -- and class-wp.php matches the RAW request
      # segment against it. Rails hands the segment over DECODED, so `/tag/tag-with-😀-emoji/`
      # arrived here as the literal emoji and missed the stored `tag-with-%f0%9f%98%80-emoji`.
      # Same re-encoding Web::SingularController and Web::AttachmentsController already do.
      slug = encoded(params[:slug])
      term = find_term(slug, "post_tag")
      return not_found unless term

      @query = build(tag: slug)
      render_archive(build_screen(:tag, term: term))
    end

    def author
      user = Identity::User.find_by(login: params[:login])
      return not_found unless user

      @query = build(author: user.id)
      render_archive(build_screen(:author, author: user))
    end

    private

    # ⚠️ `paged` arrives as a PATH segment on the `/…/page/N/` routes and as a query
    # parameter on `?paged=N`; class-wp.php cannot tell the two apart because the rewrite
    # rule turns the segment INTO the query var. Merging it here is what makes the rewrite
    # and the query string the same fact. Without it the paged routes matched, queried
    # page 1 and rendered the unpaged archive under a paged URL.
    def build(**vars)
      request.query_parameters
             .merge(params[:paged].present? ? { paged: params[:paged] } : {})
             .merge(vars)
             .then { |merged| Retrieval::PostQuery.from_request(merged) }
    end

    # utf8_uri_encode()'s output shape: every non-ASCII byte as %xx in lowercase hex.
    def encoded(segment)
      segment.to_s.gsub(/[^\x00-\x7F]/) do |char|
        char.bytes.map { |byte| format("%%%02x", byte) }.join
      end
    end

    def find_term(slug, taxonomy)
      Classification::Term.joins(:taxonomy).find_by(slug: slug, taxonomies: { name: taxonomy })
    end

    # `found_posts` feeds exactly one thing: the `search-results` / `search-no-results`
    # body class (post-template.php:665).
    def build_screen(kind, **facts)
      Presentation::Screen.new(kind: kind, paged: @query.page,
                               found_posts: @query.records.length, **facts)
    end

    def render_archive(screen, queried_object_exists: true)
      # BR-MIGRATE-045: an empty archive returns 200 if the queried object exists; an
      # empty PAGED archive always 404s. The asymmetry is easy to get wrong and is
      # asserted by parity_tests/07.
      #
      # ⚠️ A DATE archive has no queried object at all. WP::handle_404() lists the archive
      # types that may stay 200 while empty -- is_tag(), is_category(), is_tax(),
      # is_author(), is_post_type_archive() -- and dates are deliberately not among them,
      # so an empty month 404s where an author with no posts does not. Verified against
      # the oracle: /2026/08/ is 404, /author/oracle_editor/ is 200. Before this the
      # rebuild answered /2026/08/ with a 200 empty archive.
      exists = screen.date? ? @query.records.any? : queried_object_exists
      return not_found if @query.not_found?(queried_object_exists: exists)

      render_screen(screen, query: @query)
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
