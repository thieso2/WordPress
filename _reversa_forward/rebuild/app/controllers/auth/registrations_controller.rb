# frozen_string_literal: true

module Auth
  # auth.register (GET/POST /register) -- wp-login.php `case 'register'` (:1095-1201).
  class RegistrationsController < BaseController
    # :1108-1111: a closed site bounces to the login screen's `registration=disabled`.
    before_action :require_open_registration

    def new
      @errors = Identity::Errors.new
      @user_login = ""
      @user_email = ""
      @redirect_to = params[:redirect_to].to_s
      render :new
    end

    # :1117-1132 -> register_new_user() (user.php:3548) -> Identity::Registration.
    def create
      @user_login = params[:user_login].to_s
      @user_email = params[:user_email].to_s
      @redirect_to = params[:redirect_to].to_s

      registration = Identity::Registration.call(login: @user_login, email: @user_email, login_url: login_url)
      @errors = Identity::Errors.new
      registration.errors.each { |e| @errors.add(e.code, e.message) }

      return render(:new, status: :unprocessable_content) if @errors.any?

      # default-filters.php:541 `register_new_user` -> wp_send_new_user_notifications()
      # -> wp_new_user_notification( $id, null, 'both' ) (pluggable.php:2276).
      notify(registration.user)
      target = php_truthy?(params[:redirect_to]) ? safe_redirect_target(params[:redirect_to]) : check_email_path(checkemail: "registered")
      redirect_after_submit(target)
    end

    private

    def require_open_registration
      redirect_to login_path(registration: "disabled") unless registration_open?
    end

    # pluggable.php:2276-2400: the admin is told of the registration; the user gets a
    # password-set link, which is a reset key (get_password_reset_key(), :2352).
    def notify(user)
      admin_email = Configuration::Setting["admin_email"].to_s
      Auth::Mailer.new_user_admin(user: user, site_title: site_title_plain, admin_email: admin_email).deliver_now if admin_email.present?
      key = Identity::PasswordReset.issue_key!(user)
      Auth::Mailer.new_user_login_details(user: user, site_title: site_title_plain,
                                          reset_url: reset_password_url(login: user.login, key: key)).deliver_now
    rescue StandardError => e
      # wp_mail() failures are silent on this path in the legacy (the return value is
      # not read); the registration stands.
      Rails.logger.warn("auth.register: notification failed (#{e.class}: #{e.message})")
    end
  end
end
