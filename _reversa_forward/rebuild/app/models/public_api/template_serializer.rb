# frozen_string_literal: true

module PublicApi
  # A Composition::Template as WP_REST_Templates_Controller::prepare_item_for_response()
  # emits it — the same serialiser for `wp_template` and `wp_template_part`, because the
  # legacy uses one controller for both and differs only in two conditional fields
  # (`is_custom` on templates, `area` on parts, :768/:775).
  #
  # ⚠️ Every template the rebuild holds for the active theme is FILE-BACKED: `theme:sync`
  # loads `templates/*.html` and `parts/*.html` into the table, and nothing writes them
  # back (the Site Editor's save path is Console::SiteEditorController, a separate track).
  # So `source`/`origin`/`wp_id`/`author`/`modified`/`date` are the legacy's values for a
  # template that has never been customised — 'theme', null, 0, 0, null, null — and
  # `original_source` is 'theme' by :846's first arm. When the write path lands, those
  # become row state; they are constants here because they are constants in the data.
  class TemplateSerializer
    # get_default_block_template_types() is the table `description` comes from and the
    # test `is_custom` performs: a slug the table does not name is a theme's own
    # `customTemplates` entry (block-template-utils.php,
    # `_build_block_template_result_from_file`).
    def initialize(template, part: nil)
      @template = template
      @part = part.nil? ? template.kind == "part" : part
    end

    def as_json
      data = {
        id: id,
        theme: @template.theme_slug,
        # :684-690 — `core/pattern` references are EXPANDED before the response is built,
        # "so they don't need to be resolved client-side in the editor". Six of the eight
        # templates this theme ships are one such reference; without the pass the editor
        # opens an empty canvas. Composition::PatternResolver is the port.
        content: { raw: Composition::PatternResolver.resolve_content(@template.content.to_s) },
        slug: @template.slug,
        source: "theme",
        origin: nil,
        type: type,
        description: description,
        title: { raw: title, rendered: title },
        status: "publish",
        wp_id: 0,
        has_theme_file: true
      }
      data[:is_custom] = custom? unless part?
      data[:author] = 0
      data[:area] = @template.area.to_s.presence || "uncategorized" if part?
      data[:modified] = nil
      data[:date] = nil
      data[:author_text] = author_text
      data[:original_source] = "theme"
      data[:_links] = links
      data
    end

    # `$_wp_current_template_id` — "<theme>//<slug>" (block-template.php:93).
    def id = "#{@template.theme_slug}//#{@template.slug}"

    private

    def part? = @part
    def type = part? ? "wp_template_part" : "wp_template"
    def rest_base = part? ? "template-parts" : "templates"

    def title = @template.title.to_s.presence || @template.slug.to_s

    # A part carries no description in the legacy either — the field exists on the shared
    # schema and is empty for every `wp_template_part`.
    def description
      return "" if part?

      Presentation::ThemeSiteData.default_template_types.dig(@template.slug, "description").to_s
    end

    def custom? = !Presentation::ThemeSiteData.default_template_types.key?(@template.slug)

    # :900 — for a theme-original template the author text is the THEME's display name,
    # falling back to its slug when the theme has no Name header.
    def author_text
      theme = Presentation::Theme.find_by(slug: @template.theme_slug)
      theme&.name.presence || @template.theme_slug.to_s
    end

    # get_available_actions(): `wp:action-publish` needs the type's publish cap and
    # `wp:action-unfiltered-html` needs `unfiltered_html`. Both routes into this
    # serialiser are gated on `edit_theme_options`, which on a single site only the
    # administrator role holds — and the administrator holds the other two as well
    # (Access::RoleCatalogue). So for every caller who can reach this, both links are
    # present; they are emitted unconditionally rather than recomputed per request.
    def links
      self_href = Url.rest("/wp/v2/#{rest_base}/#{id}")
      {
        self: [{ href: self_href, targetHints: { allow: %w[GET POST PUT PATCH DELETE] } }],
        collection: [{ href: Url.rest("/wp/v2/#{rest_base}") }],
        about: [{ href: Url.rest("/wp/v2/types/#{type}") }],
        "wp:action-publish": [{ href: self_href }],
        "wp:action-unfiltered-html": [{ href: self_href }],
        curies: Entity.curies
      }
    end
  end
end
