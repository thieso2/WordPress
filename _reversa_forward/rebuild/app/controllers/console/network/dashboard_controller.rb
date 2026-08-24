# frozen_string_literal: true

module Console
  module Network
    # console.ms-admin — ms-admin.php (which is only `wp_redirect( network_admin_url() )`)
    # → wp-admin/network/index.php, the Network Admin dashboard.
    #
    # The legacy grid is hook-registered (wp_dashboard_setup, dashboard.php:77); AD-01
    # removed the hooks, so DEV-002 makes it DECLARED — and the network dashboard declares
    # exactly ONE core widget, `network_dashboard_right_now` (dashboard.php:454), because
    # every other network widget on the oracle arrives through a filter.
    #
    # Right Now is: the two quick links, the counts sentence, and the two search forms.
    # Every string below is verbatim from wp-admin/includes/dashboard.php:454-525.
    class DashboardController < BaseController
      self.network_capability = "manage_network"

      # GET /console/network
      def index
        @page_title = "Dashboard"
        @screen = "console.ms-admin"
        @network_nav_key = "console.ms-admin"

        # dashboard.php:457-462 — the two quick links, each behind its own capability.
        @can_create_sites = site_can?("create_sites")
        @can_create_users = site_can?("create_users")

        # get_blog_count() / get_user_count(). DEV-003: the legacy reads these from the
        # `blog_count`/`user_count` network options, refreshed by wp_update_network_counts();
        # here they are exact counts, honestly priced.
        without_tenant do
          @site_count = Tenancy::Site.count
          @user_count = Identity::User.count
        end

        # dashboard.php:468-473 — _n( '%s site', '%s sites' ), _n( '%s user', '%s users' ),
        # then __( 'You have %1$s and %2$s.' ). Assembled here so the view prints one string.
        blog_text = "#{number_with_delimiter(@site_count)} #{@site_count == 1 ? 'site' : 'sites'}"
        user_text = "#{number_with_delimiter(@user_count)} #{@user_count == 1 ? 'user' : 'users'}"
        @right_now_sentence = "You have #{blog_text} and #{user_text}."
      end

      private

      def number_with_delimiter(value) = ActiveSupport::NumberHelper.number_to_delimited(value)
    end
  end
end
