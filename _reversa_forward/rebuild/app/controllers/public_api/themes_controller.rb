# frozen_string_literal: true

module PublicApi
  # /wp/v2/themes — WP_REST_Themes_Controller.
  #
  # The site editor's first question: which theme am I editing, and what does it support?
  # `?status=active` is the only filter this surface serves, because it is the only one
  # with an answer here — DEV-011 kept themes as DATA, and an INACTIVE theme is a row
  # nobody rendered from and whose files were never read (`rake theme:sync` loads exactly
  # one). Asking for anything else says so rather than inventing an empty list.
  #
  # ⚠️ The response's split brain, and why it is honest. `stylesheet`, `template`,
  # `version`, `name` and `status` come from Presentation::Theme — the row. Everything
  # else (`description`, `author`, `tags`, `requires_php`, `theme_supports`,
  # `default_template_types`…) is a fact about the theme's FILES, which the rebuild does
  # not store because nothing else reads it: it is generated data, read through
  # Presentation::ThemeSiteData exactly the way Presentation::Assets reads the head's
  # stylesheets. See the header of `rake theme:site_data:generate`.
  #
  # Permission: `switch_themes` OR `manage_network_themes` OR `edit_posts`
  # (WP_REST_Themes_Controller::get_items_permissions_check, :90-107). The oracle's refusal
  # is the theme-specific `rest_cannot_view_active_theme`, not the generic one.
  class ThemesController < BaseController
    permission :index, :read_active_theme

    def index
      status = params[:status].presence
      unless status.nil? || Array(status).include?("active") || status.to_s == "active"
        # Only the active theme exists as a rendered object here (see the class note).
        return render_json([])
      end

      theme = Presentation::Theme.active.first
      return render_json([]) if theme.nil?

      render_json([serialize(theme)])
    end

    private

    def read_active_theme
      allowed = current_actor && (
        Access::SitePolicy.new(current_actor, nil).permit?(:switch_themes) ||
        Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts)
      )
      return true if allowed

      raise PublicApi::RestError.new("rest_cannot_view_active_theme",
                                     "Sorry, you are not allowed to view the active theme.",
                                     current_actor ? 403 : 401)
    end

    # WP_REST_Themes_Controller::prepare_item_for_response(), in the field order the
    # oracle emits.
    def serialize(theme)
      meta = Presentation::ThemeSiteData.theme_for(theme.slug) || {}
      {
        stylesheet: theme.slug,
        template: (meta["template"].presence || theme.parent_slug.presence || theme.slug),
        requires_php: meta["requires_php"].to_s,
        requires_wp: meta["requires_wp"].to_s,
        textdomain: meta["textdomain"].to_s,
        # The ROW is authoritative for the version — it is what `theme:load` wrote and what
        # every other surface reads.
        version: theme.version.to_s,
        screenshot: absolute(meta["screenshot"]),
        author: rich(meta["author"]),
        author_uri: rich(meta["author_uri"]),
        description: rich(meta["description"]),
        name: rich(meta["name"], raw_fallback: theme.name),
        tags: rich(meta["tags"]),
        theme_uri: rich(meta["theme_uri"]),
        status: theme.active? ? "active" : "inactive",
        theme_supports: meta["theme_supports"] || {},
        is_block_theme: meta.fetch("is_block_theme", true),
        stylesheet_uri: absolute(meta["stylesheet_uri"]),
        template_uri: absolute(meta["template_uri"]),
        default_template_types: default_template_types,
        default_template_part_areas: Presentation::ThemeSiteData.default_template_part_areas,
        _links: links(theme)
      }
    end

    # `get_default_block_template_types()` is a slug-keyed map; the controller flattens it
    # to a list with `slug` folded in (:809-816).
    def default_template_types
      Presentation::ThemeSiteData.default_template_types.map do |slug, type|
        { title: type["title"], description: type["description"], slug: slug.to_s }
      end
    end

    # The `$rich_field_mappings` pairs — `{raw, rendered}` for every header that carries
    # markup (`$theme->display( $header )` applies the theme's own markup filters, which
    # is why `author` renders as a link and `tags` renders as a comma list).
    def rich(value, raw_fallback: nil)
      return { raw: raw_fallback.to_s, rendered: raw_fallback.to_s } if value.nil?
      return value if value.is_a?(Hash) && value.key?("raw")

      { raw: value, rendered: value }
    end

    # The generated data stores the three URL fields site-relative so they render against
    # THIS site's home, not the oracle's host.
    def absolute(path)
      value = path.to_s
      return "" if value.empty?
      return value if value.start_with?("http://", "https://")

      "#{Url.home}#{value}"
    end

    def links(theme)
      {
        self: [{ href: Url.rest("/wp/v2/themes/#{theme.slug}"), targetHints: { allow: %w[GET] } }],
        collection: [{ href: Url.rest("/wp/v2/themes") }],
        "wp:user-global-styles": [{ href: Url.rest("/wp/v2/global-styles/#{user_global_styles_id(theme)}") }],
        curies: Entity.curies
      }
    end

    # BR-MIGRATE-208/209: the user layer's record is CREATED on first access, which is
    # what makes this link always resolvable — the site editor follows it immediately.
    def user_global_styles_id(theme)
      store = Presentation::GlobalStyles.new
      record = store.find_for_theme(theme.slug) || store.create_for_theme(theme.slug)
      record && record["id"]
    end
  end
end
