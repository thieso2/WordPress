# frozen_string_literal: true

module Console
  module Network
    # console.ms-sites — ms-sites.php → wp-admin/network/sites.php, the network Sites list
    # (WP_MS_Sites_List_Table). A P-LIST instantiation: it builds a Console::ListModel and
    # renders console/shared/_list, so the panel structure, the bulk form, the DEV-004
    # confirmation and the pager are the ones every other list screen already uses.
    #
    # LITERAL strings verbatim from network/sites.php and
    # wp-admin/includes/class-wp-ms-sites-list-table.php:
    #   columns   'URL' / 'Last Updated' / 'Registered' / 'Users'          (:383-391)
    #   views     'All' / 'Public' / 'Archived' / 'Spam' / 'Flagged for Deletion' (:228-291)
    #   bulk      'Delete' / 'Mark as spam' / 'Not spam'                   (:302-309)
    #   row       'Edit' 'Dashboard' 'Flag for Deletion' 'Remove Deletion Flag'
    #             'Archive' 'Unarchive' 'Spam' 'Not Spam' 'Delete Permanently' 'Visit'
    #                                                                      (:740-868)
    #   empty     'No sites found.'                                        (:217-219)
    #   notices   sites.php:322-372, one per updated_action
    #
    # ⚠️ `mature` is NOT reproduced. The registry table (db/migrate/20260823000400) has no
    # such column, and the legacy's own comment says "the mature/unmature UI exists only as
    # external code" (sites.php:88) — i.e. it is reachable only through a plugin, and there
    # is no plugin system (AD-01). Recorded as a deliberate omission, not a gap.
    class SitesController < BaseController
      include Console::ListActions

      self.network_capability = "manage_sites"

      # sites.php:158-161 — the delete arm re-checks `delete_sites`; site-new.php:17 gates
      # the Add Site screen on `create_sites` with its own message.
      DELETE_DENIED = "Sorry, you are not allowed to access this page."
      MAIN_SITE_DENIED = "Sorry, you are not allowed to change the current site."
      ADD_DENIED = "Sorry, you are not allowed to add sites to this network."

      # sites.php:59-79 — the confirmation prompt for each action, `%s` the site address.
      MANAGE_ACTIONS = {
        "activateblog"   => "You are about to remove the deletion flag from the site %s.",
        "deactivateblog" => "You are about to flag the site %s for deletion.",
        "unarchiveblog"  => "You are about to unarchive the site %s.",
        "archiveblog"    => "You are about to archive the site %s.",
        "unspamblog"     => "You are about to unspam the site %s.",
        "spamblog"       => "You are about to mark the site %s as spam.",
        "deleteblog"     => "You are about to delete the site %s."
      }.freeze

      # sites.php:322-372 — the notice for each completed action.
      NOTICES = {
        "all_notspam"    => "Sites removed from spam.",
        "all_spam"       => "Sites marked as spam.",
        "all_delete"     => "Sites permanently deleted.",
        "delete"         => "Site permanently deleted.",
        "not_deleted"    => "Sorry, you are not allowed to delete that site.",
        "archiveblog"    => "Site archived.",
        "unarchiveblog"  => "Site unarchived.",
        "activateblog"   => "Site deletion flag removed.",
        "deactivateblog" => "Site flagged for deletion.",
        "unspamblog"     => "Site removed from spam.",
        "spamblog"       => "Site marked as spam."
      }.freeze

      SORTABLE = %w[blogname lastupdated registered].freeze

      # GET /console/network/sites
      def index
        @page_title = "Sites"
        @screen = "console.ms-sites"
        @network_nav_key = "console.ms-sites"

        without_tenant do
          page = list_page(ordered(searched(status_scoped(Tenancy::Site.all))), strategy: :exact)
          @user_counts = user_counts_for(page.records)
          @list = build_list(page)
        end
        render "console/network/sites/index"
      end

      # POST /console/network/sites/bulk — the ONE endpoint every bulk action and every
      # state-changing row action posts through, so single-row and bulk share one code path
      # and one DEV-004 confirmation (the P-LIST contract).
      def bulk
        return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

        action = bulk_action_name
        sites = without_tenant { Tenancy::Site.where(id: bulk_ids).order(:id).to_a }
        return redirect_to(list_path, status: :see_other) if sites.empty?

        # sites.php:257 / :168 — the main site is never changed through this screen.
        return deny!(MAIN_SITE_DENIED) if sites.any? { |s| main_site?(s) }

        case action
        when "deleteblog", "delete"
          destroy_sites(sites, action)
        when "spamblog", "unspamblog", "spam", "notspam",
             "archiveblog", "unarchiveblog", "activateblog", "deactivateblog"
          flag_sites(sites, action)
        else
          redirect_to list_path, status: :see_other
        end
      end

      # GET /console/network/sites/new — network/site-new.php:192, `Add Site`.
      def new
        return deny!(ADD_DENIED) unless site_can?("create_sites")

        @page_title = "Add Site"
        @screen = "console.ms-site-new"
        @network_nav_key = "console.ms-sites"
        @errors = []
        @form = { "domain" => "", "title" => "", "email" => "" }
        render "console/network/sites/new"
      end

      # POST /console/network/sites — site-new.php:37-180.
      def create
        return deny!(ADD_DENIED) unless site_can?("create_sites")

        @page_title = "Add Site"
        @screen = "console.ms-site-new"
        @network_nav_key = "console.ms-sites"
        blog = params.fetch(:blog, {}).permit(:domain, :title, :email).to_h
        @form = { "domain" => blog["domain"].to_s.strip, "title" => blog["title"].to_s.strip,
                  "email" => blog["email"].to_s.strip }
        @errors = validate_new_site(@form)
        return render("console/network/sites/new", status: :unprocessable_content) if @errors.any?

        site = nil
        without_tenant do
          site = Tenancy::Site.create!(domain: @form["domain"], path: "/",
                                       name: @form["title"], registered_at: Time.current)
        end
        Tenancy::Provisioner.provision!(site)
        ensure_site_administrator(site, @form["email"])

        # site-new.php:174 — 'Site added. <a href="%1$s">Visit Dashboard</a> or <a href="%2$s">Edit Site</a>'
        flash[:success] = "Site added."
        redirect_to "/console/network/sites/#{site.id}", status: :see_other
      end

      private

      def list_path = "/console/network/sites"
      def bulk_path = "/console/network/sites/bulk"

      # ── The list ────────────────────────────────────────────────────────────────────

      def build_list(page)
        ListModel.new(
          screen: "console.ms-sites",
          title: "Sites",
          # sites.php:381 — 'Add Site', behind create_sites.
          primary_action: (site_can?("create_sites") ? { label: "Add Site", path: "/console/network/sites/new" } : nil),
          tabs: status_tabs,
          filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search Sites", value: params[:s].to_s)],
          bulk_actions: bulk_actions,
          columns: columns,
          rows: page.records.map { |site| row_for(site) },
          page: page,
          strategy: :exact,
          base_path: list_path,
          bulk_path: bulk_path,
          empty_message: "No sites found.",
          query: list_query,
          order: list_order,
          orderby: list_orderby(SORTABLE, default: "blogname"),
          search_query: params[:s].presence
        )
      end

      # get_columns(), class-wp-ms-sites-list-table.php:383-391 — LITERAL. The `plugins`
      # ("Actions") column exists only when a filter is hooked, so AD-01 removes it.
      def columns
        [
          ListModel::Column.new(key: "blogname", label: "URL", sortable: true, sort_key: "blogname"),
          ListModel::Column.new(key: "lastupdated", label: "Last Updated", sortable: true, sort_key: "lastupdated"),
          ListModel::Column.new(key: "registered", label: "Registered", sortable: true, sort_key: "registered"),
          ListModel::Column.new(key: "users", label: "Users", sortable: false)
        ]
      end

      # get_bulk_actions(), :302-309. Delete is DEV-004-confirmed.
      def bulk_actions
        actions = []
        actions << ListModel::BulkAction.new(value: "delete", label: "Delete", destructive: true) if site_can?("delete_sites")
        actions << ListModel::BulkAction.new(value: "spam", label: "Mark as spam", destructive: false)
        actions << ListModel::BulkAction.new(value: "notspam", label: "Not spam", destructive: false)
        actions
      end

      # get_views(), :228-291 — wp_count_sites(). A view appears only when its count is
      # positive, exactly as the legacy's `if ( (int) $counts[ $status ] > 0 )`.
      def status_tabs
        counts = {
          "all" => Tenancy::Site.count,
          "public" => Tenancy::Site.where(public: true).count,
          "archived" => Tenancy::Site.where(archived: true).count,
          "spam" => Tenancy::Site.where(spam: true).count,
          "deleted" => Tenancy::Site.where(deleted: true).count
        }
        labels = { "all" => "All", "public" => "Public", "archived" => "Archived",
                   "spam" => "Spam", "deleted" => "Flagged for Deletion" }
        current = params[:status].to_s

        counts.filter_map do |status, count|
          next if count.zero?

          number = ActiveSupport::NumberHelper.number_to_delimited(count)
          ListModel::Tab.new(
            key: status, count: count,
            label: %(#{labels[status]} <span class="count">(#{number})</span>).html_safe,
            query: { "status" => (status == "all" ? nil : status) },
            current: (status == "all" ? current.empty? || current == "all" : current == status)
          )
        end
      end

      def status_scoped(scope)
        case params[:status].to_s
        when "public"   then scope.where(public: true)
        when "archived" then scope.where(archived: true)
        when "spam"     then scope.where(spam: true)
        when "deleted"  then scope.where(deleted: true)
        else scope
        end
      end

      # sites.php:389-397 / WP_MS_Sites_List_Table::prepare_items — the search box matches
      # the site address (domain + path) and the site name.
      def searched(scope)
        term = params[:s].to_s.strip
        return scope if term.empty?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope.where("sites.domain ILIKE :q OR sites.path ILIKE :q OR sites.name ILIKE :q", q: like)
      end

      # get_sortable_columns(), :414-428. `registered` sorts by blog_id in the legacy —
      # the registry's id is that same monotonic identity.
      def ordered(scope)
        dir = list_order.upcase
        case list_orderby(SORTABLE, default: "blogname")
        when "lastupdated" then scope.order(Arel.sql("sites.updated_at #{dir}, sites.id #{dir}"))
        when "registered"  then scope.order(Arel.sql("sites.id #{dir}"))
        else scope.order(Arel.sql("sites.domain #{dir}, sites.path #{dir}, sites.id #{dir}"))
        end
      end

      # column_users(), :594-620 — the number of users with a role on that site. Roles are
      # ROWS here (T-03), scoped by role_assignments.site_id (BR-MS-04).
      def user_counts_for(sites)
        return {} if sites.empty?

        Identity::RoleAssignment.where(site_id: sites.map(&:id))
                                .group(:site_id).distinct.count(:user_id)
      end

      def row_for(site)
        ListModel::Row.new(
          id: site.id,
          cells: {
            "blogname" => blogname_cell(site),
            "lastupdated" => date_cell(site.updated_at, never: true),
            "registered" => date_cell(site.registered_at || site.created_at, never: false),
            "users" => ERB::Util.html_escape(@user_counts.fetch(site.id, 0).to_s)
          },
          actions: row_actions(site),
          # :257 — the main site cannot be bulk-acted on, so it carries no checkbox.
          selectable: !main_site?(site)
        )
      end

      # column_blogname(), :470-509 — the site address as a link to Edit Site, followed by
      # the site states ('Main', 'Archived', 'Spam', 'Flagged for Deletion') and, in excerpt
      # mode, '%1$s &#8211; %2$s' (title – tagline). The state list is :661-710.
      def blogname_cell(site)
        address = ERB::Util.html_escape(site_address(site))
        states = site_states(site)
        markup = +%(<strong><a href="/console/network/sites/#{site.id}" class="edit">#{address}</a>)
        markup << " &#8212; #{ERB::Util.html_escape(states.join(', '))}" if states.any?
        markup << "</strong>"
        markup << %(<p>#{ERB::Util.html_escape(site.name)}</p>) if site.name.present?
        markup.html_safe
      end

      def site_states(site)
        states = []
        states << "Main" if main_site?(site)
        current = params[:status].to_s
        states << "Archived" if site.archived? && current != "archived"
        states << "Spam" if site.spam? && current != "spam"
        states << "Flagged for Deletion" if site.deleted? && current != "deleted"
        states
      end

      # column_lastupdated()/column_registered(), :512-556. `__( 'Y/m/d g:i:s a' )` is the
      # excerpt-mode format; '&#x2014;' for an unset registration, 'Never' for no update.
      def date_cell(value, never:)
        return (never ? "Never" : "&#x2014;").html_safe if value.blank?

        ERB::Util.html_escape(value.strftime("%Y/%m/%d %l:%M:%S %P").squeeze(" "))
      end

      # handle_row_actions(), :740-868. The main site gets only Edit / Dashboard / Visit;
      # every other site gets the seven. Each state-changing action posts through the bulk
      # endpoint (P-LIST contract) rather than a nonce'd GET.
      def row_actions(site)
        actions = [
          ListModel::RowAction.new(label: "Edit", path: "/console/network/sites/#{site.id}", method: :get, key: "edit"),
          ListModel::RowAction.new(label: "Dashboard", path: site_admin_url(site), method: :get, key: "backend")
        ]

        unless main_site?(site)
          actions << if site.deleted?
                       state_action(site, "activateblog", "Remove Deletion Flag", key: "activate")
                     else
                       state_action(site, "deactivateblog", "Flag for Deletion", key: "deactivate")
                     end
          actions << if site.archived?
                       state_action(site, "unarchiveblog", "Unarchive", key: "unarchive")
                     else
                       state_action(site, "archiveblog", "Archive", key: "archive")
                     end
          actions << if site.spam?
                       state_action(site, "unspamblog", "Not Spam", key: "unspam")
                     else
                       state_action(site, "spamblog", "Spam", key: "spam")
                     end
          if site_can?("delete_sites")
            actions << state_action(site, "deleteblog", "Delete Permanently", key: "delete", destructive: true)
          end
        end

        actions << ListModel::RowAction.new(label: "Visit", path: site_home_url(site), method: :get, key: "visit")
        actions
      end

      def state_action(site, action, label, key:, destructive: false)
        ListModel::RowAction.new(label: label, path: bulk_path, method: :post,
                                 params: { bulk_action: action, confirmed: "0", "ids[]" => site.id },
                                 destructive: destructive, key: key)
      end

      # ── The write arms ──────────────────────────────────────────────────────────────

      # sites.php:274-306 — archived / deleted / spam are plain flag writes. `update_blog_status`.
      def flag_sites(sites, action)
        attribute, value, notice = case action
                                   when "archiveblog"    then [:archived, true, "archiveblog"]
                                   when "unarchiveblog"  then [:archived, false, "unarchiveblog"]
                                   when "deactivateblog" then [:deleted, true, "deactivateblog"]
                                   when "activateblog"   then [:deleted, false, "activateblog"]
                                   when "spamblog"       then [:spam, true, "spamblog"]
                                   when "unspamblog"     then [:spam, false, "unspamblog"]
                                   when "spam"           then [:spam, true, "all_spam"]
                                   when "notspam"        then [:spam, false, "all_notspam"]
                                   end

        without_tenant { sites.each { |site| site.update!(attribute => value) } }
        flash[:success] = NOTICES.fetch(notice)
        redirect_to list_path, status: :see_other
      end

      # sites.php:158-200 — wpmu_delete_blog( $id, true ). DEV-004 confirms first; the
      # legacy's own confirmation screen (sites.php:110-146) is the same interstitial, so
      # the shared confirm partial carries the legacy's warning copy verbatim.
      def destroy_sites(sites, action)
        unless site_can?("delete_sites")
          flash[:error] = NOTICES.fetch("not_deleted")
          return redirect_to(list_path, status: :see_other)
        end

        unless bulk_confirmed?
          single = sites.one? && action == "deleteblog"
          prompt = if single
                     format(MANAGE_ACTIONS.fetch("deleteblog"), site_address(sites.first))
                   else
                     "You are about to delete the following sites:"
                   end
          return render_bulk_confirmation(
            # sites.php:113 / :204 — 'Confirm your action'; the warning is :123.
            title: "Confirm your action",
            prompt: "Deleting a site is a permanent action that cannot be undone. " \
                    "This will delete the entire site and its uploads directory. #{prompt}",
            button: single ? "Delete this site permanently" : "Delete these sites permanently",
            action: action, ids: sites.map(&:id), items: sites.map { |s| site_address(s) },
            post_path: bulk_path, cancel_path: list_path
          )
        end

        without_tenant do
          sites.each do |site|
            # The paired operation to Provisioner.provision! — the row AND its schema go.
            Tenancy::Provisioner.deprovision!(site)
            Identity::RoleAssignment.where(site_id: site.id).delete_all
            site.destroy!
          end
        end
        flash[:success] = NOTICES.fetch(sites.one? ? "delete" : "all_delete")
        redirect_to list_path, status: :see_other
      end

      # site-new.php:87-101 — the four wp_die() validations, verbatim.
      def validate_new_site(form)
        errors = []
        errors << "Missing site title." if form["title"].empty?
        if form["domain"].empty?
          errors << "Missing or invalid site address."
        elsif !form["domain"].match?(/\A[a-z0-9][a-z0-9.\-]*\z/)
          # site-new.php:230 — 'Only lowercase letters (a-z), numbers, and hyphens are allowed.'
          errors << "Missing or invalid site address."
        elsif Tenancy::Site.exists?(domain: form["domain"], path: "/")
          # wpmu_validate_blog_signup() — 'Sorry, that site already exists!'
          errors << "Sorry, that site already exists!"
        end
        if form["email"].empty?
          errors << "Missing email address."
        elsif !form["email"].match?(URI::MailTo::EMAIL_REGEXP)
          errors << "Invalid email address."
        end
        errors
      end

      # site-new.php:110-140 — "If the admin email for the new site does not exist in the
      # database, a new user will also be created", and that user is the new site's
      # administrator. Roles are per-site rows (BR-MS-04), so the assignment is scoped.
      def ensure_site_administrator(site, email)
        without_tenant do
          login = email.split("@").first.to_s.downcase.gsub(/[^a-z0-9]/, "")
          user = Identity::User.find_by(email: email) ||
                 Identity::User.create!(login: login.presence || "user#{SecureRandom.hex(3)}",
                                        email: email, nicename: login.presence || "user",
                                        display_name: login.presence || email,
                                        password: SecureRandom.base58(12))
          user.assign_role("administrator", site_id: site.id)
        end
      end
    end
  end
end
