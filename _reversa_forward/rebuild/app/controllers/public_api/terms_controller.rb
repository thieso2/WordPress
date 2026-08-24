# frozen_string_literal: true

module PublicApi
  # /wp/v2/categories and /wp/v2/tags — WP_REST_Terms_Controller. Public collection
  # (BR-REST-05); the item registers a `read_item` callback so a missing id is
  # rest_term_invalid (404). REST default is orderby=name asc, hide_empty=false — every
  # term, count-0 included.
  class TermsController < BaseController
    include CollectionPagination

    permission :show, :read_item

    TAXONOMY = nil # subclass sets it.

    def index
      scope = term_scope.order(Arel.sql("LOWER(terms.name) ASC"), :id)
      total = scope.count
      records = scope.offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/#{rest_base}")
      render_json(records.map { |t| TermSerializer.new(t).as_json })
    end

    def show
      render_json(TermSerializer.new(loaded_term).as_json)
    end

    private

    def term_scope
      Classification::Term.joins(:taxonomy).where(taxonomies: { name: self.class::TAXONOMY })
                          .includes(:taxonomy)
    end

    def rest_base = TermSerializer::REST_BASE.fetch(self.class::TAXONOMY)

    def read_item
      loaded_term
      true
    end

    def loaded_term
      @loaded_term ||= term_scope.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_term_invalid", "Term does not exist.", 404))
    end
  end
end
