# frozen_string_literal: true

module Console
  # console.index — wp-admin/index.php, modernized (target_screens.md:549). The
  # dashboard's widgets were HOOK-registered (wp_add_dashboard_widget, dashboard.php:73);
  # AD-01 removed the hook system, so DEV-002 makes the grid DECLARED — a plain list of
  # widgets this controller assembles. DEV-003: the At a Glance totals are exact counts
  # here, not the legacy's cached estimates.
  #
  # Gate: `read` (the capability every role holds; index.php requires only a logged-in
  # user with the dashboard). Declared `:authenticated` — being past auth_redirect is the
  # whole requirement, and BR-CAP-05 would allow it regardless.
  class DashboardController < BaseController
    include Chrome

    def index
      @counts = {
        posts: safe_count { Publishing::Article.published.count },
        pages: safe_count { Publishing::Page.published.count },
        comments: safe_count { Discussion::Comment.count },
      }
      @pending_comments = safe_count { Discussion::Comment.where(status: "pending").count }
      @search_discouraged = Platform::Health.search_engines_discouraged?
      @recent_posts = recent_posts
    end

    private

    def recent_posts
      Publishing::Article.published.order(published_at: :desc).limit(5).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def safe_count
      yield
    rescue ActiveRecord::StatementInvalid, NoMethodError
      0
    end
  end
end
