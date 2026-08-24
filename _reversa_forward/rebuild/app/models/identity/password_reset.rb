# frozen_string_literal: true

module Identity
  # The password-reset key and its lifecycle: retrieve_password() (wp-includes/user.php
  # :3261), get_password_reset_key() (:3099), check_password_reset_key() (:3175) and
  # reset_password() (:3510), plus the form rules wp-login.php `case 'resetpass'`
  # (:935-1000) applies before calling them.
  #
  # The key lives where the legacy keeps it: the user row. `user_activation_key` holds
  # "<issued-at>:<hash>" (:3157) and is `users.activation_key_digest` here; the raw key
  # exists only in the email. One key per user, the newer replacing the older, and a
  # successful login voids it (wp_signon(), :122 -- Identity::User#record_login!).
  #
  # AD-01 removes `allow_password_reset`, `password_reset_expiration`,
  # `lostpassword_user_data`, `lostpassword_errors`, `send_retrieve_password_email`,
  # `retrieve_password_message` and `password_reset_key_expired`, plus the actions
  # around them. Every string below is LITERAL (target_screens.md § auth.lostpassword,
  # § auth.resetpass); the model never sends the mail -- that is the surface's.
  module PasswordReset
    # :3152 `wp_generate_password( 20, false )`: 20 characters from [a-zA-Z0-9].
    KEY_LENGTH = 20

    # :3206 `apply_filters( 'password_reset_expiration', DAY_IN_SECONDS )`, unfiltered.
    EXPIRATION = 1.day

    # BR-MIGRATE-112 / BR-AUTH-02 (pluggable.php:2761): a password longer than 4096
    # bytes hashes to '*', which never verifies. The target keeps the consequence -- the
    # account's password is unusable until the next reset -- with the disabled sentinel
    # the seeding pipeline already uses for the same state.
    MAX_PASSWORD_BYTES = 4096

    MESSAGES = {
      # retrieve_password() :3273
      empty_username: "<strong>Error:</strong> Please enter a username or email address.",
      # :3281 (invalid_email) and :3339 (invalidcombo) share one string.
      invalid_email: "<strong>Error:</strong> There is no account with that username or email address.",
      invalidcombo: "<strong>Error:</strong> There is no account with that username or email address.",
      # get_password_reset_key() :3131 -- unreachable here (multisite spam flag only),
      # kept because the legacy's code path exists.
      no_password_reset: "Password reset is not allowed for this user",
      # check_password_reset_key() :3184-3245: both codes print the same string.
      invalid_key: "Invalid key.",
      expired_key: "Invalid key.",
      # wp-login.php:942, 947 -- the `?error=` round trip after an invalid/expired key.
      invalidkey: "<strong>Error:</strong> Your password reset link appears to be invalid. Please request a new link below.",
      expiredkey: "<strong>Error:</strong> Your password reset link has expired. Please request a new link below.",
      # wp-login.php:994, 1000. ⚠️ The first carries no "<strong>Error:</strong>" prefix.
      password_reset_empty_space: "The password cannot be a space or all spaces.",
      password_reset_mismatch: "<strong>Error:</strong> The passwords do not match."
    }.freeze

    Request = Struct.new(:user, :key, :errors, keyword_init: true) do
      def success? = errors.empty?
    end

    module_function

    # retrieve_password(), user.php:3261-3340 up to the point where the mail is built.
    # Returns a Request: on success `user` and the RAW `key` the surface must mail;
    # otherwise `errors`. The account-existence disclosure is the legacy's and is kept
    # (target_screens.md § auth.lostpassword: "preserved verbatim including its
    # account-existence disclosure behaviour").
    def request(identifier)
      errors = Identity::Errors.new
      # :3269: trimmed (the legacy also unslashes -- RISK-008: not here).
      identifier = Identity::Registration.php_trim(identifier.to_s)
      user = nil

      # :3271 `empty( $user_login )`: PHP empty(), so "0" is empty too (oracle: "0" ->
      # empty_username, not invalidcombo).
      if php_empty?(identifier)
        errors.add(:empty_username, MESSAGES[:empty_username])
      elsif (at = identifier.index("@")) && at.positive?
        # :3274-3282: by email, then by login, then the invalid_email string.
        user = Identity::User.find_by(email: identifier) || find_by_login(identifier)
        errors.add(:invalid_email, MESSAGES[:invalid_email]) if user.nil?
      else
        user = find_by_login(identifier)
      end

      return Request.new(user: nil, key: nil, errors: errors) if errors.any?
      # :3338: a username that matched nothing.
      if user.nil?
        errors.add(:invalidcombo, MESSAGES[:invalidcombo])
        return Request.new(user: nil, key: nil, errors: errors)
      end

      Request.new(user: user, key: issue_key!(user), errors: errors)
    end

    # get_password_reset_key(), user.php:3099-3172: a fresh 20-character key, stored as
    # "<unix time>:<hash>". The hash is a keyed HMAC rather than the legacy's
    # wp_fast_hash(); the algorithm is not observable, the "one key, replaced on
    # reissue, voided on login" behaviour is.
    def issue_key!(user)
      key = generate_key
      user.update_column(:activation_key_digest, "#{Time.current.to_i}:#{hash_key(key)}")
      key
    end

    # check_password_reset_key(), user.php:3175-3258. Returns [user, nil] or
    # [nil, code] with code :invalid_key or :expired_key -- the two codes wp-login.php
    # :960-966 routes to different `?error=` values.
    def check(key, login)
      # :3180: everything outside [a-z0-9] is dropped before anything else.
      key = key.to_s.gsub(/[^a-z0-9]/i, "")
      return [nil, :invalid_key] if key.empty?
      # :3188 `empty( $login )` -- PHP empty(), "0" included.
      return [nil, :invalid_key] if php_empty?(login.to_s)

      user = find_by_login(login)
      return [nil, :invalid_key] if user.nil?

      stored = user.activation_key_digest.to_s
      if stored.include?(":")
        issued_at, pass_key = stored.split(":", 2)
        expiration_time = issued_at.to_i + EXPIRATION.to_i
      else
        # :3214: a pre-4.3 key without a timestamp. The pipeline never writes one, but
        # the branch is the legacy's and it decides `expired_key` below.
        pass_key = stored
        expiration_time = false
      end
      return [nil, :invalid_key] if pass_key.blank?

      correct = ActiveSupport::SecurityUtils.secure_compare(hash_key(key), pass_key)
      return [user, nil] if correct && expiration_time && Time.current.to_i < expiration_time
      return [nil, :expired_key] if correct && expiration_time
      # :3236: a plaintext key stored pre-3.7, or a hashed key without an expiry.
      return [nil, :expired_key] if ActiveSupport::SecurityUtils.secure_compare(stored, key) || (correct && !expiration_time)

      [nil, :invalid_key]
    end

    # wp-login.php:990-1001 -- the form's own validation, BEFORE reset_password().
    # `pass1` is trimmed in place (:992); an entirely-whitespace password is an error;
    # a mismatch against the trimmed `pass2` is an error. An EMPTY pass1 is neither --
    # the legacy silently re-renders the form (:1018 requires a non-empty pass1 to
    # proceed). Returns [trimmed_pass1, errors].
    def validate(pass1, pass2)
      errors = Identity::Errors.new
      pass1 = pass1.to_s
      trimmed = pass1
      # PHP `empty()`: "" and "0" are both empty. A pass1 of "0" is therefore never
      # validated and never saved, exactly as the oracle treats it.
      if !php_empty?(pass1)
        trimmed = Identity::Registration.php_trim(pass1)
        errors.add(:password_reset_empty_space, MESSAGES[:password_reset_empty_space]) if php_empty?(trimmed)
      end
      if !php_empty?(trimmed) && Identity::Registration.php_trim(pass2.to_s) != trimmed
        errors.add(:password_reset_mismatch, MESSAGES[:password_reset_mismatch])
      end
      [trimmed, errors]
    end

    # reset_password() (user.php:3510) -> wp_set_password() (pluggable.php:3103):
    # the digest changes and `user_activation_key` is cleared. The digest change
    # destroys every session (Identity::User's after_update -- BR-AUTH-05). The
    # `default_password_nag` user meta the legacy also clears has no target column
    # (AD-03 promoted no such key), so nothing corresponds to it.
    def reset!(user, new_password)
      new_password = new_password.to_s
      user.transaction do
        if new_password.bytesize > MAX_PASSWORD_BYTES
          user.update!(password_digest: Seeding::Transformations::DISABLED_DIGEST)
        else
          # wp_hash_password() trims (pluggable.php:2757); the form already did.
          user.update!(password: new_password)
        end
        user.update_column(:activation_key_digest, nil)
      end
      user
    end

    # wp-login.php:1018: the reset only proceeds for a pass1 that is not `empty()`.
    def submitted?(trimmed_pass1) = !php_empty?(trimmed_pass1)

    # ── internals ──────────────────────────────────────────────────────────────

    def php_empty?(str) = str.nil? || str == "" || str == "0"

    # get_user_by( 'login', $value ) -- WP_User::get_data_by() (class-wp-user.php:224,
    # :241-245): a falsy value finds nothing, and the login is passed through
    # sanitize_user() (non-strict) before the lookup, so "<b>oracle_author</b>" finds
    # oracle_author, as the oracle's retrieve_password() does.
    def find_by_login(value)
      value = value.to_s
      return nil if php_empty?(value)

      Identity::User.find_by(login: Identity::Registration.sanitize_user(value))
    end

    KEY_ALPHABET = [*"a".."z", *"A".."Z", *"0".."9"].freeze

    def generate_key
      Array.new(KEY_LENGTH) { KEY_ALPHABET[SecureRandom.random_number(KEY_ALPHABET.length)] }.join
    end

    def hash_key(key)
      OpenSSL::HMAC.hexdigest("SHA256", salt, key)
    end

    def salt
      @salt ||= Rails.application.key_generator.generate_key("identity/password_reset", 32)
    end
  end
end
