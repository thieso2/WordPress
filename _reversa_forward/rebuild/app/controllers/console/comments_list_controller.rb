# frozen_string_literal: true

module Console
  # console.edit-comments — the Comments list (wp-admin/edit-comments.php,
  # WP_Comments_List_Table). P-LIST over Discussion::Comment, EXACT pagination
  # (target_screens.md § Part 5). console.moderation is the same screen with
  # ?status=pending (the legacy alias).
  #
  # ⚠️ The moderation DEVIATIONS (BR-CMT-04/08/10) are about how a verdict is COMPUTED,
  # not how the list renders; the list shows the four target statuses (pending, approved,
  # spam, trashed) mapped onto the legacy's tabs. LITERAL strings — columns, bulk labels,
  # status tabs, "No comments found." — are verbatim from WP_Comments_List_Table.
  #
  # A distinct controller from the P-EDIT track's Console::CommentsController (the single
  # comment editor at /console/comments/:id/edit): edit-comments.php and comment.php are
  # separate screens in the legacy too.
  class CommentsListController < BaseController
    include Console::ListActions

    # GET /console/comments
    def index
      @page_title = "Comments"
      @screen = "console.edit-comments"

      relation = ordered(status_scoped(Discussion::Comment.all)).includes(:post)
      page = list_page(relation, strategy: :exact)
      @list = build_list(page)
      render "console/comments_list/index"
    end

    # POST /console/comments/bulk
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      comments = Discussion::Comment.where(id: bulk_ids).to_a

      if DESTRUCTIVE.include?(action) && !bulk_confirmed?
        return confirm_bulk(action, comments)
      end

      count = run_bulk(action, comments)
      redirect_to list_path(status: params[:status]), notice: bulk_notice(action, count), status: :see_other
    end

    private

    DESTRUCTIVE = %w[spam trash delete].freeze
    SORTABLE = %w[date].freeze

    def status_scoped(scope)
      case current_status
      when "pending"  then scope.in_pending
      when "approved" then scope.in_approved
      when "spam"     then scope.in_spam
      when "trash"    then scope.in_trashed
      else scope.where.not(status: %w[spam trashed]) # "all" excludes spam and trash
      end
    end

    # The alias route passes ?status=pending; the legacy's own tab value is 'moderated'.
    def current_status
      s = params[:status].to_s
      s == "moderated" ? "pending" : s
    end

    def ordered(scope)
      dir = list_order.upcase
      scope.order(Arel.sql("comments.submitted_at #{dir}, comments.id #{dir}"))
    end

    def build_list(page)
      ListModel.new(
        screen: "console.edit-comments",
        title: "Comments",
        tabs: status_tabs,
        filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search Comments", value: params[:s].to_s)],
        bulk_actions: bulk_actions,
        columns: columns,
        rows: page.records.map { |comment| row_for(comment) },
        page: page,
        strategy: :exact,
        base_path: list_path,
        bulk_path: bulk_path,
        empty_message: current_status == "trash" ? "No comments found in Trash." : "No comments found.",
        query: list_query,
        order: list_order,
        orderby: "date",
        search_query: params[:s].presence
      )
    end

    # get_columns(), class-wp-comments-list-table.php:497 — LITERAL.
    def columns
      [
        ListModel::Column.new(key: "author", label: "Author", sortable: false),
        ListModel::Column.new(key: "comment", label: "Comment", sortable: false),
        ListModel::Column.new(key: "response", label: "In response to", sortable: false),
        ListModel::Column.new(key: "date", label: "Submitted on", sortable: true, sort_key: "date")
      ]
    end

    # get_bulk_actions(), class-wp-comments-list-table.php:388 — the set depends on the
    # current status tab. Every label LITERAL.
    def bulk_actions
      status = current_status
      actions = []
      actions << ListModel::BulkAction.new(value: "unapprove", label: "Unapprove", destructive: false) if %w[all approved].include?(status_or_all)
      actions << ListModel::BulkAction.new(value: "approve", label: "Approve", destructive: false) if %w[all pending].include?(status_or_all)
      actions << ListModel::BulkAction.new(value: "spam", label: "Mark as spam", destructive: true) if %w[all pending approved trash].include?(status_or_all)
      if status == "trash"
        actions << ListModel::BulkAction.new(value: "untrash", label: "Restore", destructive: false)
      elsif status == "spam"
        actions << ListModel::BulkAction.new(value: "unspam", label: "Not spam", destructive: false)
      end
      if %w[trash spam].include?(status)
        actions << ListModel::BulkAction.new(value: "delete", label: "Delete permanently", destructive: true)
      else
        actions << ListModel::BulkAction.new(value: "trash", label: "Move to Trash", destructive: true)
      end
      actions
    end

    def status_or_all = current_status.presence || "all"

    STATUS_TAB = [
      %w[pending Pending], %w[approved Approved], %w[spam Spam], %w[trash Trash]
    ].freeze

    def status_tabs
      counts = Discussion::Comment.group(:status).count
      all_count = counts.reject { |s, _| %w[spam trashed].include?(s) }.values.sum
      cur = current_status
      tabs = [tab("all", "All", all_count, cur.empty? || cur == "all", nil)]
      STATUS_TAB.each do |key, label|
        model_status = key == "trash" ? "trashed" : (key == "pending" ? "pending" : key)
        n = counts[model_status].to_i
        next if n.zero? && !%w[spam trash].include?(key)

        tabs << tab(key, label, n, cur == key, key)
      end
      tabs
    end

    def tab(key, label, count, current, query_value)
      ListModel::Tab.new(
        key: key, count: count,
        label: %(#{label} <span class="count">(#{ActiveSupport::NumberHelper.number_to_delimited(count)})</span>).html_safe,
        query: { "status" => query_value }, current: current
      )
    end

    def row_for(comment)
      ListModel::Row.new(
        id: comment.id,
        cells: {
          "author" => author_cell(comment),
          "comment" => ERB::Util.html_escape(comment.content.to_s.truncate(200)),
          "response" => response_cell(comment),
          "date" => comment.submitted_at&.strftime("%Y/%m/%d at %l:%M %P").to_s.strip
        },
        actions: row_actions(comment)
      )
    end

    def author_cell(comment)
      name = comment.author_name.presence || comment.user&.display_name.presence || "Anonymous"
      out = %(<strong>#{ERB::Util.html_escape(name)}</strong>)
      out += %(<br>#{ERB::Util.html_escape(comment.author_email)}) if comment.author_email.present?
      out.html_safe
    end

    def response_cell(comment)
      post = comment.post
      return "—".html_safe if post.nil?

      %(<a href="/console/posts/#{post.id}/edit">#{ERB::Util.html_escape(post.title.presence || "(no title)")}</a>).html_safe
    end

    # Row actions gated on CommentPolicy — approve/unapprove/spam/trash all map to
    # edit_comment (class-wp-comments-list-table row actions). The exact set shown depends
    # on the comment's current status, as the legacy's handle_row_actions does.
    def row_actions(comment)
      return [] unless can?(Access::CommentPolicy, comment, :edit)

      acts = []
      if comment.approved?
        acts << action_button("Unapprove", "unapprove", comment, key: "unapprove")
      else
        acts << action_button("Approve", "approve", comment, key: "approve")
      end
      acts << action_button("Edit", nil, comment, path: "/console/comments/#{comment.id}/edit", key: "edit")
      acts << action_button("Spam", "spam", comment, destructive: true, key: "spam")
      unless comment.trashed?
        acts << action_button("Trash", "trash", comment, destructive: true, key: "trash")
      end
      acts
    end

    def action_button(label, value, _comment, path: nil, destructive: false, key: nil)
      if path
        ListModel::RowAction.new(label: label, path: path, method: :get, key: key)
      else
        ListModel::RowAction.new(label: label, path: bulk_path, method: :post,
                                 params: { bulk_action: value, confirmed: (destructive ? "0" : nil), "ids[]" => _comment.id }.compact,
                                 destructive: destructive, key: key)
      end
    end

    def run_bulk(action, comments)
      count = 0
      comments.each do |comment|
        next unless can?(Access::CommentPolicy, comment, :edit)

        case action
        when "approve"   then comment.approve!(by: current_actor)
        when "unapprove" then comment.unapprove!(by: current_actor)
        when "spam"      then comment.mark_spam!(by: current_actor)
        when "unspam"    then comment.unapprove!(by: current_actor)
        when "trash"     then comment.trash!(by: current_actor)
        when "untrash"   then comment.unapprove!(by: current_actor)
        when "delete"    then comment.destroy!
        else next
        end
        count += 1
      end
      count
    end

    def confirm_bulk(action, comments)
      comments = comments.select { |c| can?(Access::CommentPolicy, c, :edit) }
      label = { "spam" => "Mark as spam", "trash" => "Move to Trash", "delete" => "Delete permanently" }.fetch(action, action)
      render_bulk_confirmation(
        title: "Comments",
        prompt: "You are about to apply “#{label}” to #{comments.length} comment(s).",
        button: label,
        action: action,
        ids: comments.map(&:id),
        items: comments.map { |c| "#{c.author_name.presence || "Anonymous"}: #{c.content.to_s.truncate(60)}" },
        post_path: bulk_path,
        cancel_path: list_path(status: params[:status])
      )
    end

    def bulk_notice(action, count)
      {
        "approve" => "#{count} comment(s) approved.", "unapprove" => "#{count} comment(s) unapproved.",
        "spam" => "#{count} comment(s) marked as spam.", "unspam" => "#{count} comment(s) restored.",
        "trash" => "#{count} comment(s) moved to the Trash.", "untrash" => "#{count} comment(s) restored.",
        "delete" => "#{count} comment(s) permanently deleted."
      }.fetch(action, "Done.")
    end

    def list_path(status: nil)
      status.present? ? "/console/comments?status=#{status}" : "/console/comments"
    end

    def bulk_path = "/console/comments/bulk"
  end
end
