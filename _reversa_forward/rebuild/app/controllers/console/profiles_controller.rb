# frozen_string_literal: true

module Console
  # console.profile — the current user's own account screen (P-EDIT). Legacy origin:
  # wp-admin/profile.php (IS_PROFILE_PAGE), saving through edit_user( get_current_user_id() ).
  #
  # ⚠️ DEV-008: `admin_color` is NOT reproduced (no admin colour schemes, DEV-005; no
  # admin_color column). The editor preferences (rich_editing, syntax_highlighting, toolbar)
  # have no column either and are dropped. The surviving editable fields are email, url
  # (Website), display_name, locale (Language) and password. There is no role editor on the
  # profile screen (a user cannot promote themselves here).
  class ProfilesController < BaseController
    include UserForm

    before_action :load_self

    # GET /console/profile — profile.php. Editing oneself needs no capability
    # (BR-CAP-07): Access::UserPolicy(:edit) returns an empty set that ALLOWS, so the
    # single auth gate (a live session) is the whole of it.
    def show
      @page_title = "Profile" # profile.php:40 (LITERAL)
      @form_errors = []
      render :show
    end

    # PATCH/PUT /console/profile — edit_user( current user ).
    def update
      @page_title = "Profile"
      @form_errors = []
      apply_profile_fields(@user)
      apply_password(@user, update: true)

      if @form_errors.empty? && @user.save
        # profile.php update: "Profile updated." — and a password change ends the other
        # sessions (Identity::User#end_all_sessions!), so re-issue this browser's cookie so
        # the actor is not logged out of the screen they just saved.
        reissue_session_if_password_changed
        flash[:success] = "Profile updated."
        redirect_to console_profile_path, status: :see_other
      else
        collect_model_errors(@user)
        render :show, status: :unprocessable_content
      end
    end

    private

    def load_self
      @user = current_actor
      # The auth gate guarantees an actor; this is belt-and-braces for a session that
      # resolved to nil between the gate and here.
      auth_redirect if @user.nil?
    end

    # Identity::User#after_update destroys every session when the digest changes
    # (BR-AUTH-05). On the profile screen the acting browser must survive its own password
    # change, so a fresh session is started and the cookie rewritten — the legacy does the
    # same via wp_clear_auth_cookie()+wp_set_auth_cookie() (user.php:255-260).
    def reissue_session_if_password_changed
      return unless @user.saved_change_to_password_digest?

      issue_session_cookie!(@user, remember: false)
    end
  end
end
