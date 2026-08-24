# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# The de-duplication window (BR-MIGRATE-280 / BR-MIGRATE-281, legacy BR-CRON-04 / BR-CRON-05,
# wp-includes/cron.php:117-169) is the one genuinely non-trivial piece of scheduling behaviour
# the framework does NOT absorb — Solid Queue owns persistence, dispatch and single-execution, but
# it has no concept of "reject an identical event within +/-10 minutes". So it is reproduced
# (Scheduling::DedupWindow, driven by Scheduling::Scheduler) and verified against the oracle here.
#
# The spec drives the REAL path end to end: a Scheduling::Scheduler over a MemoryStore seeded with
# existing events, then schedule_single for the candidate. The oracle bridge seeds the same events
# into the `cron` option and calls wp_schedule_single_event(). For every case the two must agree on
# scheduled-vs-duplicate. Offsets are seconds relative to each side's own now; the window logic is
# now-relative (see DedupWindow), so the two clocks need not be identical.
module CronDedupOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE    = File.expand_path("support/cron_dedup_oracle.php", __dir__)

  # Each case: candidate [offset, args, hook] and a list of existing [offset, args, hook].
  # hook "A" => SchedulingSpecJobA (legacy 'test_hook'), "B" => SchedulingSpecJobB ('other_hook').
  CASES = [
    { cand: [3600, [1], "A"], existing: [[3600, [1], "A"]] },   # exact same => dup
    { cand: [3600, [1], "A"], existing: [[2999, [1], "A"]] },   # below c-600 => scheduled
    { cand: [3600, [1], "A"], existing: [[3000, [1], "A"]] },   # == c-600 lower edge => dup
    { cand: [3600, [1], "A"], existing: [[4200, [1], "A"]] },   # == c+600 upper edge => dup
    { cand: [3600, [1], "A"], existing: [[4201, [1], "A"]] },   # above c+600 => scheduled
    { cand: [300,  [1], "A"], existing: [[-5000, [1], "A"]] },  # near-term: all past identical count => dup
    { cand: [-300, [1], "A"], existing: [[400, [1], "A"]] },    # past cand: event in next 10m counts => dup
    { cand: [-300, [1], "A"], existing: [[601, [1], "A"]] },    # past cand: beyond now+600 => scheduled
    { cand: [3600, [1], "A"], existing: [[3600, [2], "A"]] },   # different args => scheduled
    { cand: [3600, [1], "A"], existing: [[3600, [1], "B"]] },   # different hook => scheduled
    { cand: [3600, [1], "A"], existing: [] },                   # nothing scheduled => scheduled
    { cand: [300,  [1], "A"], existing: [[1000, [1], "A"]] },   # near-term: upper bound still applies => scheduled
    { cand: [599,  [1], "A"], existing: [[1199, [1], "A"]] },   # near-term upper edge => dup
    { cand: [599,  [1], "A"], existing: [[1200, [1], "A"]] },   # just past near-term upper edge => scheduled
    { cand: [1200, [1], "A"], existing: [[0, [1], "A"]] },      # min branch: existing at now below c-600 => scheduled
    { cand: [3600, [1], "A"], existing: [[3600, [1], "A"], [3600, [2], "A"]] }, # dup among mixed => dup
    { cand: [3600, [1], "A"], existing: [[100, [1], "A"], [7200, [1], "A"]] },  # identical but far outside window => scheduled
  ].freeze

  module_function

  def available?
    File.exist?(BOOTSTRAP) && system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  def php_shape
    CASES.map do |c|
      c_off, c_args, c_hook = c[:cand]
      existing = c[:existing].map { |e_off, e_args, e_hook| [e_off, e_args, php_hook(e_hook)] }
      [c_off, existing, c_args, php_hook(c_hook)]
    end
  end

  def php_hook(sym)
    sym == "B" ? "other_hook" : "test_hook"
  end

  def oracle_verdicts
    @oracle_verdicts ||= begin
      stdout, stderr, status = Open3.capture3({ "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP }, "php", BRIDGE,
                                              stdin_data: JSON.generate(php_shape))
      raise "oracle bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end
  end
end

# Two named job classes so "different hook" is a real distinction in Event#key (job_class.name).
class SchedulingSpecJobA < ApplicationJob; def perform(*); end; end
class SchedulingSpecJobB < ApplicationJob; def perform(*); end; end

RSpec.describe Scheduling::DedupWindow do
  before { skip "PHP oracle not available" unless CronDedupOracle.available? }

  around do |example|
    prev = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = prev
  end

  def job_for(hook) = hook == "B" ? SchedulingSpecJobB : SchedulingSpecJobA

  it "agrees with the oracle on every de-duplication case" do
    now = Time.now.to_i
    scheduler = Scheduling::Scheduler.new(store: Scheduling::MemoryStore.new, clock: -> { Time.at(now) })

    divergences = CronDedupOracle::CASES.zip(CronDedupOracle.oracle_verdicts).filter_map do |c, oracle|
      store     = Scheduling::MemoryStore.new
      scheduler = Scheduling::Scheduler.new(store: store, clock: -> { Time.at(now) })

      # Seed existing events directly into the store (no dedup on seed — the legacy bridge seeds
      # the cron option the same way), then attempt the candidate.
      c[:existing].each do |e_off, e_args, e_hook|
        store.enqueue(job_class: job_for(e_hook), run_at: Time.at(now + e_off), args: e_args)
      end

      c_off, c_args, c_hook = c[:cand]
      result = scheduler.schedule_single(job_class: job_for(c_hook), run_at: Time.at(now + c_off), args: c_args)
      rebuild = result.scheduled? ? "scheduled" : (result.duplicate? ? "duplicate_event" : result.code)

      next if rebuild == oracle

      "#{c.inspect}\n    oracle:  #{oracle}\n    rebuild: #{rebuild}"
    end

    expect(divergences).to be_empty, "dedup window diverges from the oracle:\n\n#{divergences.join("\n")}"
  end
end
