# frozen_string_literal: true

module Console
  module Network
    # console.ms-users — ms-users.php → wp-admin/network/users.php, the network Users list
    # (WP_MS_Users_List_Table). A P-LIST instantiation over Identity::User, which is a
    # GLOBAL table: BR-MS-01, "users and usermeta are shared network-wide", so this list is
    # every account on the network and the Sites column is the per-site role rows (T-03,
    # BR-MS-04) rather than the legacy's one usermeta key per blog prefix.
    #
    # LITERAL strings verbatim from network/users.php and
    # wp-admin/includes/class-wp-ms-users-list-table.php:
    #   columns  'Username' 'Name' 'Email' 'Registered' 'Sites'   (:192-198)
    #   views    'All' / 'Super Admin' | 'Super Admins'            (:132-169)
    #   bulk     'Delete' / 'Mark as spam' / 'Not spam'            (:110-118)
    #   row      'Edit' / 'Delete'                                 (:543-556)
    #   marker   ' &mdash; Super Admin'                            (:286-288)
    #   empty    'No users found.'                                 (:124-126)
    #   notices  users.php:313-330
    class UsersController < BaseController
      include Console::ListActions

      self.network_capability = "manage_network_users"

      ADD_DENIED = "Sorry, you are not allowed to add users to this network."
      DELETE_DENIED = "Sorry, you are not allowed to access this page."

      NOTICES = {
        "delete"   => "User deleted.",
        "all_delete" => "Users deleted.",
        "spam"     => "Users marked as spam.",
        "notspam"  => "Users removed from spam.",
        "add"      => "User added."
      }.freeze

      SORTABLE = %w[username email registered].freeze

      # GET /console/network/users
      def index
        @page_title = "Users"
        @screen = "console.ms-users"
        @network_nav_key = "console.ms-users"

        without_tenant do
          @super_admin_ids = Tenancy::NetworkSetting.super_admin_ids
          page = list_page(ordered(searched(role_scoped(Identity::User.all))), strategy: :exact)
          @sites_for = sites_for(page.records)
          @list = build_list(page)
        end
        render "console/network/users/index"
      end

      # POST /console/network/users/bulk
      def bulk
        return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

        action = bulk_action_name
        users = without_tenant { Identity::User.where(id: bulk_ids).order(:id).to_a }
        return redirect_to(list_path, status: :see_other) if users.empty?

        # users.php:88 — 'Warning! User cannot be modified. The user %s is a network
        # administrator.' A super admin is never bulk-modified through this screen.
        super_ids = Tenancy::NetworkSetting.super_admin_ids
        blocked = users.find { |u| super_ids.include?(u.id) }
        if blocked
          flash[:error] = "Warning! User cannot be modified. The user #{blocked.login} is a network administrator."
          return redirect_to(list_path, status: :see_other)
        end

        case action
        when "delete"  then destroy_users(users)
        when "spam"    then flag_users(users, "spam")
        when "notspam" then flag_users(users, "notspam")
        else redirect_to list_path, status: :see_other
        end
      end

      # GET /console/network/users/new — network/user-new.php:107, `Add User`.
      def new
        return deny!(ADD_DENIED) unless site_can?("create_users")

        @page_title = "Add User"
        @screen = "console.ms-user-new"
        @network_nav_key = "console.ms-users"
        @errors = []
        @form = { "username" => "", "email" => "" }
        render "console/network/users/new"
      end

      # POST /console/network/users — user-new.php:37-95.
      def create
        return deny!(ADD_DENIED) unless site_can?("create_users")

        @page_title = "Add User"
        @screen = "console.ms-user-new"
        @network_nav_key = "console.ms-users"
        submitted = params.fetch(:user, {}).permit(:username, :email).to_h
        @form = { "username" => submitted["username"].to_s.strip, "email" => submitted["email"].to_s.strip }
        @errors = validate_new_user(@form)
        return render("console/network/users/new", status: :unprocessable_content) if @errors.any?

        without_tenant do
          Identity::User.create!(login: @form["username"], email: @form["email"],
                                 nicename: @form["username"].downcase, display_name: @form["username"],
                                 password: SecureRandom.base58(12))
        end
        redirect_after_submit(list_path, notice: NOTICES.fetch("add"))
      rescue ActiveRecord::RecordInvalid
        # user-new.php:55 — new WP_Error( 'add_user_fail', __( 'Cannot add user.' ) )
        @errors = ["Cannot add user."]
        render "console/network/users/new", status: :unprocessable_content
      end

      private

      def list_path = "/console/network/users"
      def bulk_path = "/console/network/users/bulk"

      def build_list(page)
        ListModel.new(
          screen: "console.ms-users",
          title: "Users",
          # users.php:358 — 'Add User', behind create_users.
          primary_action: (site_can?("create_users") ? { label: "Add User", path: "/console/network/users/new" } : nil),
          tabs: role_tabs,
          filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search Users", value: params[:s].to_s)],
          bulk_actions: bulk_actions,
          columns: columns,
          rows: page.records.map { |user| row_for(user) },
          page: page,
          strategy: :exact,
          base_path: list_path,
          bulk_path: bulk_path,
          empty_message: "No users found.",
          query: list_query,
          order: list_order,
          orderby: list_orderby(SORTABLE, default: "username"),
          search_query: params[:s].presence
        )
      end

      # get_columns(), :190-199 — LITERAL.
      def columns
        [
          ListModel::Column.new(key: "username", label: "Username", sortable: true, sort_key: "username"),
          ListModel::Column.new(key: "name", label: "Name", sortable: false),
          ListModel::Column.new(key: "email", label: "Email", sortable: true, sort_key: "email"),
          ListModel::Column.new(key: "registered", label: "Registered", sortable: true, sort_key: "registered"),
          ListModel::Column.new(key: "blogs", label: "Sites", sortable: false)
        ]
      end

      # get_bulk_actions(), :110-118.
      def bulk_actions
        actions = []
        actions << ListModel::BulkAction.new(value: "delete", label: "Delete", destructive: true) if site_can?("delete_users")
        actions << ListModel::BulkAction.new(value: "spam", label: "Mark as spam", destructive: false)
        actions << ListModel::BulkAction.new(value: "notspam", label: "Not spam", destructive: false)
        actions
      end

      # get_views(), :132-169 — 'All' and 'Super Admin'/'Super Admins'. Membership is the
      # `site_admins` NETWORK option (Tenancy::NetworkSetting), never a PHP global: BR-CAP-14
      # discarded `$super_admins` as a privilege-escalation vector (discard_log.md §4).
      def role_tabs
        total = Identity::User.count
        supers = @super_admin_ids.length
        current = params[:role].to_s
        [
          ListModel::Tab.new(key: "all", count: total,
                             label: %(All <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(total)})</span>).html_safe,
                             query: { "role" => nil }, current: current != "super"),
          ListModel::Tab.new(key: "super", count: supers,
                             label: %(#{supers == 1 ? 'Super Admin' : 'Super Admins'} <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(supers)})</span>).html_safe,
                             query: { "role" => "super" }, current: current == "super")
        ]
      end

      # :60-66 — `?role=super` restricts the query to get_super_admins().
      def role_scoped(scope)
        return scope unless params[:role].to_s == "super"

        scope.where(id: @super_admin_ids)
      end

      def searched(scope)
        term = params[:s].to_s.strip
        return scope if term.empty?

        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope.where("users.login::text ILIKE :q OR users.email::text ILIKE :q OR users.display_name ILIKE :q", q: like)
      end

      def ordered(scope)
        dir = list_order.upcase
        case list_orderby(SORTABLE, default: "username")
        when "email"      then scope.order(Arel.sql("users.email #{dir}, users.id #{dir}"))
        when "registered" then scope.order(Arel.sql("users.registered_at #{dir}, users.id #{dir}"))
        else scope.order(Arel.sql("users.login #{dir}, users.id #{dir}"))
        end
      end

      # column_blogs(), :373-440 — every site the user has a role on, each with its Edit
      # link into the Edit Site screen.
      def sites_for(users)
        return {} if users.empty?

        assignments = Identity::RoleAssignment.where(user_id: users.map(&:id)).where.not(site_id: nil)
                                              .pluck(:user_id, :site_id)
        site_ids = assignments.map(&:last).uniq
        sites = Tenancy::Site.where(id: site_ids).index_by(&:id)
        assignments.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(user_id, site_id), out|
          site = sites[site_id]
          out[user_id] << site if site
        end
      end

      def row_for(user)
        ListModel::Row.new(
          id: user.id,
          cells: {
            "username" => username_cell(user),
            "name" => ERB::Util.html_escape(user.display_name.to_s),
            "email" => %(<a href="mailto:#{ERB::Util.html_escape(user.email)}">#{ERB::Util.html_escape(user.email)}</a>).html_safe,
            "registered" => ERB::Util.html_escape(user.registered_at&.strftime("%Y/%m/%d %l:%M:%S %P").to_s.squeeze(" ")),
            "blogs" => sites_cell(user)
          },
          actions: row_actions(user),
          # :551 — a super admin carries no Delete, so it carries no checkbox either.
          selectable: !@super_admin_ids.include?(user.id)
        )
      end

      # column_username(), :265-295 — the login, then ' &mdash; Super Admin' for a network
      # administrator (:286-288).
      def username_cell(user)
        markup = +%(<strong><a href="/console/users/#{user.id}/edit">#{ERB::Util.html_escape(user.login)}</a>)
        markup << " &mdash; Super Admin" if @super_admin_ids.include?(user.id)
        markup << "</strong>"
        markup.html_safe
      end

      def sites_cell(user)
        sites = @sites_for.fetch(user.id, [])
        return "&#x2014;".html_safe if sites.empty?

        sites.map do |site|
          address = ERB::Util.html_escape(site_address(site))
          %(<span class="site-#{site.id}">#{address} <a href="/console/network/sites/#{site.id}">Edit</a></span>)
        end.join("<br>").html_safe
      end

      # :540-560 — 'Edit' always; 'Delete' unless the user is a super admin.
      def row_actions(user)
        actions = [ListModel::RowAction.new(label: "Edit", path: "/console/users/#{user.id}/edit",
                                            method: :get, key: "edit")]
        if site_can?("delete_users") && !@super_admin_ids.include?(user.id)
          actions << ListModel::RowAction.new(label: "Delete", path: bulk_path, method: :post,
                                              params: { bulk_action: "delete", confirmed: "0", "ids[]" => user.id },
                                              destructive: true, key: "delete")
        end
        actions
      end

      # users.php:189-241 — wp_delete_user() per selected id. DEV-004 confirms first.
      def destroy_users(users)
        return deny!(DELETE_DENIED) unless site_can?("delete_users")

        users = users.reject { |u| u.id == current_actor&.id }
        return redirect_to(list_path, status: :see_other) if users.empty?

        unless bulk_confirmed?
          return render_bulk_confirmation(
            title: "Confirm your action",
            # users.php:290 (help) — the bulk action "will permanently delete selected users".
            prompt: "The bulk action will permanently delete selected users, or mark/unmark " \
                    "those selected as spam. Spam users will have posts removed and will be " \
                    "unable to sign up again with the same email addresses.",
            button: "Confirm", action: "delete", ids: users.map(&:id),
            items: users.map(&:login), post_path: bulk_path, cancel_path: list_path
          )
        end

        without_tenant { users.each(&:destroy!) }
        flash[:success] = NOTICES.fetch(users.one? ? "delete" : "all_delete")
        redirect_to list_path, status: :see_other
      end

      # users.php:60-140 — the spam arm. `users.status` carries what the legacy kept in
      # `wp_users.spam`; there is no separate column to add.
      def flag_users(users, action)
        status = action == "spam" ? "spam" : "active"
        without_tenant { users.each { |user| user.update_column(:status, status) } }
        flash[:success] = NOTICES.fetch(action)
        redirect_to list_path, status: :see_other
      end

      # user-new.php:41-60 — 'Cannot create an empty user.' then the duplicate checks.
      def validate_new_user(form)
        errors = []
        if form["username"].empty? || form["email"].empty?
          errors << "Cannot create an empty user."
          return errors
        end
        errors << "Invalid email address." unless form["email"].match?(URI::MailTo::EMAIL_REGEXP)
        if Identity::User.exists?(login: form["username"]) || Identity::User.exists?(email: form["email"])
          # site-users.php:296 — 'Duplicated username or email address.'
          errors << "Duplicated username or email address."
        end
        errors
      end
    end
  end
end
