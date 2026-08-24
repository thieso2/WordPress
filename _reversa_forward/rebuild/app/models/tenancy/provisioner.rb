# frozen_string_literal: true

module Tenancy
  # Provisioning a new tenant: CREATE SCHEMA + build the blog-scoped tables inside it
  # (target_screens.md Part 6: "the signup flow therefore triggers a schema creation and
  # migration run"). This is why Tenancy is sequenced LAST (RISK-009) — it is real DDL, and
  # it runs per new site.
  #
  # ── What lives where ────────────────────────────────────────────────────────────────
  # Only the BLOG-scoped tables (target_data_model.md `blog` scope) are created in the new
  # schema. The GLOBAL tables (users, role_assignments, sessions, application_passwords,
  # data_requests, the tenancy registry, and Rails' schema_migrations/ar_internal_metadata)
  # stay in the single shared/global schema — a new tenant must NOT get its own users table,
  # or a user could not be network-wide (BR-MS-01: "users and usermeta are shared
  # network-wide").
  #
  # ── How the tables are built ──────────────────────────────────────────────────────────
  # `CREATE TABLE <schema>.<t> (LIKE <global>.<t> INCLUDING ALL)` replicates each blog table
  # from the canonical copy in the global schema, including its indexes, defaults, CHECK
  # constraints and — because the columns are `GENERATED ... AS IDENTITY` (db/structure.sql)
  # — an INDEPENDENT identity sequence per schema. So two tenants get genuinely separate id
  # counters, not a shared one.
  #
  # ⚠️ Honest limitation (reported): `LIKE` does NOT copy FOREIGN KEY constraints (a Postgres
  # rule — an FK can only be defined, not cloned). The provisioned blog tables therefore have
  # their indexes and checks but not the cross-table FKs the public template carries. That is
  # acceptable for the additive skeleton and its isolation proof (row visibility is what
  # isolation turns on, and that is enforced by the schema boundary, not the FKs); the
  # production-grade path re-runs the blog-scoped migrations in the schema so the FKs are
  # recreated. Recorded as a deferred item, not hidden.
  module Provisioner
    # The blog-scoped tables, in an order safe for LIKE (order is irrelevant to LIKE since no
    # FKs are created, but kept aggregate-grouped for readability). Derived from
    # target_data_model.md's `blog` scope column. The GLOBAL tables are deliberately absent.
    # ⚠️ The edit-lock is COLUMNS on `posts` (AD-03, 20260823000300_add_edit_lock_to_posts),
    # not a table — so there is no `post_edit_locks` here. Active Storage's tables
    # (active_storage_*) are deliberately LEFT GLOBAL in this skeleton: per-tenant blob
    # isolation is a further step, noted in the report. The rest is target_data_model.md's
    # `blog` scope, verbatim.
    BLOG_TABLES = %w[
      posts revisions post_attributes post_status_transitions
      taxonomies terms term_assignments
      comments moderation_verdicts comment_rate_limits
      assets asset_variants
      settings
      menus menu_items themes templates patterns
      redirects embed_caches
    ].freeze

    module_function

    def connection = ActiveRecord::Base.connection

    def schema_exists?(schema_name)
      connection.select_value(
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = #{connection.quote(schema_name)}"
      ).present?
    end

    # Create the schema and its blog tables. Idempotent-ish: `CREATE SCHEMA IF NOT EXISTS`
    # and it skips a table that already exists, so a retry after a partial failure completes
    # rather than raising. Runs inside a transaction so a failure leaves no half-schema.
    def provision!(site)
      raise Tenancy::NotEnabled, "provisioning requires config.x.multisite.enabled" unless Tenancy.enabled?

      schema = site.schema_name
      raise Tenancy::InvalidSchemaName, schema.inspect unless schema.match?(Tenancy::SCHEMA_NAME)

      quoted = Tenancy.quote_schema(schema)
      global = Tenancy.quote_schema(Tenancy.global_schema)

      connection.transaction do
        connection.execute("CREATE SCHEMA IF NOT EXISTS #{quoted}")
        BLOG_TABLES.each do |table|
          next if table_exists_in?(schema, table)

          connection.execute(
            %(CREATE TABLE #{quoted}."#{table}" (LIKE #{global}."#{table}" INCLUDING ALL))
          )
        end
      end
      site
    end

    # Drop a tenant schema and everything in it (site teardown / test cleanup).
    def deprovision!(site)
      raise Tenancy::NotEnabled, "deprovisioning requires config.x.multisite.enabled" unless Tenancy.enabled?

      connection.execute("DROP SCHEMA IF EXISTS #{Tenancy.quote_schema(site.schema_name)} CASCADE")
    end

    def table_exists_in?(schema, table)
      connection.select_value(<<~SQL).present?
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = #{connection.quote(schema)} AND table_name = #{connection.quote(table)}
      SQL
    end
  end
end
