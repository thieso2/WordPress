# frozen_string_literal: true

module Console
  module Network
    # The NETWORK ADMIN surface — wp-admin/network/*.php (ms-admin.php redirects here;
    # ms-sites.php / ms-users.php / ms-themes.php / ms-options.php are the 3.0 shims that
    # forward to network/sites.php, users.php, themes.php, settings.php).
    #
    # ⚠️⚠️ THE ACCEPTANCE GATE (target_architecture.md § Tenancy, RISK-009). Multisite is
    # OFF by default and this whole surface is STRICTLY ADDITIVE:
    #
    #   * `require_network!` is PREPENDED, so it runs ahead of BaseController's
    #     auth_redirect AND ahead of ApplicationController's AD-04 check. With
    #     `Tenancy.enabled? == false` every one of these URLs answers 404 with
    #     my-sites.php:13's verbatim `Multisite support is not enabled.` — the screens do
    #     not exist on a single site, exactly as wp-admin has no network/ directory
    #     reachable without a network.
    #   * Nothing here is reachable from the single-site menu: the proposed "Network" menu
    #     entry is gated on the `manage_network` capability, which NO role holds
    #     (Access::RoleCatalogue) — it is satisfied only by the super-admin bypass in
    #     Access::BasePolicy, which is itself false unless Tenancy.enabled?. So the entry
    #     is invisible on a single site by construction, not by a second flag.
    #   * No Wave 0–4 file is touched, no query on the single-site path changes, and the
    #     25-screen front-end parity gate is untouched (nothing here is a front end).
    #
    # ── Authorization (AD-04) ─────────────────────────────────────────────────────────
    # Declared `:authenticated`, then gated IN THE CONTROLLER on the network capability.
    # The same reasoning Console::SettingsController records: a `:policy` denial is a bare
    # 403 with no body, and DEV-009 requires the wp_die() refusal string VERBATIM. The
    # capability is still enforced — `require_capability!` — just where the right message
    # is reachable. The capabilities are wp-admin's own, one per screen:
    #
    #   manage_network         network/index.php:16
    #   manage_sites           network/sites.php:13, site-info.php:13
    #   manage_network_users   network/users.php:14
    #   manage_network_themes  network/themes.php:14
    #   manage_network_options network/settings.php:17
    #
    # None of them appears in Access::RoleCatalogue, so Access::SitePolicy's `default:`
    # arm (capabilities.php:864) requires the capability of itself and NOBODY holds it —
    # which is precisely map_meta_cap()'s multisite behaviour: these are super-admin-only
    # capabilities, granted by is_super_admin() rather than by a role. Access::BasePolicy
    # already implements that bypass (BR-MS-05) over the `site_admins` network option.
    #
    # THE CONTROLLER IS THE ONLY LAYER THAT TOUCHES ACCESS (BR-CAP-05). The views below
    # receive booleans; not one of them asks a policy.
    class BaseController < Console::BaseController
      include Console::Chrome

      # network/index.php:16 — wp_die( __( 'Sorry, you are not allowed to access this page.' ), 403 ).
      ACCESS_DENIED = "Sorry, you are not allowed to access this page."
      # my-sites.php:13 — wp_die( __( 'Multisite support is not enabled.' ) ).
      NOT_MULTISITE = "Multisite support is not enabled."

      # ⚠️ PREPENDED: ahead of auth_redirect and ahead of the AD-04 declaration check, so a
      # single-site install answers 404 for anonymous and signed-in requests alike. The
      # screen does not exist; it is not merely refused.
      prepend_before_action :require_network!
      before_action :guard_network_capability

      helper_method :network_nav, :network_screen

      # Per-controller capability declaration — the `$cap` each network/*.php opens with.
      # nil means "no network capability beyond being on the network" (my-sites.php gates
      # on `read`, which every role holds).
      class_attribute :network_capability, instance_accessor: false, default: nil

      # The network menu (wp-admin/network/menu.php). Plugins is ABSENT and its absence is
      # a ruling, not a gap: AD-01 removed the extension system, so `manage_network_plugins`
      # governs nothing. Updates / Upgrade Network / Network Setup have no rebuild surface.
      # Rendered as an in-page nav because the sidebar MENU is the integrator's file; the
      # proposed top-level entry is returned with this track's handoff.
      NAV = [
        { key: "console.ms-admin",  label: "Dashboard", path: "/console/network",          capability: "manage_network" },
        { key: "console.ms-sites",  label: "Sites",     path: "/console/network/sites",    capability: "manage_sites" },
        { key: "console.ms-users",  label: "Users",     path: "/console/network/users",    capability: "manage_network_users" },
        { key: "console.ms-themes", label: "Themes",    path: "/console/network/themes",   capability: "manage_network_themes" },
        { key: "console.ms-options", label: "Settings", path: "/console/network/settings", capability: "manage_network_options" }
      ].freeze

      private

      # The nav AS THIS ACTOR MAY SEE IT. Every capability is resolved here; the partial
      # renders what it is handed (BR-CAP-05).
      def network_nav
        @network_nav ||= NAV.select { |entry| site_can?(entry[:capability]) }
                            .map { |entry| entry.merge(current: entry[:key] == network_screen) }
      end

      # The network screen id this request belongs to, for the nav's current marker. The
      # site-edit cluster lives under Sites, as `$parent_file = 'sites.php'` puts it.
      def network_screen = @network_nav_key.presence || current_screen

      def require_network!
        return if Tenancy.enabled?

        @message = NOT_MULTISITE
        render "console/shared/not_found", status: :not_found
      end

      def guard_network_capability
        capability = self.class.network_capability
        return true if capability.nil?

        require_capability!(capability, ACCESS_DENIED)
      end

      # The network console operates on the GLOBAL tables (sites, users, network_settings)
      # regardless of the inbound host, so it must never inherit a tenant resolved from the
      # request. Everything here reads the global schema; a per-site read is an EXPLICIT
      # `site.switch { ... }` (the Edit Site → Settings tab) and nothing else.
      def without_tenant(&block)
        Tenancy.current_site ? Tenancy.without_tenant(&block) : yield
      end

      # `untrailingslashit( $blog->domain . $blog->path )` — the site address wp-admin
      # prints in every row, confirmation and heading (class-wp-ms-sites-list-table.php:747).
      def site_address(site)
        "#{site.domain}#{site.path}".sub(%r{/\z}, "")
      end

      # `get_home_url( $blog_id, '/' )` and `get_admin_url( $blog_id )` — the front end and
      # the dashboard of another site. The scheme follows the current request, as
      # get_home_url() follows the network's.
      def site_home_url(site) = "#{request.protocol}#{site.domain}#{site.path}"
      def site_admin_url(site) = "#{site_home_url(site).sub(%r{/\z}, '')}/console"

      # Whether a site is the network's main site. `is_main_site()` compares against the
      # network's `blog_id`; the rebuild's registry has no such column, so the main site is
      # the first row — the site the network was created around. Resolved once per request.
      def main_site_id
        return @main_site_id if defined?(@main_site_id)

        @main_site_id = Tenancy::Site.order(:id).limit(1).pick(:id)
      end

      def main_site?(site) = site.id == main_site_id
    end
  end
end
