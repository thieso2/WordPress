# frozen_string_literal: true

module Presentation
  # The theme facts that live in the theme's FILES rather than in the cascade — read the
  # way Presentation::Assets reads db/theme/assets.json, and for the same reason: they are
  # generated data (`rake theme:site_data:generate`), never hand-written, so a WordPress or
  # theme update is a re-run rather than a re-read.
  #
  # ⚠️ Why these are not columns on `themes`. The table carries exactly what the four-origin
  # cascade needs (slug, parent, version, active, theme_json, user_styles). A description,
  # an author URI, a tag list and a `theme_supports` block are neither cascade inputs nor
  # anything the rebuild WRITES; they are a projection of style.css's header and of core's
  # `add_theme_support()` defaults. Adding six columns nothing updates would put a second
  # copy of the theme's own files in the database. AD-06's spirit, one layer up.
  #
  # The document is keyed by the ACTIVE theme's stylesheet; `for(slug)` returns nil for any
  # other, which is exactly the surface WP_REST_Global_Styles_Controller states out loud:
  # "This endpoint only supports the active theme for now."
  module ThemeSiteData
    PATH = Rails.root.join("db", "theme", "site_data.json")

    module_function

    def document
      @document ||= (File.exist?(PATH) ? JSON.parse(File.read(PATH)) : {}).freeze
    end

    def reset! = (@document = nil)

    # The frozen `/wp/v2/themes` item for the theme this data was generated from, or nil.
    def theme_for(stylesheet)
      theme = document["theme"]
      return nil if theme.nil? || theme["stylesheet"].to_s != stylesheet.to_s

      theme
    end

    # get_default_block_template_types() — slug => { title, description }.
    def default_template_types = document["default_template_types"] || {}

    # get_allowed_block_template_part_areas().
    def default_template_part_areas = document["default_template_part_areas"] || []

    # WP_Block_Pattern_Categories_Registry::get_all_registered().
    def block_pattern_categories = document["block_pattern_categories"] || []

    # WP_Theme_JSON_Resolver::get_style_variations() — the documents
    # `/global-styles/themes/<t>/variations` returns as-is.
    def style_variations = document["style_variations"] || []

    # The theme's block style-variation partials, in the shape
    # `WP_Theme_JSON_Resolver::get_theme_data()` injects them:
    # { "core/group" => { "section-1" => {…styles…} } }.
    def block_style_variations = document["block_style_variations"] || {}

    # The theme's `theme.json` with those partials injected under
    # `styles.blocks.<type>.variations.<slug>` — the 'theme' origin as the legacy
    # assembles it, which is what the cascade must be fed.
    #
    # ⚠️ Values stay in theme.json's `var:preset|…` spelling. Styling::ThemeJson's
    # constructor runs resolve_custom_css_format() over `styles`, so the rewrite to
    # `var(--wp--preset--…)` happens there, once, for every origin alike.
    def theme_json_with_variations(theme_json)
      partials = block_style_variations
      return theme_json if partials.empty?

      document = Marshal.load(Marshal.dump(theme_json.to_h))
      blocks = ((document["styles"] ||= {})["blocks"] ||= {})
      partials.each do |block_type, variations|
        node = (blocks[block_type] ||= {})
        existing = node["variations"] || {}
        node["variations"] = variations.merge(existing)
      end
      document
    end
  end
end
