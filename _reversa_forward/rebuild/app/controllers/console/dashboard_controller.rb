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
      load_dashboard
    end

    # POST /console/quick-draft — wp-admin/post.php `case 'post-quickdraft-save'` (:73-101),
    # the Quick Draft widget's save. edit_post() reads post_title/content and saves a DRAFT;
    # an empty title AND content is refused with the LITERAL error. The QuickPress widget is
    # registered only for an actor with create_posts (dashboard.php:86-88), so the same gate
    # guards the POST — mapped through the record's own policy (create_posts → edit_posts),
    # exactly as console/posts#new does for get_default_post_to_edit().
    def quick_draft
      return head :forbidden unless can_create_posts?

      title   = params[:post_title].to_s.strip
      content = params[:content].to_s.strip

      # post.php:102 — 'Cannot create a draft post with empty title and content.'
      if title.empty? && content.empty?
        @quick_draft_error = "Cannot create a draft post with empty title and content."
        load_dashboard
        return render :index, status: :unprocessable_content
      end

      draft = Publishing::Article.new(author: current_actor, status: :draft,
                                      title: title, content: content, excerpt: "")
      draft.actor = current_actor
      draft.save!
      # post.php:108 — 'Draft created successfully.'
      redirect_after_submit(console_dashboard_path, notice: "Draft created successfully.")
    end

    private

    # Assembles every declared widget's data (DEV-002). Shared by #index and the
    # re-render arm of #quick_draft.
    def load_dashboard
      @posts_count        = safe_count { Publishing::Article.published.count }
      @pages_count        = safe_count { Publishing::Page.published.count }
      @approved_comments  = safe_count { Discussion::Comment.approved.count }
      @moderated_comments = safe_count { Discussion::Comment.in_pending.count }

      @can_edit_posts = site_can?(:edit_posts)
      @can_edit_pages = site_can?(:edit_pages)

      @search_discouraged = Platform::Health.search_engines_discouraged? && site_can?(:manage_options)

      # wp_dashboard_site_activity (dashboard.php:942) — three sections.
      @future_posts    = future_posts   # 'Publishing Soon' (status=future, ASC)
      @recent_posts    = recent_posts   # 'Recently Published' (status=publish, DESC)
      @recent_comments = recent_comments

      # QuickPress (dashboard.php:86) + 'Your Recent Drafts' (dashboard.php:637).
      @can_create_posts = can_create_posts?
      @recent_drafts    = recent_drafts if @can_create_posts
    end

    # wp_dashboard_recent_posts( status 'future', order ASC ) — the 5 nearest scheduled
    # posts. post_type 'post' only, as the legacy's default (dashboard.php:947-950).
    def future_posts
      Publishing::Article.in_scheduled.order(Arel.sql("published_at ASC NULLS LAST, id ASC")).limit(5).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def recent_posts
      Publishing::Article.published.order(Arel.sql("published_at DESC NULLS LAST, id DESC")).limit(5).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # wp_dashboard_recent_comments (dashboard.php:1082) — the 5 most recent comments, spam
    # and trash excluded; an actor without edit_posts sees only approved ones (:1091-1093).
    def recent_comments
      scope = Discussion::Comment.where.not(status: %w[spam trashed])
      scope = scope.approved unless @can_edit_posts
      scope.order(submitted_at: :desc, id: :desc).limit(5).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # wp_dashboard_recent_drafts (dashboard.php:637) — the current user's own drafts,
    # newest-modified first, up to 4 fetched so the widget can show "View all" past 3.
    def recent_drafts
      Publishing::Article.in_draft.where(author_id: current_actor&.id)
                         .order(updated_at: :desc, id: :desc).limit(4).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # dashboard.php:86 — current_user_can( get_post_type_object('post')->cap->create_posts ).
    # create_posts maps through the record's policy to edit_posts (the auto_draft the actor
    # owns), the same resolution console/posts#new relies on.
    def can_create_posts?
      probe = Publishing::Article.new(author: current_actor, status: :auto_draft,
                                      title: "", content: "", excerpt: "")
      Access::PostPolicy.for(current_actor, probe).permit?(:edit)
    end

    def safe_count
      yield
    rescue ActiveRecord::StatementInvalid, NoMethodError
      0
    end
  end
end
