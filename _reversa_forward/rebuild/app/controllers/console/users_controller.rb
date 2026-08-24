# frozen_string_literal: true

module Console
  # console.user-edit / console.user-new (P-EDIT). Legacy origin: wp-admin/user-edit.php
  # and wp-admin/user-new.php, both saving through edit_user() (wp-admin/includes/user.php:30).
  #
  # ROLES ARE ROWS (T-03, F-MS-04): the legacy's serialized `{prefix}capabilities` map is
  # gone; a role is an Identity::RoleAssignment. Setting a role on this screen REPLACES the
  # user's site role, as wp_update_user()/set_role() does.
  #
  # ⚠️ Fields that have no column in the target model are NOT reproduced: first_name,
  # last_name, nickname, biographical info (usermeta, dropped — target_data_model.md), and
  # admin_color (DEV-008). The surviving editable fields are email, url, display_name,
  # locale, password and role.
  #
  # ⚠️ edit_user()'s validation MESSAGES are verbatim from the legacy but do NOT live on
  # Identity::User (its validations are the DB-backed uniqueness/presence, AD-05). The admin
  # form carries them here — the one place in this track where the error text is the
  # surface's rather than the model's, because the legacy admin owns these strings, not the
  # user object. The DB unique indexes remain the backstop.
  class UsersController < BaseController
    include UserForm

    before_action :load_user, only: %i[edit update]
    before_action :authorize_edit, only: %i[edit update]
    before_action :authorize_create, only: %i[new create]

    # GET /console/users/:id/edit — user-edit.php.
    def edit
      @page_title = "Edit User" # user-edit.php:44 title (LITERAL)
      @form_errors = []
      render :edit
    end

    # PATCH/PUT /console/users/:id — edit_user( $user_id ).
    def update
      @form_errors = []
      apply_profile_fields(@user)
      apply_password(@user, update: true)
      role = apply_role(@user)
      return if performed? # apply_role may deny! (an ineligible role → 403)

      if @form_errors.empty? && @user.save
        set_role!(@user, role) if role
        flash[:success] = "User updated." # user-edit.php update messages (LITERAL)
        redirect_to edit_console_user_path(@user), status: :see_other
      else
        collect_model_errors(@user)
        @page_title = "Edit User"
        render :edit, status: :unprocessable_content
      end
    end

    # GET /console/users/new — user-new.php.
    def new
      @page_title = "Add User" # user-new.php:269 title (LITERAL)
      @user = Identity::User.new
      @form_errors = []
      @new_user_role = Configuration::Setting["default_role"].presence || "subscriber"
      render :new
    end

    # POST /console/users — edit_user() with no id (create branch).
    def create
      @page_title = "Add User"
      @form_errors = []
      @user = Identity::User.new
      login = params[:user_login].to_s

      validate_new_login(login)
      @user.login = login
      @user.nicename = unique_nicename(login)
      @user.display_name = login if @user.display_name.blank?
      apply_profile_fields(@user)
      apply_password(@user, update: false)
      role = apply_role(@user) || (Configuration::Setting["default_role"].presence || "subscriber")
      return if performed? # apply_role may deny! (an ineligible role → 403)

      @new_user_role = role

      if @form_errors.empty? && @user.save
        set_role!(@user, role)
        flash[:success] = "New user created." # user-new.php messages (LITERAL)
        redirect_to edit_console_user_path(@user), status: :see_other
      else
        collect_model_errors(@user)
        render :new, status: :unprocessable_content
      end
    end

    private

    # includes/user.php:47-58: a role is applied only with promote_users, and only when it
    # is an editable role — otherwise wp_die( 'Sorry, you are not allowed to give users that
    # role.', 403 ). Returns the role string to set after save, or nil.
    def apply_role(user)
      return nil unless params.key?(:role) && params[:role].present?
      return nil unless Access::UserPolicy.new(current_actor, user).permit?(:promote)

      role = params[:role].to_s
      unless Access::RoleCatalogue::ROLES.key?(role)
        deny!("Sorry, you are not allowed to give users that role.")
        return nil
      end
      role
    end

    def set_role!(user, role)
      user.role_assignments.where(site_id: nil).destroy_all
      user.assign_role(role)
    end

    # ── create-only username validation (includes/user.php:186-199) ──────────────────

    def validate_new_login(login)
      if login.strip.empty?
        add_error("<strong>Error:</strong> Please enter a username.")
      elsif !Identity::Registration.valid_username?(login)
        add_error("<strong>Error:</strong> This username is invalid because it uses illegal characters. Please enter a valid username.")
      elsif Identity::User.exists?(login: login)
        add_error("<strong>Error:</strong> This username is already registered. Please choose another one.")
      end
    end

    def unique_nicename(login)
      base = Sanitizing::Formatting.sanitize_title(login).presence || "user"
      return base unless Identity::User.exists?(nicename: base)

      suffix = 2
      suffix += 1 while Identity::User.exists?(nicename: "#{base}-#{suffix}")
      "#{base}-#{suffix}"
    end

    # ── loading + authorization ──────────────────────────────────────────────────────

    def load_user
      @user = Identity::User.find_by(id: params[:id])
      not_found!("Invalid user ID.") if @user.nil? # user-edit.php:26
    end

    def authorize_edit
      return if performed?

      # user-edit.php:56 — current_user_can( 'edit_user', $user_id ). Editing oneself is
      # allowed with no capability (BR-CAP-07/BR-MIGRATE-103, an empty set that ALLOWS).
      authorize!(Access::UserPolicy, @user, :edit,
                 "Sorry, you are not allowed to edit this user.")
    end

    def authorize_create
      # user-new.php:22 — current_user_can( 'create_users' ).
      authorize!(Access::UserPolicy, Identity::User.new, :create,
                 "Sorry, you are not allowed to create users.")
    end
  end
end
