# frozen_string_literal: true

module Scheduling
  # The de-duplication window, BR-MIGRATE-280 and BR-MIGRATE-281 (legacy BR-CRON-04/05,
  # wp-includes/cron.php:132-160). This is the one genuinely non-trivial piece of scheduling
  # behaviour, so it is reproduced exactly and verified against the oracle
  # (spec/models/scheduling/dedup_window_differential_spec.rb).
  #
  # The legacy decision, verbatim in structure (cron.php:135-160):
  #
  #     if ( $event->timestamp < time() + 10 * MINUTE_IN_SECONDS ) {
  #         $min_timestamp = 0;                              // BR-MIGRATE-281
  #     } else {
  #         $min_timestamp = $event->timestamp - 10 * MINUTE_IN_SECONDS;
  #     }
  #     if ( $event->timestamp < time() ) {
  #         $max_timestamp = time() + 10 * MINUTE_IN_SECONDS;
  #     } else {
  #         $max_timestamp = $event->timestamp + 10 * MINUTE_IN_SECONDS;
  #     }
  #     foreach ( $crons as $event_timestamp => $cron ) {
  #         if ( $event_timestamp < $min_timestamp ) continue;
  #         if ( $event_timestamp > $max_timestamp ) break;
  #         if ( isset( $cron[$hook][$key] ) ) { $duplicate = true; break; }
  #     }
  #
  # In words (BR-MIGRATE-280): a candidate single event duplicates an existing identical event
  # (same key — see Event) whose scheduled time falls within a +/-10-minute window of the candidate.
  # Two asymmetric adjustments to that window:
  #
  #   * BR-MIGRATE-281 — if the candidate is due within the next 10 minutes OR is already past
  #     (`candidate < now + 600`), the lower bound drops to 0, so EVERY past identical event counts.
  #     This is what stops a repeatedly-failing near-term event from accumulating copies.
  #   * If the candidate itself is in the past (`candidate < now`), the upper bound is pinned to
  #     `now + 600` rather than `candidate + 600`, so an identical event anywhere in the next ten
  #     minutes is treated as the same work.
  #
  # The legacy's sort-and-break loop is only an early-exit optimisation over a sorted map; the
  # decision it computes is "does any identical event lie in [min, max]?", which is what `duplicate?`
  # evaluates directly. Verified equivalent against the oracle across the window edges.
  module DedupWindow
    TEN_MINUTES = 10 * 60

    module_function

    # @param candidate_at [Integer] epoch seconds the new event would run at
    # @param existing_ats [Array<Integer>] epoch seconds of already-scheduled IDENTICAL events
    #   (same Event#key); the caller supplies only same-key timestamps, mirroring the legacy's
    #   `isset( $cron[$hook][$key] )` test inside the loop
    # @param now [Integer] epoch seconds of the current time
    # @return [Boolean] true when the candidate duplicates one of the existing events
    def duplicate?(candidate_at:, existing_ats:, now:)
      min = min_timestamp(candidate_at, now)
      max = max_timestamp(candidate_at, now)
      existing_ats.any? { |at| at >= min && at <= max }
    end

    # @return [(Integer, Integer)] the inclusive [min, max] bounds for a candidate, exposed so callers
    #   and specs can inspect the window the legacy would compute.
    def bounds(candidate_at:, now:)
      [min_timestamp(candidate_at, now), max_timestamp(candidate_at, now)]
    end

    def min_timestamp(candidate_at, now)
      candidate_at < now + TEN_MINUTES ? 0 : candidate_at - TEN_MINUTES
    end

    def max_timestamp(candidate_at, now)
      candidate_at < now ? now + TEN_MINUTES : candidate_at + TEN_MINUTES
    end
  end
end
