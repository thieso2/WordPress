# frozen_string_literal: true

module Tenancy
  # Every background job carries an EXPLICIT tenant identifier and sets its own search_path
  # — the multisite half of paradigm_decision.md implication 1, and the RISK-009 mitigation
  # spelled out in target_architecture.md: "every background job carrying an explicit tenant
  # identifier rather than inheriting ambient state."
  #
  # The legacy's switch_to_blog() mutated a process global that a job would inherit from
  # whatever ran before it on the worker (BR-MS-03, and the unbalanced-stack hazard of
  # BR-MS-02). That is exactly the failure this prevents: the tenant is captured into the
  # job's SERIALIZED payload at enqueue time (from Tenancy::Current, the per-request context)
  # and re-established from the payload at perform time inside an explicit Tenancy.switch —
  # so a worker thread that just ran tenant A's job cannot leak A into tenant B's job, and a
  # job enqueued off the tenant path (single-site) carries no tenant and runs on the global
  # schema unchanged.
  #
  # Mix into any ActiveJob that touches blog-scoped data:
  #   class Publishing::PublishScheduledJob < ApplicationJob
  #     include Tenancy::TenantContext
  #   end
  module TenantContext
    extend ActiveSupport::Concern

    included do
      # The site id this job belongs to, captured at enqueue. nil ⇒ no tenant (single-site,
      # or a genuinely global job) ⇒ the global schema, i.e. the Wave 0–4 behaviour.
      attr_accessor :tenant_site_id

      # Establish the tenant for the whole of perform, and ONLY for perform. `around_perform`
      # (not an override of `#perform`) so it wraps the concrete job's own `perform` — a
      # method override in the module would be shadowed by the job class's own definition.
      # When multisite is off, or no tenant was captured, the block runs directly on the
      # global schema — a true no-op, so single-site jobs behave exactly as before.
      around_perform do |job, block|
        site = job.send(:resolve_tenant_site)
        site ? Tenancy.switch(site) { block.call } : block.call
      end
    end

    # Capture the current tenant at enqueue. ActiveJob calls this when the job object is
    # built; Current.site is the request/job context that enqueued it.
    def initialize(*args, **kwargs)
      super
      self.tenant_site_id ||= Tenancy::Current.site&.id
    end

    # Persist the tenant id in the serialized job so the executing worker gets it explicitly,
    # not from any ambient state.
    def serialize
      super.merge("tenant_site_id" => tenant_site_id)
    end

    def deserialize(job_data)
      super
      self.tenant_site_id = job_data["tenant_site_id"]
    end

    private

    def resolve_tenant_site
      return nil unless Tenancy.enabled?
      return nil if tenant_site_id.nil?

      Tenancy.without_tenant { Tenancy::Site.find_by(id: tenant_site_id) }
    end
  end
end
