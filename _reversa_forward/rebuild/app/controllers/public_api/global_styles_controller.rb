# frozen_string_literal: true

module PublicApi
  # /wp/v2/global-styles — WP_REST_Global_Styles_Controller. Three shapes, one cascade:
  #
  #   GET/PUT /wp/v2/global-styles/:id                     the USER layer  ('custom' origin)
  #   GET     /wp/v2/global-styles/themes/:stylesheet      the THEME layer (default+blocks+theme)
  #   GET     /wp/v2/global-styles/themes/:stylesheet/variations   the theme's style variations
  #
  # All three are answered from the four-origin cascade the rebuild already renders the
  # front end with (Styling::ThemeJsonResolver, BR-MIGRATE-206…210), so a value the editor
  # shows is the same value the page ships. Nothing here has its own copy of the merge.
  #
  # ⚠️ BR-MIGRATE-208: ONE user record per theme, which here is the `themes.user_styles`
  # COLUMN, not a row in a documents table. So `:id` is the theme's id, and
  # `Presentation::GlobalStyles` — the pack's persistence seam — is the only thing that
  # knows that. The record is created on first access (:209), which is what makes the
  # `wp:user-global-styles` link the themes endpoint hands out always resolvable.
  #
  # ⚠️ The theme endpoints serve the ACTIVE theme only. That is not a rebuild limitation:
  # "This endpoint only supports the active theme for now."
  # (class-wp-rest-global-styles-controller.php:565), answered with `rest_theme_not_found`.
  class GlobalStylesController < BaseController
    permission :show, :read_record
    permission :update, :edit_record
    permission :theme, :read_global_styles
    permission :variations, :read_global_styles

    # GET /wp/v2/global-styles/:id
    def show
      render_json(serialize_record(loaded_theme))
    end

    # PUT /wp/v2/global-styles/:id — the user layer, written back to `themes.user_styles`.
    def update
      theme = loaded_theme
      body = request_body
      config = user_config(theme)

      config["settings"] = deep_stringify(body["settings"]) if body.key?("settings")
      config["styles"] = deep_stringify(body["styles"]) if body.key?("styles")
      # BR-MIGRATE-210: the flag is what makes the document trusted at read time, so a
      # write must never drop it.
      config["isGlobalStylesUserThemeJSON"] = true
      config["version"] ||= Styling::ThemeJson::LATEST_SCHEMA

      theme.update!(user_styles: config)
      render_json(serialize_record(theme))
    end

    # GET /wp/v2/global-styles/themes/:stylesheet
    def theme
      theme = active_theme_or_404!
      merged = merged_theme_data(theme)
      render_json({
                    settings: merged.settings,
                    styles: merged.raw_data["styles"] || {},
                    _links: {
                      self: [{ href: Url.rest("/wp/v2/global-styles/themes/#{theme.slug}"),
                               targetHints: { allow: %w[GET] } }]
                    }
                  })
    end

    # GET /wp/v2/global-styles/themes/:stylesheet/variations — get_theme_items() returns
    # each variation document AS-IS (:648-659), so this is the frozen
    # `WP_Theme_JSON_Resolver::get_style_variations()` list, nothing more.
    def variations
      active_theme_or_404!
      render_json(Presentation::ThemeSiteData.style_variations)
    end

    private

    # ── permission callbacks (BR-CAP-05: only the controller touches Access) ──────────

    # `read_post` on a wp_global_styles post, which map_meta_cap resolves to the post
    # type's `read` cap — `edit_theme_options` (theme.php's register_post_type).
    def read_record
      loaded_theme # a bad id is rest_global_styles_not_found BEFORE any capability talk.
      if context == "edit" && !can_edit_theme_options?
        raise PublicApi::RestError.new("rest_forbidden_context",
                                       "Sorry, you are not allowed to edit this global style.",
                                       current_actor ? 403 : 401)
      end
      return true if can_edit_theme_options?

      raise PublicApi::RestError.new("rest_cannot_view",
                                     "Sorry, you are not allowed to view this global style.",
                                     current_actor ? 403 : 401)
    end

    def edit_record
      loaded_theme
      return true if can_edit_theme_options?

      raise PublicApi::RestError.new("rest_cannot_edit",
                                     "Sorry, you are not allowed to edit this global style.",
                                     current_actor ? 403 : 401)
    end

    # :523-552 — `edit_posts` OR any show_in_rest type's edit cap OR `edit_theme_options`.
    def read_global_styles
      return true if current_actor && (
        Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts) || can_edit_theme_options?
      )

      raise PublicApi::RestError.new("rest_cannot_read_global_styles",
                                     "Sorry, you are not allowed to access the global styles on this site.",
                                     current_actor ? 403 : 401)
    end

    def can_edit_theme_options?
      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_theme_options)
    end

    # ── records ──────────────────────────────────────────────────────────────────────

    def loaded_theme
      @loaded_theme ||= begin
        id = params[:id].to_i
        record = id.positive? ? Presentation::Theme.find_by(id: id) : nil
        raise not_found if record.nil?

        record
      end
    end

    def not_found
      PublicApi::RestError.new("rest_global_styles_not_found",
                               "No global styles config exists with that ID.", 404)
    end

    def active_theme_or_404!
      stylesheet = CGI.unescape(params[:stylesheet].to_s)
      record = Presentation::Theme.active.first
      if record.nil? || record.slug != stylesheet
        raise PublicApi::RestError.new("rest_theme_not_found", "Theme not found.", 404)
      end

      record
    end

    # The 'custom' origin's document, as stored — `{}` when the theme has no user layer
    # yet, which serialises as the empty `settings`/`styles` the oracle emits (:345-350).
    def user_config(theme)
      value = theme.user_styles
      return {} unless value.is_a?(Hash)
      return {} unless value["isGlobalStylesUserThemeJSON"] == true

      deep_stringify(value)
    end

    # `default` → `blocks` → `theme`, stopping there (:573). The theme origin's data is
    # its `theme.json` WITH the block style-variation partials injected, which is what
    # `WP_Theme_JSON_Resolver::get_theme_data()` feeds the merge — see
    # Presentation::ThemeSiteData#theme_json_with_variations.
    def merged_theme_data(theme)
      Styling::ThemeJsonResolver.new(
        store: Presentation::GlobalStyles.new,
        stylesheet: theme.slug,
        core_data: Styling::CoreThemeData::DATA,
        block_data: Presentation::GlobalStylesheet.block_data,
        theme_data: Presentation::ThemeSiteData.theme_json_with_variations(theme.theme_json || {})
      ).merged_data("theme")
    end

    def serialize_record(theme)
      config = user_config(theme)
      title = Styling::GlobalStylesStore::INITIAL_TITLE
      {
        id: theme.id,
        title: { raw: title, rendered: title },
        settings: config["settings"].presence || {},
        styles: config["styles"].presence || {},
        _links: record_links(theme)
      }
    end

    def record_links(theme)
      self_href = Url.rest("/wp/v2/global-styles/#{theme.id}")
      links = {
        self: [{ href: self_href, targetHints: { allow: %w[GET POST PUT PATCH] } }],
        about: [{ href: Url.rest("/wp/v2/types/wp_global_styles") }],
        "version-history": [{ count: 0, href: "#{self_href}/revisions" }]
      }
      # get_available_actions(): the action links are the caller's, not the record's.
      links[:"wp:action-publish"] = [{ href: self_href }] if can_edit_theme_options?
      if current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_css)
        links[:"wp:action-edit-css"] = [{ href: self_href }]
      end
      links[:curies] = Entity.curies
      links
    end

    def deep_stringify(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, deep_stringify(v)] }
      when Array then value.map { |v| deep_stringify(v) }
      else value
      end
    end

    def request_body
      parsed = request.request_parameters
      return parsed if parsed.is_a?(Hash) && parsed.any?

      raw = request.raw_post.to_s
      return {} if raw.empty?

      decoded = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      decoded.is_a?(Hash) ? decoded : {}
    end
  end
end
