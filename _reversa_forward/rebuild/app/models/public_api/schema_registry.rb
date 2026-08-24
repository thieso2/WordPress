# frozen_string_literal: true

module PublicApi
  # The `/wp/v2/types`, `/wp/v2/taxonomies` and `/wp/v2/statuses` endpoints are pure
  # metadata: they describe the object types the server knows about, not stored rows.
  #
  # DEV-002 (AD-01 removed hooks): where the legacy builds these lists by walking the
  # runtime registries that `register_post_type()`, `register_taxonomy()` and
  # `register_post_status()` populate through hooks, this migration DECLARES them as a
  # frozen table. The set is fixed for this corpus (WordPress core with no plugins), and
  # a plugin can no longer add to it, so the declaration IS the observable contract.
  #
  # Values transcribed field-by-field from the live oracle's `/wp/v2/{types,taxonomies,
  # statuses}` responses (get_post_type_object() / get_taxonomy() /
  # WP_REST_Post_Statuses_Controller::prepare_item_for_response()).
  module SchemaRegistry
    module_function

    # ── Post types (show_in_rest ⇒ present in /wp/v2/types) ──────────────────────
    # rest_base -> collection segment; icon is the dashicon or null.
    TYPES = {
      "post" => { name: "Posts", slug: "post", description: "", hierarchical: false,
                  has_archive: false, icon: "dashicons-admin-post",
                  taxonomies: %w[category post_tag], rest_base: "posts" },
      "page" => { name: "Pages", slug: "page", description: "", hierarchical: true,
                  has_archive: false, icon: "dashicons-admin-page",
                  taxonomies: [], rest_base: "pages" },
      "attachment" => { name: "Media", slug: "attachment", description: "", hierarchical: false,
                        has_archive: false, icon: "dashicons-admin-media",
                        taxonomies: [], rest_base: "media" },
      "nav_menu_item" => { name: "Navigation Menu Items", slug: "nav_menu_item", description: "",
                           hierarchical: false, has_archive: false, icon: nil,
                           taxonomies: %w[nav_menu], rest_base: "menu-items" },
      "wp_block" => { name: "Patterns", slug: "wp_block", description: "", hierarchical: false,
                      has_archive: false, icon: nil, taxonomies: %w[wp_pattern_category],
                      rest_base: "blocks" },
      "wp_template" => { name: "Templates", slug: "wp_template",
                         description: "Templates to include in your theme.", hierarchical: false,
                         has_archive: false, icon: nil, taxonomies: [], rest_base: "templates" },
      "wp_template_part" => { name: "Template Parts", slug: "wp_template_part",
                              description: "Template parts to include in your templates.",
                              hierarchical: false, has_archive: false, icon: nil,
                              taxonomies: [], rest_base: "template-parts" },
      "wp_global_styles" => { name: "Global Styles", slug: "wp_global_styles",
                              description: "Global styles to include in themes.",
                              hierarchical: false, has_archive: false, icon: nil,
                              taxonomies: [], rest_base: "global-styles" },
      "wp_navigation" => { name: "Navigation Menus", slug: "wp_navigation",
                           description: "Navigation menus that can be inserted into your site.",
                           hierarchical: false, has_archive: false, icon: nil,
                           taxonomies: [], rest_base: "navigation" },
      "wp_font_family" => { name: "Font Families", slug: "wp_font_family", description: "",
                            hierarchical: false, has_archive: false, icon: nil,
                            taxonomies: [], rest_base: "font-families" },
      "wp_font_face" => { name: "Font Faces", slug: "wp_font_face", description: "",
                          hierarchical: false, has_archive: false, icon: nil, taxonomies: [],
                          rest_base: "font-families/(?P<font_family_id>[\\d]+)/font-faces" }
    }.freeze

    # ── Taxonomies (show_in_rest) ────────────────────────────────────────────────
    TAXONOMIES = {
      "category" => { name: "Categories", slug: "category", description: "", types: %w[post],
                      hierarchical: true, rest_base: "categories" },
      "post_tag" => { name: "Tags", slug: "post_tag", description: "", types: %w[post],
                      hierarchical: false, rest_base: "tags" },
      "nav_menu" => { name: "Navigation Menus", slug: "nav_menu", description: "",
                      types: %w[nav_menu_item], hierarchical: false, rest_base: "menus" },
      "wp_pattern_category" => { name: "Pattern Categories", slug: "wp_pattern_category",
                                 description: "", types: %w[wp_block], hierarchical: false,
                                 rest_base: "wp_pattern_category" }
    }.freeze

    # ── Post statuses ────────────────────────────────────────────────────────────
    # WP_REST_Post_Statuses_Controller: a status appears for the caller only when it is
    # `public` OR the caller can `edit_posts` (check_read_permission, :294). `publish` is
    # the only public status, so an anonymous caller sees exactly `{publish}` — verified
    # against the oracle. `date_floating` is true only for `draft`/`pending`/`auto-draft`.
    STATUSES = {
      "publish" => { name: "Published", public: true, queryable: true, slug: "publish",
                     date_floating: false, _public: true },
      "future"  => { name: "Scheduled", public: false, queryable: false, slug: "future",
                     date_floating: false, _public: false },
      "draft"   => { name: "Draft", public: false, queryable: false, slug: "draft",
                     date_floating: true, _public: false },
      "pending" => { name: "Pending", public: false, queryable: false, slug: "pending",
                     date_floating: true, _public: false },
      "private" => { name: "Private", public: false, queryable: false, slug: "private",
                     date_floating: false, _public: false }
    }.freeze
  end
end
