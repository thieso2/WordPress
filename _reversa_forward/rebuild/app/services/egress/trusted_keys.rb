# frozen_string_literal: true

module Egress
  # BR-MIGRATE-341 (BR-FS-10), the keys half. Legacy: wp_trusted_keys(),
  # wp-admin/includes/file.php:1545 -- an array of base64-encoded Ed25519 public keys.
  #
  # ⚠️ CONTINGENT (parity_specs.md, ambiguity P-4): this rule is live only because
  # DEV-011 kept `console.theme-install`. If remote theme installation is dropped,
  # BR-FS-07, BR-FS-09, BR-FS-10 and BR-UPD-04 become VOID together and this file goes
  # with them.
  #
  # AD-01: the legacy's `wp_trusted_keys` filter is not reproduced. The trusted set is
  # what it is; it is configuration data, not an extension point.
  class TrustedKeys
    include Enumerable

    # Ed25519 public keys are 32 raw bytes (SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES).
    PUBLIC_KEY_BYTES = 32

    def self.default = new(Configuration::Setting["trusted_signing_keys"] || [])

    def initialize(base64_keys) = @base64_keys = Array(base64_keys)

    def each(&) = @base64_keys.each(&)
    def to_a = @base64_keys.dup
    def empty? = @base64_keys.empty?
  end
end
