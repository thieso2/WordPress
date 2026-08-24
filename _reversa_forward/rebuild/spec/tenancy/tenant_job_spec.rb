# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# (c) a background job carries its tenant EXPLICITLY.
# implication 1 / RISK-009: no ambient state. The job captures the tenant into its serialized
# payload at enqueue and re-establishes it at perform, so a worker that just ran tenant A's
# job cannot leak A into tenant B's.
RSpec.describe "Tenancy::TenantContext", :tenancy do
  # A probe job: records the search_path it runs under and where it wrote.
  probe = Class.new(ApplicationJob) do
    include Tenancy::TenantContext
    cattr_accessor :observed_search_path
    def perform
      self.class.observed_search_path =
        ActiveRecord::Base.connection.select_value("SHOW search_path")
    end
  end
  before { stub_const("TenancyProbeJob", probe) }

  it "captures the current tenant into the serialized job payload at enqueue time" do
    with_multisite do
      site = provision_site(domain: "job.example", schema_name: "job_site")

      job = Tenancy.switch(site) { TenancyProbeJob.new }
      expect(job.tenant_site_id).to eq(site.id)
      expect(job.serialize["tenant_site_id"]).to eq(site.id)

      # A round-trip through serialize/deserialize preserves the explicit identifier.
      revived = TenancyProbeJob.new.tap { |j| j.deserialize(job.serialize) }
      expect(revived.tenant_site_id).to eq(site.id)
    end
  end

  it "runs perform under the captured tenant's schema, not ambient state" do
    with_multisite do
      site = provision_site(domain: "perform.example", schema_name: "perform_site")

      # Enqueue while site is current; then CLEAR the ambient context before performing, to
      # prove perform relies on the carried identifier, not on what happens to be current.
      job = Tenancy.switch(site) { TenancyProbeJob.new }
      Tenancy::Current.site = nil

      job.perform_now
      expect(probe.observed_search_path).to include("perform_site")

      # And after perform, the ambient context is restored to what it was (nil) — the job
      # did not mutate a global.
      expect(Tenancy::Current.site).to be_nil
    end
  end

  it "runs on the global schema when no tenant was captured (single-site behaviour)" do
    with_multisite do
      job = Tenancy.without_tenant { TenancyProbeJob.new }
      expect(job.tenant_site_id).to be_nil
      job.perform_now
      expect(probe.observed_search_path).not_to be_nil
    end
  end
end
