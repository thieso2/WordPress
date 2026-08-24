# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-332..342. Most filesystem rules are shared-hosting transport MECHANISM that
# Active Storage absorbs; what is reproduced is the surviving write-boundary invariant and
# the signature-check provenance (delegated to Egress::SignatureVerifier).
RSpec.describe Platform::Storage do
  it "keeps the legacy uploads URL space every golden screen references" do
    expect(described_class::BASE_URL).to eq("/wp-content/uploads")
  end

  describe "the surviving filesystem invariant — the write boundary (parity_specs.md)" do
    it "accepts a relative key that stays inside the store" do
      expect(described_class.within_boundary?("2026/03/photo.png")).to be(true)
    end

    it "refuses a key whose .. segment escapes the declared root" do
      expect(described_class.within_boundary?("2026/../../etc/passwd")).to be(false)
    end

    it "refuses an empty key" do
      expect(described_class.within_boundary?("")).to be(false)
    end
  end

  describe "the signature-check provenance (BR-MIGRATE-340/341)" do
    it "mirrors the verifier's length and algorithm rather than re-deriving them" do
      expect(described_class::SIGNATURE_BYTES).to eq(Egress::SignatureVerifier::SIGNATURE_BYTES)
      expect(described_class::SIGNATURE_BYTES).to eq(64)   # SODIUM_CRYPTO_SIGN_BYTES
      expect(described_class::HASH_ALGORITHM).to eq(Egress::SignatureVerifier::HASH_ALGORITHM)
      expect(described_class::HASH_ALGORITHM).to eq("SHA384")
    end

    it "routes verification to the single implementation (Egress::SignatureVerifier)" do
      expect(Egress::SignatureVerifier).to receive(:new).and_call_original
      # An empty signature list verifies nothing — the verifier reports no_signature (not
      # an unsupported failure), returned as-is through the Platform façade.
      result = described_class.verify_package_signature(content: "x", signatures: [],
                                                        filename_for_errors: "pkg.zip")
      expect(result.verified?).to be(false)
      # no_signature where Ed25519/SHA-384 are available; unsupported where they are not —
      # either way an unverified result, never a silent pass.
      expect(result.error_code).to be_in(%w[signature_verification_no_signature
                                            signature_verification_unsupported])
    end
  end
end
