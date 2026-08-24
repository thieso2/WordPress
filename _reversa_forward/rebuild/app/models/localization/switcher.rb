# frozen_string_literal: true

module Localization
  # BC-16 -- the switch STACK. WP_Locale_Switcher (class-wp-locale-switcher.php),
  # BR-I18N-06/07 (BR-MIGRATE-288/289). switch_to_locale() and switch_to_user_locale()
  # push; restore_previous_locale() pops; restore_current_locale() unwinds to the base.
  #
  # The legacy kept the stack as private state on a single global instance
  # ($wp_locale_switcher). paradigm_decision.md implication 1 forbids that global: the
  # stack lives in Localization::Current (ActiveSupport::CurrentAttributes), reset per
  # request, so a switch made inside a job or a request can never survive it. Every method
  # here reproduces the corresponding WP_Locale_Switcher method's exact control flow and
  # return contract; the only substitution is *where the stack lives*.
  #
  # The hooks the legacy fired -- `switch_locale`, `restore_previous_locale`,
  # `change_locale` (:98, :149, :300) -- are gone (AD-01); nothing listened to them in
  # core beyond the reload, which is reproduced directly.
  module Switcher
    module_function

    # switch_to_locale(), :75-101. Returns false and does NOTHING if the target equals the
    # current locale (:77) or is not an available language (:81); otherwise pushes the frame
    # (:85), reloads all textdomains in the new locale (:87), and returns true.
    def switch_to_locale(locale, user_id: nil)
      return false if Localization::Locale.current == locale
      return false unless Localization::Locale.available?(locale)

      Current.instance.push(locale, user_id)
      Catalogue.reload_all(locale)
      true
    end

    # switch_to_user_locale(), :111-114. The user's locale, with the user id kept as the
    # frame's context so a caller can read get_switched_user_id().
    def switch_to_user_locale(user)
      switch_to_locale(Localization::Locale.user_locale(user), user_id: user&.id)
    end

    # restore_previous_locale(), :123-152. Pops (:124); false if the stack was already empty
    # (:126). Otherwise the new effective locale is the frame now on top, or the request base
    # if the stack is empty (:131-137), the textdomains reload (:139), and the restored
    # locale string is returned (:151).
    def restore_previous_locale
      popped = Current.instance.pop
      return false if popped.nil?

      locale = Current.instance.switched_locale || Current.instance.original_locale || Localization::Locale.site_locale
      Catalogue.reload_all(locale)
      locale
    end

    # restore_current_locale(), :161-169. No-op returning false if nothing is switched
    # (:162); otherwise collapse the stack to the base and pop once, landing back on the
    # request's original locale.
    def restore_current_locale
      return false unless switched?

      base = Current.instance.original_locale || Localization::Locale.site_locale
      Current.instance.switch_stack = [[base, false]]
      restore_previous_locale
    end

    # is_switched(), :178.
    def switched? = Current.instance.switched?

    # get_switched_locale(), :189. false, not nil, to match the legacy return.
    def switched_locale = Current.instance.switched_locale || false

    # get_switched_user_id(), :206.
    def switched_user_id = Current.instance.switched_user_id || false
  end
end
