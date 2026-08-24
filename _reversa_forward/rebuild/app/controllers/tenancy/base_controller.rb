# frozen_string_literal: true

module Tenancy
  # The signup/activation surface (target_screens.md Part 6, 5 screens, MODERNIZED mode).
  # wp-signup.php + wp-activate.php, one screen per state instead of one script branching on
  # request shape. A delivery SURFACE, so it is one of the only places allowed to depend on
  # Access/Tenancy (target_architecture.md Note 2).
  #
  # These screens are NOT among the 25 byte-parity front-end screens (they are Wave 5,
  # post-launch), so the mode is modernized: the CONTRACT is semantic and every user-facing
  # string is the legacy's verbatim (wp-signup.php / wp-activate.php, cited at each use) —
  # DEV-009 lets only branding differ, and RISK-008 forbids copy editing.
  class BaseController < ApplicationController
    layout "tenancy"

    # These screens exist only under multisite. With it disabled (single site, the default),
    # the whole surface answers with the legacy's "not available" state rather than 404 —
    # wp-signup.php short-circuits to `_e( 'Registration has been disabled.' )` when signups
    # are closed (wp-signup.php:82). A single site is the strongest form of "closed".
    before_action :require_multisite

    helper_method :multisite_enabled?

    private

    def multisite_enabled? = Tenancy.enabled?

    def require_multisite
      return if Tenancy.enabled?

      # Rendered inside the tenancy layout; 200, as wp-signup.php returns for the disabled
      # state (it is a page, not an error).
      render "tenancy/shared/disabled"
    end
  end
end
