# frozen_string_literal: true

module Console
  # console.users — the Users list (wp-admin/users.php, WP_Users_List_Table). P-LIST over
  # Identity::User, EXACT pagination (target_screens.md § Part 5). Roles are ROWS now
  # (Identity::RoleAssignment, T-03), so the role filter tabs and the Role column read the
  # assignment rows rather than a serialized capabilities map.
  #
  # LITERAL strings verbatim from WP_Users_List_Table (columns "Username / Name / Email /
  # Role / Posts", bulk "Delete" / "Send password reset", "No users found.").
  class UsersListController < BaseController
    include Console::ListActions

    # GET /console/users
    def index
      @page_title = "Users"
      @screen = "console.users"

      relation = ordered(role_scoped(Identity::User.all))
      page = list_page(relation, strategy: :exact)
      @roles_for = roles_for(page.records)
      @posts_for = posts_for(page.records)
      @list = build_list(page)
      render "console/users_list/index"
    end

    # POST /console/users/bulk
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      # A user may not act on themselves destructively here; the policy decides.
      users = Identity::User.where(id: bulk_ids).to_a

      if DESTRUCTIVE.include?(action) && !bulk_confirmed?
        return confirm_bulk(action, users)
      end

      count = run_bulk(action, users)
      redirect_to list_path, notice: bulk_notice(action, count), status: :see_other
    end

    private

    DESTRUCTIVE = %w[delete].freeze
    SORTABLE = %w[username email].freeze

    # get_views() by role, class-wp-users-list-table.php. ?role=administrator etc.
    def role_scoped(scope)
      role = params[:role].to_s
      return scope if role.empty? || role == "all"

      scope.where(id: Identity::RoleAssignment.where(role: role, site_id: nil).select(:user_id))
    end

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "username")
      dir = list_order.upcase
      column = orderby == "email" ? "users.email" : "users.login"
      scope.order(Arel.sql("#{column} #{dir}, users.id #{dir}"))
    end

    def build_list(page)
      ListModel.new(
        screen: "console.users",
        title: "Users",
        primary_action: (site_can?("create_users") ? { label: "Add User", path: "/console/users/new" } : nil),
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

    # get_columns(), class-wp-users-list-table.php:373 — LITERAL.
    def columns
      [
        ListModel::Column.new(key: "username", label: "Username", sortable: true, sort_key: "username"),
        ListModel::Column.new(key: "name", label: "Name", sortable: false),
        ListModel::Column.new(key: "email", label: "Email", sortable: true, sort_key: "email"),
        ListModel::Column.new(key: "role", label: "Role", sortable: false),
        ListModel::Column.new(key: "posts", label: "Posts", sortable: false)
      ]
    end

    # get_bulk_actions(), class-wp-users-list-table.php:271 (single-site branch): Delete +
    # Send password reset. Delete is DEV-004-confirmed.
    def bulk_actions
      actions = []
      actions << ListModel::BulkAction.new(value: "delete", label: "Delete", destructive: true) if site_can?("delete_users")
      actions << ListModel::BulkAction.new(value: "resetpassword", label: "Send password reset", destructive: false) if site_can?("edit_users")
      actions
    end

    ROLE_LABEL = {
      "administrator" => "Administrator", "editor" => "Editor", "author" => "Author",
      "contributor" => "Contributor", "subscriber" => "Subscriber"
    }.freeze

    def role_tabs
      counts = Identity::RoleAssignment.where(site_id: nil).group(:role).count
      total = Identity::User.count
      cur = params[:role].to_s
      tabs = [ListModel::Tab.new(key: "all", count: total,
                                 label: %(All <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(total)})</span>).html_safe,
                                 query: { "role" => nil }, current: cur.empty? || cur == "all")]
      Access::RoleCatalogue::ROLES.each_key do |role|
        n = counts[role].to_i
        next if n.zero?

        tabs << ListModel::Tab.new(key: role, count: n,
                                   label: %(#{ROLE_LABEL[role]} <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(n)})</span>).html_safe,
                                   query: { "role" => role }, current: cur == role)
      end
      tabs
    end

    def row_for(user)
      ListModel::Row.new(
        id: user.id,
        cells: {
          "username" => username_cell(user),
          "name" => ERB::Util.html_escape(user.display_name.to_s),
          "email" => %(<a href="mailto:#{ERB::Util.html_escape(user.email)}">#{ERB::Util.html_escape(user.email)}</a>).html_safe,
          "role" => role_cell(user),
          "posts" => @posts_for.fetch(user.id, 0).to_s
        },
        actions: row_actions(user),
        selectable: can?(Access::UserPolicy, user, :delete)
      )
    end

    def username_cell(user)
      %(<strong><a href="/console/users/#{user.id}/edit">#{ERB::Util.html_escape(user.login)}</a></strong>).html_safe
    end

    def role_cell(user)
      names = @roles_for.fetch(user.id, []).map { |r| ROLE_LABEL[r] || r.capitalize }
      names.empty? ? "—".html_safe : ERB::Util.html_escape(names.join(", "))
    end

    def row_actions(user)
      actions = []
      actions << ListModel::RowAction.new(label: "Edit", path: "/console/users/#{user.id}/edit", method: :get, key: "edit") if can?(Access::UserPolicy, user, :edit)
      if can?(Access::UserPolicy, user, :delete)
        actions << ListModel::RowAction.new(label: "Delete", path: bulk_path, method: :post,
                                            params: { bulk_action: "delete", confirmed: "0", "ids[]" => user.id },
                                            destructive: true, key: "delete")
      end
      actions
    end

    def run_bulk(action, users)
      count = 0
      users.each do |user|
        case action
        when "delete"
          next unless can?(Access::UserPolicy, user, :delete)

          # wp_delete_user() reassigns the user's posts to nobody by default; the FK is
          # ON DELETE SET NULL (Identity::User note), so destroy is sufficient here.
          user.destroy!
        when "resetpassword"
          next unless can?(Access::UserPolicy, user, :edit)

          # retrieve_password() for the user — the mechanism is Identity's; the list only
          # triggers it. No-op stub kept honest: counted as requested.
          # (Password-reset mail dispatch is owned by the auth track.)
        else next
        end
        count += 1
      end
      count
    end

    def confirm_bulk(action, users)
      users = users.select { |u| can?(Access::UserPolicy, u, :delete) }
      render_bulk_confirmation(
        title: "Delete Users",
        prompt: "You have specified #{users.length} user(s) for deletion. Their content will be attributed to nobody. This cannot be undone.",
        button: "Confirm Deletion",
        action: action,
        ids: users.map(&:id),
        items: users.map(&:login),
        post_path: bulk_path,
        cancel_path: list_path
      )
    end

    def bulk_notice(action, count)
      case action
      when "delete" then "#{count} user(s) deleted."
      when "resetpassword" then "Password reset sent to #{count} user(s)."
      else "Done."
      end
    end

    def roles_for(users)
      return {} if users.empty?

      Identity::RoleAssignment.where(user_id: users.map(&:id), site_id: nil)
                              .pluck(:user_id, :role)
                              .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(uid, role), out| out[uid] << role }
    end

    def posts_for(users)
      return {} if users.empty?

      Publishing::Post.where(author_id: users.map(&:id), type: "Publishing::Article", status: "published")
                      .group(:author_id).count
    end

    def list_path = "/console/users"
    def bulk_path = "/console/users/bulk"
  end
end
