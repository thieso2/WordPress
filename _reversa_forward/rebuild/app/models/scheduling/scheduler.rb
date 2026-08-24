# frozen_string_literal: true

module Scheduling
  # The scheduling API's observable decisions, reproduced on Active Job / Solid Queue.
  #
  # This is the successor to `wp_schedule_single_event()` / `wp_schedule_event()` /
  # `wp_next_scheduled()` (wp-includes/cron.php). It is deliberately thin (BC-13: "holds no
  # invariants of its own"): the two decisions it owns are the de-duplication window (DedupWindow)
  # and recurrence validation (Schedule). Everything else — persistence, dispatch, retries, the
  # single-run-at-the-right-time guarantee — is ABSORBED by the job backend (discard_log.md § 3).
  #
  # ── What the legacy did and where it now lives ────────────────────────────────────────────────
  #   BR-CRON-01  one autoloaded `cron` option ............ Solid Queue's job tables (a real store)
  #   BR-CRON-02  md5(serialize(args)) identity ........... Event#key (equivalence preserved)
  #   BR-CRON-06..11  visitor-driven spawning/locking ..... Solid Queue dispatcher + worker
  #   BR-CRON-13  cron-array format migration ............. n/a (no such format)
  #   BR-MIGRATE-282  pre_schedule_event filter ........... GONE (AD-01). A hook that let an external
  #                   cron take over scheduling has no analogue: there is no runtime extension point,
  #                   and the queue always runs, so `DISABLE_WP_CRON` has no analogue either.
  #
  # The `store` collaborator answers exactly one question the dedup decision needs — "what identical
  # events are already scheduled?" — and is the seam where the job backend plugs in. Production uses
  # SolidQueueStore; specs inject a deterministic in-memory store. The scheduler never reaches for a
  # process global (implication 1): `now` and the store travel in explicitly.
  class Scheduler
    # The outcome of a schedule attempt, mirroring the legacy's true / false|WP_Error return
    # (cron.php:169). `scheduled?` is the true case; a rejected duplicate carries the legacy's
    # 'duplicate_event' code (cron.php:163), an unknown recurrence the 'invalid_schedule' code
    # (cron.php:265), an invalid timestamp 'invalid_timestamp' (cron.php:255).
    Result = Struct.new(:status, :code, :run_at, keyword_init: true) do
      def scheduled? = status == :scheduled
      def duplicate? = status == :duplicate
      def invalid?   = status == :invalid
    end

    def initialize(store:, clock: -> { Time.now })
      @store = store
      @clock = clock
    end

    # Schedule a one-off event — the successor to `wp_schedule_single_event()`.
    #
    # Applies the de-duplication window (BR-MIGRATE-280/281) against the identical events the store
    # reports, then enqueues the concrete Active Job. Returns a Result; on a duplicate NOTHING is
    # enqueued, exactly as the legacy scheduled nothing and returned false / a 'duplicate_event'
    # WP_Error.
    #
    # @param job_class [Class] the Active Job to run (the target's "hook")
    # @param run_at [Time] when it should run
    # @param args [Array] positional arguments passed to the job and folded into its identity
    def schedule_single(job_class:, run_at:, args: [])
      now = current_time
      return Result.new(status: :invalid, code: "invalid_timestamp") unless valid_timestamp?(run_at)

      existing = @store.scheduled_ats(job_class: job_class, args: args)

      if DedupWindow.duplicate?(candidate_at: run_at.to_i, existing_ats: existing, now: now.to_i)
        return Result.new(status: :duplicate, code: "duplicate_event", run_at: run_at)
      end

      @store.enqueue(job_class: job_class, run_at: run_at, args: args)
      Result.new(status: :scheduled, run_at: run_at)
    end

    # Schedule a recurring event — the successor to `wp_schedule_event()`. Recurrence must be one of
    # the four built-ins (BR-MIGRATE-279); an unknown one is rejected with 'invalid_schedule', as the
    # legacy did (cron.php:265). The legacy's `wp_schedule_event()` does NOT de-duplicate — only the
    # single-event path does — so this path registers the recurring definition without a window check.
    #
    # The recurring dispatch itself is owned by Solid Queue (config/recurring.yml); this method exists
    # so a caller can schedule a recurrence dynamically with the same validation the legacy applied.
    def schedule_recurring(job_class:, recurrence:, run_at: current_time, args: [])
      return Result.new(status: :invalid, code: "invalid_timestamp") unless valid_timestamp?(run_at)
      return Result.new(status: :invalid, code: "invalid_schedule") unless Schedule.exists?(recurrence)

      @store.enqueue_recurring(job_class: job_class, recurrence: recurrence, run_at: run_at, args: args)
      Result.new(status: :scheduled, run_at: run_at)
    end

    # The next scheduled run for an identical event, or nil — the successor to `wp_next_scheduled()`
    # (cron.php:520), which callers use to avoid scheduling a duplicate in the first place. Returns a
    # Time so callers do not juggle epochs.
    def next_scheduled(job_class:, args: [])
      earliest = @store.scheduled_ats(job_class: job_class, args: args).min
      earliest && Time.at(earliest)
    end

    private

    def current_time
      @clock.call
    end

    # The legacy rejects a non-positive / non-numeric timestamp with 'invalid_timestamp'
    # (cron.php:249). A Time is always positive here; guard the epoch to mirror the decision.
    def valid_timestamp?(run_at)
      run_at.respond_to?(:to_i) && run_at.to_i.positive?
    end
  end
end
