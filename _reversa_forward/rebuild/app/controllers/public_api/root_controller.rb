# frozen_string_literal: true

module PublicApi
  # The REST index (`/wp-json/`) and the `rest_no_route` catch-all
  # (class-wp-rest-server.php:435, get_index / :1096, error_to_response). No permission
  # callback -> public (BR-REST-05). The index is what the front-end's
  # `<link rel="https://api.w.org/" href=".../wp-json/">` discovery tag points at, so it
  # MUST resolve; every golden page carries that link.
  #
  # ⚠️ SCOPE (reported). The legacy index also embeds a self-describing `routes` map with
  # the full JSON-Schema `args` of EVERY registered route — 133 entries, ~195 KB, most of
  # them write/system/plugin routes that are out of this READ-surface pass. What is
  # reproduced here is: the site-header fields verbatim (the values a consumer actually
  # reads — name, description, url, home, timezone, namespaces, authentication), and a
  # `routes` map for the routes this pass SERVES. The deferred namespaces
  # (wp-site-health/v1, wp-block-editor/v1, wp-abilities/v1) and the write endpoints are
  # named in the handoff report, not silently advertised.
  class RootController < BaseController
    def index
      render_json(index_document)
    end

    # `/wp/v2` — the same document filtered to a single namespace (get_namespace_index,
    # :493). Same header, `routes` limited to that namespace.
    def namespace
      render_json(index_document(only_namespace: "wp/v2"))
    end

    # Anything under /wp-json that matched no route, any method. class-wp-rest-server.php
    # :1096: `rest_no_route`, HTTP 404.
    def no_route
      raise PublicApi::RestError.new("rest_no_route",
                                     "No route was found matching the URL and request method.", 404)
    end

    private

    def index_document(only_namespace: nil)
      routes = route_table
      routes = routes.select { |_, v| v[:namespace] == only_namespace || v[:namespace].to_s.empty? } if only_namespace
      {
        name: Configuration::Setting["blogname"].to_s,
        description: Configuration::Setting["blogdescription"].to_s,
        url: Entity.site.site_url,
        home: Entity.site.home_url,
        gmt_offset: gmt_offset,
        timezone_string: Configuration::Setting["timezone_string"].to_s,
        namespaces: namespaces_for(routes),
        authentication: [],
        site_logo: 0,
        site_icon: 0,
        site_icon_url: "",
        routes: routes,
        _links: { help: [{ href: "https://developer.wordpress.org/rest-api/" }] }
      }
    end

    # get_option('gmt_offset'): the current UTC offset (DST-aware) of the site timezone,
    # in whole/fractional hours. Matches the oracle (Europe/Madrid -> 2 in summer).
    def gmt_offset
      tz = Configuration::Setting["timezone_string"].to_s
      if tz.present?
        secs = TZInfo::Timezone.get(tz).current_period.utc_total_offset
        offset = secs / 3600.0
        return offset == offset.to_i ? offset.to_i : offset
      end
      # `get_option('gmt_offset')` is `false`/'' when unset (WordPress returns 0 then).
      raw = Configuration::Setting["gmt_offset"]
      num = begin
        Float(raw)
      rescue ArgumentError, TypeError
        0.0
      end
      num == num.to_i ? num.to_i : num
    rescue StandardError
      0
    end

    # The legacy lists namespaces in registration order:
    #   oembed/1.0, wp/v2, wp-site-health/v1, wp-block-editor/v1, wp-abilities/v1.
    # This pass serves the first two; the trailing three are deferred admin/editor
    # surfaces (named in the handoff report) and are NOT advertised — advertising a
    # namespace whose routes do not exist would be a false contract.
    NAMESPACE_ORDER = %w[oembed/1.0 wp/v2 wp-site-health/v1 wp-block-editor/v1 wp-abilities/v1].freeze

    def namespaces_for(routes)
      served = routes.values.map { |r| r[:namespace] }.reject(&:blank?).uniq
      NAMESPACE_ORDER.select { |ns| served.include?(ns) }
    end

    # The routes this pass serves, in the legacy's route-entry shape (a route -> its
    # methods, endpoints and self link). `args.context` is the one arg every read route
    # carries; the full arg schema is out of the read-surface scope (see class note).
    def route_table
      table = {}
      table["/"] = index_route
      GET_COLLECTIONS.each { |path| table[path] = collection_route(path) }
      GET_ITEMS.each { |tmpl| table[tmpl] = item_route(tmpl) }
      table["/oembed/1.0/embed"] = oembed_route
      table
    end

    GET_COLLECTIONS = %w[
      /wp/v2/posts /wp/v2/pages /wp/v2/media /wp/v2/categories /wp/v2/tags
      /wp/v2/users /wp/v2/comments /wp/v2/types /wp/v2/taxonomies /wp/v2/statuses
    ].freeze

    GET_ITEMS = [
      "/wp/v2/posts/(?P<id>[\\d]+)", "/wp/v2/pages/(?P<id>[\\d]+)",
      "/wp/v2/media/(?P<id>[\\d]+)", "/wp/v2/categories/(?P<id>[\\d]+)",
      "/wp/v2/tags/(?P<id>[\\d]+)", "/wp/v2/users/(?P<id>[\\d]+)",
      "/wp/v2/comments/(?P<id>[\\d]+)"
    ].freeze

    def namespace_of(path) = path.start_with?("/wp/v2") ? "wp/v2" : (path.start_with?("/oembed") ? "oembed/1.0" : "")

    def index_route
      { namespace: "", methods: %w[GET],
        endpoints: [{ methods: %w[GET], args: { context: { default: "view", required: false } } }],
        _links: { self: [{ href: Url.rest("/") }] } }
    end

    def collection_route(path)
      { namespace: namespace_of(path), methods: %w[GET],
        endpoints: [{ methods: %w[GET], args: context_arg }],
        _links: { self: [{ href: Url.rest(path) }] } }
    end

    def item_route(tmpl)
      { namespace: namespace_of(tmpl), methods: %w[GET],
        endpoints: [{ methods: %w[GET], args: context_arg }] }
    end

    def oembed_route
      { namespace: "oembed/1.0", methods: %w[GET],
        endpoints: [{ methods: %w[GET], args: {
          url: { description: "The URL of the resource for which to fetch oEmbed data.",
                 type: "string", format: "uri", required: true },
          format: { default: "json", required: false },
          maxwidth: { default: 600, required: false },
          maxheight: { required: false }
        } }],
        _links: { self: [{ href: Url.rest("/oembed/1.0/embed") }] } }
    end

    def context_arg
      { context: { description: "Scope under which the request is made; determines fields present in response.",
                   type: "string", enum: %w[view embed edit], default: "view", required: false } }
    end
  end
end
