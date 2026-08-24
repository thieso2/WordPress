# frozen_string_literal: true

# T-09, closed. Wave 0's seeding pipeline COUNTED `wp_global_styles`, `wp_font_family`
# and `wp_font_face` rows and deliberately did not load them, because the `styling` pack
# is a leaf with zero dependencies and therefore owns no table
# (lib/seeding/pipeline.rb:703). The pack expresses persistence as the
# `Styling::GlobalStylesStore` interface instead; this migration gives the Rails app the
# storage that interface is implemented over.
#
# Two columns, both on `themes`, because both belong to a theme and to nothing else:
#
#   * `theme_json` — the theme's OWN theme.json, i.e. the 'theme' origin of the
#     four-origin cascade (BR-MIGRATE-206). In the legacy this is a FILE read on every
#     request through WP_Theme_JSON_Resolver::get_theme_data(); here it is loaded once by
#     `rake theme:load` so that a request never touches the theme directory.
#   * `user_styles` — the 'custom' origin, the legacy's single `wp_global_styles` post per
#     theme (BR-MIGRATE-208). One row per theme is exactly what the legacy enforces, so a
#     column on `themes` says it structurally instead of by convention.
#
# ⚠️ NOT a settings row. AD-06 removed three of `options`' four responsibilities precisely
# so that unrelated documents stop sharing a table with the site title.
class AddThemeDocumentsToThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :themes, :theme_json, :jsonb, null: false, default: {}
    add_column :themes, :user_styles, :jsonb, null: true

    # The templates table already carries (theme_slug, slug, kind); a title is what
    # _build_block_template_result_from_file() sets from the theme's theme.json /
    # get_default_block_template_types() (block-template-utils.php:615). Resolution never
    # reads it, but dropping it would lose a fact the source carries.
    add_column :templates, :title, :text, null: false, default: ""

    # `patterns` gains the two header fields the theme's pattern files declare that the
    # Wave 0 table had no column for: `Description` and `Inserter`
    # (WP_Block_Patterns_Registry). Both are part of the document, not of its rendering.
    add_column :patterns, :description, :text, null: false, default: ""
    add_column :patterns, :inserter, :boolean, null: false, default: true

    add_index :templates, %i[theme_slug kind slug], unique: true,
              name: "index_templates_on_theme_kind_slug"
  end
end
