# frozen_string_literal: true

# Tenancy wiring (Wave 5). Two jobs, both STRICTLY ADDITIVE:
#   1. Declare the multisite config, defaulting OFF. Single-site (Waves 0–4) reads
#      `Tenancy.enabled? == false` and every tenancy code path short-circuits.
#   2. Install the RISK-009 connection-checkout reset. It is registered unconditionally but
#      its body returns immediately unless `Tenancy.enabled?`, so with multisite off NO
#      `SET search_path` is ever issued and the pool behaves exactly as before.
#
# target_architecture.md § Tenancy (:355), RISK-009, paradigm_decision.md implication 1.

Rails.application.configure do
  # OFF by default. This is the acceptance gate: nothing in Waves 0–4 changes unless a
  # deployment explicitly turns multisite on.
  config.x.multisite.enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch("MULTISITE", false)) || false

  # The shared schema holding the GLOBAL tables. `public` is where Waves 0–4 already put
  # every table, so enabling multisite adds per-site schemas beside the globals rather than
  # moving anything.
  config.x.multisite.global_schema = ENV.fetch("MULTISITE_GLOBAL_SCHEMA", "public")
end

# RISK-009: reset `search_path` on connection CHECKOUT, never on checkin. A connection
# returned to the pool may carry the previous borrower's tenant; resetting on checkout means
# the NEXT borrower always gets the search_path for ITS OWN current context
# (Tenancy::Current), so a tenant can never leak across a pool hand-off.
#
# `define_callbacks :checkout` lives on AbstractAdapter (Rails 8.1); `clean!` runs it on
# every checkout (connection_pool.rb#checkout_and_verify → conn.clean!). We hook the
# concrete PostgreSQL adapter via its load hook so the class exists when we register.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  # `self` here is ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.
  set_callback :checkout, :after do
    # `self` in the callback is the connection instance. No-op unless multisite is enabled.
    Tenancy.reset_search_path_on_checkout!(self)
  end
end
