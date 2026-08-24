# frozen_string_literal: true

require "digest"
require "json"

module Scheduling
  # The identity of a scheduled event. Legacy BR-CRON-02 (discarded, BR-DISCARD-053):
  # `$crons[$timestamp][$hook][ md5( serialize( $args ) ) ]` — an event is identified by its hook
  # and a hash of its arguments (wp-includes/cron.php:132, :201).
  #
  # The MECHANISM — `md5(serialize())` over PHP's serialization format, stored as an array key in the
  # autoloaded `cron` option — is absorbed by the job backend (discard_log.md § 3: "a job backend
  # with real job ids and uniqueness"). What is REPRODUCED is the observable consequence: two events
  # with the same hook and the same arguments are the SAME event for de-duplication (BR-MIGRATE-280),
  # and two that differ in either the hook or any argument are DIFFERENT.
  #
  # So `md5(serialize($args))` becomes a stable, language-independent digest of a canonical encoding
  # of the arguments. The bytes differ from the legacy's (PHP serialize vs JSON, md5 vs sha256) —
  # that is deliberate: nothing external reads this key, it is internal identity only. Only the
  # equivalence relation is preserved, and that is what the oracle's dedup decisions test.
  #
  # The "hook" in the target is the concrete Active Job class: there is no runtime hook registry
  # (AD-01), so scheduled work is a real job class, not a string dispatched through a callback table.
  Event = Struct.new(:job_class_name, :args, keyword_init: true) do
    # The arguments digest — the successor to `md5(serialize($args))`. Canonicalised so that logically
    # equal arguments hash equally regardless of hash-key insertion order.
    def args_digest
      Digest::SHA256.hexdigest(JSON.generate(canonical(args)))
    end

    # The full stable job key: hook (job class) plus arguments digest. Two events are duplicates of
    # one another (subject to the time window, see DedupWindow) exactly when their keys are equal.
    def key
      "#{job_class_name}:#{args_digest}"
    end

    private

    # Deep, order-independent normalisation: hashes are sorted by stringified key, arrays keep order
    # (their order is meaningful — they are positional call arguments), scalars pass through.
    def canonical(value)
      case value
      when Hash
        value.map { |k, v| [k.to_s, canonical(v)] }.sort_by(&:first).to_h
      when Array
        value.map { |v| canonical(v) }
      else
        value
      end
    end
  end
end
