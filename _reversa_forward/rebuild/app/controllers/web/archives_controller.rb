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

    def category
      # A hierarchical path: /category/top-category/middle-category/ addresses the LEAF.
      slug = params[:path].to_s.split("/").last
      term = find_term(slug, "category")
      return not_found unless term

      @query = build(category_name: slug)
      render_archive(build_screen(:category, term: term))
    end

    def tag
      term = find_term(params[:slug], "post_tag")
      return not_found unless term

      @query = build(tag: params[:slug])
      render_archive(build_screen(:tag, term: term))
    end

    def author
      user = Identity::User.find_by(login: params[:login])
      return not_found unless user

      @query = build(author: user.id)
      render_archive(build_screen(:author, author: user))
    end

    private

    def build(**vars)
      Retrieval::PostQuery.from_request(request.query_parameters.merge(vars))
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

    def render_archive(screen)
      # BR-MIGRATE-045: an empty archive returns 200 if the queried object exists; an
      # empty PAGED archive always 404s. The asymmetry is easy to get wrong and is
      # asserted by parity_tests/07.
      return not_found if @query.not_found?(queried_object_exists: true)

      render_screen(screen, query: @query)
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
