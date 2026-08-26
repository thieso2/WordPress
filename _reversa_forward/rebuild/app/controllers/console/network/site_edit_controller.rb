# frozen_string_literal: true

module Console
  module Network
    # console.ms-site-edit — the Edit Site cluster. wp-admin splits it across four scripts
    # that share one heading and one tab bar (network_edit_site_nav, wp-admin/includes/ms.php
    # :1105-1170): site-info.php, site-users.php, site-themes.php, site-settings.php.
    # Modernized mode keeps that INFORMATION ARCHITECTURE exactly — same four tabs, same
    # order, same per-tab controls — in one controller with one action per tab.
    #
    # LITERAL strings verbatim:
    #   'Edit Site: %s'                       site-info.php:134
    #   'Visit' | 'Dashboard'                 site-info.php:147
    #   'Info' 'Users' 'Themes' 'Settings'    includes/ms.php:1112-1129
    #   'Site Address (URL)' 'Registered' 'Last Updated' 'Attributes'
    #   'Public' 'Archived' 'Spam' 'Flagged for Deletion'   site-info.php:172-208
    #   'Site info updated.'                  site-info.php:126
    #   'Site options updated.'               site-settings.php:78
    #   'Theme enabled.' / 'Theme disabled.'  site-themes.php:194, :211
    #   'Invalid site ID.'                    site-info.php:23
    #   'The requested site does not exist.'  site-info.php:28
    #   'Sorry, you are not allowed to edit this site.'  site-info.php:14
    #
    # ⚠️ `mature` is not reproduced (no column in the registry; the legacy calls its own
    # mature UI "external code only", sites.php:88 — and there are no plugins under AD-01).
    class SiteEditController < BaseController
      self.network_capability = "manage_sites"

      EDIT_DENIED = "Sorry, you are not allowed to edit this site."
      INVALID_ID = "Invalid site ID."
      NO_SUCH_SITE = "The requested site does not exist."

      # The four tabs, in wp-admin's order (includes/ms.php:1109-1131).
      TABS = [
        { key: "site-info",     label: "Info",     suffix: "" },
        { key: "site-users",    label: "Users",    suffix: "/users" },
        { key: "site-themes",   label: "Themes",   suffix: "/themes" },
        { key: "site-settings", label: "Settings", suffix: "/settings" }
      ].freeze

      before_action :load_site
      helper_method :site_tabs

      # GET /console/network/sites/:id — the Info tab (site-info.php).
      def info
        prepare("site-info")
        render "console/network/site_edit/info"
      end

      # POST /console/network/sites/:id — site-info.php:38-121, `action=update-site`.
      def update_info
        prepare("site-info")
        blog = params.fetch(:blog, {}).permit(:url, :public, :archived, :spam, :deleted).to_h

        attributes = { public: checkbox(blog["public"]) }
        # :48-52 — on the network's main site the domain and path may not change, and the
        # archived/spam/deleted flags are not offered at all.
        unless main_site?(@site)
          attributes[:archived] = checkbox(blog["archived"])
          attributes[:spam] = checkbox(blog["spam"])
          attributes[:deleted] = checkbox(blog["deleted"])
          domain, path = parse_site_url(blog["url"])
          attributes[:domain] = domain if domain.present?
          attributes[:path] = path if path.present?
        end

        without_tenant { @site.update!(attributes) }
        redirect_after_submit("/console/network/sites/#{@site.id}", notice: "Site info updated.")
      rescue ActiveRecord::RecordInvalid => e
        @errors = e.record.errors.full_messages
        render "console/network/site_edit/info", status: :unprocessable_content
      end

      # GET /console/network/sites/:id/users — site-users.php. The members of THIS site.
      # Roles are rows scoped by site_id (BR-MS-04), so membership is a plain query; the
      # legacy had to switch_to_blog() to read wp_{id}_capabilities out of usermeta.
      def users
        prepare("site-users")
        assignments = without_tenant do
          Identity::RoleAssignment.where(site_id: @site.id).order(:user_id).to_a
        end
        roles_by_user = assignments.group_by(&:user_id).transform_values { |rows| rows.map(&:role) }
        members = without_tenant { Identity::User.where(id: roles_by_user.keys).order(:login).to_a }
        @members = members.map { |user| [user, roles_by_user.fetch(user.id, [])] }
        render "console/network/site_edit/users"
      end

      # GET /console/network/sites/:id/themes — site-themes.php. Which themes THIS site may
      # choose from. The network-enabled set is not shown here ("Network enabled themes are
      # not shown on this screen.", site-themes.php:237); the per-site set is the site's own
      # `allowedthemes` setting, read inside the tenant schema.
      def themes
        prepare("site-themes")
        load_theme_state
        render "console/network/site_edit/themes"
      end

      # POST /console/network/sites/:id/themes — site-themes.php:186-232.
      def update_themes
        prepare("site-themes")
        slug = params[:theme].to_s
        enable = params[:enable].to_s == "1"

        if slug.empty?
          flash[:error] = "No theme selected." # site-themes.php:227
          return redirect_to("/console/network/sites/#{@site.id}/themes", status: :see_other)
        end

        with_site_settings do
          allowed = Array(Configuration::Setting["allowedthemes"] || [])
          allowed = enable ? (allowed | [slug]) : (allowed - [slug])
          Configuration::Setting.set("allowedthemes", allowed)
        end
        redirect_after_submit("/console/network/sites/#{@site.id}/themes",
                              notice: enable ? "Theme enabled." : "Theme disabled.")
      end

      # GET /console/network/sites/:id/settings — site-settings.php:118-190, the site's own
      # options rendered one row per option, `option[<name>]`.
      def settings
        prepare("site-settings")
        load_site_options
        render "console/network/site_edit/settings"
      end

      # POST /console/network/sites/:id/settings — site-settings.php:38-70.
      def update_settings
        prepare("site-settings")
        submitted = params.fetch(:option, {}).to_unsafe_h

        with_site_settings do
          submitted.each do |name, value|
            next if name.to_s.start_with?("_")
            next if Configuration::Setting::PROTECTED_NAMES.include?(name.to_s)
            next if Configuration::Setting::BARRED_NAMES.include?(name.to_s)

            existing = Configuration::Setting.find_by(name: name.to_s)
            next if existing.nil? # only options the screen actually rendered are writable

            Configuration::Setting.set(name.to_s, sanitize_option(name.to_s, cast_like(existing.value, value)))
          end
        end
        redirect_after_submit("/console/network/sites/#{@site.id}/settings",
                              notice: "Site options updated.")
      end

      private

      def load_site
        id = params[:id].to_i
        return not_found!(INVALID_ID) if id.zero?

        @site = without_tenant { Tenancy::Site.find_by(id: id) }
        return not_found!(NO_SUCH_SITE) if @site.nil?

        true
      end

      def prepare(tab)
        @tab = tab
        # site-info.php:134 — sprintf( __( 'Edit Site: %s' ), esc_html( $details->blogname ) ).
        @page_title = "Edit Site: #{@site.name.presence || site_address(@site)}"
        @screen = "console.ms-site-edit"
        @network_nav_key = "console.ms-sites"
        @site_visit_url = site_home_url(@site)
        @site_dashboard_url = site_admin_url(@site)
        @site_address = site_address(@site)
        @is_main_site = main_site?(@site)
        @errors ||= []
      end

      # network_edit_site_nav() (includes/ms.php:1105-1170). Every tab carries `manage_sites`
      # there, which this controller already required, so all four are shown.
      def site_tabs
        TABS.map do |tab|
          tab.merge(path: "/console/network/sites/#{@site.id}#{tab[:suffix]}", current: tab[:key] == @tab)
        end
      end

      def checkbox(value) = value.to_s == "1"

      # site-info.php:55-77 — the submitted URL is parsed back into domain + path, with a
      # default path of `/` and the port preserved.
      def parse_site_url(url)
        raw = url.to_s.strip
        return [nil, nil] if raw.empty?

        raw = "http://#{raw}" unless raw.match?(%r{\A[a-z][a-z0-9+.\-]*://}i)
        parsed = URI.parse(raw)
        domain = parsed.host.to_s
        domain += ":#{parsed.port}" if parsed.port && ![80, 443].include?(parsed.port)
        path = parsed.path.presence || "/"
        path = "#{path}/" unless path.end_with?("/")
        [domain.presence, path]
      rescue URI::InvalidURIError
        [nil, nil]
      end

      # ── Reading INSIDE the tenant ───────────────────────────────────────────────────
      #
      # The only place in the network console that leaves the global schema. ⚠️ Guarded on
      # the schema actually carrying the table: `search_path` is `<tenant>, public`, so a
      # site whose schema was never provisioned would silently resolve `settings` to the
      # GLOBAL table and this screen would edit the network's own site options. That is a
      # real footgun of schema-per-site and it is closed here, not documented away.
      def site_schema_ready?
        return @site_schema_ready if defined?(@site_schema_ready)

        @site_schema_ready = @site.provisioned? &&
                             Tenancy::Provisioner.table_exists_in?(@site.schema_name, "settings")
      end

      def with_site_settings(&block)
        return unless site_schema_ready?

        @site.switch(&block)
      end

      def load_site_options
        @site_options = []
        return unless site_schema_ready?

        @site.switch do
          # site-settings.php:124-133 — `option_name NOT LIKE '\_%'`: the underscore-
          # prefixed internals are not offered for editing.
          rows = Configuration::Setting.where("name NOT LIKE ?", "\\_%").order(:name).to_a
          @site_options = rows.map { |row| [row.name, *display_value(row.value)] }
        end
      end

      def load_theme_state
        @themes = without_tenant { Presentation::Theme.order(:slug).to_a }
        # The network-enabled set (ms-themes/`allowedthemes`, the network option) is
        # excluded from this screen exactly as site-themes.php:237 says it is.
        @network_enabled = Array(Tenancy::NetworkSetting["allowedthemes"] || [])
        @site_enabled = []
        with_site_settings { @site_enabled = Array(Configuration::Setting["allowedthemes"] || []) }
      end

      # site-settings.php:141-151 — a serialized value is shown, not edited: the legacy
      # prints 'SERIALIZED DATA' and disables the field. jsonb has no serialization to
      # unwrap, so the equivalent is: scalars are editable, structures are shown read-only.
      def display_value(value)
        case value
        when String, Numeric, TrueClass, FalseClass then [value.to_s, true]
        when nil then ["", true]
        else [value.to_json, false]
        end
      end

      # A form posts strings; the stored value has a shape. Preserve it rather than turning
      # every option into a string (AD-06: settings are typed, not a serialized blob).
      # ⚠️ RISK-023 V7. site-settings.php:60 writes each submitted option through
      # `update_option()`, and update_option() runs `sanitize_option()` — whose
      # blogname/blogdescription arm is `esc_html( $value )` (formatting.php:5006). That is
      # not cosmetic: it is the reason those two options are HTML-ESCAPED AT REST, and the
      # reason `Configuration::Setting.display` is allowed to hand them to a view as
      # `html_safe` (see the note on Setting::SANITIZED_ON_WRITE).
      #
      # This screen reached `Setting.set` directly — the equivalent of a raw DB write, not
      # of update_option() — so a `blogname` submitted here was stored UNESCAPED and then
      # printed as trusted HTML by every surface that shows the site title, `site_name`
      # among them. The other two write paths (console/settings_controller via
      # SettingsRegistry field casts, and public_api/settings_controller:175) both apply it;
      # this was the third and it did not.
      def sanitize_option(name, value)
        return value unless Configuration::Setting::SANITIZED_ON_WRITE.include?(name)

        Configuration::SettingsRegistry::ESC_HTML.call(value)
      end

      def cast_like(existing, submitted)
        case existing
        when Integer then submitted.to_s.to_i
        when Float then submitted.to_s.to_f
        when TrueClass, FalseClass then %w[1 true yes on].include?(submitted.to_s.downcase)
        else submitted.to_s
        end
      end
    end
  end
end
