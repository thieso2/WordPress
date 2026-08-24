# frozen_string_literal: true

module Platform
  # The upgrader — BR-MIGRATE-343..351 (BR-UPD-01..09).
  #
  # ⚠️ FRAMEWORK ABSORPTION (topology_decision.md: updates-and-upgrader, "absorbed by the
  # framework"). This is the most-absorbed group in the wave: the legacy upgrader polls
  # wordpress.org, downloads core/plugin/theme packages, and rewrites files on disk — and
  # the rebuild is NOT WordPress, has no update server, ships plugins/themes as tables not
  # files (AD-02), and deploys through the framework, not through in-place file swaps. So
  # the map is:
  #
  #   VOID — no analogue (the rebuild has no wordpress.org to poll; recorded, not built):
  #     BR-MIGRATE-343 (update_core/update_plugins/update_themes site transients)
  #     BR-MIGRATE-344 (check-timeout escalation 1min→1hr→2hr→12hr)
  #     BR-MIGRATE-345 (re-check suppressed within 12h of last_checked)
  #       → these three describe POLLING an external update API. There is no such API here.
  #         `Rails.cache` (Solid Cache) is the transient store the legacy used, but there
  #         is nothing to cache into it — no analogue, void. See VOID_UPDATE_CHECK.
  #
  #   ABSORBED — mechanism replaced part-for-part, observable kept elsewhere:
  #     BR-MIGRATE-348 (core update-core.php per-version file manifests, delete obsolete
  #       files) → the deploy pipeline. A release IS the manifest; there is no runtime
  #       file-removal step to reproduce.
  #     BR-MIGRATE-349/350/351 (upgrade_NNN sequence / dbDelta diff / $wp_db_version) →
  #       Rails migrations + schema_migrations, reproduced as Platform::SchemaVersion.
  #       This module DEFERS to it rather than restating it.
  #
  #   REPRODUCED — observable behaviour, wired to the framework equivalent:
  #     BR-MIGRATE-346 (packages signature-verified AFTER download, BEFORE extraction) →
  #       Egress::Package#install! (built). The ORDER is the observable, and it is already
  #       enforced there; this module names it and defers.
  #     BR-MIGRATE-347 (the site enters maintenance mode for the duration of
  #       install_package()) → a REAL maintenance flag, reproduced here as
  #       Platform::Updates::Maintenance, and `install_package` wraps a package install in
  #       it so the two rules (346 verify-before-extract, 347 maintenance-spans-install)
  #       compose exactly as class-wp-upgrader.php runs them.
  #
  # Pure-Ruby leaf: reads Rails.cache and Egress (a service), depends on no app/models
  # namespace and no delivery surface.
  module Updates
    # BR-MIGRATE-343/344/345 named as void, so a reader of the rule set finds the decision
    # here rather than an absence. Nothing polls; nothing is cached; the timeout ladder
    # has no clock to climb.
    VOID_UPDATE_CHECK = %w[BR-MIGRATE-343 BR-MIGRATE-344 BR-MIGRATE-345].freeze

    # BR-MIGRATE-347 (BR-UPD-05). "The site enters maintenance mode for the duration of
    # install_package()." The legacy writes ABSPATH/.maintenance holding
    # `$upgrading = time()` and treats the site as under maintenance until that timestamp
    # is 10 minutes old (class-wp-upgrader.php:1032, wp-includes/load.php:447).
    #
    # Reproduced as a REAL flag, not a file: a timestamp in Rails.cache (Solid Cache,
    # persistent, framework-owned) with the same 10-minute window. No global mutable state
    # (implication 1) — the flag lives in the shared cache, read explicitly, never a
    # process global like the legacy's `$upgrading`.
    module Maintenance
      # wp-includes/load.php:447 — `( time() - $upgrading ) >= 10 * MINUTE_IN_SECONDS`.
      WINDOW = 10 * 60
      CACHE_KEY = "platform/maintenance"

      module_function

      # Enter maintenance (upgrader::maintenance_mode(true)). Records the moment; the flag
      # self-expires after WINDOW so a crashed install cannot wedge the site forever,
      # exactly as the legacy's 10-minute staleness check does.
      def enable
        Rails.cache.write(CACHE_KEY, Time.current.to_i, expires_in: WINDOW)
      end

      # Leave maintenance (upgrader::maintenance_mode(false)) — the legacy deletes the file.
      def disable
        Rails.cache.delete(CACHE_KEY)
      end

      # wp_is_maintenance_mode(): true only while the flag exists AND its timestamp is
      # younger than the window. A stale timestamp is not maintenance (:447).
      def active?
        started = Rails.cache.read(CACHE_KEY)
        return false if started.nil?

        (Time.current.to_i - started.to_i) < WINDOW
      end

      # Run a block with the site in maintenance, guaranteeing it is lifted afterward —
      # the try/ensure shape of install_package()'s maintenance_mode(true)…(false).
      def during
        enable
        yield
      ensure
        disable
      end
    end

    module_function

    # BR-MIGRATE-346 + BR-MIGRATE-347 composed, the way WP_Upgrader::install_package runs
    # them: maintenance spans the whole install (347), and inside it the package is
    # verified before a single byte is extracted (346, enforced by Egress::Package). The
    # verification and extraction themselves are Egress's; this method owns only the
    # maintenance envelope around them.
    #
    # @param package [Egress::Package] a downloaded, not-yet-extracted package.
    # @param into    [#write] the extraction destination (memory or a directory).
    # @return the destination, after a verified extraction.
    def install_package(package, into:)
      Maintenance.during do
        package.install!(into: into) # verifies (346), then extracts; raises if unverified.
        into
      end
    end

    # BR-MIGRATE-349/350/351 do not live here — they are Platform::SchemaVersion. This
    # accessor exists so "is the schema current?" is answerable from the upgrader surface
    # the way the legacy answered it from wp-admin/upgrade.php, without duplicating the
    # logic.
    def schema_current? = SchemaVersion.up_to_date?
  end
end
