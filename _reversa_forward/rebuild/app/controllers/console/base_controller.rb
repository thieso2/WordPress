# frozen_string_literal: true

module Console
  # The administration console surface (wp-admin/*), modernized mode
  # (target_screens.md § Part 1, screen_modernization_decision.md). One controller base
  # for every /console screen: the single auth gate, the ConsoleLayout chrome, and
  # `current_actor` resolved from the session cookie Wave 3 built.
  #
  # A delivery surface, so — with the other console controllers, the auth controllers and
  # the views — one of the ONLY places allowed to depend on Access (target_architecture.md
  # Note 2). bin/check_cycles is what keeps that true; nothing under app/models reaches up
  # into a policy.
  #
  # This is the reconciled foundation base (tasks #9/#20): it carries both the P-LIST
  # chrome (menu, screen title, list gate) and the P-EDIT track's per-record helpers
  # (authorize!, deny!, not_found!), so both families of console screens share one door.
  class BaseController < ApplicationController
    include Auth::SessionCookie

    layout "console"

    # ⚠️ Ordering matters. ApplicationController runs `enforce_authorization_declaration`
    # (AD-04) as its own before_action; for a console route declared `:policy` or
    # `:authenticated` an UNAUTHENTICATED actor would fail and get a bare 403. But the
    # legacy's auth_redirect() (wp-admin/admin.php:104-106, BR-MIGRATE-325) redirects an
    # unauthenticated console request to the login screen — with the requested URL in
    # redirect_to and reauth=1 so the login screen clears any stale cookie first — BEFORE
    # any capability is consulted. Prepending puts this ahead of the inherited check:
    # logged out → redirect to /login; logged in but unauthorized → 403.
    prepend_before_action :auth_redirect

    # Never index or cache the console (admin-header.php: wp_robots_sensitive_page +
    # nocache_headers).
    before_action :no_store_console

    helper_method :console_menu, :console_page_title, :current_actor, :current_screen, :site_title

    LOGIN_PATH = "/login"

    private

    # is_admin() is true across the whole console, so determine_locale() resolves to the
    # signed-in user's locale (BR-I18N-04 / BR-MIGRATE-286). `locale_user` is current_actor,
    # already resolved from the session cookie above.
    def admin_surface? = true

    # `get_bloginfo( 'name', 'display' )`. The shared ConsoleLayout prints it in the
    # <title>; Auth::BaseController exposes the same helper for the login chrome, and the
    # console needs its own since it does not descend from Auth. Already HTML-escaped at
    # rest (BR-MIGRATE-014), so `site_name`/`Setting.display` marks it safe.
    def site_title = site_name

    # auth_redirect(), wp-admin/admin.php:100-140. `wp_safe_redirect( wp_login_url(
    # $_SERVER['REQUEST_URI'], true ) )` — /login?redirect_to=<path>&reauth=1.
    def auth_redirect
      return if current_actor.present?

      redirect_to "#{LOGIN_PATH}?#{URI.encode_www_form(redirect_to: request.fullpath, reauth: '1')}",
                  status: :found
    end

    # ── Chrome (P-LIST + every console screen) ──────────────────────────────────────
    #
    # The legacy admin menu is hook-assembled in wp-admin/menu.php; AD-01 removes the
    # hooks, so the top-level menu is a DECLARED structure (DEV-002), one entry per built
    # screen. Each entry names the capability that reveals it, evaluated through Access
    # exactly as the list pages are gated — so a contributor sees Posts and Media but not
    # Users, as on the oracle.
    MENU = [
      { key: "console.index",         label: "Dashboard",  path: "/console",                capability: nil },
      { key: "console.edit",          label: "Posts",      path: "/console/posts",          capability: "edit_posts" },
      { key: "console.upload",        label: "Media",      path: "/console/media",          capability: "upload_files" },
      { key: "console.edit-pages",    label: "Pages",      path: "/console/pages",          capability: "edit_pages" },
      { key: "console.edit-comments", label: "Comments",   path: "/console/comments",       capability: "edit_posts" },
      { key: "console.edit-tags",     label: "Categories", path: "/console/terms/category", capability: "manage_categories" },
      { key: "console.users",         label: "Users",      path: "/console/users",          capability: "list_users" }
    ].freeze

    def console_menu
      MENU.select do |entry|
        entry[:capability].nil? || site_can?(entry[:capability])
      end
    end

    # The screen <title> / <h1> — a LITERAL string from the legacy. Both names resolve to
    # @page_title so P-LIST and the P-EDIT track set the same ivar.
    def console_page_title = @page_title.to_s

    # The legacy `console.*` screen id, for body classes / test hooks. Set @screen in the
    # action; defaults from the controller name.
    def current_screen = @screen.presence || "console.#{controller_name}"

    # A site-wide capability check through Access::SitePolicy — the record-less arm, the
    # same primitive a route's own declaration names. The one door the list controllers
    # reach Access through for menu/gate questions.
    def site_can?(capability)
      Access::SitePolicy.new(current_actor, nil).permit?(capability)
    end

    # ── Per-record authorization (P-EDIT + row/bulk actions) ────────────────────────
    #
    # current_user_can( $meta_cap, $id ) through the object policy, the way a surface may
    # (target_architecture.md Note 2). Owner override 1 (BR-CAP-05) is in force: a policy
    # arm emitting no capabilities ALLOWS. On denial the legacy calls wp_die() with a
    # verbatim message and a 403; `deny!` reproduces that.
    def authorize!(policy_class, record, action, message)
      return true if policy_class.new(current_actor, record).permit?(action)

      deny!(message)
    end

    # Whether the actor may perform `action` on `record` under `policy_class` — the
    # boolean the list controllers use to decide which row/bulk actions to render (the
    # view never asks Access; the controller resolves it, BR-CAP-05).
    def can?(policy_class, record, action)
      policy_class.new(current_actor, record).permit?(action)
    end

    # wp_die( $message, 403 ) — the admin's "Sorry, you are not allowed to…" page,
    # reduced to a small forbidden document carrying the legacy's verbatim message.
    def deny!(message)
      @message = message
      render "console/shared/forbidden", status: :forbidden
      false
    end

    # A record named in the URL that does not exist is the admin's "invalid item" wp_die,
    # answered here as a 404 so a bad id cannot leak as a 500.
    def not_found!(message)
      @message = message
      render "console/shared/not_found", status: :not_found
      false
    end

    def no_store_console
      response.headers["Cache-Control"] = "no-cache, must-revalidate, max-age=0, no-store, private"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
  end
end
