# frozen_string_literal: true

module Console
  # console.site-editor — wp-admin/site-editor.php. The Site Editor React island
  # (DEV-012, D-3). site-editor.php loads the block-editor bundle scoped to templates,
  # template parts and Global Styles across the theme.json four-origin cascade
  # (target_screens.md § The editor). DEV-002 folds the Customizer, widgets and the header/
  # background screens in here.
  #
  # The island (app/frontend/site_editor/*) mounts on #show. Its server half:
  #   * #templates_index  — the template/part browser (Composition::Template).
  #   * #template_blocks  — one template's content parsed into the block tree.
  #   * #update_template  — save a block tree back to template.content, serialized SERVER-
  #                         SIDE through Composition::Serializer (the one verified grammar).
  #   * #styles           — the theme's user Global Styles (themes.user_styles, the 'custom'
  #                         origin of the cascade — BR-MIGRATE-208, ONE row per theme).
  #   * #update_styles    — save the user styles layer.
  #
  # Template editing reuses the very same block canvas as the post editor: a template IS a
  # document of block markup (AD-02 split wp_template/-part/wp_navigation out of wp_posts),
  # so the parse/serialize round-trip and the React block components are shared verbatim.
  class SiteEditorController < ApplicationController
    include Console::EditorAuthGate

    layout "editor"

    before_action :authorize_theme_options!
    before_action :load_template, only: %i[template_blocks update_template]

    # GET /console/site-editor — mounts the island. The template list is also inlined as a
    # noscript fallback (an honest read-only inventory when JS is off).
    def show
      @editor_island = true
      @templates = ordered_templates("template")
      @parts = ordered_templates("part")
    end

    # GET /console/site-editor/templates — the browser data for the island.
    def templates_index
      render json: {
        active_theme: Presentation::Theme.active_slug,
        templates: ordered_templates("template").map { |t| template_summary(t) },
        parts: ordered_templates("part").map { |t| template_summary(t) }
      }
    end

    # GET /console/site-editor/templates/:id/blocks
    def template_blocks
      render json: {
        id: @template.id,
        title: @template.title.presence || @template.slug,
        slug: @template.slug,
        kind: @template.kind,
        area: @template.area,
        blocks: tree_json(Composition::Parser.parse(@template.content.to_s))
      }
    end

    # PATCH /console/site-editor/templates/:id — save the edited block tree.
    def update_template
      payload = json_body
      @template.content = Composition::Serializer.serialize(Array(payload["blocks"]))
      @template.title = payload["title"].to_s if payload.key?("title")
      @template.save!
      render json: { ok: true, id: @template.id, notice: "Template saved." }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    # GET /console/site-editor/styles — the user Global Styles layer + the palette/typography
    # the theme exposes, so the panel can offer the theme's own tokens.
    def styles
      theme = active_theme_record
      user = theme&.user_styles || {}
      render json: {
        theme: theme&.slug,
        user_styles: user,
        settings: theme_settings(theme)
      }
    end

    # PATCH /console/site-editor/styles — persist the user layer (themes.user_styles).
    def update_styles
      theme = active_theme_record
      return render(json: { ok: false, errors: ["No active theme."] }, status: :unprocessable_content) if theme.nil?

      payload = json_body
      raw = payload["user_styles"]
      # An explicit null (or an empty object) CLEARS the user layer back to NULL — the
      # un-customized state. Storing {} instead would add an empty 'custom' origin to the
      # cascade, which is observably different from having no user layer at all.
      cleared = raw.nil? || (raw.is_a?(Hash) && (raw.empty? || raw.fetch("styles", nil).blank?))
      theme.update!(user_styles: cleared ? nil : deep_stringify(raw))
      render json: { ok: true, notice: "Styles saved." }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    private

    def ordered_templates(kind)
      Composition::Template.where(kind: kind, theme_slug: theme_slugs).order(:area, :slug).to_a
    end

    # The active theme and its ancestry (child + parent), so an inherited template shows up.
    def theme_slugs
      active = Presentation::Theme.active.first
      return [] if active.nil?
      slugs = active.respond_to?(:ancestry) ? active.ancestry.map { |t| t.respond_to?(:slug) ? t.slug : t } : [active.slug]
      slugs.uniq
    end

    def active_theme_record = Presentation::Theme.active.first

    def template_summary(t)
      { id: t.id, slug: t.slug, title: t.title.presence || t.slug, area: t.area, kind: t.kind,
        theme_slug: t.theme_slug, wp_id: "#{t.theme_slug}//#{t.slug}" }
    end

    def theme_settings(theme)
      return {} if theme.nil?
      # resolver.merged_data is a Styling::ThemeJson wrapping the resolved four-origin
      # theme.json; .raw_data is the hash. The palette lives at settings.color.palette.
      raw = theme.resolver.merged_data.raw_data rescue nil
      { color_palette: dig_palette(raw), font_sizes: dig_font_sizes(raw) }
    rescue StandardError
      {}
    end

    def dig_palette(raw)
      return [] unless raw.is_a?(Hash)
      pal = raw.dig("settings", "color", "palette")
      pal = pal.values.flatten if pal.is_a?(Hash) # origin-keyed
      Array(pal).filter_map { |c| c.is_a?(Hash) ? { "slug" => c["slug"], "color" => c["color"], "name" => c["name"] } : nil }
    end

    def dig_font_sizes(raw)
      return [] unless raw.is_a?(Hash)
      fs = raw.dig("settings", "typography", "fontSizes")
      fs = fs.values.flatten if fs.is_a?(Hash)
      Array(fs).filter_map { |c| c.is_a?(Hash) ? { "slug" => c["slug"], "size" => c["size"], "name" => c["name"] } : nil }
    end

    def load_template
      @template = Composition::Template.find(params[:id])
    end

    def tree_json(blocks)
      blocks.map do |b|
        { name: b.block_name, attrs: b.attrs || {}, innerHTML: b.inner_html.to_s,
          innerContent: b.inner_content, innerBlocks: tree_json(b.inner_blocks || []) }
      end
    end

    def json_body
      return {} if request.raw_post.blank?
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end

    def deep_stringify(obj)
      case obj
      when Hash then obj.to_h { |k, v| [k.to_s, deep_stringify(v)] }
      when Array then obj.map { |v| deep_stringify(v) }
      else obj
      end
    end

    def authorize_theme_options!
      return if Access::SitePolicy.new(current_actor, nil).permit?(:edit_theme_options)

      head :forbidden
    end
  end
end
