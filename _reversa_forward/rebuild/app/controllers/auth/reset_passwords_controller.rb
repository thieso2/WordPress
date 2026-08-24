# frozen_string_literal: true

module Auth
  # auth.resetpass (GET/POST /login/reset-password) -- wp-login.php `case 'resetpass':
  # case 'rp':` (:906-1093).
  #
  # The key arrives in the emailed URL (`?login=&key=`), is moved into the
  # `wp-resetpass` cookie and the URL is redirected clean (:911-916) so the key never
  # sits in a referrer. Every later request reads the cookie. The form carries the key
  # again as `rp_key`, and the two must agree (:923-925).
  class ResetPasswordsController < BaseController
    def show
      if params[:key].is_a?(String) && params[:login].is_a?(String)
        write_reset_cookie!(params[:login], params[:key], path: request.path)
        return redirect_to reset_password_path
      end

      user, code = resolve_user
      return bounce(code) unless user

      @errors = Identity::Errors.new
      @rp_login = user.login
      @rp_key = @rp_key_from_cookie
      render :show
    end

    def create
      user, code = resolve_user
      # :923-925: a submitted form whose rp_key is not the cookie's key is no user at all.
      # `isset( $_POST['pass1'] )`: an empty or all-spaces pass1 still triggers the check
      # (oracle: pass1="" or "   " with a wrong rp_key -> bounce to error=invalidkey).
      if user && params.key?(:pass1) &&
         !ActiveSupport::SecurityUtils.secure_compare(@rp_key_from_cookie.to_s, params[:rp_key].to_s)
        user = nil
        code = :invalid_key
      end
      return bounce(code) unless user

      pass1, @errors = Identity::PasswordReset.validate(params[:pass1], params[:pass2])

      # :1018-1034: a non-empty, valid pass1 resets and shows the success notice.
      if @errors.empty? && Identity::PasswordReset.submitted?(pass1)
        Identity::PasswordReset.reset!(user, pass1)
        notify_password_change(user)
        flash[:password_reset] = true
        return redirect_after_submit(login_path)
      end

      @rp_login = user.login
      @rp_key = @rp_key_from_cookie
      render :show, status: :unprocessable_content
    end

    private

    # :918-932: the cookie names the login and key; check_password_reset_key() decides.
    def resolve_user
      login, key = read_reset_cookie
      @rp_key_from_cookie = key
      return [nil, :invalid_key] if login.nil?

      Identity::PasswordReset.check(key, login)
    end

    # :935-945: clear the cookie and send the visitor back to request a new link, with
    # the reason in the query string.
    def bounce(code)
      clear_reset_cookie!(path: reset_password_path)
      redirect_to lost_password_path(error: code == :expired_key ? "expiredkey" : "invalidkey"),
                  status: (request.post? ? :see_other : :found)
    end

    # default-filters.php:540 `after_password_reset` -> wp_password_change_notification()
    # (pluggable.php:2197): the admin is told, unless the admin is the one resetting.
    def notify_password_change(user)
      admin_email = Configuration::Setting["admin_email"].to_s
      return if admin_email.casecmp?(user.email.to_s)

      Auth::Mailer.password_changed(user: user, site_title: site_title_plain, admin_email: admin_email).deliver_now
    rescue StandardError => e
      Rails.logger.warn("auth.resetpass: admin notification failed (#{e.class}: #{e.message})")
    end
  end
end
