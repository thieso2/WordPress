# frozen_string_literal: true

module Tenancy
  # wp-signup.php — the three signup screens (target_screens.md Part 6):
  #   * tenancy.user_signup  GET  /signup        — username + email
  #   * tenancy.blog_signup   GET  /signup/site   — site address, title, privacy
  #   * tenancy.signup_confirm GET /signup/confirm — "check your inbox"
  # POST targets write a Tenancy::Signup (the wp_signups row) with an activation_key; the
  # provisioning of the actual PostgreSQL schema happens at /activate time, not here.
  class SignupsController < BaseController
    # tenancy.user_signup — the account form. wp-signup.php:280-320 (signup_user()).
    def user_signup
      @user_login = params[:user_name].to_s
      @user_email = params[:user_email].to_s
      @errors = []
      render :user_signup
    end

    # tenancy.blog_signup — the site form. wp-signup.php:150-260 (signup_blog()). In the
    # legacy this is the second step of one page; here it is its own screen and carries the
    # account fields forward as hidden params.
    def blog_signup
      @user_login = params[:user_name].to_s
      @user_email = params[:user_email].to_s
      @blog_domain = params[:blogname].to_s
      @blog_title = params[:blog_title].to_s
      @blog_public = params.fetch(:blog_public, "1").to_s
      @errors = []
      render :blog_signup
    end

    # POST /signup — decides which of the two flows the submit belongs to, validates, writes
    # the Signup, and advances. `signup_form` in the legacy branches on `stage`
    # (wp-signup.php:990). A blog signup with a site address goes straight to confirm; a
    # user-only signup ('user' radio) does too. A first submit of just the account fields
    # advances to the site form.
    def create
      @user_login = params[:user_name].to_s.strip
      @user_email = params[:user_email].to_s.strip
      @blog_domain = params[:blogname].to_s.strip
      @blog_title = params[:blog_title].to_s.strip
      @blog_public = params.fetch(:blog_public, "1").to_s
      @signup_kind = params[:signup_for].presence || (@blog_domain.present? ? "blog" : "user")
      @errors = validate

      if @errors.any?
        template = @signup_kind == "blog" ? :blog_signup : :user_signup
        return render(template, status: :unprocessable_content)
      end

      # No site yet: an account-only first step with the site form still to come.
      if @signup_kind == "blog" && @blog_domain.blank?
        return render(:blog_signup)
      end

      signup = build_signup
      signup.save!

      # ⚠️ No email is sent (Action Mailer is out of this track's scope); the activation_key
      # is surfaced to the confirmation screen so the flow is walkable end-to-end. Recorded
      # as a deferred wiring point.
      redirect_to signup_confirm_path(email: signup.user_email, key: signup.activation_key),
                  status: :see_other
    end

    # tenancy.signup_confirm — the "almost ready / check your inbox" message.
    # wp-signup.php:700-725 (user) and :860-885 (blog).
    def confirm
      @user_email = params[:email].to_s
      @activation_key = params[:key].to_s
      # The confirmation copy differs by signup kind (confirm_user_signup vs
      # confirm_blog_signup). Recover the persisted signup by its activation_key.
      @signup = Tenancy::Signup.find_by(activation_key: @activation_key)
      @signup_kind = @signup&.kind || "user"
      @user_login = @signup&.user_login.to_s
      @blog_domain = @signup&.domain.to_s
      @blog_path = @signup&.path.to_s
      @blog_title = @signup&.title.to_s
      render :confirm
    end

    private

    def build_signup
      if @signup_kind == "blog"
        Tenancy::Signup.new(kind: "blog", user_login: @user_login, user_email: @user_email,
                            domain: @blog_domain, path: "/", title: @blog_title.presence || @blog_domain,
                            meta: { "blog_public" => @blog_public })
      else
        Tenancy::Signup.new(kind: "user", user_login: @user_login, user_email: @user_email)
      end
    end

    # The legacy's validation lives in wpmu_validate_user_signup()/wpmu_validate_blog_signup().
    # The observable subset: non-empty username/email, a plausible email, and — for a blog —
    # a site address that is not already taken. Literal messages from wp-signup.php.
    def validate
      errors = []
      errors << "Please enter a username." if @user_login.blank?
      errors << "Please enter a valid email address." unless @user_email.match?(URI::MailTo::EMAIL_REGEXP)
      if @signup_kind == "blog" && @blog_domain.present?
        errors << "Sorry, that site already exists!" if Tenancy::Site.exists?(domain: @blog_domain, path: "/")
      end
      errors
    end
  end
end
