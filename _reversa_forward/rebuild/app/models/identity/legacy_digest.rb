# frozen_string_literal: true

require "bcrypt"

module Identity
  # T-10: "The target must verify legacy phpass ($P$) and bcrypt ($2y$) digests, and
  # transparently rehash to the target algorithm on next successful login."
  #
  # The plan names two formats; the oracle actually ships a third, and it is the one
  # every user in a WordPress 7.2 corpus carries. wp_hash_password()
  # (wp-includes/pluggable.php) since 6.8:
  #
  #     $password_to_hash = base64_encode( hash_hmac('sha384', trim($password), 'wp-sha384', true) );
  #     return '$wp' . password_hash( $password_to_hash, PASSWORD_BCRYPT, $options );
  #
  # The '$wp' prefix exists "to facilitate distinguishing vanilla bcrypt hashes", and the
  # SHA-384 pre-hash exists "to retain entropy from a password that's longer than 72
  # bytes" — bcrypt's input limit.
  #
  # ⚠️ Reproduced asymmetry: wp_hash_password() trims the password before hashing;
  # wp_check_password() does NOT trim before verifying. So a password with leading or
  # trailing whitespace hashes one way and verifies another. That is the unfiltered
  # default, and under AD-01 it is the specification. Do not "fix" it here — a parity
  # test asserts it.
  module LegacyDigest
    WP_PREFIX = "$wp"
    HMAC_KEY = "wp-sha384"
    PHPASS_PREFIXES = %w[$P$ $H$].freeze
    BCRYPT_PREFIXES = %w[$2y$ $2a$ $2b$].freeze

    # The digest the TARGET writes: bcrypt via has_secure_password, which bcrypt-ruby
    # emits with the $2a$ prefix. Everything else recognised here arrived from the
    # legacy corpus and is rehashed on next successful login (T-10).
    TARGET_PREFIX = "$2a$"

    module_function

    def format_of(digest)
      d = digest.to_s
      return :wp_bcrypt if d.start_with?(WP_PREFIX)
      return :phpass    if PHPASS_PREFIXES.any? { |p| d.start_with?(p) }
      return :bcrypt    if BCRYPT_PREFIXES.any? { |p| d.start_with?(p) }
      return :md5       if d.length == 32 && d.match?(/\A[0-9a-f]{32}\z/)

      :unknown
    end

    def recognised?(digest) = format_of(digest) != :unknown

    def verify(password, digest)
      case format_of(digest)
      when :wp_bcrypt then verify_wp_bcrypt(password, digest)
      when :bcrypt    then safe_bcrypt(digest, password.to_s)
      when :phpass    then PhpassVerifier.verify(password, digest)
      when :md5
        ActiveSupport::SecurityUtils.secure_compare(Digest::MD5.hexdigest(password.to_s), digest.to_s)
      else
        false
      end
    end

    # Every legacy format is upgradeable: the target algorithm is plain bcrypt over the
    # password itself, via has_secure_password.
    def upgradeable?(digest) = format_of(digest) != :unknown

    # Mirror of wp_password_needs_rehash() (wp-includes/pluggable.php:2911), which is the
    # half of T-10 that is easy to lose. T-10 names TWO legacy formats to rehash --
    # phpass ($P$) *and* bcrypt ($2y$) -- and the oracle agrees:
    #
    #   wp_password_needs_rehash('$2y$12$...')     === true   // not $wp-prefixed
    #   wp_password_needs_rehash('$wp$2y$12$...')  === false  // already the target format
    #
    # The legacy distinguishes its own digests by the '$wp' prefix; here the target
    # format is what has_secure_password writes, so the discriminator is TARGET_PREFIX.
    # A PHP-produced $2y$ digest verifies (bcrypt-ruby reads it) but is still a legacy
    # digest, and treating it as native is exactly how a corpus never finishes migrating.
    def needs_rehash?(digest)
      recognised?(digest) && !digest.to_s.start_with?(TARGET_PREFIX)
    end

    def pre_hash(password)
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA384", HMAC_KEY, password.to_s))
    end

    def verify_wp_bcrypt(password, digest)
      # Note: no trim() here — wp_check_password() does not trim. See the ⚠️ above.
      safe_bcrypt(digest.to_s.delete_prefix(WP_PREFIX), pre_hash(password))
    end

    def safe_bcrypt(hash, candidate)
      BCrypt::Password.new(hash) == candidate
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end
end
