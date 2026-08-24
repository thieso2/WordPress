# frozen_string_literal: true

module PublicApi
  # /wp/v2/pages — the `page` subtype. Same controller shape as posts; the subtype
  # differences (parent, menu_order, no format/sticky/terms) live in PostSerializer.
  class PagesController < PostsController
    REST_BASE = "pages"
    POST_TYPE = "page"

    private

    def model_scope = Publishing::Page
  end
end
