# frozen_string_literal: true

module Auth
  # auth.login (GET/POST /login) and auth.logout (DELETE /session) -- wp-login.php
  # `case 'login'` (:1301-1590) and `case 'logout'` (:804-841).
  class SessionsController < BaseController
    # GET /login -- wp-login.php:1301-1590 with an empty $_POST.
    def new
      @errors = Identity::Errors.new
      @redirect_to = requested_redirect_to
      @user_login = ""
      @rememberme = false

      # :1463-1465 "Clear any stale cookies." -- `reauth` signs the browser out first
      # and renders a clean form. The session row is left to expire, as the legacy's
      # wp_clear_auth_cookie() leaves it (pluggable.php:1208).
      clear_session_cookie! if reauth?

      # :1467-1473: a reset-flow cookie left behind pre-fills the login and is cleared.
      if (reset = read_reset_cookie)
        @user_login = Identity::Registration.sanitize_user(reset.first)
        clear_reset_cookie!(path: reset_password_path)
      end

      add_get_messages(@errors) unless reauth?
      render :new
    end

    # POST /login -- wp_signon() (user.php:41) and the test-cookie check (:1353-1377).
    def create
      @redirect_to = requested_redirect_to
      # wp_signon(), user.php:58 `! empty( $_POST['rememberme'] )`.
      @rememberme = php_truthy?(params[:rememberme])
      user, errors = Identity::User.authenticate_login(params[:log].to_s, params[:pwd].to_s,
                                                       lost_password_url: lost_password_url)

      # :1363-1371: a browser that did not send the test cookie back cannot hold a
      # session, whatever the credentials were. The legacy still sets the auth cookies
      # on this path (they are useless to that browser); here no session is started.
      if params[:testcookie].present? && !test_cookie_present?
        user = nil
        errors = Identity::Errors.new.add(:test_cookie, TEST_COOKIE_MESSAGE)
      end

      if user && !reauth?
        issue_session_cookie!(user, remember: @rememberme)
        user.record_login!
        return redirect_after_submit(landing_for(user))
      end

      # :1432-1436: a successful `reauth` POST renders the clean form (the legacy sets
      # the cookies, then clears them at :1464 -- no session survives either way).
      @errors = reauth? ? Identity::Errors.new : errors
      # :1483-1485: the typed identifier is kept only for these two outcomes.
      @user_login = %w[incorrect_password empty_password].include?(@errors.code) ? params[:log].to_s : ""
      render :new, status: :unprocessable_content
    end

    # DELETE /session -- wp-login.php:804-841. check_admin_referer('log-out') is the
    # request-forgery token; Rails' authenticity token stands in (DEV-006). wp_logout()
    # (pluggable.php:744): destroy the CURRENT session row, clear the cookie. Not
    # `:authenticated`: the legacy runs this for a logged-out browser too and lands it
    # on the same "You are now logged out." screen.
    def destroy
      current_session&.destroy
      clear_session_cookie!

      # :811-824: an explicit redirect_to is honoured (safely); the default is the
      # login screen with the logged-out message.
      target = if params[:redirect_to].present?
                 safe_redirect_target(params[:redirect_to])
               else
                 login_path(loggedout: "true")
               end
      redirect_after_submit(target)
    end

    private

    TEST_COOKIE_MESSAGE = "<strong>Error:</strong> Cookies are blocked or not supported by your browser. " \
                          "You must <a href=\"https://developer.wordpress.org/advanced-administration/wordpress/cookies/" \
                          "#enable-cookies-in-your-browser\">enable cookies</a> to use WordPress."

    # :1314 `! empty( $_REQUEST['reauth'] )`.
    def reauth? = php_truthy?(params[:reauth])

    # :1324-1333: `redirect_to` from the request, default admin_url().
    def requested_redirect_to
      params[:redirect_to].is_a?(String) && params[:redirect_to].present? ? params[:redirect_to] : CONSOLE_PATH
    end

    # :1440-1459: the messages the login form shows on arrival. `about.php?updated`,
    # recovery mode and authorize-application have no target screen.
    def add_get_messages(errors)
      # :1447 `isset( $_GET['loggedout'] ) && $_GET['loggedout']` -- "0" shows nothing.
      if php_truthy?(params[:loggedout])
        errors.add(:loggedout, "You are now logged out.", severity: :message)
      elsif params[:registration] == "disabled"
        errors.add(:registerdisabled, "<strong>Error:</strong> User registration is currently not allowed.")
      end
      # wp-login.php:1024: the reset flow's success notice, carried here over the
      # redirect (target_screens.md § auth.resetpass: "then routes to auth.login").
      if flash[:password_reset]
        errors.add(:password_reset, "Your password has been reset. <a href=\"#{ERB::Util.html_escape(login_path)}\">Log in</a>",
                   severity: :message)
      end
    end

    # :1411-1428. An explicit, safe redirect_to wins; the admin default is refined by
    # capability -- no `edit_posts` sends a reader to their profile and anyone else home.
    def landing_for(user)
      requested = @redirect_to
      admin_default = requested.blank? || [CONSOLE_PATH, "#{CONSOLE_PATH}/"].include?(requested) ||
                      requested == "#{request.base_url}#{CONSOLE_PATH}/" || requested == "#{request.base_url}#{CONSOLE_PATH}"
      if admin_default
        return requested.presence || CONSOLE_PATH if actor_has_capability?(user, "edit_posts")

        return actor_has_capability?(user, "read") ? PROFILE_PATH : "/"
      end

      safe_redirect_target(requested)
    end
  end
end
