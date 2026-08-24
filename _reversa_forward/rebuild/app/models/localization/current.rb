# frozen_string_literal: true

module Localization
  # Per-request locale context. BC-16 (target_architecture.md), and the direct answer to
  # paradigm_decision.md **implication 1** ("global mutable state has no Rails analogue"):
  # the legacy carried the request locale and the switch stack in process globals -- the
  # `$locale` global read by get_locale() (l10n.php:31) and the private `$stack` inside the
  # single WP_Locale_Switcher instance (class-wp-locale-switcher.php:23). Both are ambient
  # state that every call reaches into.
  #
  # Here that state is per-request and travels EXPLICITLY. `ActiveSupport::CurrentAttributes`
  # is reset by Rails at the start of every request and never leaks between them, so there
  # is no process-wide singleton anywhere -- exactly implication 1's requirement.
  #
  # Two things live here:
  #   * `request_locale` -- the base locale determine_locale() resolved for THIS request
  #     (set once by the surface, see Localization::Locale.for_request);
  #   * `switch_stack`   -- WP_Locale_Switcher's stack (BR-I18N-06 / BR-MIGRATE-288),
  #     a list of [locale, user_id] frames pushed by switch_to_locale() and popped by
  #     restore_previous_locale().
  class Current < ActiveSupport::CurrentAttributes
    # The determine_locale() result for the request. Nil until a surface resolves it, so
    # `Locale.current` can still fall back to the site locale off the request path (jobs,
    # console rake tasks) without inventing an ambient default.
    attribute :request_locale

    # The switch frames. Kept as an array attribute rather than a Ruby global; reset with
    # the rest of Current between requests, so a job that switched a locale cannot bleed
    # that switch into the next request on the same thread.
    attribute :switch_stack

    # WP_Locale_Switcher stores `determine_locale()` at construction (:49) as the locale to
    # fall back to once the stack empties. The request base plays that role here.
    def original_locale = request_locale

    def stack = self.switch_stack ||= []

    # Push a [locale, user_id] frame (switch_to_locale, :85).
    def push(locale, user_id)
      stack.push([locale, user_id])
    end

    # Pop the top frame (restore_previous_locale, array_pop at :124). nil when empty.
    def pop = stack.empty? ? nil : stack.pop

    # The locale of the top frame, or nil if nothing is switched (get_switched_locale, :189).
    def switched_locale
      frame = stack.last
      frame && frame[0]
    end

    # The user id of the top frame (get_switched_user_id, :206).
    def switched_user_id
      frame = stack.last
      frame && frame[1]
    end

    def switched? = !stack.empty?
  end
end
