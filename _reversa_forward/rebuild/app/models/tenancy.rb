# frozen_string_literal: true

# Tenancy — the Wave 5 cross-cutting concern (target_architecture.md § Tenancy, :355).
#
# NOT a bounded context: a schema-level concern. `BR-MS-01` (BR-MIGRATE-357) puts one
# PostgreSQL SCHEMA per site, selected by `search_path` — NOT the legacy's prefixed
# table set (wp_{blog_id}_posts). The blog-scoped tables live per-schema; the GLOBAL
# tables (users, role_assignments, sessions, application_passwords, data_requests, and
# the tenancy registry itself) live in a shared schema on every search_path.
#
# ⚠️⚠️ STRICTLY ADDITIVE. target_architecture.md sequences this LAST because it "changes
# connection handling for everything before it" (RISK-009). Single-site — everything built
# in Waves 0–4 — MUST keep working byte-for-byte. So the entire module is a transparent
# NO-OP unless `Tenancy.enabled?`, and `enabled?` defaults to false. When disabled:
#   * the checkout callback (config/initializers/tenancy.rb) returns before touching SQL,
#   * `switch`/`current_site`/`super_admin?` all resolve to the single-site answer,
#   * no `SET search_path` is ever issued, so the connection keeps the structure.sql
#     default (`"$user", public`) and every Wave 0–4 query is unchanged.
#
# ── implication 1 (paradigm_decision.md): global mutable state has no Rails analogue ──
# `switch_to_blog()`'s process-global mutation of `$wpdb->prefix` + the object cache blog
# prefix (BR-MS-03 / BR-MIGRATE-358) does NOT come back, and its stack discipline
# (BR-MS-02, discarded) is not reproduced. The current tenant lives in
# `Tenancy::Current` (ActiveSupport::CurrentAttributes) — reset per request, never a
# process global — and every background job carries an EXPLICIT tenant identifier
# (Tenancy::TenantContext) rather than inheriting ambient state.
module Tenancy
  # A schema name is an SQL identifier we interpolate into `SET search_path` (there is no
  # bind-parameter form of SET), so it must be validated, never trusted. Lower-snake only.
  SCHEMA_NAME = /\A[a-z_][a-z0-9_]*\z/

  class InvalidSchemaName < StandardError; end
  class NotEnabled < StandardError; end

  module_function

  # The single gate. Everything in this file short-circuits to the single-site answer
  # when this is false, and false is the default (config/initializers/tenancy.rb).
  def enabled?
    Rails.application.config.x.multisite.enabled == true
  end

  # The shared schema that holds the GLOBAL tables (target_data_model.md `global` scope)
  # plus the tenancy registry. Defaults to `public`, which is where Waves 0–4 already put
  # every table — so enabling multisite does not move the global tables, it only adds
  # per-site schemas beside them. Configurable for a deployment that isolates globals into
  # their own schema.
  def global_schema
    (Rails.application.config.x.multisite.global_schema || "public").to_s
  end

  # The search_path a connection must carry for a given site. With a tenant: the tenant
  # schema first (so blog-scoped tables resolve there), the global schema second (so
  # users/sessions/… resolve to the shared copy). Without a tenant, but enabled: just the
  # global schema (the network-admin / signup context, which only ever touches globals).
  def search_path_for(site)
    if site
      [quote_schema(site.schema_name), quote_schema(global_schema)].join(", ")
    else
      quote_schema(global_schema)
    end
  end

  # The current tenant for THIS request/job, or nil. Nil is the single-site answer and the
  # "no tenant resolved yet" answer both — Current is reset per request.
  def current_site = Tenancy::Current.site

  def current_schema = current_site&.schema_name

  # Enter a tenant context: set Current.site AND apply the search_path to the connection
  # already in hand (the checkout callback only governs FUTURE checkouts). Restores the
  # previous site and search_path on the way out — the block form can nest without the
  # unbalanced-stack failure BR-MS-02 was discarded to avoid, because the previous value
  # is captured locally, not on an ambient stack.
  def switch(site)
    raise NotEnabled, "Tenancy.switch requires config.x.multisite.enabled" unless enabled?

    previous = Tenancy::Current.site
    Tenancy::Current.site = site
    apply_search_path!
    yield
  ensure
    if enabled?
      Tenancy::Current.site = previous
      apply_search_path!
    end
  end

  # Run a block with NO tenant (global schema only). Used by the signup/activation surface
  # and the network console, which operate on global tables regardless of any inbound host.
  def without_tenant(&block) = switch(nil, &block)

  # Push the current context onto the live connection. Idempotent; safe to call repeatedly.
  # No-op when disabled, so single-site never issues a SET.
  def apply_search_path!(connection = ActiveRecord::Base.connection)
    return unless enabled?

    connection.execute("SET search_path TO #{search_path_for(current_site)}")
    nil
  end

  # The RISK-009 primitive, invoked from the connection :checkout callback. A returned
  # connection must not leak a tenant to the next borrower, so we RESET on checkout (never
  # on checkin): whatever the previous borrower left, the next borrower gets the search_path
  # for ITS OWN current context. Disabled ⇒ untouched, so the pool behaves exactly as it did
  # in Waves 0–4.
  def reset_search_path_on_checkout!(connection)
    return unless enabled?

    connection.execute("SET search_path TO #{search_path_for(current_site)}")
  rescue StandardError
    # A connection that cannot accept the SET (mid-teardown, dead socket) is discarded by
    # the pool anyway; never raise out of a checkout callback.
    nil
  end

  # BR-MS-05 (BR-MIGRATE-360): super admins sit ABOVE the role system and bypass every
  # capability check except do_not_allow. Membership is the `site_admins` NETWORK option
  # (Tenancy::NetworkSetting) — NOT the `$super_admins` PHP global, which BR-CAP-14
  # discarded as a privilege-escalation vector (discard_log.md §4). Single site (disabled)
  # has no network and therefore no super admins: false, so Access is unchanged.
  def super_admin?(actor)
    return false unless enabled?
    return false if actor.nil?

    Tenancy::NetworkSetting.super_admin_ids.include?(actor.id)
  end

  # Validate + double-quote a schema identifier for interpolation into SET search_path.
  def quote_schema(name)
    name = name.to_s
    raise InvalidSchemaName, name.inspect unless name.match?(SCHEMA_NAME)

    %("#{name}")
  end
end
