# frozen_string_literal: true

module Identity
  # AGG-User accepted command `register` (target_domain_model.md § AGG-User): the
  # self-service registration form, wp-login.php `case 'register'` (:1095-1132) ->
  # register_new_user() (wp-includes/user.php:3548-3662) -> wp_create_user() (:2997)
  # -> wp_insert_user() (:2220).
  #
  # Every string below is LITERAL (target_screens.md § auth.register), including the
  # `<strong>Error:</strong>` prefix the legacy bakes into the message, and every
  # validation rule is the legacy's pre-filter default. AD-01 removes
  # `user_registration_email`, `illegal_user_logins`, `registration_errors`,
  # `pre_user_login`, `pre_user_nicename` and the `register_post` / `register_new_user`
  # actions: the order and the outcome of the checks here are final. Verified string
  # for string against the oracle's own register_new_user() in
  # spec/models/identity/registration_differential_spec.rb.
  #
  # RISK-008: the legacy wp_unslash()es the two fields before calling
  # register_new_user() (wp-login.php:1118,1122). Rails params are never slashed, so
  # the values arrive here exactly as the user typed them and NO unslash pass exists.
  class Registration
    Error = Struct.new(:code, :message, keyword_init: true)

    # user.php:3563-3589 and :3632-3638; wp-login.php:1442.
    MESSAGES = {
      empty_username:  "<strong>Error:</strong> Please enter a username.",
      invalid_username: "<strong>Error:</strong> This username is invalid because it uses illegal characters. Please enter a valid username.",
      username_exists: "<strong>Error:</strong> This username is already registered. Please choose another one.",
      not_allowed:     "<strong>Error:</strong> Sorry, that username is not allowed.",
      empty_email:     "<strong>Error:</strong> Please type your email address.",
      invalid_email:   "<strong>Error:</strong> The email address is not correct.",
      email_exists:    '<strong>Error:</strong> This email address is already registered. <a href="%s">Log in</a> with this address or choose another one.',
      registerfail:    "<strong>Error:</strong> Could not register you&hellip; please contact the <a href=\"mailto:%s\">site admin</a>!",
      registerdisabled: "<strong>Error:</strong> User registration is currently not allowed."
    }.freeze

    # user.php:3571 / :2343: `apply_filters( 'illegal_user_logins', array() )`. Core
    # attaches nothing to that filter, so the pre-filter default is the empty list and
    # under AD-01 it is the permanent list. The check and its string are kept because
    # they are the legacy's; the arm is unreachable until someone edits this constant.
    ILLEGAL_LOGINS = [].freeze

    # wp_insert_user(): user_login is 60 characters, user_nicename 50 (:2330-2334,
    # :2365-2369). `mb_strlen`, so characters, not bytes.
    LOGIN_MAX_CHARS = 60
    NICENAME_MAX_CHARS = 50

    # register_new_user() :3629: `wp_generate_password( 12, false )` -- a throwaway;
    # the legacy emails a password-set link and never this value.
    GENERATED_PASSWORD_LENGTH = 12

    attr_reader :login, :email, :errors, :user

    # `login_url` is interpolated into the email_exists message -- `wp_login_url()` in
    # the legacy. It is a route, and routes belong to the surface, so the surface
    # passes it in.
    def initialize(login:, email:, login_url:, settings: Configuration::Setting)
      @login = login.to_s
      @email = email.to_s
      @login_url = login_url.to_s
      @settings = settings
      @errors = []
      @user = nil
    end

    def self.call(**) = new(**).call

    # wp-login.php:1108: `if ( ! get_option( 'users_can_register' ) )`.
    def self.open?(settings: Configuration::Setting)
      value = settings["users_can_register"]
      value.present? && value.to_s != "0"
    end

    def success? = errors.empty? && user.present?

    def call
      # wp-login.php:1108-1111 redirects to `?registration=disabled`, whose message
      # (:1442) is the one surfaced here.
      return fail!(:registerdisabled) unless self.class.open?(settings: @settings)

      validate_username!
      validate_email!
      return self if errors.any?                                   # :3625

      create_user!
      self
    end

    private

    def fail!(code, message = MESSAGES.fetch(code))
      errors << Error.new(code: code.to_s, message: message)
      self
    end

    # register_new_user() :3551-3575. The ORDER is the rule: one username error at most,
    # and the checks short-circuit exactly as the legacy's elseif chain does.
    def validate_username!
      @sanitized_login = Identity::Registration.sanitize_user(login)

      if @sanitized_login == ""
        fail!(:empty_username)
      elsif !Identity::Registration.valid_username?(login)
        fail!(:invalid_username)
        @sanitized_login = ""
      elsif Identity::User.exists?(login: @sanitized_login)            # username_exists()
        fail!(:username_exists)
      elsif ILLEGAL_LOGINS.map(&:downcase).include?(@sanitized_login.downcase)
        fail!(:invalid_username, MESSAGES[:not_allowed])               # code is invalid_username
      end
    end

    # :3578-3592. `is_email()` and `email_exists()`; the latter is a case-insensitive
    # lookup in both systems (MySQL collation there, citext here).
    def validate_email!
      if email == ""
        fail!(:empty_email)
      elsif !Identity::Registration.email?(email)
        fail!(:invalid_email)
      elsif Identity::User.exists?(email: email)
        fail!(:email_exists, format(MESSAGES[:email_exists], Sanitizing::Formatting.esc_url(@login_url)))
      end
    end

    # :3629-3641. wp_create_user() -> wp_insert_user(); ANY failure in there -- a login
    # over 60 characters, a nicename that sanitizes to nothing, a race on the unique
    # indexes -- collapses to the single `registerfail` message, with `admin_email`
    # interpolated. That flattening is the legacy's and it is kept.
    def create_user!
      nicename = allocate_nicename(@sanitized_login)
      raise ActiveRecord::RecordInvalid if nicename.nil?

      Identity::User.transaction do
        @user = Identity::User.create!(
          login: @sanitized_login, email: email, nicename: nicename,
          display_name: @sanitized_login,                             # :2482, no first/last name
          password: SecureRandom.alphanumeric(GENERATED_PASSWORD_LENGTH)
        )
        # :2658-2662: no explicit role -> `get_option( 'default_role' )`.
        @user.assign_role(@settings["default_role"].to_s.presence || "subscriber")
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      @user = nil
      fail!(:registerfail, format(MESSAGES[:registerfail], Sanitizing::Formatting.esc_attr(@settings["admin_email"].to_s)))
    end

    # wp_insert_user() :2323-2392, the part that can still fail after register_new_user()'s
    # own checks. Returns nil where the legacy returns a WP_Error.
    def allocate_nicename(user_login)
      return nil if user_login.empty? || user_login.length > LOGIN_MAX_CHARS

      # :2355: "build a nicename from the user_login" -- mb_substr( $user_login, 0, 50 ),
      # then sanitize_title().
      nicename = Sanitizing::Formatting.sanitize_title(user_login[0, NICENAME_MAX_CHARS]).to_s
      nicename = nicename.dup.force_encoding(Encoding::UTF_8)
      return nil if nicename.empty? || nicename.length > NICENAME_MAX_CHARS

      # :2373-2385: a nicename held by a DIFFERENT login gets a numeric suffix, and the
      # budget is 49 characters minus the suffix's width so the whole thing fits in 50.
      return nicename unless nicename_taken?(nicename, user_login)

      suffix = 2
      loop do
        base_length = 49 - suffix.to_s.length
        candidate = "#{nicename[0, base_length]}-#{suffix}"
        return candidate unless nicename_taken?(candidate, user_login)

        suffix += 1
      end
    end

    def nicename_taken?(nicename, user_login)
      Identity::User.where(nicename: nicename).where.not(login: user_login).exists?
    end

    class << self
      # sanitize_user(), wp-includes/formatting.php:2149-2177, with the `sanitize_user`
      # filter removed (AD-01).
      def sanitize_user(username, strict: false)
        s = strip_all_tags(username.to_s)
        s = Sanitizing::Formatting.remove_accents(s).dup.force_encoding(Encoding::UTF_8)
        s = s.gsub(/%([a-fA-F0-9][a-fA-F0-9])/, "")      # Remove percent-encoded characters.
        s = s.gsub(/&.+?;/, "")                           # Remove HTML entities.
        s = s.gsub(/[^a-z0-9 _.\-@]/i, "") if strict       # If strict, reduce to ASCII.
        s = php_trim(s)
        s.gsub(/\s+/, " ")                                # Consolidate contiguous whitespace.
      end

      # validate_username(), user.php:2138-2150: the strict sanitization must be the
      # identity, and the result must not be `empty()` -- which in PHP is also true of
      # the string "0".
      def valid_username?(username)
        username = username.to_s
        sanitized = sanitize_user(username, strict: true)
        sanitized == username && sanitized != "" && sanitized != "0"
      end

      # is_email(), wp-includes/formatting.php:3613-3700, with the `is_email` filter
      # removed (AD-01). Byte lengths and PCRE's `$` (which matches before a final
      # newline) are reproduced.
      def email?(email)
        email = email.to_s
        return false if email.bytesize < 6                       # email_too_short
        return false if email.index("@", 1).nil?                 # email_no_at

        local, domain = email.split("@", 2)
        return false unless local.match?(%r{\A[a-zA-Z0-9!#$%&'*+/=?^_`{|}~.\-]+\n?\z}) # local_invalid_chars
        return false if domain.match?(/\.{2,}/)                  # domain_period_sequence
        return false if php_trim(domain, ".") != domain          # domain_period_limits

        subs = domain.split(".", -1)
        return false if subs.length < 2                          # domain_no_periods

        subs.all? do |sub|
          php_trim(sub, "-") == sub &&                           # sub_hyphen_limits
            sub.match?(/\A[a-z0-9-]+\n?\z/i)                     # sub_invalid_chars
        end
      end

      # wp_strip_all_tags(), formatting.php:5610-5648, without `$remove_breaks`.
      def strip_all_tags(text)
        text = text.to_s.gsub(%r{<(script|style)[^>]*?>.*?</\1>}mi, "")
        text = Sanitizing::Formatting.strip_tags(text).dup.force_encoding(Encoding::UTF_8)
        php_trim(text)
      end

      # PHP trim(): " \t\n\r\0\x0B" plus whatever the caller adds.
      def php_trim(string, extra = "")
        chars = Regexp.escape(" \t\n\r\0\x0B#{extra}")
        string.gsub(/\A[#{chars}]+|[#{chars}]+\z/, "")
      end
    end
  end
end
