# frozen_string_literal: true

module PublicApi
  # The `X-WP-Total` / `X-WP-TotalPages` headers and the RFC5988 `Link` header the REST
  # server adds to every paginated collection
  # (class-wp-rest-posts-controller.php:400-430). `page`/`per_page` clamp to WP's own
  # bounds (per_page 1..100, default 10).
  module CollectionPagination
    DEFAULT_PER_PAGE = 10
    MAX_PER_PAGE = 100

    def page_param = [params[:page].to_i, 1].max.then { |n| n.zero? ? 1 : n }

    def per_page_param
      requested = params[:per_page].present? ? params[:per_page].to_i : DEFAULT_PER_PAGE
      requested = DEFAULT_PER_PAGE if requested <= 0
      [requested, MAX_PER_PAGE].min
    end

    # WP paginates in-DB; here the collection is already an array slice's parent count.
    def set_pagination_headers(total:, base_path:)
      page = page_param
      per_page = per_page_param
      total_pages = per_page.positive? ? (total.to_f / per_page).ceil : 0
      response.set_header("X-WP-Total", total.to_s)
      response.set_header("X-WP-TotalPages", total_pages.to_s)

      query = request.query_parameters.except("page")
      links = []
      if page > 1
        prev_page = page - 1
        q = prev_page == 1 ? query : query.merge("page" => prev_page)
        links << %(<#{link_url(base_path, q)}>; rel="prev")
      end
      if page < total_pages
        links << %(<#{link_url(base_path, query.merge("page" => page + 1))}>; rel="next")
      end
      response.set_header("Link", links.join(", ")) if links.any?
    end

    # add_query_arg() preserves the existing argument ORDER and appends `page` last —
    # `?per_page=2&page=2`, not the alphabetised `?page=2&per_page=2` that to_query emits.
    def link_url(base_path, query)
      url = Url.rest(base_path)
      return url if query.empty?

      encoded = query.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
      "#{url}?#{encoded}"
    end
  end
end
