# frozen_string_literal: true

module Egress
  # BR-MIGRATE-338 (BR-FS-07), BR-MIGRATE-340 (BR-FS-09), BR-MIGRATE-341 (BR-FS-10).
  # Legacy: verify_file_signature(), wp-admin/includes/file.php:1410.
  #
  # ⚠️ CONTINGENT on DEV-011 -- see Egress::TrustedKeys.
  #
  # Rule 4 (no copy editing): the three message strings below are the legacy's, verbatim,
  # `<span class="code">` and all.
  class SignatureVerifier
    # SODIUM_CRYPTO_SIGN_BYTES.
    SIGNATURE_BYTES = 64
    # Packages are hashed with SHA-384 and the DETACHED signature is over that digest,
    # not over the file bytes (file.php:1483: hash_file('sha384', $filename, true)).
    HASH_ALGORITHM = "SHA384"

    UNSUPPORTED_MESSAGE = "The authenticity of <span class=\"code\">%s</span> could not be " \
                          "verified as signature verification is unavailable on this system."
    NO_SIGNATURE_MESSAGE = "The authenticity of <span class=\"code\">%s</span> could not be " \
                           "verified as no signature was found."
    FAILED_MESSAGE = "The authenticity of <span class=\"code\">%s</span> could not be verified."

    # The legacy returns `true`, `false` or a WP_Error whose data carries `skipped_key`
    # and `skipped_sig`. Those counters are part of its observable output (BR-FS-09 names
    # them), so they are part of this result rather than an internal tally.
    Result = Struct.new(:verified, :error_code, :message, :skipped_signatures, :skipped_keys,
                        keyword_init: true) do
      def verified? = verified
      def failed? = !verified
    end

    def initialize(trusted_keys:)
      @trusted_keys = trusted_keys
    end

    def verify(content:, signatures:, filename_for_errors: "package")
      # BR-MIGRATE-338 (BR-FS-07): a runtime that cannot do Ed25519 or SHA-384 reports
      # signature_verification_unsupported -- explicitly NOT a verification failure.
      unless self.class.supported?
        return unsupported(filename_for_errors)
      end

      signatures = Array(signatures).reject { |s| s.nil? || s.to_s.strip.empty? }
      if signatures.empty?
        return Result.new(verified: false, error_code: "signature_verification_no_signature",
                          message: format(NO_SIGNATURE_MESSAGE, filename_for_errors),
                          skipped_signatures: 0, skipped_keys: 0)
      end

      digest = OpenSSL::Digest.digest(HASH_ALGORITHM, content)
      skipped_signatures = 0
      skipped_keys = 0

      signatures.each do |signature|
        raw = decode64(signature)
        # BR-MIGRATE-340 (BR-FS-09): a signature whose DECODED length is not 64 bytes is
        # skipped and counted -- it is never handed to the verifier, and it never counts
        # as a valid one either.
        if raw.nil? || raw.bytesize != SIGNATURE_BYTES
          skipped_signatures += 1
          next
        end

        @trusted_keys.each do |key|
          public_key = load_key(key)
          if public_key.nil?
            skipped_keys += 1
            next
          end

          return Result.new(verified: true, skipped_signatures: skipped_signatures,
                            skipped_keys: skipped_keys) if verified?(public_key, raw, digest)
        end
      end

      Result.new(verified: false, error_code: "signature_verification_failed",
                 message: format(FAILED_MESSAGE, filename_for_errors),
                 skipped_signatures: skipped_signatures, skipped_keys: skipped_keys)
    end

    def self.supported?
      OpenSSL::Digest.new(HASH_ALGORITHM)
      OpenSSL::PKey.new_raw_public_key("ED25519", "\x00".b * TrustedKeys::PUBLIC_KEY_BYTES)
      true
    rescue StandardError
      false
    end

    private

    def unsupported(filename)
      Result.new(verified: false, error_code: "signature_verification_unsupported",
                 message: format(UNSUPPORTED_MESSAGE, filename),
                 skipped_signatures: 0, skipped_keys: 0)
    end

    def decode64(value)
      Base64.decode64(value.to_s)
    rescue ArgumentError
      nil
    end

    # Only pass valid public keys through (file.php:1500): 32 raw bytes, or skipped.
    def load_key(key)
      raw = decode64(key)
      return nil if raw.nil? || raw.bytesize != TrustedKeys::PUBLIC_KEY_BYTES

      OpenSSL::PKey.new_raw_public_key("ED25519", raw)
    rescue OpenSSL::PKey::PKeyError
      nil
    end

    def verified?(public_key, signature, digest)
      public_key.verify(nil, signature, digest)
    rescue OpenSSL::PKey::PKeyError
      false
    end
  end
end
