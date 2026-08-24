# frozen_string_literal: true

require "rails_helper"

# Scheduling::Scheduler — the observable decisions of wp_schedule_single_event() /
# wp_schedule_event() / wp_next_scheduled() (wp-includes/cron.php), reproduced on Active Job /
# Solid Queue. The two decisions it owns are the dedup window (covered end-to-end against the
# oracle in dedup_window_differential_spec) and recurrence validation; persistence and dispatch
# are absorbed by the backend. These are the unit-level decisions around those.
class SchedulerSpecJob < ApplicationJob; def perform(*); end; end

RSpec.describe Scheduling::Scheduler do
  around do |example|
    prev = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = prev
  end

  let(:now)   { Time.utc(2026, 8, 23, 12, 0, 0) }
  let(:store) { Scheduling::MemoryStore.new }
  subject(:scheduler) { described_class.new(store: store, clock: -> { now }) }

  describe "#schedule_single" do
    it "schedules a fresh event and enqueues the job" do
      result = scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: now + 3600, args: [1])
      expect(result).to be_scheduled
      expect(SchedulerSpecJob).to have_been_enqueued.with(1)
    end

    it "rejects a duplicate within the window and enqueues NOTHING" do
      scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: now + 3600, args: [1])
      expect {
        result = scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: now + 3600, args: [1])
        expect(result).to be_duplicate
        expect(result.code).to eq("duplicate_event")
      }.not_to change { store.scheduled_ats(job_class: SchedulerSpecJob, args: [1]).size }
    end

    it "rejects a non-positive timestamp with invalid_timestamp (cron.php:249)" do
      result = scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: Time.at(0), args: [])
      expect(result).to be_invalid
      expect(result.code).to eq("invalid_timestamp")
    end
  end

  describe "#schedule_recurring" do
    it "accepts a built-in recurrence" do
      expect(scheduler.schedule_recurring(job_class: SchedulerSpecJob, recurrence: "hourly")).to be_scheduled
    end

    it "rejects an unknown recurrence with invalid_schedule (cron.php:265)" do
      result = scheduler.schedule_recurring(job_class: SchedulerSpecJob, recurrence: "monthly")
      expect(result).to be_invalid
      expect(result.code).to eq("invalid_schedule")
    end

    it "does NOT de-duplicate (only the single-event path does, per cron.php)" do
      scheduler.schedule_recurring(job_class: SchedulerSpecJob, recurrence: "hourly", args: [1])
      expect(scheduler.schedule_recurring(job_class: SchedulerSpecJob, recurrence: "hourly", args: [1])).to be_scheduled
    end
  end

  describe "#next_scheduled" do
    it "returns the earliest identical run, mirroring wp_next_scheduled() (cron.php:520)" do
      scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: now + 7200, args: [1])
      scheduler.schedule_single(job_class: SchedulerSpecJob, run_at: now + 3600, args: [1])
      expect(scheduler.next_scheduled(job_class: SchedulerSpecJob, args: [1])).to eq(Time.at((now + 3600).to_i))
    end

    it "is nil when no identical event is scheduled" do
      expect(scheduler.next_scheduled(job_class: SchedulerSpecJob, args: [99])).to be_nil
    end
  end
end
