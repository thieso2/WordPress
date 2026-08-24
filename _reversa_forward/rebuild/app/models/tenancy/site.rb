# frozen_string_literal: true

module Tenancy
  # A site = a PostgreSQL SCHEMA (BR-MS-01 / BR-MIGRATE-357). This is the registry row that
  # names the schema and maps a host+path to it; it lives in the GLOBAL schema (like the
  # legacy `wp_blogs`/`wp_site`, which target_data_model.md :583 deferred to Wave 5 because
  # "the schema-per-site model replaces most of them"). It is the ONE table read before a
  # tenant is known, so it is never itself tenant-scoped.
  #
  # The legacy addressed a blog by `blog_id` and derived the table prefix `wp_{blog_id}_`
  # (class-wpdb.php:291). Here the address is `schema_name` and the tables are real
  # PostgreSQL objects in that schema — no prefix arithmetic, and `search_path` does the
  # selection the prefix used to do.
  class Site < ApplicationRecord
    self.table_name = "sites"

    # sunrise.php (BR-MS-06 / BR-MIGRATE-361) resolved a request host to a blog before
    # network bootstrap, enabling domain mapping. That was a drop-in mechanism, gone under
    # AD-01/DEV-011; the OBSERVABLE part — host+path → site — is these two columns and
    # Tenancy::Resolver. Domain mapping beyond a direct match is noted, not built.
    validates :domain, presence: true
    validates :path, presence: true
    validates :schema_name, presence: true, uniqueness: true,
                            format: { with: Tenancy::SCHEMA_NAME }
    validates :domain, uniqueness: { scope: :path }

    has_many :signups, class_name: "Tenancy::Signup", foreign_key: :site_id, dependent: :nullify,
                       inverse_of: :site

    # A blog's status flags (legacy wp_blogs.archived/deleted/spam). Kept as observable
    # state; a non-public/archived/deleted site is resolvable but its front end is gated by
    # the surface, not by mutating any global.
    def active? = !archived? && !deleted? && !spam?

    # schema_name defaults to a deterministic, collision-free identifier derived from the
    # row id. Assigned after insert (id is not known before), so callers may also pass an
    # explicit schema_name (the signup flow derives one from the requested site address).
    before_validation :assign_default_schema_name, on: :create

    # RISK-009 caveat surfaced as code: provisioning creates the schema + tables, so a Site
    # row without its schema is a half-created tenant. Tenancy::Provisioner.provision!
    # is the paired operation; `provisioned?` asks PostgreSQL, not this row.
    def provisioned?
      self.class.connection.select_value(
        "SELECT 1 FROM information_schema.schemata WHERE schema_name = #{self.class.connection.quote(schema_name)}"
      ).present?
    end

    # Run a block with this site's schema on the search_path. Delegates to Tenancy.switch,
    # which restores the previous context on exit (no ambient stack — BR-MS-02 stays gone).
    def switch(&block) = Tenancy.switch(self, &block)

    private

    def assign_default_schema_name
      return if schema_name.present?

      # A transient placeholder that is replaced with `site_<id>` in after_create; unique
      # enough to pass the insert, readable once the id is known.
      self.schema_name = "site_pending_#{SecureRandom.hex(6)}"
    end

    after_create :assign_id_schema_name

    def assign_id_schema_name
      return unless schema_name.start_with?("site_pending_")

      update_column(:schema_name, "site_#{id}")
    end
  end
end
