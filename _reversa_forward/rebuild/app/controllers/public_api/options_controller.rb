# frozen_string_literal: true

module PublicApi
  # `OPTIONS /wp-json/...` — the route descriptor WordPress answers with
  # (WP_REST_Server::dispatch's OPTIONS handling → get_route_options()). @wordpress/core-data
  # sends it to discover what the CURRENT USER may do with an endpoint: the `Allow` header is
  # what decides whether the editor offers Save, Trash and so on.
  #
  # The verbs are derived from THIS application's own route table rather than declared in a
  # second list, so the answer cannot drift from what the router will actually accept — if a
  # write route is removed, the editor stops offering the control on the next request.
  class OptionsController < BaseController
    # A descriptor is metadata about the surface, not about a record; the oracle answers it
    # for anonymous callers too (only the `Allow` header narrows by capability).
    def show
      path = "/wp-json/#{params[:rest_path]}"
      verbs = allowed_verbs(path)
      return render_rest_error(RestError.new(:rest_no_route, "No route was found matching the URL and request method.", status: 404)) if verbs.empty?

      response.set_header("Allow", verbs.join(", "))
      render json: {
        namespace: "wp/v2",
        methods: verbs,
        endpoints: verbs.map { |v| { methods: [v], args: {} } },
        schema: schema_for(path)
      }.compact
    end

    private

    # Ask the router which verbs it recognises for this path. HEAD follows GET, as Rack does,
    # and is not advertised separately — the oracle does not advertise it either.
    def allowed_verbs(path)
      %w[GET POST PUT PATCH DELETE].select do |verb|
        route = (Rails.application.routes.recognize_path(path, method: verb) rescue nil)
        route && route[:controller].to_s.start_with?("public_api") &&
          !%w[no_route options].include?(route[:action].to_s)
      end
    end

    # The item schema where we have one to give. `title` is the only field Gutenberg reads
    # from here on the paths it probes, so an honest minimal descriptor beats a fabricated
    # full JSON-Schema that would claim fields the endpoints do not implement.
    def schema_for(path)
      case path
      when %r{/wp/v2/posts}      then { "$schema": "http://json-schema.org/draft-04/schema#", title: "post", type: "object" }
      when %r{/wp/v2/pages}      then { "$schema": "http://json-schema.org/draft-04/schema#", title: "page", type: "object" }
      when %r{/wp/v2/media}      then { "$schema": "http://json-schema.org/draft-04/schema#", title: "attachment", type: "object" }
      when %r{/wp/v2/blocks}     then { "$schema": "http://json-schema.org/draft-04/schema#", title: "wp_block", type: "object" }
      when %r{/wp/v2/templates}  then { "$schema": "http://json-schema.org/draft-04/schema#", title: "wp_template", type: "object" }
      when %r{/wp/v2/settings}   then { "$schema": "http://json-schema.org/draft-04/schema#", title: "settings", type: "object" }
      when %r{/wp/v2/global-styles} then { "$schema": "http://json-schema.org/draft-04/schema#", title: "wp_global_styles", type: "object" }
      end
    end
  end
end
