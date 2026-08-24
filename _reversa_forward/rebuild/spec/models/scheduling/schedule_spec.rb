# frozen_string_literal: true

require "rails_helper"

# Scheduling::Schedule — the four built-in recurrences (BR-MIGRATE-279, legacy BR-CRON-03,
# wp-includes/cron.php:1133 wp_get_schedules()). The extensibility hook (cron_schedules) is gone
# under AD-01, so the list is FINAL. Intervals reproduce the legacy exactly; display strings are
# the legacy's verbatim (RISK-008 / DEV-009 — UI wording, not project identity).
RSpec.describe Scheduling::Schedule do
  it "defines exactly the four built-ins in the legacy's order" do
    expect(described_class.names).to eq(%w[hourly twicedaily daily weekly])
  end

  it "reproduces the legacy intervals in seconds (cron.php:1133)" do
    expect(described_class.interval("hourly")).to eq(3600)
    expect(described_class.interval("twicedaily")).to eq(12 * 3600)
    expect(described_class.interval("daily")).to eq(86_400)
    expect(described_class.interval("weekly")).to eq(7 * 86_400)
  end

  it "carries the legacy display strings verbatim" do
    expect(described_class.display("hourly")).to eq("Once Hourly")
    expect(described_class.display("twicedaily")).to eq("Twice Daily")
    expect(described_class.display("daily")).to eq("Once Daily")
    expect(described_class.display("weekly")).to eq("Once Weekly")
  end

  it "recognises only the built-ins (no runtime extension point, AD-01)" do
    expect(described_class.exists?("hourly")).to be(true)
    expect(described_class.exists?("monthly")).to be(false)
    expect(described_class.exists?("")).to be(false)
  end

  it "exposes a Solid Queue recurring expression for each built-in" do
    described_class.names.each { |n| expect(described_class.cron(n)).to be_a(String).and(be_present) }
  end

  it "returns nil for an unknown recurrence rather than raising" do
    expect(described_class.interval("nope")).to be_nil
    expect(described_class.cron("nope")).to be_nil
  end
end
