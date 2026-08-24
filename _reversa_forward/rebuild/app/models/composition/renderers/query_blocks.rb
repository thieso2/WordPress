# frozen_string_literal: true

module Composition
  module Renderers
    # The query-loop family: core/query and the six blocks that only exist inside it.
    #
    # Legacy specification, one file per block:
    #   wp-includes/blocks/query.php:19                    render_block_core_query
    #   wp-includes/blocks/post-template.php:49            render_block_core_post_template
    #   wp-includes/blocks/query-pagination.php:18         render_block_core_query_pagination
    #   wp-includes/blocks/query-pagination-next.php:21    render_block_core_query_pagination_next
    #   wp-includes/blocks/query-pagination-previous.php:19
    #   wp-includes/blocks/query-pagination-numbers.php:21
    #   wp-includes/blocks/query-no-results.php:21
    #
    # Rules: BR-MIGRATE-041 (private query vars never come from a URL -- enforced by
    # Retrieval::PostQuery, which every listing here goes through), BR-MIGRATE-194..205
    # (the render pipeline and block supports), BR-MIGRATE-045/047 (paging and counts).
    #
    # ── Three pieces of global state the legacy reads, and where they went ──────────
    #
    # AD-01 removes the hook system; paradigm_decision.md implication 1 removes global
    # mutable state. Four of the seven callbacks below read `$_GET` directly and two
    # read `$_SERVER['REQUEST_URI']` (through add_query_arg / get_pagenum_link). Those
    # are globals exactly like `$post` was, so they travel explicitly on RenderContext's
    # `context` hash, beside the block context the schemas already describe:
    #
    #   ctx.context[:request_path]   -- the current request path INCLUDING its query
    #                                   string, e.g. "/", "/page/2/", "/?s=article".
    #                                   Stands in for $_SERVER['REQUEST_URI'].
    #   ctx.context[:request_params] -- the URL's query parameters as a string-keyed
    #                                   Hash. Stands in for $_GET.
    #   ctx.query                    -- the MAIN Retrieval::PostQuery, i.e. the global
    #                                   $wp_query that `"inherit": true` inherits.
    #
    # Both context keys are Symbols on purpose: block context keys are Strings (they
    # come from `providesContext`), so a request key can never be confused for one.
    #
    # ── What this file deliberately does NOT do ────────────────────────────────────
    #
    # The layout support (`wp_render_layout_support_flag`, block-supports/layout.php:984)
    # is a `render_block` filter that runs over EVERY block with layout support and adds
    # `is-layout-*` / `wp-container-*` classes plus a matching CSS rule. core/query,
    # core/post-template and core/query-pagination all have it, and the golden query
    # screens show it: `is-layout-flow wp-block-query-is-layout-flow` on the query <div>,
    # `is-layout-flex … wp-container-core-query-pagination-is-layout-<hash>` on the
    # pagination <nav>, plus that hash's rule in `core-block-supports-inline-css`.
    # It is cross-cutting infrastructure and it already exists, ported by the layout
    # agent in `Renderers::LayoutBlocks`; `SupportChain` below calls it — the same
    # delegation `NavigationBlocks::Supports.apply` makes, and for the same reason: a
    # second copy of the layout hash would drift, and the hash names the CSS rule.
    # `wrapper_attributes` below still computes only the four supports that are
    # per-block and attribute-only (align, custom classname, generated classname,
    # anchor), exactly what the render CALLBACK itself contributes in the legacy.
    module QueryBlocks
      # Everything shared by the seven renderers. Kept as module functions so no renderer
      # can accumulate state between blocks.
      module Support
        module_function

        # ── PHP semantics the callbacks depend on ────────────────────────────────────

        # PHP's `(int)` cast on a string: leading whitespace, optional sign, digits.
        def php_intval(value)
          return value.to_i if value.is_a?(Numeric)

          match = value.to_s.match(/\A[[:space:]]*([+-]?[0-9]+)/)
          match ? match[1].to_i : 0
        end

        # PHP's `empty()`. Used verbatim by the callbacks: `empty( $_GET[ $page_key ] )`
        # treats "0" as empty, which Ruby's `blank?` does not.
        def php_empty?(value)
          return true if value.nil? || value == false || value == 0 || value == "" || value == "0"
          return true if value.respond_to?(:empty?) && value.empty?

          false
        end

        # PHP's `trim()` character set, for `empty( trim( $content ) )`.
        def php_trim(text) = text.to_s.gsub(/\A[ \t\n\r\0\x0B]+|[ \t\n\r\0\x0B]+\z/, "")

        # The whole test, as the callbacks write it. ⚠️ `empty()`, not `=== ''`: content
        # that trims to the single character "0" is EMPTY to PHP, and the pagination and
        # no-results wrappers are suppressed for it.
        def blank_content?(text) = php_empty?(php_trim(text))

        def truthy?(value) = value == true || value == "true" || value == 1 || value == "1"

        def esc_url(url) = Sanitizing::Formatting.esc_url(url.to_s)
        def esc_attr(text) = Sanitizing::Formatting.esc_attr(text.to_s)
        def esc_html(text) = Sanitizing::Formatting.esc_html(text.to_s)

        # wp-includes/formatting.php sanitize_html_class(): strip percent-encoded
        # octets, then everything outside [A-Za-z0-9_-]. The corpus depends on it --
        # a tag slugged `tag-with-%f0%9f%98%80-emoji` becomes `tag-with--emoji`.
        def sanitize_html_class(classname, fallback = "")
          sanitized = classname.to_s.gsub(/%[a-fA-F0-9][a-fA-F0-9]/, "").gsub(/[^A-Za-z0-9_-]/, "")
          return sanitize_html_class(fallback) if sanitized.empty? && !fallback.to_s.empty?

          sanitized
        end

        def trailingslashit(text) = "#{untrailingslashit(text)}/"
        def untrailingslashit(text) = text.to_s.sub(%r{[/\\]+\z}, "")

        # ── $_GET / $_SERVER['REQUEST_URI'] replacements ────────────────────────────

        def request_uri(ctx) = (ctx.context[:request_path] || "/").to_s
        def request_params(ctx) = (ctx.context[:request_params] || {}).transform_keys(&:to_s)

        # wp-includes/functions.php:1144 add_query_arg(), two-argument form (the only
        # form the query blocks use), plus the array form paginate_links() needs.
        def add_query_arg(args, uri)
          uri = uri.to_s
          frag = uri[/#.*\z/] || ""
          uri = uri[0, uri.length - frag.length] unless frag.empty?

          protocol = uri[%r{\Ahttps?://}i] || ""
          uri = uri[protocol.length..] || "" unless protocol.empty?

          if uri.include?("?")
            base, query = uri.split("?", 2)
            base = "#{base}?"
          elsif !protocol.empty? || !uri.include?("=")
            base = "#{uri}?"
            query = ""
          else
            base = ""
            query = uri
          end

          qs = parse_str(query)
          # "This re-URL-encodes things that were already in the query string."
          qs = qs.transform_values { |v| php_urlencode(php_urldecode(v)) }
          args.each { |key, value| qs[key.to_s] = value }
          qs.reject! { |_, value| value == false }

          result = build_query(qs)
          result = result.gsub(/\A\?+|\?+\z/, "")
          result = result.gsub(/=(&|\z)/) { Regexp.last_match(1) }
          result = "#{protocol}#{base}#{result}#{frag}"
          result = result.sub(/\?+\z/, "")
          result.sub("?#", "#")
        end

        def remove_query_arg(key, uri) = add_query_arg({ key.to_s => false }, uri)

        # PHP parse_str() over a query string, flat keys only -- which is all the
        # pagination URLs ever carry.
        def parse_str(query)
          query.to_s.split("&").each_with_object({}) do |pair, out|
            next if pair.empty?

            key, value = pair.split("=", 2)
            out[php_urldecode(key)] = value.nil? ? "" : value
          end
        end

        # build_query() -> _http_build_query( $data, null, '&', '', false ). ⚠️ That last
        # `false` is `$urlencode`, so build_query does NOT encode: keys and values are
        # concatenated raw. Only the args already present in the URL are encoded, by the
        # `urlencode_deep()` call in add_query_arg above. A value handed to
        # add_query_arg() therefore reaches the href exactly as given -- which is why
        # `add_query_arg( 'b', 'x y' )` yields a literal space.
        def build_query(params)
          params.map { |key, value| "#{key}=#{value}" }.join("&")
        end

        def php_urlencode(value)
          value.to_s.gsub(/[^a-zA-Z0-9_.\-]/) do |char|
            char == " " ? "+" : char.bytes.map { |b| format("%%%02X", b) }.join
          end
        end

        def php_urldecode(value) = value.to_s.tr("+", " ").gsub(/%([0-9a-fA-F]{2})/) { Regexp.last_match(1).hex.chr }

        # ── Site/rewrite facts, read once from Configuration and Routing ────────────

        def home_url = Configuration::Setting["home"].to_s
        def permalink_structure = Configuration::Setting["permalink_structure"].to_s
        def using_permalinks? = !permalink_structure.empty?
        def use_trailing_slashes? = permalink_structure.end_with?("/")
        def pagination_base = Routing::PermalinkStructure.current.pagination_base

        def user_trailingslashit(text) = use_trailing_slashes? ? trailingslashit(text) : untrailingslashit(text)

        # wp-includes/link-template.php:2432 get_pagenum_link(). The `index.php` and
        # non-pretty-permalink arms are ported because the setting is data, not a
        # constant -- the oracle runs with /%year%/%monthnum%/%postname%/.
        def get_pagenum_link(pagenum, ctx)
          pagenum = pagenum.to_i
          request = remove_query_arg("paged", request_uri(ctx))

          home_root = begin
            URI.parse(home_url).path.to_s
          rescue URI::InvalidURIError
            ""
          end
          request = request.sub(/\A#{Regexp.escape(home_root)}/i, "") unless home_root.empty?
          request = request.sub(%r{\A/+}, "")

          unless using_permalinks?
            base = trailingslashit(home_url)
            return pagenum > 1 ? add_query_arg({ "paged" => pagenum }, "#{base}#{request}") : "#{base}#{request}"
          end

          query_string = request[/\?.*?\z/] || ""
          request = request.sub(/\?.*?\z/, "") unless query_string.empty?
          request = request.sub(%r{#{Regexp.escape(pagination_base)}/\d+/?\z}, "")
          request = request.sub(/\Aindex\.php/i, "")
          request = request.sub(%r{\A/+}, "")

          parts = [untrailingslashit(home_url), untrailingslashit(request)]
          parts += [pagination_base, pagenum.to_s] if pagenum > 1
          # PHP array_filter() drops "" and "0".
          result = user_trailingslashit(parts.reject { |p| p == "" || p == "0" }.join("/"))
          esc_url("#{result}#{query_string}")
        end

        # ── Block context ───────────────────────────────────────────────────────────

        def page_key(ctx)
          id = ctx.context["queryId"]
          id.nil? ? "query-page" : "query-#{id}-page"
        end

        # `empty( $_GET[ $page_key ] ) ? 1 : (int) $_GET[ $page_key ]`
        def current_page(ctx)
          raw = request_params(ctx)[page_key(ctx)]
          php_empty?(raw) ? 1 : php_intval(raw)
        end

        def query_context(ctx) = ctx.context["query"].is_a?(Hash) ? ctx.context["query"] : {}
        def inherit?(ctx) = truthy?(query_context(ctx)["inherit"])
        def enhanced_pagination?(ctx) = truthy?(ctx.context["enhancedPagination"])
        def max_page(ctx) = php_intval(query_context(ctx)["pages"])

        # wp-includes/blocks.php:3084 get_query_pagination_arrow(). Returns nil, not "",
        # when there is no arrow -- the callers test it with `if ( $pagination_arrow )`.
        ARROW_MAP = {
          "none" => "",
          "arrow" => { "next" => "→", "previous" => "←" },
          "chevron" => { "next" => "»", "previous" => "«" },
        }.freeze

        def pagination_arrow(ctx, is_next)
          attribute = ctx.context["paginationArrow"]
          return nil if php_empty?(attribute)

          arrows = ARROW_MAP[attribute.to_s]
          return nil if php_empty?(arrows)

          type = is_next ? "next" : "previous"
          classes = "wp-block-query-pagination-#{type}-arrow is-arrow-#{attribute}"
          "<span class='#{classes}' aria-hidden='true'>#{arrows[type]}</span>"
        end

        # ── The listing. Every branch goes through Retrieval::PostQuery ─────────────

        # One page of the loop's records plus the two numbers the pagination blocks ask
        # for. `home` is WP_Query::parse_query's `is_home`: a query with no search, no
        # author, no term and no date is the blog index, and that is the only condition
        # under which sticky posts are promoted (class-wp-query.php:3584).
        Page = Struct.new(:records, :total_pages, :page, :home, keyword_init: true)

        HOME_DISQUALIFYING_VARS = %i[s search author category_name tag term taxonomy
                                     year monthnum day name].freeze

        def home_like?(vars)
          HOME_DISQUALIFYING_VARS.none? { |key| vars[key].present? }
        end

        # get_post_class() asks `is_home() && ! is_paged()` -- the GLOBAL conditionals,
        # not the loop's own query. A sticky post listed by a secondary loop on a search
        # page therefore carries no `sticky` class, while the same post on the blog index
        # does; golden-web-search.html and golden-web-home.html show exactly that pair.
        def main_is_home_unpaged?(ctx)
          main = ctx.query
          return false if main.nil?

          home_like?(main.vars) && main.page <= 1
        end

        # BR-MIGRATE-041 lives in Retrieval::PostQuery; nothing here builds a scope.
        #
        # The `page` handed to promote_sticky is WP_Query's own `$page`
        # (class-wp-query.php:2811), and the two branches genuinely differ. The main query pages with `paged`, so promotion only
        # happens on its first page. A query built from a query BLOCK always pages with
        # `offset` and never sets `paged` (blocks.php:2876), so WP_Query computes
        # `$page = 1` for it on EVERY page -- and promotes stickies every time. That is
        # not a rounding error: it is why the corpus's "More posts" loop shows five items
        # for a `perPage` of four (golden-web-search.html).
        def loop_page(ctx, page)
          if inherit?(ctx)
            main = ctx.query
            return Page.new(records: [], total_pages: 0, page: 1, home: false) if main.nil?

            home = home_like?(main.vars)
            records = main.records.to_a
            records = promote_sticky(records, main.page, main.vars[:post_type] || "post") if home
            Page.new(records: records, total_pages: main.total_pages, page: main.page, home: home)
          else
            vars = build_query_vars(ctx, page)
            query = Retrieval::PostQuery.new(vars, trusted: true)
            home = home_like?(vars) && !ignore_sticky?(ctx)
            records = query.records.to_a
            records = promote_sticky(records, 1, vars[:post_type]) if home
            Page.new(records: records, total_pages: query.total_pages, page: query.page, home: home)
          end
        end

        # `sticky: "only"` and `"ignore"` both set ignore_sticky_posts (blocks.php:2844,
        # :2848); "only" additionally needs post__in, which is not expressible -- see
        # build_query_vars below.
        def ignore_sticky?(ctx)
          %w[only ignore].include?(query_context(ctx)["sticky"].to_s)
        end

        # class-wp-query.php:3582 -- "Put sticky posts at the top of the posts array."
        # Two arms, and the corpus needs both:
        #   :3588  relocate stickies already in this page's results to the front,
        #          keeping the order they appeared in;
        #   :3609  fetch the stickies that were NOT in the results and splice them in
        #          after the relocated ones -- which is why page one can come back
        #          LONGER than posts_per_page.
        def promote_sticky(records, page, post_type)
          return records if page > 1

          ids = sticky_ids
          return records if ids.empty?

          front, rest = records.partition { |record| ids.include?(record.id) }
          front + fetch_sticky(ids - front.map(&:id), post_type) + rest
        end

        # ⚠️ The one place this family narrows a relation outside Retrieval::PostQuery.
        #
        # The legacy fetches these with `post__in`, which BR-MIGRATE-041 classes as a
        # PRIVATE query var, and PostQuery therefore offers no way to set -- correctly,
        # because the rule exists so a URL can never name specific rows. This caller is
        # not a URL: the ids come from the `sticky_posts` SETTING. So the visibility
        # decision (post type, published-only) still comes from PostQuery, and only the
        # id restriction is added on top of the relation it returns. Written out because
        # narrowing someone else's relation is exactly the move that quietly erodes a
        # security boundary, and it should be visible when it happens.
        def fetch_sticky(ids, post_type)
          return [] if ids.empty?

          Retrieval::PostQuery
            .new({ post_type: post_type || "post", posts_per_page: ids.length }, trusted: true)
            .relation.where(id: ids).limit(ids.length).to_a
        end

        def sticky_ids
          value = Configuration::Setting["sticky_posts"]
          value.is_a?(Array) ? value : []
        end

        # wp-includes/blocks.php:2817 build_query_vars_from_query_block(), translated to
        # Retrieval::PostQuery's vocabulary. The `query_loop_block_query_vars` filter at
        # line 3068 is gone (AD-01); the value below the filter is the specification.
        #
        # ⚠️ Not expressible through Retrieval::PostQuery, and therefore not implemented:
        #   * `offset`      -- PostQuery derives offset from `paged` alone.
        #   * `taxQuery` / `categoryIds` / `tagIds` -- these carry TERM IDS; PostQuery
        #     filters by term SLUG.
        #   * `exclude` / `excludeCurrent` / `parents` / `format` -- need post__not_in,
        #     post_parent__in and a post_format taxonomy, none of which exist.
        #   * `sticky: "only"` and `"exclude"` -- need post__in / post__not_in.
        # None of them occurs in the corpus's query blocks; all are reported.
        VIEWABLE_POST_TYPES = %w[post page].freeze

        def build_query_vars(ctx, page)
          query = query_context(ctx)
          vars = { post_type: "post", order: "DESC", orderby: "date", paged: page }

          type = query["postType"]
          vars[:post_type] = type if !php_empty?(type) && VIEWABLE_POST_TYPES.include?(type.to_s)

          per_page = query["perPage"]
          vars[:posts_per_page] = per_page.to_i.abs if numeric?(per_page)

          order = query["order"].to_s.upcase
          vars[:order] = order if %w[ASC DESC].include?(order)
          vars[:orderby] = query["orderBy"] if query.key?("orderBy") && !query["orderBy"].nil?

          author = author_id(query["author"])
          vars[:author] = author if author

          vars[:s] = query["search"] unless php_empty?(query["search"])
          vars
        end

        def numeric?(value)
          return true if value.is_a?(Numeric)

          value.is_a?(String) && value.match?(/\A[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\z/)
        end

        # The legacy accepts an array, a comma-separated string or an int and turns all
        # three into `author__in`. PostQuery carries a single author, so only the
        # one-author case is expressible; a multi-author list is reported, not guessed.
        def author_id(value)
          ids = case value
                when Array then value.map { |v| php_intval(v) }
                when String then value.split(",").map { |v| php_intval(v) }
                when Integer then [value]
                else []
                end
          ids = ids.reject(&:zero?)
          ids.length == 1 ? ids.first : nil
        end

        # ── get_post_class(), wp-includes/post-template.php:494 ─────────────────────

        # The legacy's post_status values, which the rebuild renamed. The CLASS NAME is
        # part of the literal screen, so the legacy spelling is what gets emitted.
        STATUS_NAMES = {
          "auto_draft" => "auto-draft", "draft" => "draft", "pending" => "pending",
          "scheduled" => "future", "published" => "publish", "private" => "private",
          "trashed" => "trash",
        }.freeze

        def post_type_of(record) = record.is_a?(Publishing::Page) ? "page" : "post"

        def post_class(record, css_class, sticky:)
          classes = css_class.to_s.split(/\s+/).reject(&:empty?).map { |c| esc_attr(c) }
          classes << "post-#{record.id}"
          type = post_type_of(record)
          classes << type
          classes << "type-#{type}"
          classes << "status-#{STATUS_NAMES.fetch(record.status.to_s, record.status.to_s)}"
          # post_type_supports( 'post', 'post-formats' ) -- registered for 'post' only,
          # and the corpus has no post_format terms, so every article is standard.
          classes << "format-standard" if type == "post"

          password_required = record.password_digest.present?
          classes << "post-password-required" if password_required
          # current_theme_supports( 'post-thumbnails' ) is true for twentytwentyfive.
          classes << "has-post-thumbnail" if record.featured_asset_id.present? && !password_required
          # is_sticky() && is_home() && ! is_paged()
          classes << "sticky" if sticky && sticky_ids.include?(record.id)
          classes << "hentry"
          classes.concat(taxonomy_classes(record))
          classes.map { |c| esc_attr(c) }.uniq
        end

        # get_taxonomies( array( 'public' => true ) ) in registration order is
        # category, post_tag, post_format; get_the_terms() orders by name ASC.
        # 'post_tag' uses the 'tag' prefix for backward compatibility.
        PUBLIC_TAXONOMIES = %w[category post_tag post_format].freeze

        def taxonomy_classes(record)
          terms = Classification::Term
                  .joins(:taxonomy, :assignments)
                  .where(term_assignments: { classifiable_type: "Publishing::Post",
                                             classifiable_id: record.id })
                  .where(taxonomies: { name: PUBLIC_TAXONOMIES })
                  .select("terms.*, taxonomies.name AS taxonomy_name")
                  .order("terms.name ASC")

          grouped = terms.group_by { |term| term.attributes["taxonomy_name"] }
          PUBLIC_TAXONOMIES.flat_map do |taxonomy|
            Array(grouped[taxonomy]).filter_map do |term|
              next if term.slug.blank?

              term_class = sanitize_html_class(term.slug, term.id.to_s)
              term_class = term.id.to_s if term_class.match?(/\A[0-9]+\z/) || term_class.gsub("-", "").empty?
              if taxonomy == "post_tag"
                "tag-#{term_class}"
              else
                sanitize_html_class("#{taxonomy}-#{term_class}", "#{taxonomy}-#{term.id}")
              end
            end
          end
        end

        # ── paginate_links(), wp-includes/general-template.php:4873 ─────────────────
        #
        # Only what the two callers ask for: `prev_next` is always false and `type` is
        # always 'plain', so the prev/next arms and the list/array shapes are omitted
        # rather than ported dead. `number_format_i18n` is the identity for en_US below
        # 1,000 and the thousands separator above it, which no corpus page reaches.
        #
        # The legacy defaults `total` and `current` from the GLOBAL $wp_query
        # (:4881-4882). Both callers here pass them explicitly instead -- the inherit
        # branch passing `current` where the legacy relies on get_query_var('paged'),
        # which is the same number by construction (Retrieval::PostQuery#page).
        def paginate_links(ctx, args)
          pagenum_link = html_entity_decode(get_pagenum_link(1, ctx))
          url_parts = pagenum_link.split("?")

          base = if using_permalinks? && !use_trailing_slashes?
                   untrailingslashit(url_parts[0])
                 else
                   trailingslashit(url_parts[0])
                 end
          base = "#{base}%_%"

          format = using_permalinks? ? user_trailingslashit("#{pagination_base}/%#%") : "?paged=%#%"
          format = "/#{format.sub(%r{\A/+}, "")}" if using_permalinks? && !use_trailing_slashes?

          args = { "base" => base, "format" => format, "aria_current" => "page",
                   "show_all" => false, "end_size" => 1, "mid_size" => 2,
                   "add_args" => {}, "add_fragment" => "",
                   "before_page_number" => "", "after_page_number" => "" }.merge(args)

          add_args = args["add_args"].is_a?(Hash) ? args["add_args"].dup : {}
          if url_parts[1]
            format_parts = args["base"].sub("%_%", args["format"]).split("?")
            format_args = parse_str(format_parts[1] || "")
            url_query_args = parse_str(url_parts[1])
            format_args.each_key { |key| url_query_args.delete(key) }
            add_args = add_args.merge(url_query_args.transform_values { |v| php_urlencode(php_urldecode(v)) })
          end

          total = args["total"].to_i
          return nil if total < 2

          current = args["current"].to_i
          end_size = args["end_size"].to_i
          end_size = 1 if end_size < 1
          mid_size = args["mid_size"].to_i
          mid_size = 2 if mid_size.negative?

          page_links = []
          dots = false

          (1..total).each do |n|
            if n == current
              page_links << %(<span aria-current="#{esc_attr(args["aria_current"])}" class="page-numbers current">) +
                            "#{args["before_page_number"]}#{n}#{args["after_page_number"]}</span>"
              dots = true
            elsif args["show_all"] ||
                  n <= end_size ||
                  (current.positive? && n >= current - mid_size && n <= current + mid_size) ||
                  n > total - end_size
              link = args["base"].sub("%_%", n == 1 ? "" : args["format"]).sub("%#%", n.to_s)
              link = add_query_arg(add_args, link) if add_args.any?
              link += args["add_fragment"]
              page_links << %(<a class="page-numbers" href="#{esc_url(link)}">) +
                            "#{args["before_page_number"]}#{n}#{args["after_page_number"]}</a>"
              dots = true
            elsif dots && !args["show_all"]
              page_links << '<span class="page-numbers dots">&hellip;</span>'
              dots = false
            end
          end

          page_links.join("\n")
        end

        # html_entity_decode() over the entities esc_url() can have introduced.
        def html_entity_decode(text)
          text.to_s.gsub("&#038;", "&").gsub("&amp;", "&").gsub("&#039;", "'")
        end

        # ── get_block_wrapper_attributes(), class-wp-block-supports.php:203 ──────────
        #
        # Supports computed here, in registration order (wp-settings.php:415-418):
        # align, custom classname, generated classname; then anchor (line 433) as `id`.
        # See the file header for the ones deliberately left to a shared supports layer.
        MERGE_ORDER = %w[style class id aria-label].freeze

        def wrapper_attributes(type, attrs, extra = {})
          support = {}
          classes = []
          classes << "align#{attrs["align"]}" if type && block_supports?(type, "align", false) && attrs.key?("align")
          classes << attrs["className"] if attrs["className"].is_a?(String) && !attrs["className"].empty?
          classes << "wp-block-#{type.short_name}" if type && block_supports?(type, "className", true)
          support["class"] = classes.join(" ") unless classes.empty?
          if type && block_supports?(type, "anchor", false) && !php_empty?(attrs["anchor"])
            support["id"] = attrs["anchor"].to_s
          end

          return "" if support.empty? && extra.empty?

          attributes = {}
          MERGE_ORDER.each do |name|
            new_value = scalar_string(support[name])
            extra_value = scalar_string(extra[name])
            next if new_value.empty? && extra_value.empty?

            attributes[name] = merge_attribute(name, new_value, extra_value)
          end
          extra.each do |name, value|
            next if MERGE_ORDER.include?(name.to_s)
            next unless value.is_a?(String) || value.is_a?(Numeric)

            attributes[name.to_s] = value.to_s
          end
          return "" if attributes.empty?

          attributes.map { |name, value| %(#{name}="#{esc_attr(value)}") }.join(" ")
        end

        def merge_attribute(name, new_value, extra_value)
          case name
          when "class"
            (extra_value.split(/\s+/).reject(&:empty?) + new_value.split(/\s+/).reject(&:empty?)).uniq.join(" ")
          when "style"
            [new_value.strip.sub(/;\z/, ""), extra_value.strip.sub(/;\z/, "")].reject(&:empty?).join(";")
          else
            extra_value.empty? ? new_value : extra_value
          end
        end

        def scalar_string(value)
          return "" if value.nil? || value == true || value == false
          return value.to_s if value.is_a?(String) || value.is_a?(Numeric)

          ""
        end

        # block_has_support( $block_type, $feature, $default_value )
        def block_supports?(type, feature, default_value)
          supports = type.supports || {}
          return default_value unless supports.key?(feature)

          value = supports[feature]
          value != false && !value.nil?
        end
      end

      # Renders inner blocks by splicing them back into `inner_content`'s nil slots,
      # exactly as Renderers::Base does, but under a context of this block's choosing.
      # Every block in this family provides or scopes context, so none of them can use
      # Base#render unchanged.
      module Splicing
        private

        def splice(child_ctx)
          return block.inner_html.to_s if block.inner_blocks.empty?

          index = -1
          block.inner_content.map do |chunk|
            next chunk unless chunk.nil?

            index += 1
            Renderer.render_block(block.inner_blocks[index], child_ctx)
          end.join
        end

        def support = Support
      end

      # The `render_block` filter chain the legacy applies to EVERY block's output after
      # its own callback has run (typography → settings → elements → layout → dimensions
      # → block-style-variations, all priority 10 on `render_block`). For this family it
      # is what puts `is-layout-flow wp-block-query-is-layout-flow` on the query <div>
      # (layout.php:984) and the `wp-container-core-query-pagination-is-layout-<hash>`
      # class + stored CSS rule on the pagination <nav>.
      #
      # Prepended into each renderer so it wraps the callback's output exactly where the
      # legacy filter runs: on this block's own HTML, before the parent splices it in.
      # The implementation is the shared port in `Renderers::LayoutBlocks` — calling it
      # rather than re-porting it is deliberate (two copies of the layout hash would
      # drift, and the hash names the CSS rule the style store emits).
      module SupportChain
        def render
          # wp_render_elements_support_styles runs on `render_block_data` — BEFORE the
          # callback — and MUTATES `attrs.className`, appending `wp-elements-<n>`
          # (elements.php:186-188). That is why the class travels through
          # get_block_wrapper_attributes' custom-classname support and lands BETWEEN the
          # author's className and the generated `wp-block-…` class, not after the
          # supports. The mutation is reproduced on both attr views the renderer reads.
          elements_class = LayoutBlocks::ElementsSupport.prepare(block, ctx)
          if elements_class
            merged = [attrs["className"].to_s, elements_class].reject(&:empty?).join(" ")
            attrs["className"] = merged
            block.attrs["className"] = merged if block.attrs.is_a?(Hash)
          end

          html = super.to_s
          return html if html.strip.empty?

          LayoutBlocks.apply_supports(html, block, ctx, elements_class)
        end
      end

      # wp-includes/blocks/query.php:19 render_block_core_query.
      #
      # The callback returns `$content` untouched unless enhanced pagination is on. Its
      # style_handles bookkeeping (lines 42-53) is a mutation of the shared block type
      # object -- global state, and under AD-01 unreachable anyway; the collector in
      # Composition::StyleCollector decides what CSS ships.
      #
      # What the callback does NOT do, but WP_Block does, is hand `queryId`, `query`,
      # `displayLayout` and `enhancedPagination` to the subtree (block.json
      # providesContext). class-wp-block.php:190 provides a key only when the attribute
      # EXISTS after defaults are applied, which is why `queryId` and `displayLayout`
      # are conditional here and the other two are not.
      class Query < Base
        include Splicing
        prepend SupportChain
        handles "core/query"

        PROVIDES = { "queryId" => "queryId", "query" => "query",
                     "displayLayout" => "displayLayout",
                     "enhancedPagination" => "enhancedPagination" }.freeze

        def render
          content = splice(ctx.with(context: provided_context))
          return content unless interactive?

          processor = Markup::TagProcessor.new(content)
          return content unless processor.next_tag

          processor.set_attribute("data-wp-interactive", "core/query")
          processor.set_attribute("data-wp-router-region", "query-#{attrs["queryId"]}")
          processor.set_attribute("data-wp-context", "{}")
          processor.set_attribute("data-wp-key", attrs["queryId"].to_s)
          processor.get_updated_html
        end

        private

        def provided_context
          PROVIDES.each_with_object({}) do |(context_name, attribute_name), out|
            out[context_name] = attrs[attribute_name] if attrs.key?(attribute_name)
          end
        end

        # `enhancedPagination === true && isset( queryId )`
        def interactive? = attrs["enhancedPagination"] == true && !attrs["queryId"].nil?
      end

      # wp-includes/blocks/post-template.php:49 render_block_core_post_template.
      class PostTemplate < Base
        include Splicing
        prepend SupportChain
        handles "core/post-template"

        def render
          page = support.current_page(ctx)
          records = support.loop_page(ctx, page).records
          # `if ( ! $query->have_posts() ) { return ''; }`
          return "" if records.empty?

          sticky = support.main_is_home_unpaged?(ctx)
          items = records.map { |record| item(record, sticky) }.join
          %(<ul #{support.wrapper_attributes(type, attrs, "class" => classnames)}>#{items}</ul>)
        end

        private

        def item(record, sticky)
          child = ctx.with(post: record,
                           context: { "postType" => support.post_type_of(record),
                                      "postId" => record.id })
          content = elements_class_on_first_tag(splice(child))
          classes = support.post_class(record, "wp-block-post", sticky: sticky)
          directives = if support.enhanced_pagination?(ctx)
                         %( data-wp-key="post-template-item-#{record.id}")
                       else
                         ""
                       end
          %(<li#{directives} class="#{support.esc_attr(classes.join(" "))}">#{content}</li>)
        end

        # post-template.php:126 renders each item through `WP_Block::render()` under the
        # unregistered name 'core/null', which still applies the `render_block` filters —
        # and the ONE filter with an effect there is `wp_render_elements_class_name`
        # (elements.php:276): it finds the `wp-elements-*` token the render_block_data
        # mutation left in THIS block's className and adds it to the item content's
        # first tag. That is why every item of a link-coloured post-template carries the
        # same `wp-elements-<n>` class as the <ul>.
        def elements_class_on_first_tag(content)
          token = attrs["className"].to_s.split(/[ \t\f\r\n]+/).find { |t| t.start_with?("wp-elements-") }
          return content if token.nil? || content.empty?

          processor = Markup::TagProcessor.new(content)
          return content unless processor.next_tag

          processor.add_class(token)
          processor.get_updated_html
        end

        # post-template.php:83-101, verbatim including the leading space the legacy
        # leaves before `has-link-color` and trims off at the end.
        def classnames
          names = +""
          layout = ctx.context["displayLayout"]
          if layout.is_a?(Hash) && ctx.context.key?("query") && layout["type"] == "flex"
            names << "is-flex-container columns-#{layout["columns"]}"
          end
          names << " has-link-color" if attrs.dig("style", "elements", "link", "color", "text")

          grid = attrs["layout"].is_a?(Hash) ? attrs["layout"] : {}
          if grid["type"] == "grid" && !support.php_empty?(grid["columnCount"])
            names << " #{Sanitizing::Formatting.sanitize_title("columns-#{grid["columnCount"]}")}"
            names << " has-native-responsive-grid" unless support.php_empty?(grid["minimumColumnWidth"])
          end
          support.php_trim(names)
        end
      end

      # wp-includes/blocks/query-pagination.php:18 render_block_core_query_pagination.
      #
      # The `aria-label` is the literal string 'Pagination'; AD-01 means __() has no
      # translation to apply and no filter to change it.
      class QueryPagination < Base
        include Splicing
        prepend SupportChain
        handles "core/query-pagination"

        def render
          content = splice(ctx.with(context: { "paginationArrow" => attrs["paginationArrow"],
                                               "showLabel" => attrs["showLabel"] }))
          return "" if support.blank_content?(content)

          classes = attrs.dig("style", "elements", "link", "color", "text") ? "has-link-color" : ""
          wrapper = support.wrapper_attributes(type, attrs,
                                               "aria-label" => "Pagination", "class" => classes)
          %(<nav #{wrapper}>#{content}</nav>)
        end
      end

      # Shared by next and previous: both read the same context, build the same wrapper
      # and apply the same interactivity directives.
      class PaginationLink < Base
        include Splicing

        private

        def show_label? = ctx.context.key?("showLabel") ? support.truthy?(ctx.context["showLabel"]) : true

        def label_text(default_label)
          value = attrs["label"]
          value.is_a?(String) && !value.empty? ? support.esc_html(value) : default_label
        end

        # `preg_replace( '/&([^#])(?![a-z]{1,8};)/i', '&#038;$1', $label )` --
        # get_next_posts_link()/get_previous_posts_link() run it over the label.
        def encode_ampersands(label)
          label.to_s.gsub(/&([^#])(?![a-z]{1,8};)/i) { "&#038;#{Regexp.last_match(1)}" }
        end

        def apply_directives(content, key, class_name)
          return content unless support.enhanced_pagination?(ctx)

          processor = Markup::TagProcessor.new(content)
          return content unless processor.next_tag("tag_name" => "a", "class_name" => class_name)

          processor.set_attribute("data-wp-key", key)
          processor.set_attribute("data-wp-on--click", "core/query::actions.navigate")
          processor.set_attribute("data-wp-on--mouseenter", "core/query::actions.prefetch")
          processor.set_attribute("data-wp-watch", "core/query::callbacks.prefetch")
          processor.get_updated_html
        end
      end

      # wp-includes/blocks/query-pagination-next.php:21.
      class QueryPaginationNext < PaginationLink
        prepend SupportChain
        handles "core/query-pagination-next"

        DEFAULT_LABEL = "Next Page"

        def render
          page_key = support.page_key(ctx)
          page = support.current_page(ctx)
          maximum = support.max_page(ctx)

          wrapper = support.wrapper_attributes(type, attrs)
          text = label_text(DEFAULT_LABEL)
          label = show_label? ? text : ""
          arrow = support.pagination_arrow(ctx, true)
          wrapper = %(#{wrapper} aria-label="#{text}") if label.empty?
          label = "#{label}#{arrow}" if arrow

          content = if support.inherit?(ctx)
                      inherited_link(label, maximum, wrapper)
                    elsif maximum.zero? || maximum > page
                      custom_link(label, page, page_key, wrapper)
                    else
                      ""
                    end

          apply_directives(content, "query-pagination-next", "wp-block-query-pagination-next")
        end

        private

        # get_next_posts_link(), link-template.php:2565. The callback installs
        # `next_posts_link_attributes` itself, so under AD-01 the wrapper attributes are
        # simply part of the anchor.
        #
        # ⚠️ The legacy also guards on `! is_single()`, which suppresses the link when an
        # INHERITING query loop is rendered on a singular screen. `is_single()` is a
        # property of the main query and RenderContext carries no equivalent, so the
        # guard is not implemented. No corpus screen reaches it: single.html and page.html
        # contain no query loop, and the only inheriting loop lives in index/archive/search.
        def inherited_link(label, maximum, wrapper)
          main = ctx.query
          return "" if main.nil?

          maximum = main.total_pages if maximum > main.total_pages
          maximum = main.total_pages if maximum.zero?
          paged = main.page
          paged = 1 if paged.zero?
          return "" unless paged + 1 <= maximum

          href = support.esc_url(support.get_pagenum_link(paged + 1, ctx))
          %(<a href="#{href}" #{wrapper}>#{encode_ampersands(label)}</a>)
        end

        # `! $max_page || $max_page > $page` already checked by the caller.
        def custom_link(label, page, page_key, wrapper)
          custom = support.loop_page(ctx, page)
          return "" if custom.total_pages.zero? || custom.total_pages == page

          href = support.esc_url(support.add_query_arg({ page_key => page + 1 },
                                                       support.request_uri(ctx)))
          %(<a href="#{href}" #{wrapper}>#{label}</a>)
        end
      end

      # wp-includes/blocks/query-pagination-previous.php:19.
      class QueryPaginationPrevious < PaginationLink
        prepend SupportChain
        handles "core/query-pagination-previous"

        DEFAULT_LABEL = "Previous Page"

        def render
          page_key = support.page_key(ctx)
          page = support.current_page(ctx)
          maximum = support.max_page(ctx)

          wrapper = support.wrapper_attributes(type, attrs)
          text = label_text(DEFAULT_LABEL)
          label = show_label? ? text : ""
          arrow = support.pagination_arrow(ctx, false)
          wrapper = %(#{wrapper} aria-label="#{text}") if label.empty?
          label = "#{arrow}#{label}" if arrow

          content = if support.inherit?(ctx)
                      inherited_link(label, wrapper)
                    else
                      custom_link(label, page, page_key, maximum, wrapper)
                    end

          apply_directives(content, "query-pagination-previous", "wp-block-query-pagination-previous")
        end

        private

        # get_previous_posts_link(), link-template.php:2665: `! is_single() && $paged > 1`.
        def inherited_link(label, wrapper)
          main = ctx.query
          return "" if main.nil? || main.page <= 1

          href = support.esc_url(support.get_pagenum_link([main.page - 1, 1].max, ctx))
          %(<a href="#{href}" #{wrapper}>#{encode_ampersands(label)}</a>)
        end

        def custom_link(label, page, page_key, maximum, wrapper)
          block_max_pages = support.loop_page(ctx, page).total_pages
          total = maximum.zero? || maximum > block_max_pages ? block_max_pages : maximum
          return "" unless page > 1 && page <= total

          href = support.esc_url(support.add_query_arg({ page_key => page - 1 },
                                                       support.request_uri(ctx)))
          %(<a href="#{href}" #{wrapper}>#{label}</a>)
        end
      end

      # wp-includes/blocks/query-pagination-numbers.php:21.
      class QueryPaginationNumbers < Base
        include Splicing
        prepend SupportChain
        handles "core/query-pagination-numbers"

        def render
          page = support.current_page(ctx)
          maximum = support.max_page(ctx)
          mid_size = attrs.key?("midSize") ? support.php_intval(attrs["midSize"]) : nil

          content = support.inherit?(ctx) ? inherited(maximum, mid_size) : custom(page, maximum, mid_size)
          return "" if content.nil? || content.empty?

          content = apply_directives(content) if support.enhanced_pagination?(ctx)
          %(<div #{support.wrapper_attributes(type, attrs)}>#{content}</div>)
        end

        private

        def inherited(maximum, mid_size)
          main = ctx.query
          return nil if main.nil?

          total = maximum.zero? || maximum > main.total_pages ? main.total_pages : maximum
          args = { "prev_next" => false, "total" => total, "current" => main.page }
          args["mid_size"] = mid_size unless mid_size.nil?
          support.paginate_links(ctx, args)
        end

        # The legacy swaps the global $wp_query for the block's own so that
        # paginate_links() reads the right max_num_pages. Here the numbers are passed
        # in, so there is nothing to swap and nothing to restore.
        def custom(page, maximum, mid_size)
          block_max_pages = support.loop_page(ctx, page).total_pages
          total = maximum.zero? || maximum > block_max_pages ? block_max_pages : maximum
          page_key = support.page_key(ctx)

          args = { "base" => "%_%", "format" => "?#{page_key}=%#%",
                   "current" => [1, page].max, "total" => total, "prev_next" => false }
          args["mid_size"] = mid_size unless mid_size.nil?
          # general-template.php's own comment: paginate_links() ignores `format` on
          # page 1, which for a custom query yields an empty link back to the current
          # page. The fake `cst` arg is the legacy's documented workaround (trac 53868).
          args["add_args"] = { "cst" => "" } if page != 1
          # query-pagination-numbers.php:84-88: `$paged = empty($_GET['paged']) ? null :
          # (int) $_GET['paged'];` and then `if ( $paged )`. The SECOND test is on the
          # CAST value, so `?paged=0x` -- non-empty, but (int) 0 -- leaves add_args alone
          # and the `cst` workaround survives. Skipping on the cast alone is the same
          # test for every input, because every value empty() rejects also casts to 0.
          paged = support.php_intval(support.request_params(ctx)["paged"])
          args["add_args"] = { "paged" => paged } unless paged.zero?
          support.paginate_links(ctx, args)
        end

        def apply_directives(content)
          processor = Markup::TagProcessor.new(content)
          index = 0
          while processor.next_tag("class_name" => "page-numbers")
            if processor.get_attribute("data-wp-key").nil?
              processor.set_attribute("data-wp-key", "index-#{index}")
              index += 1
            end
            processor.set_attribute("data-wp-on--click", "core/query::actions.navigate") if processor.get_tag == "A"
          end
          processor.get_updated_html
        end
      end

      # wp-includes/blocks/query-no-results.php:21.
      #
      # ⚠️ The emptiness test is `$query->post_count > 0` -- the number of records on
      # THIS page, not the total. An empty page 2 therefore shows the no-results block,
      # which is the legacy's behaviour and not an oversight.
      class QueryNoResults < Base
        include Splicing
        prepend SupportChain
        handles "core/query-no-results"

        def render
          content = splice(ctx)
          return "" if support.blank_content?(content)

          page = support.current_page(ctx)
          return "" if support.loop_page(ctx, page).records.any?

          classes = attrs.dig("style", "elements", "link", "color", "text") ? "has-link-color" : ""
          %(<div #{support.wrapper_attributes(type, attrs, "class" => classes)}>#{content}</div>)
        end
      end
    end
  end
end
