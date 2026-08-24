# frozen_string_literal: true

module Console
  module Network
    # console.ms-themes — ms-themes.php → wp-admin/network/themes.php. What this screen does
    # is stated by its own help tab (themes.php:314): "This screen enables and disables the
    # inclusion of themes available to choose in the Appearance menu for each site. It does
    # not activate or deactivate which theme a site is currently using."
    #
    # So it is one network option, `allowedthemes` — held here in Tenancy::NetworkSetting
    # (the wp_sitemeta replacement, BR-MS-08) — plus a P-LIST over the installed themes.
    #
    # ⚠️ Under multisite the `themes` table is BLOG-scoped (Tenancy::Provisioner::BLOG_TABLES),
    # so a tenant schema holds that site's copy. The network console runs with NO tenant, so
    # `Presentation::Theme` resolves to the GLOBAL schema's copy — which is the canonical
    # installed set every tenant is cloned from, and therefore the right catalogue for a
    # network-wide enable/disable. Recorded because it is a consequence of the schema-per-site
    # choice rather than an obvious one.
    #
    # LITERAL strings verbatim from network/themes.php and
    # wp-admin/includes/class-wp-ms-themes-list-table.php:
    #   columns 'Theme' / 'Description'                         (:337-342)
    #   views   'All' / 'Enabled' / 'Disabled'                  (:381-469)
    #   bulk    'Network Enable' / 'Network Disable'            (:479-489)
    #   row     'Network Enable' / 'Network Disable'            (:602-635)
    #   empty   'No themes found.' / 'No themes are currently available.'  (:324-329)
    #   notice  'Theme enabled.' / '%s themes enabled.' / 'Theme disabled.' / '%s themes disabled.'
    #                                                           (themes.php:387-408)
    class ThemesController < BaseController
      include Console::ListActions

      self.network_capability = "manage_network_themes"

      # themes.php:14 — wp_die( __( 'Sorry, you are not allowed to manage network themes.' ) ).
      # ⚠️ The base controller's gate uses network/index.php's message; this screen's own
      # wp_die string is more specific, so it overrides it.
      MANAGE_DENIED = "Sorry, you are not allowed to manage network themes."

      ALLOWED_THEMES = "allowedthemes"
      SORTABLE = %w[name].freeze

      # GET /console/network/themes
      def index
        @page_title = "Themes"
        @screen = "console.ms-themes"
        @network_nav_key = "console.ms-themes"

        without_tenant do
          @enabled = enabled_slugs
          @all_themes = Presentation::Theme.order(:slug).to_a
          page = list_page(ordered(searched(status_scoped(Presentation::Theme.all))), strategy: :exact)
          @list = build_list(page)
        end
        render "console/network/themes/index"
      end

      # POST /console/network/themes/bulk — themes.php:30-80, the enable/disable arms.
      def bulk
        return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

        enable = case bulk_action_name
                 when "enable-selected", "enable" then true
                 when "disable-selected", "disable" then false
                 end
        return redirect_to(list_path, status: :see_other) if enable.nil?

        without_tenant do
          slugs = Presentation::Theme.where(id: bulk_ids).pluck(:slug)
          current = enabled_slugs
          Tenancy::NetworkSetting[ALLOWED_THEMES] = enable ? (current | slugs) : (current - slugs)
          flash[:success] = notice_for(slugs.length, enable)
        end
        redirect_to list_path, status: :see_other
      end

      private

      def guard_network_capability
        require_capability!("manage_network_themes", MANAGE_DENIED)
      end

      def list_path = "/console/network/themes"
      def bulk_path = "/console/network/themes/bulk"

      def enabled_slugs = Array(Tenancy::NetworkSetting[ALLOWED_THEMES] || [])

      # themes.php:387-408 — singular is the bare sentence, plural carries the count.
      def notice_for(count, enable)
        verb = enable ? "enabled" : "disabled"
        return "Theme #{verb}." if count == 1

        "#{ActiveSupport::NumberHelper.number_to_delimited(count)} themes #{verb}."
      end

      def build_list(page)
        ListModel.new(
          screen: "console.ms-themes",
          title: "Themes",
          # themes.php:366 — 'Add Theme', behind install_themes. Reuses the single-site
          # installer, which is where a theme actually arrives from (DEV-011).
          primary_action: (site_can?("install_themes") ? { label: "Add Theme", path: "/console/themes/new" } : nil),
          tabs: status_tabs,
          filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search installed themes",
                                          value: params[:s].to_s)],
          bulk_actions: bulk_actions,
          columns: columns,
          rows: page.records.map { |theme| row_for(theme) },
          page: page,
          strategy: :exact,
          base_path: list_path,
          bulk_path: bulk_path,
          # :324-329 — 'No themes found.' once a filter is on, otherwise 'No themes are
          # currently available.'
          empty_message: @all_themes.any? ? "No themes found." : "No themes are currently available.",
          query: list_query,
          order: list_order,
          orderby: list_orderby(SORTABLE, default: "name"),
          search_query: params[:s].presence
        )
      end

      def columns
        [
          ListModel::Column.new(key: "name", label: "Theme", sortable: true, sort_key: "name"),
          ListModel::Column.new(key: "description", label: "Description", sortable: false)
        ]
      end

      # :479-489. Neither is destructive — enabling or disabling a theme network-wide
      # removes nothing, so DEV-004's interstitial would be noise.
      def bulk_actions
        [
          ListModel::BulkAction.new(value: "enable-selected", label: "Network Enable", destructive: false),
          ListModel::BulkAction.new(value: "disable-selected", label: "Network Disable", destructive: false)
        ]
      end

      def status_tabs
        all = @all_themes.length
        enabled = @all_themes.count { |t| @enabled.include?(t.slug) }
        disabled = all - enabled
        current = params[:status].to_s

        counts = { "all" => ["All", all], "enabled" => ["Enabled", enabled], "disabled" => ["Disabled", disabled] }
        counts.filter_map do |status, (label, count)|
          next if count.zero?

          number = ActiveSupport::NumberHelper.number_to_delimited(count)
          ListModel::Tab.new(key: status, count: count,
                             label: %(#{label} <span class="count">(#{number})</span>).html_safe,
                             query: { "status" => (status == "all" ? nil : status) },
                             current: (status == "all" ? current.empty? || current == "all" : current == status))
        end
      end

      def status_scoped(scope)
        case params[:status].to_s
        when "enabled"  then scope.where(slug: @enabled)
        when "disabled" then @enabled.empty? ? scope : scope.where.not(slug: @enabled)
        else scope
        end
      end

      def searched(scope)
        term = params[:s].to_s.strip
        return scope if term.empty?

        scope.where("themes.slug ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
      end

      def ordered(scope) = scope.order(Arel.sql("themes.slug #{list_order.upcase}, themes.id ASC"))

      def row_for(theme)
        enabled = @enabled.include?(theme.slug)
        ListModel::Row.new(
          id: theme.id,
          cells: {
            "name" => name_cell(theme, enabled),
            "description" => ERB::Util.html_escape("#{theme.slug} #{theme.version}")
          },
          actions: [row_action(theme, enabled)],
          selectable: true
        )
      end

      def name_cell(theme, enabled)
        markup = +%(<strong>#{ERB::Util.html_escape(theme.name)}</strong>)
        markup << %( <span class="count">(Enabled)</span>) if enabled
        markup.html_safe
      end

      # :602-635 — one link per row, the opposite of the current state.
      def row_action(theme, enabled)
        ListModel::RowAction.new(
          label: enabled ? "Network Disable" : "Network Enable",
          path: bulk_path, method: :post,
          params: { bulk_action: enabled ? "disable-selected" : "enable-selected",
                    confirmed: "0", "ids[]" => theme.id },
          destructive: false, key: enabled ? "disable" : "enable"
        )
      end
    end
  end
end
