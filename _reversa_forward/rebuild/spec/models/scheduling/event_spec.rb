# frozen_string_literal: true

require "rails_helper"

# Scheduling::Event — the successor to the legacy's event identity, md5(serialize($args))
# keyed under the hook (BR-CRON-02, discarded BR-DISCARD-053). The MECHANISM is absorbed by
# the job backend's real job ids; what is REPRODUCED is the equivalence relation the dedup
# decision depends on: same job class + same arguments => same event; any difference => different.
RSpec.describe Scheduling::Event do
  def key(job_class_name, args) = described_class.new(job_class_name: job_class_name, args: args).key

  it "gives identical (class, args) the same key" do
    expect(key("Job::A", [1, "x"])).to eq(key("Job::A", [1, "x"]))
  end

  it "distinguishes a difference in any argument" do
    expect(key("Job::A", [1])).not_to eq(key("Job::A", [2]))
  end

  it "distinguishes a difference in the job class (the target's 'hook')" do
    expect(key("Job::A", [1])).not_to eq(key("Job::B", [1]))
  end

  it "is order-independent for hash arguments (canonicalisation)" do
    expect(key("Job::A", [{ "a" => 1, "b" => 2 }])).to eq(key("Job::A", [{ "b" => 2, "a" => 1 }]))
  end

  it "treats symbol and string hash keys as equal after canonicalisation" do
    expect(key("Job::A", [{ a: 1 }])).to eq(key("Job::A", [{ "a" => 1 }]))
  end

  it "keeps array argument order significant (positional call arguments)" do
    expect(key("Job::A", [[1, 2]])).not_to eq(key("Job::A", [[2, 1]]))
  end

  it "produces a stable, non-empty digest" do
    expect(key("Job::A", [1])).to match(/\AJob::A:[0-9a-f]{64}\z/)
  end
end
