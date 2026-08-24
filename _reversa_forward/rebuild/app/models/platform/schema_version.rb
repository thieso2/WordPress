# frozen_string_literal: true

module Platform
  # BR-MIGRATE-351 (BR-UPD-09), BR-MIGRATE-349 (BR-UPD-07), BR-MIGRATE-350 (BR-UPD-08).
  #
  # ⚠️ FRAMEWORK ABSORPTION (topology_decision.md: updates-and-upgrader, "absorbed by the
  # framework"). The legacy schema-migration MECHANISM is gone here, replaced part for
  # part by Rails' own:
  #
  #   * BR-MIGRATE-351 — "$wp_db_version in version.php is the single schema version
  #     marker" (version.php:26, `$wp_db_version = 61833`). Rails' single marker is the
  #     `schema_migrations` table, read as `migration_context.current_version`. This
  #     module IS that marker, given a name. The legacy integer is kept as
  #     `LEGACY_DB_VERSION` for provenance, not as a live gate — the rebuild is not
  #     WordPress and does not share its numbering.
  #
  #   * BR-MIGRATE-349 — "version-gated upgrade_NNN() functions applied in sequence from
  #     the site's current db version" → Rails migrations, applied in timestamp order
  #     from `current_version`. `db/migrate/*` files ARE the upgrade_NNN() sequence; the
  #     "current vs target" gate the legacy runs on every admin load (upgrade.php's
  #     `wp_get_db_schema` compare) survives as `#up_to_date?` / `#pending`.
  #
  #   * BR-MIGRATE-350 — "dbDelta() diffs the declared CREATE TABLE schema against the
  #     live schema and emits the necessary ALTER statements" → `db/schema.rb` +
  #     `bin/rails db:migrate`, which is exactly a declared-vs-live diff. The mechanism is
  #     absorbed; the OBSERVABLE it protected — "is the live database at the schema this
  #     code expects?" — is reproduced as `#up_to_date?`.
  #
  # What is BEHAVIOUR here, not mechanism: a caller can ask whether the database is at the
  # schema this deployment expects, and, if not, which migrations are outstanding. That is
  # the one thing the legacy's version gate did that a running system still needs — the
  # rest (running the ALTERs) is `bin/rails db:migrate`, Rails' job, not this module's.
  #
  # Pure-Ruby leaf: reads the connection's migration context and nothing in `app/`.
  module SchemaVersion
    # version.php:26 at the pinned revision. Provenance only — see the header.
    LEGACY_DB_VERSION = 61_833

    module_function

    # The single marker (BR-MIGRATE-351): the highest migration version the live database
    # has recorded. `nil` before any migration has run (a fresh, empty database).
    def current
      migration_context.current_version
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      nil
    end

    # The schema this deployment's code expects — the newest migration on disk. This is
    # the legacy's `$wp_db_version` constant: the number baked into the shipped code that
    # the live database is compared against.
    def target
      migrations.last&.version
    end

    # BR-MIGRATE-349/350's surviving observable: is the live database at the schema this
    # code was written for? The legacy answered this on every admin page load and forced
    # /wp-admin/upgrade.php when it was false.
    def up_to_date?
      !migration_context.needs_migration?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    # The upgrade_NNN() functions still to run, in the sequence they would run — the
    # migrations recorded on disk but not in `schema_migrations`. Empty when up to date.
    def pending
      migration_context.open.pending_migrations.map(&:version)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      []
    end

    # A status report over the three facts a site-health / diagnostics surface reads.
    def report
      {
        current: current,
        target: target,
        up_to_date: up_to_date?,
        pending: pending,
        legacy_db_version: LEGACY_DB_VERSION,
      }
    end

    # Rails 8.1 moved the migration context off the connection and onto the pool
    # (`connection.migration_context` was removed) — the marker lives with the pool that
    # owns the schema, not with a borrowed connection.
    def migration_context
      ActiveRecord::Base.connection_pool.migration_context
    end

    def migrations
      migration_context.migrations
    end
  end
end
