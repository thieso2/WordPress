# frozen_string_literal: true

module PublicApi
  # WP_REST_Terms_Controller::prepare_item_for_response()
  # (class-wp-rest-terms-controller.php:730), for the `category` and `post_tag`
  # taxonomies. `parent` appears only for a hierarchical taxonomy.
  class TermSerializer
    include Entity

    # taxonomy name -> its REST base (the collection path segment).
    REST_BASE = { "category" => "categories", "post_tag" => "tags" }.freeze
    # the query var the wp:post_type link filters posts by.
    POST_FILTER = { "category" => "categories", "post_tag" => "tags" }.freeze

    # The `Allow`/targetHints value for a caller with no write rights.
    READ_ONLY = %w[GET].freeze

    # `allow` is the method list the CONTROLLER computed for this actor+record —
    # rest_send_allow_header()'s value, mirrored into `_links.self[0].targetHints.allow`.
    # Access is deliberately NOT reached from here (BR-CAP-05: the controller is the
    # only layer that touches Access), so the answer arrives already decided.
    def initialize(term, allow: READ_ONLY)
      @term = term
      @taxonomy = term.taxonomy&.name.to_s
      @allow = Array(allow)
    end

    def self.collection(terms, allow: READ_ONLY) = terms.map { |t| new(t, allow: allow).as_json }

    def as_json
      json = {
        id: term.id,
        count: term.count.to_i,
        description: term.description.to_s,
        link: Entity.links.term_link(term),
        name: term.name.to_s,
        slug: term.slug.to_s,
        taxonomy: @taxonomy
      }
      json[:parent] = term.parent_id.to_i if hierarchical?
      json[:meta] = []
      json[:_links] = links_for
      json
    end

    private

    attr_reader :term

    def hierarchical? = term.taxonomy&.hierarchical?
    def rest_base = REST_BASE.fetch(@taxonomy, @taxonomy)

    def links_for
      base_href = Url.rest("/wp/v2/#{rest_base}")
      out = {
        self: [{ href: "#{base_href}/#{term.id}", targetHints: { allow: @allow } }],
        collection: [{ href: base_href }],
        about: [{ href: Url.rest("/wp/v2/taxonomies/#{@taxonomy}") }]
      }
      if hierarchical? && term.parent_id.to_i.positive?
        out[:up] = [{ embeddable: true, href: "#{base_href}/#{term.parent_id}" }]
      end
      out[:"wp:post_type"] = [{ href: Url.rest("/wp/v2/posts?#{POST_FILTER.fetch(@taxonomy, @taxonomy)}=#{term.id}") }]
      out[:curies] = Entity.curies
      out
    end
  end
end
