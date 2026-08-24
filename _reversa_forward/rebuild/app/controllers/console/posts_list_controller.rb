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

      relation = ordered(status_scoped(base_scope))
      page = list_page(relation, strategy: :exact)
      @list = build_list(page)
      render "console/posts_list/index"
    end

    # POST /console/posts/bulk — the bulk-action target for the checkbox column. Destructive
    # actions (trash, delete) get the DEV-004 confirmation first.
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      posts = base_scope.where(id: bulk_ids).to_a

      if DESTRUCTIVE.include?(action) && !bulk_confirmed?
        return confirm_bulk(action, posts)
      end

      count = run_bulk(action, posts)
      redirect_to list_path, notice: bulk_notice(action, count), status: :see_other
    end

    private

    DESTRUCTIVE = %w[trash delete].freeze

    # Subclasses (pages) override these three.
    def content_class = Publishing::Article
    def type_labels = { name: "Posts", add: "Add Post", add_path: "/console/posts/new" }
    def taxonomy_columns? = true

    def base_scope = content_class.all

    # WP edit.php "all" excludes trash and auto-draft; a status tab filters to that status.
    def status_scoped(scope)
      case params[:status].to_s
      when "", "all" then scope.where.not(status: %w[trashed auto_draft])
      when "trash"   then scope.in_trashed
      else scope.where(status: params[:status])
      end
    end

    def trash_view? = params[:status].to_s == "trash"

    SORTABLE = %w[title date].freeze

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "date")
      dir = list_order.upcase
      column = orderby == "title" ? "posts.title" : "posts.published_at"
      nulls = dir == "DESC" ? "NULLS LAST" : "NULLS FIRST"
      scope.order(Arel.sql("#{column} #{dir} #{nulls}, posts.id #{dir}"))
    end

    # ── Building the P-LIST model ───────────────────────────────────────────────────

    def build_list(page)
      taxonomies = preload_taxonomies(page.records)
      ListModel.new(
        screen: "console.edit",
        title: type_labels[:name],
        primary_action: primary_action,
        tabs: status_tabs,
        filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search #{type_labels[:name]}", value: params[:s].to_s)],
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

    def primary_action
      return nil unless site_can?(content_class.hierarchical? ? "edit_pages" : "edit_posts")

      { label: type_labels[:add], path: type_labels[:add_path] }
    end

    # WP_Posts_List_Table::get_columns — LITERAL headers. Pages carry no category/tag
    # columns (no taxonomies registered for the page type).
    def columns
      cols = [ListModel::Column.new(key: "title", label: "Title", sortable: true, sort_key: "title")]
      cols << ListModel::Column.new(key: "author", label: "Author", sortable: false)
      if taxonomy_columns?
        cols << ListModel::Column.new(key: "categories", label: "Categories", sortable: false)
        cols << ListModel::Column.new(key: "tags", label: "Tags", sortable: false)
      end
      # The comments bubble: LITERAL screen-reader "Comments".
      cols << ListModel::Column.new(key: "comments",
                                    label: '<span class="screen-reader-text">Comments</span>'.html_safe, sortable: false)
      cols << ListModel::Column.new(key: "date", label: "Date", sortable: true, sort_key: "date")
      cols
    end

    # get_bulk_actions(), class-wp-posts-list-table.php:432. Non-trash: Move to Trash;
    # trash: Restore + Delete permanently. "Bulk edit" (the quick-edit UI) is deferred —
    # it needs the inline editor island, out of this pass.
    def bulk_actions
      if trash_view?
        [ListModel::BulkAction.new(value: "untrash", label: "Restore", destructive: false),
         ListModel::BulkAction.new(value: "delete", label: "Delete permanently", destructive: true)]
      else
        [ListModel::BulkAction.new(value: "trash", label: "Move to Trash", destructive: true)]
      end
    end

    # get_views(), class-wp-posts-list-table.php:289. All + one tab per status present,
    # labelled with the status object's nooped plural (post.php register_post_status),
    # verbatim, interpolated with the count.
    STATUS_LABEL = {
      "published" => "Published", "scheduled" => "Scheduled", "draft" => "Draft",
      "pending" => "Pending", "private" => "Private", "trashed" => "Trash"
    }.freeze
    STATUS_TAB_ORDER = %w[published scheduled draft pending private trashed].freeze

    def status_tabs
      counts = base_scope.where.not(status: "auto_draft").group(:status).count
      all_count = counts.reject { |s, _| s == "trashed" }.values.sum
      current = params[:status].to_s
      tabs = [ListModel::Tab.new(
        key: "all", count: all_count,
        label: %(All <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(all_count)})</span>).html_safe,
        query: { "status" => nil }, current: current.empty? || current == "all"
      )]
      STATUS_TAB_ORDER.each do |status|
        n = counts[status].to_i
        next if n.zero?

        key = status == "trashed" ? "trash" : status
        tabs << ListModel::Tab.new(
          key: key, count: n,
          label: %(#{STATUS_LABEL[status]} <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(n)})</span>).html_safe,
          query: { "status" => key }, current: current == key
        )
      end
      tabs
    end

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
          "comments" => post.comment_count.to_i.to_s,
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

    def date_cell(post)
      instant = post.published_at || post.modified_at
      return "—".html_safe if instant.nil?

      label = post.scheduled? ? "Scheduled" : (post.published? ? "Published" : "Last Modified")
      %(#{label}<br><span>#{instant.strftime("%Y/%m/%d")}</span>).html_safe
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
      actions
    end

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

    def confirm_bulk(action, posts)
      posts = posts.select { |post| can?(Access::PostPolicy, post, :delete) }
      label = action == "delete" ? "Delete permanently" : "Move to Trash"
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
      if action == "delete"
        "You are about to permanently delete #{n} item(s). This action cannot be undone."
      else
        "You are about to move #{n} item(s) to the Trash."
      end
    end

    def bulk_notice(action, count)
      case action
      when "trash"   then "#{count} item(s) moved to the Trash."
      when "untrash" then "#{count} item(s) restored from the Trash."
      when "delete"  then "#{count} item(s) permanently deleted."
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
