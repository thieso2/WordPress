# frozen_string_literal: true

module PublicApi
  # /wp/v2/tags — the `post_tag` taxonomy.
  class TagsController < TermsController
    TAXONOMY = "post_tag"
  end
end
