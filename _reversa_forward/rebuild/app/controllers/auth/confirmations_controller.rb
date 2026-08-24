# frozen_string_literal: true

module Auth
  # auth.confirmaction (GET /login/confirm) -- wp-login.php `case 'confirmaction'`
  # (:1237-1274): the link in a privacy-request email. The legacy answers every failure
  # with wp_die() (an HTTP 500 page); here each is the screen's error state with the
  # same LITERAL string and a 4xx status.
  class ConfirmationsController < BaseController
    def show
      @errors = Identity::Errors.new
      return fail_with("Missing request ID.") unless params.key?(:request_id)
      return fail_with("Missing confirm key.") unless params.key?(:confirm_key)

      # :1246: sanitize_text_field() on the key (the unslash is RISK-008's absence).
      key = Identity::Registration.strip_all_tags(params[:confirm_key].to_s).gsub(/\s+/, " ")
      request_record, code = Identity::DataRequest.validate_key(params[:request_id], key)
      return fail_with(Identity::DataRequest::MESSAGES.fetch(code)) unless request_record

      # default-filters.php:453-454: confirm, then notify the administrator.
      request_record.confirm!
      notify_admin(request_record)

      @request = request_record
      @title = "User action confirmed."
      @message = request_record.confirmed_message
      render :show
    end

    private

    def fail_with(message)
      @errors.add(:confirmaction, message)
      @title = "User action confirmed."
      render :show, status: :unprocessable_content
    end

    # _wp_privacy_send_request_confirmation_notification(), user.php:4274-4400.
    def notify_admin(request_record)
      admin_email = Configuration::Setting["admin_email"].to_s
      return if admin_email.blank?

      Auth::Mailer.request_confirmed(request: request_record, site_title: site_title_plain, admin_email: admin_email,
                                     site_url: site_url, manage_url: "#{site_url}#{CONSOLE_PATH}/privacy/#{request_record.kind}").deliver_now
    rescue StandardError => e
      Rails.logger.warn("auth.confirmaction: admin notification failed (#{e.class}: #{e.message})")
    end
  end
end
