# frozen_string_literal: true

module Auth
  # The notification emails the auth screens send. Bodies and subjects are the
  # legacy's LITERAL strings (wp-includes/user.php:3360-3400, pluggable.php:2197-2400,
  # user.php:4274-4400); only the URLs in them are the target's (DEV-006) and the
  # sender identity is branding (DEV-009). Every `*_email` filter on these paths is
  # gone under AD-01: the defaults below are the only content.
  class Mailer < ApplicationMailer
    # retrieve_password(), user.php:3345-3445. Subject "[%s] Password Reset".
    def password_reset(user:, site_title:, reset_url:, requester_ip: nil)
      @user = user
      @site_title = site_title
      @reset_url = reset_url
      @requester_ip = requester_ip
      mail(to: user.email, subject: "[#{site_title}] Password Reset")
    end

    # wp_new_user_notification(), pluggable.php:2295-2327 -- the administrator's copy.
    def new_user_admin(user:, site_title:, admin_email:)
      @user = user
      @site_title = site_title
      mail(to: admin_email, subject: "[#{site_title}] New User Registration")
    end

    # wp_new_user_notification(), pluggable.php:2352-2390 -- the user's copy, with the
    # password-set link (a reset key).
    def new_user_login_details(user:, site_title:, reset_url:)
      @user = user
      @site_title = site_title
      @reset_url = reset_url
      mail(to: user.email, subject: "[#{site_title}] Login Details")
    end

    # wp_password_change_notification(), pluggable.php:2197-2240.
    def password_changed(user:, site_title:, admin_email:)
      @user = user
      @site_title = site_title
      mail(to: admin_email, subject: "[#{site_title}] Password Changed")
    end

    # _wp_privacy_send_request_confirmation_notification(), user.php:4274-4400.
    def request_confirmed(request:, site_title:, admin_email:, site_url:, manage_url:)
      @request = request
      @site_title = site_title
      @site_url = site_url
      @manage_url = manage_url
      mail(to: admin_email, subject: "[#{site_title}] Action Confirmed: #{request.description}")
    end
  end
end
