# frozen_string_literal: true

module Console
  # console.site-health + console.site-health-info (target_screens.md:553-554). A status
  # report over Platform::Health. site-health.php gates on `view_site_health_checks`.
  class SiteHealthController < BaseController
    include Chrome

    # site-health.php:48 wp_die() — LITERAL, verbatim.
    DENIED = "Sorry, you are not allowed to access site health information."

    # site-health.php gates on `view_site_health_checks`. In the legacy that capability
    # is not held by any role — it is GRANTED at runtime by the `user_has_cap` filter
    # wp_maybe_grant_site_health_caps() (capabilities.php:1356) to whoever holds
    # `install_plugins`. AD-01 removed the filter channel, so the grant is expressed
    # directly: the underlying primitive is the gate, which admits exactly the users the
    # legacy filter would have (administrators hold `install_plugins`, RoleCatalogue).
    before_action -> { require_capability!("install_plugins", DENIED) }

    def show
      @report = Platform::Health.report
    end

    def info
      @info = Platform::Health.info
    end
  end
end
