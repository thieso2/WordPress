# frozen_string_literal: true

module Console
  # console.edit — the Posts list (wp-admin/edit.php, WP_Posts_List_Table). P-LIST over
  # Publishing::Article with EXACT pagination (target_screens.md § Part 5).
  #
  # ⚠️ A distinct controller from the editor's Console::PostsController (wp-admin/post.php,
  # the single-record editor shell): WordPress itself separates edit.php from post.php, and
  # the two live in different tracks here. The URLs match the spec — GET /console/posts is
  # the list; /console/posts/new and /console/posts/:id/edit are the editor.
  #
  # LITERAL strings are verbatim from WP_Posts_List_Table / WP_Post_Type::get_default_labels
  # (columns, bulk-action labels, status-tab nooped plurals, "No posts found."). Which rows
  # appear and what each column holds is verified against the oracle's own edit.php.
  class PostsListController < BaseController
    include Console::ListActions

    # GET /console/posts
    def index
      @page_title = type_labels[:name]
      @screen = "console.edit"

      # search (params[:s], WP_Query 's') and the months/category filters (params[:m],
      # params[:cat]) and the Mine author view (params[:author]) all restrict the
      # relation before ordering — the controls actually narrow the list now.
      relation = ordered(filtered(searched(author_scoped(status_scoped(base_scope)))))
      page = list_page(relation, strategy: :exact)
      @list = build_list(page)
      render "console/posts_list/index"
    end

    # POST /console/posts/bulk — the bulk-action target for the checkbox column. Destructive
    # actions (trash, delete) get the DEV-004 confirmation first.
    def bulk
      # extra_tablenav's "Empty Trash" (submit_button 'delete_all') deletes every trashed
      # row at once (class-wp-posts-list-table.php:606, edit.php:90 'delete_all').
      return empty_trash if params[:delete_all].present? || bulk_action_name == "delete_all"

      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name

      # "Bulk edit" is the inline (Quick Edit) editor, driven client-side; with no island
      # to intercept it there is nothing to do server-side — fall back to the list.
      return redirect_to(list_path, status: :see_other) if action == "edit"

      posts = base_scope.where(id: bulk_ids).to_a

      if DESTRUCTIVE.include?(action) && !bulk_confirmed?
        return confirm_bulk(action, posts)
      end

      count = run_bulk(action, posts)
      flash[:success] = bulk_notice(action, count)
      redirect_to list_path, status: :see_other
    end

    private

    DESTRUCTIVE = %w[trash delete].freeze

    # Subclasses (pages) override these.
    def content_class = Publishing::Article
    def type_labels = { name: "Posts", add: "Add Post", add_path: "/console/posts/new" }
    def taxonomy_columns? = true

    # The post-type-specific noun for the bulk-completion notices (edit.php:359-381:
    # "%s post moved to the Trash." / "%s posts …"). Pages override to page/pages.
    def type_noun_singular = "post"
    def type_noun_plural = "posts"

    # `$post_type_object->cap->edit_others_posts` — gates the Empty Trash control
    # (class-wp-posts-list-table.php:602). Pages swap the family suffix.
    def edit_others_cap = content_class.hierarchical? ? "edit_others_pages" : "edit_others_posts"
    def edit_cap = content_class.hierarchical? ? "edit_pages" : "edit_posts"

    def base_scope = content_class.all

    # WP edit.php "all" excludes trash and auto-draft; a status tab filters to that status.
    def status_scoped(scope)
      case params[:status].to_s
      when "", "all" then scope.where.not(status: %w[trashed auto_draft])
      when "trash"   then scope.in_trashed
      when "sticky"  then sticky_scope(scope)
      else scope.where(status: params[:status])
      end
    end

    # get_views 'mine' — the Mine view filters to the current user's posts (author=current).
    def author_scoped(scope)
      return scope if params[:author].blank?

      scope.where(author_id: params[:author])
    end

    # WP_Query 's' — a title/content/excerpt search (edit.php:490, search_box feeds 's').
    # The rebuilt search box now actually restricts the relation instead of only echoing.
    def searched(scope)
      term = params[:s].to_s.strip
      return scope if term.blank?

      like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      scope.where("posts.title ILIKE :q OR posts.content ILIKE :q OR posts.excerpt ILIKE :q", q: like)
    end

    # extra_tablenav's months_dropdown (params[:m]) and categories_dropdown (params[:cat],
    # Posts only) — class-wp-posts-list-table.php:574-599.
    def filtered(scope)
      scope = month_filtered(scope)
      scope = category_filtered(scope) if taxonomy_columns?
      scope
    end

    def month_filtered(scope)
      m = params[:m].to_s
      return scope unless m.match?(/\A\d{6}\z/) && m != "000000"

      year = m[0, 4].to_i
      month = m[4, 2].to_i
      return scope if year.zero? || month.zero?

      start = Time.zone.local(year, month, 1)
      scope.where(published_at: start...start.next_month)
    end

    def category_filtered(scope)
      cat = params[:cat].to_s
      return scope if cat.blank? || cat == "0"

      ids = Classification::Assignment
            .where(classifiable_type: "Publishing::Post", term_id: cat)
            .pluck(:classifiable_id)
      scope.where(id: ids)
    end

    def trash_view? = params[:status].to_s == "trash"

    # `show_sticky=1` (class-wp-posts-list-table.php:399): the ids in the `sticky_posts`
    # setting, minus the two statuses the view excludes.
    def sticky_scope(scope)
      scope.where(id: sticky_ids).where.not(status: %w[trashed auto_draft])
    end

    # `get_option('sticky_posts')` is an array of ids but FALSE when unset, and Array(false)
    # is [false] rather than [] — the same trap PublicApi::PostSerializer#sticky? guards.
    def sticky_ids
      list = Configuration::Setting["sticky_posts"]
      return [] unless list.is_a?(Array)

      list.map(&:to_i).reject(&:zero?)
    end

    SORTABLE = %w[title date].freeze

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "date")
      dir = list_order.upcase
      column = orderby == "title" ? "posts.title" : "posts.published_at"
      nulls = dir == "DESC" ? "NULLS LAST" : "NULLS FIRST"
      scope.order(Arel.sql("#{column} #{dir} #{nulls}, posts.id #{dir}"))
    end

    # m / cat / author are list controls too, so they must survive a re-sort or a page
    # step (list_actions#list_query whitelists only the core controls; extend it here).
    def list_query
      extra = params.permit(:m, :cat, :author).to_h.reject { |_, v| v.blank? }
      super.merge(extra)
    end

    # ── Building the P-LIST model ───────────────────────────────────────────────────

    def build_list(page)
      taxonomies = preload_taxonomies(page.records)
      ListModel.new(
        screen: "console.edit",
        title: type_labels[:name],
        primary_action: primary_action,
        tabs: status_tabs,
        filters: list_filters,
        bulk_actions: bulk_actions,
        columns: columns,
        rows: page.records.map { |post| row_for(post, taxonomies) },
        page: page,
        strategy: :exact,
        base_path: list_path,
        bulk_path: bulk_path,
        empty_message: empty_message,
        query: list_query,
        order: list_order,
        orderby: list_orderby(SORTABLE, default: "date"),
        search_query: params[:s].presence
      )
    end

    # The FilterBar: the search box, then the months/category select filters and (in the
    # Trash view) the Empty Trash control. class-wp-posts-list-table.php:568-608.
    def list_filters
      filters = [ListModel::Filter.new(kind: :search, name: "s",
                                       label: "Search #{type_labels[:name]}", value: params[:s].to_s)]
      months = month_options
      filters << ListModel::Filter.new(kind: :select, name: "m", label: "Filter by date",
                                       value: params[:m].to_s, options: months) if months.length > 1
      if taxonomy_columns?
        filters << ListModel::Filter.new(kind: :select, name: "cat", label: "Filter by category",
                                         value: params[:cat].to_s, options: category_options)
      end
      filters << ListModel::Filter.new(kind: :empty_trash, name: "delete_all", label: "Empty Trash") if show_empty_trash?
      filters
    end

    # months_dropdown (class-wp-list-table.php:712): distinct Year/Month of the type's
    # posts, newest first, with the leading "All dates" sentinel. Trash view lists the
    # trashed rows' months; every other view excludes trash and auto-draft.
    def month_options
      scope = base_scope.where.not(published_at: nil)
      scope = trash_view? ? scope.where(status: "trashed") : scope.where.not(status: %w[trashed auto_draft])
      pairs = scope.distinct.pluck(
        Arel.sql("EXTRACT(YEAR FROM published_at)::int"),
        Arel.sql("EXTRACT(MONTH FROM published_at)::int")
      )
      options = pairs.reject { |year, _| year.to_i.zero? }.sort.reverse.map do |year, month|
        ["#{Date::MONTHNAMES[month]} #{year}", format("%04d%02d", year, month)]
      end
      [["All dates", "0"]] + options
    end

    # categories_dropdown (class-wp-posts-list-table.php:464): the category terms, name
    # order, under the "All Categories" (labels->all_items) sentinel.
    def category_options
      taxonomy = Classification::Taxonomy.find_by(name: "category")
      terms = taxonomy ? Classification::Term.where(taxonomy: taxonomy).order(:name) : []
      [["All Categories", "0"]] + terms.map { |t| [t.name, t.id.to_s] }
    end

    def show_empty_trash?
      trash_view? && site_can?(edit_others_cap) && base_scope.in_trashed.exists?
    end

    def primary_action
      return nil unless site_can?(edit_cap)

      { label: type_labels[:add], path: type_labels[:add_path] }
    end

    # WP_Posts_List_Table::get_columns — LITERAL headers. Pages carry no category/tag
    # columns (no taxonomies registered for the page type). The Comments column is dropped
    # for the pending/draft/future status views (get_columns, :702-704).
    def columns
      cols = [ListModel::Column.new(key: "title", label: "Title", sortable: true, sort_key: "title")]
      cols << ListModel::Column.new(key: "author", label: "Author", sortable: false)
      if taxonomy_columns?
        cols << ListModel::Column.new(key: "categories", label: "Categories", sortable: false)
        cols << ListModel::Column.new(key: "tags", label: "Tags", sortable: false)
      end
      unless %w[pending draft scheduled].include?(params[:status].to_s)
        # The comments bubble: LITERAL screen-reader "Comments".
        cols << ListModel::Column.new(key: "comments",
                                      label: '<span class="screen-reader-text">Comments</span>'.html_safe, sortable: false)
      end
      cols << ListModel::Column.new(key: "date", label: "Date", sortable: true, sort_key: "date")
      cols
    end

    # get_bulk_actions(), class-wp-posts-list-table.php:432. Non-trash: "Bulk edit" (when
    # the user can edit) then "Move to Trash"; trash: Restore + Delete permanently.
    def bulk_actions
      if trash_view?
        [ListModel::BulkAction.new(value: "untrash", label: "Restore", destructive: false),
         ListModel::BulkAction.new(value: "delete", label: "Delete permanently", destructive: true)]
      else
        actions = []
        actions << ListModel::BulkAction.new(value: "edit", label: "Bulk edit", destructive: false) if site_can?(edit_cap)
        actions << ListModel::BulkAction.new(value: "trash", label: "Move to Trash", destructive: true)
        actions
      end
    end

    # get_views(), class-wp-posts-list-table.php:289. All + the Mine view (when the user
    # has posts and others do too) + one tab per status present, labelled with the status
    # object's nooped plural (post.php register_post_status), verbatim, with the count.
    STATUS_LABEL = {
      "published" => "Published", "scheduled" => "Scheduled", "draft" => "Draft",
      "pending" => "Pending", "private" => "Private", "trashed" => "Trash"
    }.freeze
    STATUS_TAB_ORDER = %w[published scheduled draft pending private trashed].freeze

    def status_tabs
      counts = base_scope.where.not(status: "auto_draft").group(:status).count
      all_count = counts.reject { |s, _| s == "trashed" }.values.sum
      current = params[:status].to_s
      author = params[:author].to_s
      tabs = [ListModel::Tab.new(
        key: "all", count: all_count,
        label: %(All <span class="count">(#{delimited(all_count)})</span>).html_safe,
        query: { "status" => nil, "author" => nil },
        current: (current.empty? || current == "all") && author.empty?
      )]
      mine_tab(all_count, author)&.tap { |t| tabs << t }
      STATUS_TAB_ORDER.each do |status|
        n = counts[status].to_i
        next if n.zero?

        key = status == "trashed" ? "trash" : status
        tabs << ListModel::Tab.new(
          key: key, count: n,
          label: %(#{STATUS_LABEL[status]} <span class="count">(#{delimited(n)})</span>).html_safe,
          query: { "status" => key }, current: current == key
        )
      end
      splice_sticky_tab(tabs, current)
      tabs
    end

    # class-wp-posts-list-table.php:112-125 + :398-415 — a `Sticky (n)` view, POSTS ONLY,
    # shown only when the `sticky_posts` setting is non-empty, counting rows that are
    # neither trashed nor auto-draft. It sits immediately after Published in get_views().
    def splice_sticky_tab(tabs, current)
      return unless taxonomy_columns? # posts only; pages have no sticky view

      ids = sticky_ids
      return if ids.empty?

      count = base_scope.where(id: ids).where.not(status: %w[trashed auto_draft]).count
      return if count.zero?

      tab = ListModel::Tab.new(
        key: "sticky", count: count,
        label: %(Sticky <span class="count">(#{delimited(count)})</span>).html_safe,
        query: { "status" => "sticky" }, current: current == "sticky"
      )
      at = tabs.index { |t| t.key == "published" }
      at ? tabs.insert(at + 1, tab) : tabs << tab
    end

    # get_views 'mine' (:322): shown only when the current user has authored posts AND
    # there are other authors' posts too (user_posts_count !== total).
    def mine_tab(all_count, author)
      return nil unless current_actor

      mine_count = base_scope.where.not(status: %w[trashed auto_draft]).where(author_id: current_actor.id).count
      return nil if mine_count.zero? || mine_count == all_count

      ListModel::Tab.new(
        key: "mine", count: mine_count,
        label: %(Mine <span class="count">(#{delimited(mine_count)})</span>).html_safe,
        query: { "status" => nil, "author" => current_actor.id },
        current: author == current_actor.id.to_s
      )
    end

    def delimited(n) = ActiveSupport::NumberHelper.number_to_delimited(n)

    def empty_message = content_class.hierarchical? ? "No pages found." : "No posts found."

    # ── Row cells ──────────────────────────────────────────────────────────────────

    def row_for(post, taxonomies)
      ListModel::Row.new(
        id: post.id,
        cells: {
          "title" => title_cell(post),
          "author" => author_cell(post),
          "categories" => term_cell(taxonomies.dig(post.id, "category")),
          "tags" => term_cell(taxonomies.dig(post.id, "post_tag")),
          "comments" => comments_cell(post),
          "date" => date_cell(post)
        },
        actions: row_actions(post)
      )
    end

    def title_cell(post)
      title = post.title.presence || "(no title)"
      state = post.trashed? ? nil : STATUS_LABEL[post.status].then { |l| l == "Published" ? nil : l }
      link = %(<strong><a class="row-title" href="/console/posts/#{post.id}/edit">#{ERB::Util.html_escape(title)}</a></strong>)
      link += %( — <span class="post-state">#{state}</span>) if state
      link.html_safe
    end

    def author_cell(post)
      name = post.author&.display_name.presence || post.author&.login.to_s
      ERB::Util.html_escape(name)
    end

    def term_cell(terms)
      return "—".html_safe if terms.blank?

      terms.map { |name| ERB::Util.html_escape(name) }.join(", ").html_safe
    end

    # column_comments (class-wp-posts-list-table.php:1362): a comments bubble linking to
    # the comments screen filtered to this post, not the raw integer.
    def comments_cell(post)
      count = post.comment_count.to_i
      href = "/console/comments?p=#{post.id}"
      reader = count == 1 ? "1 comment" : "#{count} comments"
      bubble = %(<a href="#{href}" class="post-com-count post-com-count-approved">) +
               %(<span class="comment-count-approved" aria-hidden="true">#{count}</span>) +
               %(<span class="screen-reader-text">#{reader}</span></a>)
      %(<div class="post-com-count-wrapper">#{bubble}</div>).html_safe
    end

    # column_date (class-wp-posts-list-table.php:1291): the status line then the timestamp
    # as "Y/m/d at g:i a". A future post whose scheduled instant has already passed shows
    # "Missed schedule" instead of "Scheduled"; a post with no date shows "Unpublished".
    def date_cell(post)
      if post.published_at.nil?
        t_time = "Unpublished"
        missed = false
      else
        t_time = post.published_at.strftime("%Y/%m/%d at %-l:%M %P")
        missed = post.published_at < Time.current
      end
      status =
        if post.published?
          "Published"
        elsif post.scheduled?
          missed ? '<strong class="error-message">Missed schedule</strong>' : "Scheduled"
        else
          "Last Modified"
        end
      %(#{status}<br />#{t_time}).html_safe
    end

    def row_actions(post)
      actions = []
      if can?(Access::PostPolicy, post, :edit)
        actions << ListModel::RowAction.new(label: "Edit", path: "/console/posts/#{post.id}/edit", method: :get, key: "edit")
      end
      if can?(Access::PostPolicy, post, :delete)
        if trash_view?
          actions << ListModel::RowAction.new(label: "Restore", path: bulk_path, method: :post,
                                              params: { bulk_action: "untrash", "ids[]" => post.id }, key: "untrash")
          actions << ListModel::RowAction.new(label: "Delete Permanently", path: bulk_path, method: :post,
                                              params: { bulk_action: "delete", confirmed: "0", "ids[]" => post.id },
                                              destructive: true, key: "delete")
        else
          actions << ListModel::RowAction.new(label: "Trash", path: bulk_path, method: :post,
                                              params: { bulk_action: "trash", confirmed: "0", "ids[]" => post.id },
                                              destructive: true, key: "trash")
        end
      end
      actions.concat(view_actions(post))
      actions
    end

    # handle_row_actions 'view'/'Preview' (class-wp-posts-list-table.php:1643): posts and
    # pages are viewable, so a published/private row gets "View" (permalink) and a
    # pending/draft/scheduled row the current user can edit gets "Preview".
    def view_actions(post)
      return [] if trash_view?

      if %w[pending draft scheduled].include?(post.status)
        return [] unless can?(Access::PostPolicy, post, :edit)

        [ListModel::RowAction.new(label: "Preview", path: preview_url(post), method: :get, key: "view")]
      else
        [ListModel::RowAction.new(label: "View", path: permalink(post), method: :get, key: "view")]
      end
    end

    def permalink(post) = post.slug.present? ? "/#{post.slug}" : "/?p=#{post.id}"
    def preview_url(post) = "/?p=#{post.id}&preview=true"

    # ── Bulk execution ──────────────────────────────────────────────────────────────

    def run_bulk(action, posts)
      count = 0
      posts.each do |post|
        case action
        when "trash"
          next unless can?(Access::PostPolicy, post, :delete)

          post.trash!(actor: current_actor)
        when "untrash"
          next unless can?(Access::PostPolicy, post, :delete)

          post.restore!(actor: current_actor)
        when "delete"
          next unless can?(Access::PostPolicy, post, :delete)

          post.delete!(actor: current_actor)
        else next
        end
        count += 1
      end
      count
    end

    # submit_button( 'Empty Trash', 'apply', 'delete_all' ) (class-wp-posts-list-table.php
    # :606) / edit.php:90 'delete_all': permanently delete every trashed row at once. Gated
    # by edit_others_posts and routed through the DEV-004 confirmation like every delete.
    def empty_trash
      return redirect_to(list_path, status: :see_other) unless site_can?(edit_others_cap)

      posts = base_scope.in_trashed.select { |post| can?(Access::PostPolicy, post, :delete) }

      return confirm_bulk("delete_all", posts) unless bulk_confirmed?

      count = 0
      posts.each do |post|
        post.delete!(actor: current_actor)
        count += 1
      end
      flash[:success] = bulk_notice("delete", count)
      redirect_to list_path, status: :see_other
    end

    def confirm_bulk(action, posts)
      posts = posts.select { |post| can?(Access::PostPolicy, post, :delete) }
      label = %w[delete delete_all].include?(action) ? "Delete permanently" : "Move to Trash"
      render_bulk_confirmation(
        title: type_labels[:name],
        prompt: confirm_prompt(action, posts.length),
        button: label,
        action: action,
        ids: posts.map(&:id),
        items: posts.map { |post| post.title.presence || "(no title)" },
        post_path: bulk_path,
        cancel_path: list_path
      )
    end

    def confirm_prompt(action, n)
      if %w[delete delete_all].include?(action)
        "You are about to permanently delete #{n} item(s). This action cannot be undone."
      else
        "You are about to move #{n} item(s) to the Trash."
      end
    end

    # Bulk-completion notices, verbatim from edit.php:359-381 ($bulk_messages), with the
    # post-type noun and the _n() singular/plural on the count.
    def bulk_notice(action, count)
      noun = count == 1 ? type_noun_singular : type_noun_plural
      case action
      when "trash"   then "#{count} #{noun} moved to the Trash."
      when "untrash" then "#{count} #{noun} restored from the Trash."
      when "delete"  then "#{count} #{noun} permanently deleted."
      else "Done."
      end
    end

    # Terms assigned to the page's posts, grouped {post_id => {taxonomy => [names]}}. One
    # query for the whole page, not per row.
    def preload_taxonomies(posts)
      return {} if posts.empty? || !taxonomy_columns?

      rows = Classification::Assignment
             .where(classifiable_type: "Publishing::Post", classifiable_id: posts.map(&:id))
             .joins(term: :taxonomy)
             .pluck(:classifiable_id, Arel.sql("taxonomies.name"), Arel.sql("terms.name"))
      rows.each_with_object({}) do |(post_id, taxonomy, name), out|
        (out[post_id] ||= {})[taxonomy] ||= []
        out[post_id][taxonomy] << name
      end
    end

    def list_path = "/console/posts"
    def bulk_path = "/console/posts/bulk"
  end
end
