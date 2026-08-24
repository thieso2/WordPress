# frozen_string_literal: true

module Tenancy
  # Per-request / per-job tenant context. The direct discharge of paradigm_decision.md
  # **implication 1** for multisite: the legacy carried the active blog in process globals
  # (`$wpdb->blogid`, `$blog_id`, the object cache's `blog_prefix`) that switch_to_blog()
  # mutated in place (BR-MS-03 / BR-MIGRATE-358) and a stack was supposed to unwind
  # (BR-MS-02, discarded). Both are ambient state every call reached into.
  #
  # Here the active site travels EXPLICITLY and lives nowhere but here.
  # `ActiveSupport::CurrentAttributes` is reset by Rails at the start of every request and
  # never leaks between them or between jobs, so there is no process-wide "current blog"
  # anywhere — exactly implication 1's requirement, and the reason a returned connection
  # can be reset from THIS value on checkout without any global to consult.
  #
  # Mirror of Localization::Current, which discharges the same implication for the locale
  # switch stack. `site` is nil off the tenant path (single-site, the signup surface before
  # a host resolves, a job that has not set its tenant) — nil IS the single-site answer, so
  # nothing here invents an ambient default.
  class Current < ActiveSupport::CurrentAttributes
    # The Tenancy::Site whose schema is on the search_path for this request/job. nil ⇒ the
    # global schema only (single-site, or a network-scoped operation).
    attribute :site
  end
end
