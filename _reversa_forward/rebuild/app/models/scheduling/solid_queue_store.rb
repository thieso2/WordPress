# frozen_string_literal: true

module Scheduling
  # The production job store: Solid Queue. This is where BR-CRON-01 is absorbed — "all scheduled
  # events live in the single autoloaded 'cron' option" becomes "all scheduled events are rows in the
  # Solid Queue job tables" (a real store with real job ids and uniqueness, discard_log.md § 3). The
  # scheduler's dedup decision is the only WordPress-specific behaviour layered on top; persistence,
  # dispatch and single-execution are the backend's.
  #
  # `scheduled_ats` answers the dedup question against pending (not-yet-finished) scheduled jobs. A
  # job is IDENTICAL to (job_class, args) when it has the same class and the same arguments — the
  # same equivalence Event#key defines, computed here from the arguments Solid Queue persisted so the
  # decision matches MemoryStore's exactly.
  #
  # Note on environments: Solid Queue is the adapter in production only (config/environments,
  # config/database.yml `queue` database); development/test do not run it, so this class is exercised
  # in production and the dedup/identity LOGIC it delegates to (DedupWindow, Event) is what the test
  # suite verifies against the oracle. Construction here does not touch the database.
  class SolidQueueStore
    # @return [Array<Integer>] epoch seconds of pending scheduled jobs identical to (job_class, args)
    def scheduled_ats(job_class:, args:)
      target = Event.new(job_class_name: job_class.name, args: args).key
      pending_scheduled(job_class.name).filter_map do |job|
        job.scheduled_at&.to_i if identity_of(job) == target
      end
    end

    # Enqueue a one-off event. Solid Queue persists a job row with `scheduled_at = run_at`; the
    # dispatcher promotes it to ready when the moment arrives. This is `wait_until`, the same
    # mechanism the publishing track already uses (Publishing::Post#reschedule_publication).
    def enqueue(job_class:, run_at:, args:)
      job_class.set(wait_until: run_at).perform_later(*args)
      true
    end

    # Register a recurring event dynamically. The static built-ins live in config/recurring.yml;
    # this covers a recurrence created at runtime, via Solid Queue's recurring-task table. The
    # frequency has already been validated by Scheduler against Schedule (BR-MIGRATE-279).
    def enqueue_recurring(job_class:, recurrence:, run_at:, args:)
      task = SolidQueue::RecurringTask.from_configuration(
        Event.new(job_class_name: job_class.name, args: args).key,
        class: job_class.name,
        args: args,
        schedule: Schedule.cron(recurrence),
        static: false
      )
      # Upsert by :key so re-registering an identical recurrence is idempotent rather than a
      # unique-index crash. `create_or_update_all` is Solid Queue 1.7's real API (create_or_update
      # does not exist); the static built-ins live in config/recurring.yml and load the same way.
      SolidQueue::RecurringTask.create_or_update_all([task])
      true
    end

    private

    def pending_scheduled(class_name)
      SolidQueue::Job
        .where(class_name: class_name, finished_at: nil)
        .where.not(scheduled_at: nil)
    end

    # The Event#key of a persisted job, computed from the arguments Solid Queue stored. Deserialising
    # back to Ruby (rather than comparing raw JSON) guarantees byte-for-byte the same identity the
    # scheduler computed from the original call. A row whose payload cannot be read is treated as a
    # non-match rather than crashing the dedup query.
    def identity_of(job)
      raw = job.arguments
      payload = raw.is_a?(String) ? JSON.parse(raw) : raw
      ruby_args = ActiveJob::Arguments.deserialize(payload.fetch("arguments", []))
      Event.new(job_class_name: job.class_name, args: ruby_args).key
    rescue StandardError
      nil
    end
  end
end
