# frozen_string_literal: true

module Auth
  # auth.checkemail (GET /login/check-email) -- wp-login.php `case 'checkemail'`
  # (:1203-1235). Message only; which message depends on `checkemail=confirm`
  # (lost password) or `checkemail=registered` (registration). Any other value shows
  # the title alone, as the legacy does.
  class CheckEmailsController < BaseController
    def show
      @errors = Identity::Errors.new
      case params[:checkemail]
      when "confirm"
        @errors.add(:confirm,
                    "Check your email for the confirmation link, then visit the <a href=\"#{ERB::Util.html_escape(login_url)}\">login page</a>.",
                    severity: :message)
      when "registered"
        @errors.add(:registered,
                    "Registration complete. Please check your email, then visit the <a href=\"#{ERB::Util.html_escape(login_url)}\">login page</a>.",
                    severity: :message)
      end
      render :show
    end
  end
end
