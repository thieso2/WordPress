# frozen_string_literal: true

module PublicApi
  # /wp/v2/types — WP_REST_Post_Types_Controller. Public metadata (no permission
  # callback, BR-REST-05): the same shape whether or not a caller is logged in, in
  # `view` context. The set is SchemaRegistry::TYPES (DEV-002, declared not hooked).
  class TypesController < BaseController
    def index
      body = SchemaRegistry::TYPES.transform_values { |t| serialize(t) }
      render_json(body)
    end

    def show
      type = SchemaRegistry::TYPES[params[:type]] ||
             raise(PublicApi::RestError.new("rest_type_invalid", "Invalid post type.", 404))
      render_json(serialize(type))
    end

    private

    # WP_REST_Post_Types_Controller::prepare_item_for_response(), view context — the
    # field order the oracle emits.
    def serialize(type)
      {
        description: type[:description],
        hierarchical: type[:hierarchical],
        has_archive: type[:has_archive],
        name: type[:name],
        slug: type[:slug],
        icon: type[:icon],
        taxonomies: type[:taxonomies],
        rest_base: type[:rest_base],
        rest_namespace: "wp/v2",
        template: [],
        template_lock: false,
        _links: {
          collection: [{ href: Url.rest("/wp/v2/types") }],
          "wp:items": [{ href: Url.rest("/wp/v2/#{type[:rest_base]}") }],
          curies: Entity.curies
        }
      }
    end
  end
end
