# frozen_string_literal: true

module PublicApi
  # BR-MIGRATE-356 (BR-SH-05). "Results are also exposed through the site-health REST
  # controller." The legacy registers `wp-site-health/v1` and serves each async test at
  # `tests/<name>` (class-wp-rest-site-health-controller.php:48). Of that battery only the
  # loopback test has a genuine analogue here (BR-MIGRATE-355 → the job queue); the rest
  # poll wordpress.org (background-updates, dotorg-communication → VOID, no update server,
  # Platform::Updates::VOID_UPDATE_CHECK) or probe shared-hosting transports
  # (authorization-header → absorbed). So one route is served, honestly, rather than a
  # namespace of stubs.
  #
  # The endpoint returns `get_test_loopback_requests()`'s document verbatim
  # (Platform::Health.loopback_rest_result), so the console site-health screen and the REST
  # surface read the SAME test — the legacy's async_direct_test invariant, one layer down.
  #
  # ⚠️ Advertising: this namespace is deliberately NOT added to the REST index's
  # `namespaces` list (PublicApi::RootController advertises only namespaces whose full
  # route set is served). One served route is not the legacy's full wp-site-health/v1
  # surface, and advertising a namespace whose routes mostly do not exist would be a false
  # contract — the same reasoning RootController already records. Reported in the handoff.
  class SiteHealthController < BaseController
    # validate_request_permission('loopback_requests') gates on `view_site_health_checks`
    # (class-wp-rest-site-health-controller.php:188). AD-01 removed the filter that GRANTS
    # that capability at runtime (wp_maybe_grant_site_health_caps() maps it onto whoever
    # holds `install_plugins`, capabilities.php:1356), so the gate is expressed directly:
    # `install_plugins`, which administrators hold (RoleCatalogue) — exactly the users the
    # legacy filter would admit. Same primitive the Console::SiteHealthController uses.
    permission :loopback_requests, :require_site_health_capability

    def loopback_requests
      render_json(Platform::Health.loopback_rest_result)
    end

    private

    # false → BaseController#deny! → rest_forbidden, 401 for anonymous / 403 for an
    # authenticated caller without the capability (rest_authorization_required_code(),
    # the same envelope validate_request_permission()'s `false` produces upstream).
    def require_site_health_capability
      return false unless current_actor

      Access::SitePolicy.new(current_actor, nil).permit?(:install_plugins)
    end
  end
end
