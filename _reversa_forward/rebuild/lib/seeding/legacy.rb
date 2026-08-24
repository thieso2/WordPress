# frozen_string_literal: true

module Seeding
  # The one-way read connection to the oracle's MySQL.
  #
  # ⚠️ RISK-002's residual lives here. data_migration_plan.md § Backfill and delta:
  #   "the pipeline must remain ONE-WAY. The rebuild must never write to the oracle's
  #    MySQL database, and this script must never acquire a reverse mode 'for
  #    convenience' — that would recreate the dual-write failure mode in miniature,
  #    with the oracle as the casualty."
  #
  # Enforced, not merely intended: the connection is opened against a MySQL user with
  # SELECT only, and every model below is readonly.
  class Legacy < ActiveRecord::Base
    self.abstract_class = true

    CONFIG = {
      adapter:  "mysql2",
      host:     ENV.fetch("ORACLE_DB_HOST", "127.0.0.1"),
      username: ENV.fetch("ORACLE_DB_USER", "wporacle_ro"),
      password: ENV.fetch("ORACLE_DB_PASSWORD", "oracle"),
      database: ENV.fetch("ORACLE_DB_NAME", "wp_oracle"),
      encoding: "utf8mb4",
      # The oracle stores '0000-00-00 00:00:00' in every draft. Asking mysql2 to cast
      # it would raise; T-01 needs to SEE the string in order to map it to NULL.
      cast_booleans: false,
      flags: %w[FOUND_ROWS],
    }.freeze

    establish_connection(CONFIG)

    PREFIX = ENV.fetch("ORACLE_DB_PREFIX", "wp_")

    def readonly? = true

    def self.table(name) = "#{PREFIX}#{name}"

    # Raw rows, with datetimes read as STRINGS so T-01 can see '0000-00-00 00:00:00'
    # rather than have the adapter reject or silently coerce it.
    def self.rows(sql)
      connection.select_all(sql).to_a
    end

    def self.count_of(table_name)
      connection.select_value("SELECT COUNT(*) FROM #{table(table_name)}").to_i
    rescue ActiveRecord::StatementInvalid
      nil # table absent in this install (e.g. multisite tables)
    end
  end
end
