# frozen_string_literal: true

module PublicApi
  # /wp/v2/categories — the `category` taxonomy.
  class CategoriesController < TermsController
    TAXONOMY = "category"
  end
end
