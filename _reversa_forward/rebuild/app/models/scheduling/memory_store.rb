# frozen_string_literal: true

module Scheduling
  # The reference store: an in-memory job store that defines the store contract Scheduler depends on,
  # in the simplest terms that still preserve the legacy's identity semantics (Event#key). It is the
  # canonical statement of "what identical events are already scheduled?", and it is what the
  # scheduler specs drive so the de-duplication decision is tested end to end without a running queue.
  #
  # It is NOT the production backend — SolidQueueStore is. Both answer the same three questions; this
  # one keeps them in a Hash keyed by Event#key, the production one asks Solid Queue's tables.
  #
  # Not process-global (implication 1): a caller constructs one and passes it in explicitly. Two
  # schedulers with two stores share nothing.
  class MemoryStore
    Entry = Struct.new(:run_at, :args, :recurrence, keyword_init: true)

    def initialize
      # Event#key => [Entry, ...]
      @by_key = Hash.new { |h, k| h[k] = [] }
    end

    # The epoch seconds of every already-scheduled event IDENTICAL to (job_class, args) — same
    # Event#key. Mirrors the legacy's `isset( $cron[$hook][$key] )` restricted to one identity.
    def scheduled_ats(job_class:, args:)
      @by_key[key_for(job_class, args)].map { |e| e.run_at.to_i }
    end

    # Record a one-off event and enqueue the real Active Job. In a store used outside tests the
    # perform_later is what actually schedules the work; the ledger entry is what later dedup queries
    # see. Kept in that order so a lost enqueue cannot leave a phantom dedup entry.
    def enqueue(job_class:, run_at:, args:)
      job_class.set(wait_until: run_at).perform_later(*args)
      @by_key[key_for(job_class, args)] << Entry.new(run_at: run_at, args: args)
      true
    end

    # Record a recurring definition. The in-memory store does not run a clock, so this only registers
    # the intent; real recurrence is Solid Queue's job (SolidQueueStore / config/recurring.yml).
    def enqueue_recurring(job_class:, recurrence:, run_at:, args:)
      @by_key[key_for(job_class, args)] << Entry.new(run_at: run_at, args: args, recurrence: recurrence)
      true
    end

    private

    def key_for(job_class, args)
      Event.new(job_class_name: job_class.name, args: args).key
    end
  end
end
