# frozen_string_literal: true

module Identity
  # AGG-User — target_domain_model.md § AGG-User. Identity merges the legacy's
  # users-roles-capabilities and authentication-and-sessions: sessions, credentials and
  # role storage share invariants, and session-token destruction already invalidates
  # every outstanding nonce (BR-AUTH-15), so they fail together.
  #
  # Global scope: shared across sites under multisite (Wave 5, BR-MS-01).
  class User < ApplicationRecord
    self.table_name = "users"

    has_secure_password validations: false

    has_many :role_assignments, class_name: "Identity::RoleAssignment", dependent: :destroy
    has_many :sessions, class_name: "Identity::Session", dependent: :destroy
    has_many :application_passwords, class_name: "Identity::ApplicationPassword", dependent: :destroy
    has_many :data_requests, class_name: "Identity::DataRequest", dependent: :nullify

    # ⚠️ Deliberately NO `has_many :posts`. `posts.author_id` is a real FK, so the
    # dependency is Publishing -> Identity; declaring the inverse here would make it
    # Identity -> Publishing as well and re-form the legacy users<->posts cycle
    # (handoff.md, "Six things that will bite", item 2). bin/check_cycles caught exactly
    # this on its first run against real models. Query from the Publishing side instead:
    #   Publishing::Post.where(author_id: user.id)
    # The FK's ON DELETE SET NULL already gives the `dependent: :nullify` behaviour.

    # The legacy has only non-unique KEYs on user_login and user_email; these are
    # UNIQUE indexes, and citext makes them case-insensitive as WordPress's lookups
    # already behaved.
    validates :login, :email, :nicename, presence: true,
                                         uniqueness: { case_sensitive: false }

    # BR-MIGRATE-115 / BR-AUTH-05 (wp-includes/pluggable.php:960), as an observable
    # rather than a mechanism: "the auth cookie HMAC key includes a 4-character fragment
    # of the password hash, so changing the password invalidates every outstanding
    # cookie." Here a cookie names a session row, so the same outcome is reached by
    # removing the rows when the digest changes. That also covers the legacy's quieter
    # consequence: the T-10 rehash on login changes the digest too, so a login that
    # rehashes signs every OTHER device out -- the oracle does exactly that, because
    # `$pass_frag` moves from substr(hash, 8, 4) to substr(hash, -4) (:961).
    after_update :end_all_sessions!, if: :saved_change_to_password_digest?

    # ── The login pipeline ───────────────────────────────────────────────────────
    #
    # wp_signon() (wp-includes/user.php:41) -> wp_authenticate() (pluggable.php:684) ->
    # the `authenticate` filter chain, whose unfiltered membership (default-filters.php)
    # is wp_authenticate_username_password (user.php:153), then
    # wp_authenticate_email_password (user.php:242). AD-01: that chain is fixed here;
    # the application-password and cookie handlers are not on the form's path (the
    # first needs an Authorization header, the second an empty form), and the spam
    # check (user.php:555) is multisite-only. No lockout or rate limit exists in the
    # legacy core and none is invented here.
    #
    # Returns [user, errors]: exactly one of the two is present. The messages are the
    # legacy's LITERAL strings (wp-login.php prints them raw), and the one user-supplied
    # fragment they embed is escaped with esc_html() as the legacy does
    # (user.php:185,213). `lost_password_url` is the surface's business -- the model
    # has no routes -- and is the only non-literal part of any message.
    def self.authenticate_login(login, password, lost_password_url:)
      errors = Identity::Errors.new
      # wp_authenticate(), pluggable.php:689-690: the identifier is sanitized (non-strict)
      # and the password trimmed BEFORE anything looks at either. ⚠️ RISK-008: the
      # legacy hands `$_POST['pwd']` over still slashed (user.php:53), so a legacy digest
      # of a password containing `"`, `'` or `\` is a digest of the slashed bytes. Rails
      # params are never slashed and no unslash pass is added, so such a user's real
      # password will not verify against the copied digest. Recorded as a finding.
      login = Identity::Registration.sanitize_user(login)
      password = Identity::Registration.php_trim(password.to_s)

      # wp_authenticate_username_password(), user.php:163-178. PHP `empty()`: wp_signon()
      # (:52-56, `! empty( $_POST['log'] )`) and :163 both treat the string "0" as empty,
      # so a username or password of "0" is the empty-field error, not a lookup. Verified
      # against the oracle: log=0 -> "The username field is empty.", pwd=0 -> "The
      # password field is empty."
      login_empty = login.empty? || login == "0"
      password_empty = password.empty? || password == "0"
      if login_empty || password_empty
        errors.add(:empty_username, "<strong>Error:</strong> The username field is empty.") if login_empty
        errors.add(:empty_password, "<strong>Error:</strong> The password field is empty.") if password_empty
        return [nil, errors]
      end

      user = find_by(login: login)
      if user
        return [user, nil] if user.authenticate_and_upgrade(password)

        # user.php:208: the incorrect_password message names the username.
        errors.add(:incorrect_password,
                   "<strong>Error:</strong> The password you entered for the username " \
                   "<strong>#{ERB::Util.html_escape(login)}</strong> is incorrect. " \
                   "<a href=\"#{ERB::Util.html_escape(lost_password_url)}\">Lost your password?</a>")
        return [nil, errors]
      end

      # user.php:181: invalid_username -- unless the identifier is an email address, in
      # which case wp_authenticate_email_password() (user.php:242) REPLACES the error.
      # The legacy runs both handlers; the second returns the first's error untouched
      # when `is_email()` says no (:271), and overrides it when it says yes.
      unless Identity::Registration.email?(login)
        errors.add(:invalid_username,
                   "<strong>Error:</strong> The username <strong>#{ERB::Util.html_escape(login)}</strong> " \
                   "is not registered on this site. If you are unsure of your username, try your email address instead.")
        return [nil, errors]
      end

      user = find_by(email: login)
      if user.nil?
        # user.php:278. ⚠️ No "<strong>Error:</strong>" prefix -- the oracle prints it bare.
        errors.add(:invalid_email, "Unknown email address. Check again or try your username.")
        return [nil, errors]
      end
      return [user, nil] if user.authenticate_and_upgrade(password)

      errors.add(:incorrect_password,
                 "<strong>Error:</strong> The password you entered for the email address " \
                 "<strong>#{ERB::Util.html_escape(login)}</strong> is incorrect. " \
                 "<a href=\"#{ERB::Util.html_escape(lost_password_url)}\">Lost your password?</a>")
      [nil, errors]
    end

    # get_user_by('login') then get_user_by('email'): the lookup order wp-login.php:1314
    # and retrieve_password() (user.php:3275) share. `strpos($s, '@')` is truthy only
    # for an '@' past the first character, and the email lookup is attempted only then.
    def self.find_by_identifier(identifier)
      identifier = identifier.to_s
      return nil if identifier.empty?

      at = identifier.index("@")
      find_by(login: identifier) || (at && at.positive? ? find_by(email: identifier) : nil)
    end

    # wp_signon(), user.php:119-131: a successful login clears `user_activation_key`,
    # i.e. any outstanding password-reset key is void once the owner logs in.
    def record_login!
      update_column(:activation_key_digest, nil) if activation_key_digest.present?
      self
    end

    # T-10: legacy digests are copied verbatim — the plaintext is unavailable by
    # construction. phpass ($P$), vanilla bcrypt ($2y$) and WordPress 6.8+'s prefixed
    # $wp$2y$ must all verify, and a legacy digest is transparently rehashed to the
    # target algorithm on next successful login. Identity::LegacyDigest holds the
    # formats; this is the behavioural rule the parity harness exercises.
    def authenticate_and_upgrade(candidate)
      # T-10: "an empty or malformed digest -> load the user with authentication
      # disabled ... never leave a user with a digest that accidentally verifies."
      # The unrecognised case has to be rejected HERE and not left to
      # has_secure_password: BCrypt::Password.new raises InvalidHash on a garbage
      # digest, and an exception on the login path is not "authentication fails".
      return false unless authentication_enabled?

      if legacy_digest?
        return false unless Identity::LegacyDigest.verify(candidate, password_digest)

        # Rehash on next successful login. After this the digest is plain bcrypt over
        # the password, which is what has_secure_password verifies.
        update!(password: candidate)
        self
      else
        authenticate(candidate)
      end
    end

    def authentication_enabled?
      password_digest.present? &&
        password_digest != Seeding::Transformations::DISABLED_DIGEST &&
        Identity::LegacyDigest.recognised?(password_digest)
    end

    def legacy_digest?
      Identity::LegacyDigest.needs_rehash?(password_digest)
    end

    # start_session / end_session / end_all_sessions -- the session commands
    # target_domain_model.md lists for AGG-User. `start_session!` returns the RAW token;
    # only its digest is ever at rest, so this is the one moment it exists.
    def start_session!(ttl: 14.days, ip: nil, user_agent: nil)
      Identity::Session.issue!(self, ttl: ttl, ip: ip, user_agent: user_agent)
    end

    # BR-AUTH-15: the session row IS the authority for every nonce minted under it, so
    # removing the row is the whole of "log out". There is no second list to sweep.
    def end_session!(raw_token)
      sessions.find_by(token_digest: Digest::SHA256.hexdigest(raw_token.to_s))&.destroy
    end

    # Roles are ROWS, not a serialized `role => true` map in a meta table
    # (F-MS-04, BR-CAP-13). T-03 explodes the legacy map into these rows.
    def roles(site_id: nil)
      role_assignments.where(site_id: site_id).pluck(:role)
    end

    def assign_role(role, site_id: nil)
      role_assignments.find_or_create_by!(role: role.to_s, site_id: site_id)
    end

    def revoke_role(role, site_id: nil)
      role_assignments.where(role: role.to_s, site_id: site_id).destroy_all
    end

    # BR-AUTH-15: destroying a session invalidates every outstanding nonce issued
    # under it. One invariant spanning what were two legacy modules.
    def end_all_sessions!
      sessions.destroy_all
    end

    # AGG-User accepted command `register`: the self-service form, register_new_user()
    # (wp-includes/user.php:3548) behind the `users_can_register` gate
    # (wp-login.php:1108). Returns the Identity::Registration, which carries either the
    # created user or the legacy's LITERAL error strings. See Identity::Registration.
    def self.register(login:, email:, login_url:, settings: Configuration::Setting)
      Identity::Registration.call(login: login, email: email, login_url: login_url, settings: settings)
    end

    # AGG-User accepted commands `request_data_export` / `request_erasure`:
    # wp_create_user_request() (wp-includes/user.php:4803) for this user's email.
    # See Identity::UserRequest.
    def request_data_export
      Identity::UserRequest.call(email: email, action: "export_personal_data")
    end

    def request_erasure
      Identity::UserRequest.call(email: email, action: "remove_personal_data")
    end
  end
end
