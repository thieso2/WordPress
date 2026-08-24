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
    # Authored against the LIVE oracle's own menu (tools/dump_menu.php dumps $menu/$submenu
    # as wp-admin builds them for a signed-in administrator), so the titles, the order and
    # the capability on every entry are observed rather than guessed. Titles are LITERAL.
    #
    # Three groups are absent on purpose, and their absence is a ruling, not a gap:
    #   · Plugins, Add Plugin, Plugin File Editor, Theme File Editor — AD-01 removed the
    #     extension system, so there is nothing for these screens to manage.
    #   · Updates / Fonts / Connectors-as-a-menu-item — no rebuild surface.
    #   · Menus appears under Appearance here though the oracle's block theme hides it;
    #     the rebuild builds the screen, so the navigation admits it.
    MENU = [
      { key: "console.index", label: "Dashboard", path: "/console", capability: nil,
        children: [{ key: "console.index", label: "Home", path: "/console", capability: nil }] },
      { separator: true },
      { key: "console.edit", label: "Posts", path: "/console/posts", capability: "edit_posts",
        children: [
          { key: "console.edit",      label: "All Posts",  path: "/console/posts",          capability: "edit_posts" },
          { key: "console.post-new",  label: "Add Post",   path: "/console/posts/new",      capability: "edit_posts" },
          { key: "console.edit-tags", label: "Categories", path: "/console/terms/category", capability: "manage_categories" },
          { key: "console.edit-tags-post_tag", label: "Tags", path: "/console/terms/post_tag", capability: "manage_post_tags" }
        ] },
      { key: "console.upload", label: "Media", path: "/console/media", capability: "upload_files",
        children: [
          { key: "console.upload",    label: "Library",        path: "/console/media",     capability: "upload_files" },
          { key: "console.media-new", label: "Add Media File", path: "/console/media/new", capability: "upload_files" }
        ] },
      { key: "console.edit-pages", label: "Pages", path: "/console/pages", capability: "edit_pages",
        children: [
          { key: "console.edit-pages", label: "All Pages", path: "/console/pages", capability: "edit_pages" },
          { key: "console.page-new",   label: "Add Page",  path: "/console/posts/new?post_type=page", capability: "edit_pages" }
        ] },
      { key: "console.edit-comments", label: "Comments", path: "/console/comments", capability: "edit_posts",
        count: :moderation },
      { separator: true },
      { key: "console.themes", label: "Appearance", path: "/console/themes", capability: "switch_themes",
        children: [
          { key: "console.themes",        label: "Themes",     path: "/console/themes",     capability: "switch_themes" },
          { key: "console.theme-install", label: "Add Theme",  path: "/console/themes/new", capability: "install_themes" },
          { key: "console.site-editor",   label: "Editor",     path: "/console/site-editor", capability: "edit_theme_options" },
          { key: "console.nav-menus",     label: "Menus",      path: "/console/menus",      capability: "edit_theme_options" }
        ] },
      { key: "console.users", label: "Users", path: "/console/users", capability: "list_users",
        children: [
          { key: "console.users",    label: "All Users", path: "/console/users",     capability: "list_users" },
          { key: "console.user-new", label: "Add User",  path: "/console/users/new", capability: "create_users" },
          { key: "console.profile",  label: "Profile",   path: "/console/profile",   capability: nil }
        ] },
      { key: "console.tools", label: "Tools", path: "/console/tools", capability: "edit_posts",
        children: [
          { key: "console.tools",                 label: "Available Tools",      path: "/console/tools",                        capability: "edit_posts" },
          { key: "console.export",                label: "Export",               path: "/console/tools/export",                 capability: "export" },
          { key: "console.site-health",           label: "Site Health",          path: "/console/tools/site-health",            capability: "view_site_health_checks" },
          { key: "console.export-personal-data",  label: "Export Personal Data", path: "/console/tools/export-personal-data",   capability: "export_others_personal_data" },
          { key: "console.erase-personal-data",   label: "Erase Personal Data",  path: "/console/tools/erase-personal-data",    capability: "erase_others_personal_data" }
        ] },
      { key: "console.options-general", label: "Settings", path: "/console/settings/general", capability: "manage_options",
        children: [
          { key: "console.options-general",    label: "General",     path: "/console/settings/general",    capability: "manage_options" },
          { key: "console.options-writing",    label: "Writing",     path: "/console/settings/writing",    capability: "manage_options" },
          { key: "console.options-reading",    label: "Reading",     path: "/console/settings/reading",    capability: "manage_options" },
          { key: "console.options-discussion", label: "Discussion",  path: "/console/settings/discussion", capability: "manage_options" },
          { key: "console.options-media",      label: "Media",       path: "/console/settings/media",      capability: "manage_options" },
          { key: "console.options-permalink",  label: "Permalinks",  path: "/console/settings/permalinks", capability: "manage_options" },
          { key: "console.options-privacy",    label: "Privacy",     path: "/console/settings/privacy",    capability: "manage_privacy_options" }
        ] }
    ].freeze

    # The navigation as THIS actor may see it. The controller resolves every capability —
    # the view never asks Access (BR-CAP-05) — and marks the open item so the sidebar can
    # render the current section expanded, as wp-admin does.
    #
    # A top-level entry survives if the actor holds its own capability OR any child's: the
    # oracle shows Users to a subscriber solely because Profile lives under it.
    def console_menu
      @console_menu ||= MENU.filter_map do |entry|
        next entry if entry[:separator]

        children = (entry[:children] || []).select { |c| permitted_entry?(c) }
        next nil unless permitted_entry?(entry) || children.any?

        entry.merge(
          children: children,
          current: current_entry?(entry, children),
          badge: badge_for(entry)
        )
      end
    end

    def permitted_entry?(entry)
      entry[:capability].nil? || site_can?(entry[:capability])
    end

    # The open section: the screen id matches the entry or one of its children, or the
    # request path sits underneath the entry's path (so /console/posts/12/edit keeps Posts
    # open even though no menu entry names that URL).
    def current_entry?(entry, children)
      screen = current_screen
      return true if entry[:key] == screen || children.any? { |c| c[:key] == screen }
      # Match on PATH as well as screen id: a screen that never set @screen (it defaults to
      # the pluralised controller name) would otherwise leave its whole section closed.
      return true if children.any? { |c| same_path?(c[:path]) }

      base = entry[:path].split("?").first
      return false if base == "/console" # Dashboard is only current on exactly /console

      request.path == base || request.path.start_with?("#{base}/")
    end

    def same_path?(path)
      base = path.to_s.split("?").first
      request.path == base
    end

    # wp-admin puts the pending-comment count in a bubble on Comments
    # (menu.php:110-118, `$awaiting_moderation`). Only that one entry carries a count.
    def badge_for(entry)
      return nil unless entry[:count] == :moderation

      count = Discussion::Comment.where(status: "pending").count
      count.positive? ? count : nil
    rescue StandardError
      nil
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
