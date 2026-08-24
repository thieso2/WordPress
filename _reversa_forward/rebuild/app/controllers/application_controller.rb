# frozen_string_literal: true

# The public delivery surface. target_architecture.md: surfaces are the ONLY things
# permitted to depend on Access -- everything below the surface must not.
class ApplicationController < ActionController::Base
  # ⚠️ AD-04. Every action resolves an authorization declaration before it runs. The
  # declaration may be `public`; it may not be absent. BR-REST-05 keeps an undeclared
  # route public at RUNTIME -- this only removes the accidental route to that outcome.
  before_action :enforce_authorization_declaration

  # ── Locale resolution (BR-I18N-01..05 / BR-MIGRATE-283..287) ────────────────────────
  #
  # determine_locale() (l10n.php:124) ran once per request off request globals; here the
  # decision is stated over facts the surface owns. Localization::Locale.determine holds the
  # precedence; the surface only supplies the four truths determine_locale() read from the
  # environment. The base surface is the FRONT END, so every predicate defaults to its
  # front-end answer (site locale); Console, Auth and PublicApi each override the one that
  # is true for them. The RESULT is stored per-request in Localization::Current (never a
  # process global -- implication 1) and I18n is pointed at it (absorbed catalogue machinery).
  before_action :resolve_request_locale

  private

  # `wp_lang` is passed on EVERY surface but honoured only when `login_surface?` is true --
  # that gating lives inside Localization::Locale.determine and IS the BR-I18N-02 security
  # boundary (a request-supplied locale before a user exists is a login-only affordance).
  def resolve_request_locale
    locale = Localization::Locale.determine(
      admin: admin_surface?,
      json_user_request: json_user_locale_request?,
      login_screen: login_surface?,
      user: locale_user,
      wp_lang_get: params[:wp_lang],
      wp_lang_cookie: cookies[:wp_lang]
    )
    Localization::Current.request_locale = locale
    Localization::Catalogue.reload_all(locale)
  end

  # Surface facts. The front end answers "no" to all three and resolves to the site locale;
  # each other surface overrides exactly the one predicate that is true for it.
  def admin_surface? = false
  def json_user_locale_request? = false
  def login_surface? = false
  def locale_user = current_actor

  # Rails dispatches HEAD to the GET action (ActionDispatch routing), and the boot check
  # in config/initializers/authorization_declarations.rb registers the routing table's
  # verbs -- so a declaration is keyed on GET and must be looked up as GET for a HEAD
  # request too. The legacy never branches on the method (wp-blog-header.php -> wp()):
  # HEAD runs the GET code path and the server drops the body.
  def route_identifier
    verb = request.head? ? "GET" : request.request_method
    "#{verb} #{controller_path}##{action_name}"
  end

  def enforce_authorization_declaration
    identifier = route_identifier
    unless Access::Declarations.declared?(identifier)
      # In development this is loud on purpose. config/initializers checks the whole
      # routing table at boot so it normally cannot get this far.
      raise Access::Declarations::Undeclared,
            "#{identifier} has no authorization declaration (AD-04). " \
            "Declare it explicitly -- `mode: :public` is a valid answer."
    end
    return if Access::Declarations.permits?(identifier, actor: current_actor)

    head :forbidden
  end

  # Wave 2 is the read path; there is no session surface until Wave 4.
  def current_actor = nil

  # `display` rather than `[]`: BR-MIGRATE-014 leaves these two already HTML-escaped at
  # rest, so escaping them again in the view renders the entities to the reader.
  def site_name
    Configuration::Setting.display("blogname").presence || "Reversa Rebuild"
  end

  def site_description = Configuration::Setting.display("blogdescription").to_s
  helper_method :site_name, :site_description

  # ── Wave 2: the block-theme render path ────────────────────────────────────────────
  #
  # wp-includes/template-loader.php is not a view; it is a DECISION followed by a render,
  # and the decision needs facts the controller already has. So the controller states the
  # facts (Presentation::Screen), and Presentation resolves the template and renders the
  # whole document. There are no ERB views on this path — the golden files are compared
  # byte for byte, and a layout would be a second, competing definition of `<head>`.
  def render_screen(screen, status: :ok, query: nil)
    # `request.fullpath` is $_SERVER['REQUEST_URI'] (path + query string) and
    # `request.query_parameters` is $_GET — the two request globals the query-loop
    # blocks read in the legacy (query_blocks.rb:28). Stated here, once, and passed
    # down; no renderer can reach for the ambient request.
    page = Presentation::Page.new(screen: screen, site_url: site_url, query: query,
                                  request_path: request.fullpath,
                                  request_params: request.query_parameters)
    render html: page.to_html.html_safe, status: status, layout: false # rubocop:disable Rails/OutputSafety
  end

  # `home_url()`. The absolute form is what the legacy prints in every self-link, and the
  # parity normalizer maps host+port to `<SITE>` on both sides (normalizer.rb:115).
  def site_url = "#{request.protocol}#{request.host_with_port}"

end
