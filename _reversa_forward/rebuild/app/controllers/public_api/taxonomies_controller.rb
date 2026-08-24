# frozen_string_literal: true

module PublicApi
  # /wp/v2/taxonomies — WP_REST_Taxonomies_Controller. Public metadata (BR-REST-05),
  # `view` context. Set is SchemaRegistry::TAXONOMIES (DEV-002, declared not hooked).
  class TaxonomiesController < BaseController
    def index
      body = SchemaRegistry::TAXONOMIES.transform_values { |t| serialize(t) }
      render_json(body)
    end

    def show
      tax = SchemaRegistry::TAXONOMIES[params[:taxonomy]] ||
            raise(PublicApi::RestError.new("rest_taxonomy_invalid", "Invalid taxonomy.", 404))
      render_json(serialize(tax))
    end

    private

    # WP_REST_Taxonomies_Controller::prepare_item_for_response(), view context.
    def serialize(tax)
      {
        name: tax[:name],
        slug: tax[:slug],
        description: tax[:description],
        types: tax[:types],
        hierarchical: tax[:hierarchical],
        rest_base: tax[:rest_base],
        rest_namespace: "wp/v2",
        _links: {
          collection: [{ href: Url.rest("/wp/v2/taxonomies") }],
          "wp:items": [{ href: Url.rest("/wp/v2/#{tax[:rest_base]}") }],
          curies: Entity.curies
        }
      }
    end
  end
end
