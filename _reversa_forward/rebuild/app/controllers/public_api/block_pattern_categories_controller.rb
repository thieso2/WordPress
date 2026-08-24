# frozen_string_literal: true

module PublicApi
  # /wp/v2/block-patterns/categories — WP_REST_Block_Pattern_Categories_Controller.
  #
  # The inserter's category list: core's own twenty-one plus whatever the active theme
  # registers (twentytwentyfive adds `twentytwentyfive_page` and
  # `twentytwentyfive_post-format`). AD-01 means there is no registry to mutate at
  # runtime — the set is generated data alongside the patterns themselves
  # (`rake theme:site_data:generate`), which is the same discipline `theme:generate`
  # already applies to the 98 pattern documents.
  #
  # Permission: `edit_posts` (:get_items_permissions_check → `rest_cannot_view`).
  class BlockPatternCategoriesController < BaseController
    permission :index, :read_patterns

    def index
      render_json(Presentation::ThemeSiteData.block_pattern_categories.map do |category|
        { name: category["name"], label: category["label"], description: category["description"].to_s }
      end)
    end

    private

    def read_patterns
      return true if current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts)

      raise PublicApi::RestError.new(
        "rest_cannot_view",
        "Sorry, you are not allowed to view the registered block pattern categories.",
        current_actor ? 403 : 401
      )
    end
  end
end
