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
      # extra_tablenav():298-320 — the bulk role-change control is rendered only with
      # promote_users and only when the table has rows (has_items()).
      @can_promote_users = site_can?("promote_users") && page.records.any?
      @list = build_list(page)
      render "console/users_list/index"
    end

    # POST /console/users/bulk
    def bulk
      # current_action():351-361 — the role-change control (extra_tablenav) submits its own
      # `changeit` button, which the oracle maps to the 'promote' action ahead of the plain
      # bulk-action select. So it is dispatched first, regardless of the select's value.
      return promote if params[:changeit].present?

      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      users = Identity::User.where(id: bulk_ids).to_a

      case action
      when "delete"
        # users.php:284-486 — the "Delete Users" screen forces a per-user content choice
        # before dodelete runs (DEV-004 confirmation, here carrying the oracle's own radios).
        return confirm_delete(users) unless bulk_confirmed?

        perform_delete(users)
      when "resetpassword"
        count = run_reset(users)
        flash[:success] = reset_notice(count)
        redirect_to list_path, status: :see_other
      else
        redirect_to list_path, status: :see_other
      end
    end

    private

    SORTABLE = %w[username email].freeze

    # get_views() by role, class-wp-users-list-table.php. ?role=administrator etc. The
    # `none` view (class-wp-users-list-table.php:243-260) returns the users with NO role
    # for this site — the assignment-row negation, not a literal role named "none".
    def role_scoped(scope)
      role = params[:role].to_s
      return scope if role.empty? || role == "all"

      site_assignees = Identity::RoleAssignment.where(site_id: nil).select(:user_id)
      return scope.where.not(id: site_assignees) if role == "none"

      scope.where(id: Identity::RoleAssignment.where(role: role, site_id: nil).select(:user_id))
    end

    # avail_roles['none'] — the count of users with no role for this site.
    def no_role_count
      Identity::User.where.not(id: Identity::RoleAssignment.where(site_id: nil).select(:user_id)).count
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
      # get_views():243-260 — the "No role" view link, shown only when users exist with no
      # role for this site (avail_roles['none']). LITERAL label "No role".
      none = no_role_count
      if none.positive?
        tabs << ListModel::Tab.new(key: "none", count: none,
                                   label: %(No role <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(none)})</span>).html_safe,
                                   query: { "role" => "none" }, current: cur == "none")
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
          "posts" => posts_cell(user)
        },
        actions: row_actions(user),
        selectable: can?(Access::UserPolicy, user, :delete)
      )
    end

    def username_cell(user)
      %(<strong><a href="/console/users/#{user.id}/edit">#{ERB::Util.html_escape(user.login)}</a></strong>).html_safe
    end

    # posts column, class-wp-users-list-table.php:606-621. When numposts > 0 the count is a
    # LINK to the user's posts (edit.php?author=ID → the P-LIST posts screen filtered by
    # author) carrying the accessible "%s posts by this author" text; otherwise a bare 0.
    def posts_cell(user)
      numposts = @posts_for.fetch(user.id, 0)
      return "0".html_safe unless numposts.positive?

      label = numposts == 1 ? "1 post by this author" : "#{ActiveSupport::NumberHelper.number_to_delimited(numposts)} posts by this author"
      %(<a href="/console/posts?author=#{user.id}" class="edit"><span aria-hidden="true">#{numposts}</span><span class="screen-reader-text">#{ERB::Util.html_escape(label)}</span></a>).html_safe
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
      # single_row():502-508 — a per-row "Send password reset" link, gated on edit_user and
      # excluded for the current user (wp_is_password_reset_allowed_for_user is true by
      # default here). LITERAL label "Send password reset".
      if user.id != current_actor&.id && can?(Access::UserPolicy, user, :edit)
        actions << ListModel::RowAction.new(label: "Send password reset", path: bulk_path, method: :post,
                                            params: { bulk_action: "resetpassword", confirmed: "0", "ids[]" => user.id },
                                            destructive: false, key: "resetpassword")
      end
      actions
    end

    # ── Bulk role change (users.php:108-176, the 'promote' action) ─────────────────────
    #
    # The role-change control in extra_tablenav() submits `new_role` + `changeit`, gated on
    # promote_users. set_role() is applied to every selected user, with the oracle's
    # self-role guards. LITERAL wp_die/notice strings throughout.
    def promote
      unless site_can?("promote_users")
        return deny!("Sorry, you are not allowed to edit this user.")
      end
      return redirect_to(list_path, status: :see_other) if bulk_ids.empty?

      role = params[:new_role].to_s
      # get_editable_roles() + the mocked 'none' role (users.php:130-133).
      unless valid_promote_role?(role)
        return deny!("Sorry, you are not allowed to give users that role.")
      end

      target = role == "none" ? "" : role # 'none' → set_role('') removes the site role
      users = Identity::User.where(id: bulk_ids).to_a
      others_changed = 0
      admin_role_error = false

      users.each do |user|
        unless can?(Access::UserPolicy, user, :promote)
          return deny!("Sorry, you are not allowed to edit this user.")
        end

        if user.id == current_actor&.id
          # :146-160 — the current user's own role is never changed through this tool.
          if target.empty?
            return deny!("Sorry, you cannot remove your own role.")
          end

          # A role that still grants promote_users is silently kept (continue); otherwise
          # err_admin_role and the role is left unchanged.
          admin_role_error = true unless Access::RoleCatalogue::ROLES.fetch(role, []).include?("promote_users")
          next
        end

        set_user_role(user, target)
        others_changed += 1
      end

      if admin_role_error
        flash[:error] = "You cannot change your own role to one that does not allow managing other users. Your role was not changed."
        flash[:success] = "Other user roles have been changed." if others_changed.positive?
      else
        flash[:success] = "Changed roles."
      end
      redirect_to list_path, status: :see_other
    end

    def valid_promote_role?(role)
      return false if role.empty?

      role == "none" || Access::RoleCatalogue::ROLES.key?(role)
    end

    def set_user_role(user, role)
      user.role_assignments.where(site_id: nil).destroy_all
      user.assign_role(role) unless role.empty?
    end

    # ── Delete Users (users.php:284-486 render + :188-241 dodelete) ─────────────────────
    #
    # The interstitial forces a per-user content choice — "Delete all content." vs
    # "Attribute all content to another user." — before anything is destroyed. Rendered by
    # the cluster's own view (the shared confirm partial has no content-reassignment slot).
    def confirm_delete(users)
      @delete_users = users.select { |u| can?(Access::UserPolicy, u, :delete) }
      @delete_current_id = current_actor&.id
      @delete_deletable = @delete_users.reject { |u| u.id == @delete_current_id }
      @delete_reassign_candidates = Identity::User.where.not(id: @delete_deletable.map(&:id)).order(:login).to_a
      with_content = Publishing::Post.where(author_id: @delete_deletable.map(&:id)).distinct.pluck(:author_id).to_set
      @delete_has_content = @delete_deletable.to_h { |u| [u.id, with_content.include?(u.id)] }
      @delete_error = params[:error].present?
      @page_title = "Delete Users"
      render "console/users_list/delete", status: :ok
    end

    # dodelete (users.php:188-241): per-user, honour the content choice, guard the current
    # user, then destroy. 'delete' removes the user's posts; 'reassign' moves them to the
    # chosen user first (wp_delete_user($id, $reassign)).
    def perform_delete(users)
      users = users.select { |u| can?(Access::UserPolicy, u, :delete) }
      current_id = current_actor&.id
      delete_options = params[:delete_option] || {}
      reassign_user = params[:reassign_user] || {}

      # A content-owning user with no option chosen → re-render with "Please select an option."
      needs_choice = users.any? do |u|
        u.id != current_id && user_has_content?(u) && !%w[delete reassign].include?(delete_options[u.id.to_s].to_s)
      end
      if needs_choice
        params[:error] = "1"
        return confirm_delete(users)
      end

      delete_count = 0
      admin_del_error = false
      missing_reassign = false

      users.each do |user|
        if user.id == current_id
          admin_del_error = true
          next
        end

        option = delete_options[user.id.to_s].to_s
        if option == "reassign" && reassign_user[user.id.to_s].to_s.strip.empty?
          missing_reassign = true
          next
        end

        case option
        when "reassign"
          Publishing::Post.where(author_id: user.id).update_all(author_id: reassign_user[user.id.to_s].to_i)
        else
          # 'delete' (or a content-free user): remove the user's posts (wp_delete_post per
          # post). destroy_all runs the dependent associations so no child FK is orphaned.
          Publishing::Post.where(author_id: user.id).destroy_all
        end
        user.destroy!
        delete_count += 1
      end

      if missing_reassign
        flash[:error] = "Users could not be deleted because no user was selected for content reassignment."
        flash[:success] = "Other users have been deleted." if delete_count.positive?
      elsif admin_del_error
        flash[:error] = "You cannot delete the current user."
        flash[:success] = "Other users have been deleted." if delete_count.positive?
      else
        flash[:success] = delete_notice(delete_count)
      end
      redirect_to list_path, status: :see_other
    end

    def user_has_content?(user)
      Publishing::Post.where(author_id: user.id).exists?
    end

    def run_reset(users)
      count = 0
      current_id = current_actor&.id
      users.each do |user|
        next unless can?(Access::UserPolicy, user, :edit)
        next if user.id == current_id # :262-265 err_admin_reset — self excluded

        # retrieve_password() for the user — the mechanism is Identity's; the list only
        # triggers it. (Password-reset mail dispatch is owned by the auth track.)
        count += 1
      end
      count
    end

    # :643-654 — "User deleted." for one, "%s users deleted." for many.
    def delete_notice(count)
      count == 1 ? "User deleted." : "#{ActiveSupport::NumberHelper.number_to_delimited(count)} users deleted."
    end

    # :687-696 — "Password reset link sent." for one, "Password reset links sent to %s users."
    def reset_notice(count)
      count == 1 ? "Password reset link sent." : "Password reset links sent to #{ActiveSupport::NumberHelper.number_to_delimited(count)} users."
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
