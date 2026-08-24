# frozen_string_literal: true

module Auth
  # auth.lostpassword (GET/POST /login/lost-password) -- wp-login.php
  # `case 'lostpassword': case 'retrievepassword':` (:843-933). DEV-010:
  # `retrievepassword` is an alias of this action, not a second screen.
  class LostPasswordsController < BaseController
    def new
      @errors = Identity::Errors.new
      add_key_error(@errors)
      @user_login = ""
      @redirect_to = params[:redirect_to].to_s
      render :new
    end

    # :845-853 -> retrieve_password() (user.php:3261).
    def create
      result = Identity::PasswordReset.request(params[:user_login].to_s)
      @errors = result.errors
      @redirect_to = params[:redirect_to].to_s

      if @errors.empty?
        deliver_reset_mail(result) or return render_form
        # :848: an explicit redirect_to wins, else the check-email screen.
        target = php_truthy?(params[:redirect_to]) ? safe_redirect_target(params[:redirect_to]) : check_email_path(checkemail: "confirm")
        return redirect_after_submit(target)
      end

      render_form
    end

    private

    def render_form
      # :877-879: the typed value is kept.
      @user_login = params[:user_login].to_s
      render :new, status: :unprocessable_content
    end

    # :856-862: the reset screen bounces here with `?error=invalidkey|expiredkey`.
    def add_key_error(errors)
      case params[:error]
      when "invalidkey" then errors.add(:invalidkey, Identity::PasswordReset::MESSAGES[:invalidkey])
      when "expiredkey" then errors.add(:expiredkey, Identity::PasswordReset::MESSAGES[:expiredkey])
      end
    end

    # user.php:3345-3445: the mail, and the one failure the form reports.
    def deliver_reset_mail(result)
      Auth::Mailer.password_reset(
        user: result.user, site_title: site_title_plain,
        reset_url: reset_password_url(login: result.user.login, key: result.key),
        # :3399: the requester's address is named only for an anonymous request.
        requester_ip: (current_actor ? nil : request.remote_ip)
      ).deliver_now
      true
    rescue StandardError => e
      Rails.logger.warn("auth.lostpassword: mail delivery failed (#{e.class}: #{e.message})")
      @errors.add(:retrieve_password_email_failure,
                  "<strong>Error:</strong> The email could not be sent. Your site may not be correctly configured to send emails. " \
                  "<a href=\"https://wordpress.org/documentation/article/reset-your-password/\">Get support for resetting your password</a>.")
      false
    end
  end
end
