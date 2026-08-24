# frozen_string_literal: true

module Platform
  # The uploads store, as a platform primitive — BR-MIGRATE-332..342 (BR-FS-01..11).
  #
  # ⚠️ FRAMEWORK ABSORPTION (topology_decision.md: filesystem-api, "absorbed by the
  # framework"). Active Storage owns files. The legacy's WP_Filesystem machinery is a
  # SHARED-HOSTING concern — it exists because WordPress cannot assume it may write to its
  # own directory and must negotiate a transport (direct / ssh2 / ftpext / ftpsockets) and
  # prove file ownership before it dares. Under a deployed Rails app writing to its own
  # configured store, none of that negotiation has an analogue. So of the eleven
  # filesystem rules, most are MECHANISM the framework replaced:
  #
  #   ABSORBED (no observable analogue — recorded as void, not reproduced):
  #     BR-MIGRATE-332 (FS_METHOD constant overrides detection)          — no transport to pick
  #     BR-MIGRATE-333 (direct write requires matching file OWNER)       — Active Storage owns its root
  #     BR-MIGRATE-334 ($allow_relaxed_file_ownership bypass)            — no ownership probe exists
  #     BR-MIGRATE-335 ($_wp_filesystem_direct_method rationale record)  — no method to record
  #     BR-MIGRATE-336 (fallback order direct→ssh2→ftpext→ftpsockets)    — one store, no fallbacks
  #     BR-MIGRATE-337 (probe the PARENT of a missing target dir)        — mkdir_p, no probe
  #     BR-MIGRATE-342 (PclZip pure-PHP fallback for ZipArchive)         — Ruby's stdlib, no fallback
  #
  #   REPRODUCED as OBSERVABLE behaviour, wired to the framework equivalent:
  #     BR-MIGRATE-338/339/340/341 — the package SIGNATURE checks (length, algorithm,
  #       skip-and-count). These are NOT filesystem-transport machinery; they are the
  #       observable authenticity contract of a downloaded package, and they live in
  #       Egress::SignatureVerifier (built, Wave 4). This module points at that authority
  #       rather than restating it (SIGNATURE_BYTES / HASH_ALGORITHM below mirror it) —
  #       ⚠️ CONTINGENT on DEV-011 (console.theme-install), same as the verifier.
  #     The one surviving filesystem INVARIANT the deviated rules kept (parity_specs.md):
  #       "the application never writes outside its declared storage paths." The uploads
  #       service enforces it (unsafe-key refusal, `..`-segment rejection); this module
  #       names the boundary so a caller can ask where it is.
  #
  # What is BEHAVIOUR here: the store's location (the URL space every golden screen
  # references), the safe-write boundary, and the listing wp_unique_filename() scans. The
  # attachment SEMANTICS on top — unique naming, /YYYY/MM foldering, MIME sniffing — are
  # Library's (Library::Asset, ::UploadDirectory, ::FileName, Wave 3), which build on this
  # primitive. Storage is the byte store; Library is the domain layer above it.
  #
  # Pure-Ruby leaf: reads the Active Storage service and Configuration, depends on no
  # surface and no other app/models namespace.
  module Storage
    # wp_get_upload_dir()['baseurl'] shape — the URL prefix every golden screen references
    # (/wp-content/uploads/YYYY/MM/<name>). The store keeps the blob key AS this relative
    # path (lib/active_storage/service/uploads_service.rb), so the static file server
    # answers the legacy URL with no controller in between.
    BASE_URL = "/wp-content/uploads"

    # Mirror of Egress::SignatureVerifier's constants (BR-MIGRATE-340/341), surfaced here
    # so the filesystem-rule provenance has a home in the Platform namespace the
    # architecture names. The VERIFIER is the single implementation — do not re-derive.
    SIGNATURE_BYTES = Egress::SignatureVerifier::SIGNATURE_BYTES   # 64, SODIUM_CRYPTO_SIGN_BYTES
    HASH_ALGORITHM  = Egress::SignatureVerifier::HASH_ALGORITHM    # "SHA384"

    module_function

    # The configured Active Storage service backing uploads (:uploads in every env). The
    # ONE place the byte store is reached, so "where do files live" has a single answer.
    def service
      ActiveStorage::Blob.services.fetch(:uploads)
    rescue KeyError
      ActiveStorage::Blob.service
    end

    # The absolute root of the uploads store — the legacy's $upload_dir['basedir']. The
    # boundary the write invariant is measured against.
    def root
      service.respond_to?(:root) ? service.root.to_s : nil
    end

    # The files already present under one relative subdirectory, which is what
    # wp_unique_filename() (functions.php:2589) scans before naming a new upload — files
    # copied in by `assets:sync` included, exactly as the legacy sees a directory rather
    # than a table. Delegated to the service so there is one listing implementation.
    def existing_names(subdir)
      service.respond_to?(:existing_names) ? service.existing_names(subdir.to_s) : []
    end

    # The write-boundary predicate (the surviving filesystem invariant): is this relative
    # key one the store will accept, i.e. does it stay inside the declared root? A key
    # with a `..` segment escapes it and is refused — the same check the uploads service
    # makes on write, exposed so a caller can ask BEFORE writing.
    def within_boundary?(key)
      segments = key.to_s.split("/")
      return false if segments.empty?

      !segments.include?("..")
    end

    # The BR-MIGRATE-338..341 authenticity check, routed to its single implementation.
    # Kept here so the filesystem-rule provenance resolves within Platform, but it holds
    # no logic of its own — Egress::SignatureVerifier is the authority.
    def verify_package_signature(content:, signatures:, filename_for_errors: "package", trusted_keys: Egress::TrustedKeys.default)
      Egress::SignatureVerifier.new(trusted_keys: trusted_keys)
                               .verify(content: content, signatures: signatures,
                                       filename_for_errors: filename_for_errors)
    end
  end
end
