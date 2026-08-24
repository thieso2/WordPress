# frozen_string_literal: true

module Scheduling
  # The built-in recurrences, BR-MIGRATE-279 (legacy BR-CRON-03, wp-includes/cron.php:1133,
  # `wp_get_schedules()`). In the legacy these four are the base of an extensible list — the
  # `cron_schedules` filter let plugins add more (cron.php:1152). AD-01 removes the hook, so the
  # list is FINAL: these four, and nothing can add a fifth at runtime. That is the whole content
  # of "behaviour is final" here.
  #
  # This is a catalog, not a mechanism. The mechanism the legacy attached to a recurrence — draining
  # the `cron` option on visitor traffic (BR-CRON-06..11) — is ABSORBED by Solid Queue's recurring
  # tasks (config/recurring.yml). What survives as observable behaviour is: which frequencies exist,
  # their names, their intervals in seconds, and their display strings.
  #
  # Display strings are the legacy's verbatim (RISK-008 / DEV-009): "Once Hourly", "Twice Daily",
  # "Once Daily", "Once Weekly". They are UI wording, not project identity — carried unchanged.
  module Schedule
    MINUTE = 60
    HOUR   = 60 * MINUTE
    DAY    = 24 * HOUR
    WEEK   = 7 * DAY

    # name => { interval: seconds, display: legacy string, cron: Solid Queue recurring expression }.
    # The `cron` column is how a recurrence is written in config/recurring.yml under `schedule:`
    # (Fugit natural-language syntax). Intervals reproduce the legacy exactly; twicedaily has no
    # single natural-language phrase, so it is spelled as the two twelve-hour marks it means.
    ALL = {
      "hourly"     => { interval: HOUR,     display: "Once Hourly", cron: "every hour" },
      "twicedaily" => { interval: 12 * HOUR, display: "Twice Daily", cron: "every day at 00:00 and 12:00" },
      "daily"      => { interval: DAY,      display: "Once Daily",  cron: "every day at midnight" },
      "weekly"     => { interval: WEEK,     display: "Once Weekly", cron: "every monday at midnight" }
    }.freeze

    module_function

    # The recurrence names, in the legacy's declared order.
    def names
      ALL.keys
    end

    # True when `name` is one of the four built-ins. The legacy's `wp_schedule_event()` rejects an
    # unknown recurrence with the WP_Error 'invalid_schedule' (cron.php:265); a caller wanting that
    # decision checks here first.
    def exists?(name)
      ALL.key?(name.to_s)
    end

    # The interval in seconds, or nil for an unknown recurrence.
    def interval(name)
      ALL.dig(name.to_s, :interval)
    end

    # The legacy display string, or nil for an unknown recurrence.
    def display(name)
      ALL.dig(name.to_s, :display)
    end

    # The Solid Queue recurring expression for config/recurring.yml, or nil.
    def cron(name)
      ALL.dig(name.to_s, :cron)
    end
  end
end
