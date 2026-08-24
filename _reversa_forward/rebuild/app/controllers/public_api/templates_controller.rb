# frozen_string_literal: true

module PublicApi
  # /wp/v2/templates — WP_REST_Templates_Controller over Composition::Template (AD-02 split
  # `wp_template` out of `wp_posts`; the rows are the same documents, in a table that says
  # what they are).
  #
  # Three actions: the collection, one template by its `<theme>//<slug>` id, and `lookup`,
  # which resolves a SLUG through the template hierarchy and answers with the single best
  # match (Presentation::TemplateLookup — the hierarchy lives there, and the resolution
  # step is Presentation::TemplateResolver's, reused rather than rewritten).
  #
  # ⚠️ The collection is scoped to the ACTIVE theme, exactly as `get_block_templates()` is:
  # it filters by the `wp_theme` term, and the seeded rows this rebuild carries under other
  # theme slugs have no such term. Verified against the oracle, which reports 8 templates
  # for twentytwentyfive and never the seeded pair.
  #
  # ⚠️ ORDER is a deliberate deviation, and the only one. The legacy returns templates in
  # the order the filesystem enumerated `templates/*.html`, which is not a fact this
  # rebuild can hold (there is no filesystem in the request path — that is the whole point
  # of AD-02). Rows come back ordered by slug, deterministically. No consumer of this
  # endpoint depends on order; the editor keys everything by id.
  #
  # Permission: `edit_theme_options` (WP_REST_Templates_Controller::
  # get_items_permissions_check → `rest_cannot_manage_templates`).
  class TemplatesController < BaseController
    permission :index, :manage_templates
    permission :show, :manage_templates
    permission :lookup, :manage_templates

    KIND = "template"

    def index
      render_json(scope.order(:slug).map { |t| serialize(t) })
    end

    def show
      render_json(serialize(loaded_template))
    end

    # GET /wp/v2/templates/lookup?slug=…&is_custom=…&template_prefix=…
    #
    # :168 — "To maintain original behavior, return an empty object rather than a 404 error
    # when no template is found." An EMPTY OBJECT, not an error and not null: the editor
    # branches on the absence of `id`.
    def lookup
      slug = params[:slug].to_s
      if slug.empty?
        raise PublicApi::RestError.new("rest_missing_callback_param",
                                       "Missing parameter(s): slug", 400, { params: ["slug"] })
      end

      template = Presentation::TemplateLookup.new(theme_slug: active_theme_slug).resolve(
        slug, is_custom: truthy?(params[:is_custom]), template_prefix: params[:template_prefix]
      )
      render_json(template ? serialize(template) : {})
    end

    private

    def manage_templates
      return true if current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_theme_options)

      raise PublicApi::RestError.new("rest_cannot_manage_templates",
                                     "Sorry, you are not allowed to access the templates on this site.",
                                     current_actor ? 403 : 401)
    end

    def active_theme_slug = @active_theme_slug ||= Presentation::Theme.active_slug

    def scope
      Composition::Template.where(kind: self.class::KIND, theme_slug: active_theme_slug)
    end

    def serialize(template) = TemplateSerializer.new(template, part: self.class::KIND == "part").as_json

    # The id is `<theme>//<slug>` — two slashes, so it arrives through a glob segment.
    #
    # ⚠️ The SINGLE-slash form is accepted too, and that is deliberate rather than lax.
    # An empty path segment is legal in a URI but is collapsed by a great many things
    # between the editor and this action — Rails' own `recognize_path`, rack-test, and
    # every reverse proxy that normalises `//`. WP explodes on `//` and 404s otherwise;
    # here the split falls back to the FIRST slash, which cannot mis-resolve because a
    # theme stylesheet slug never contains one. A template that genuinely does not exist
    # still answers rest_template_not_found.
    def loaded_template
      @loaded_template ||= begin
        raw = params[:id].to_s
        theme_slug, slug = raw.include?("//") ? raw.split("//", 2) : raw.split("/", 2)
        record = slug.present? ? scope.find_by(theme_slug: theme_slug, slug: slug) : nil
        raise PublicApi::RestError.new("rest_template_not_found",
                                       "No templates exist with that id.", 404) if record.nil?

        record
      end
    end

    # rest_sanitize_boolean() on the `is_custom` arg.
    def truthy?(value)
      return false if value.nil?

      !%w[0 false].include?(value.to_s.strip.downcase) && !value.to_s.strip.empty?
    end
  end
end
