# frozen_string_literal: true

module Console
  # console.export-personal-data + console.erase-personal-data (target_screens.md:555-556,
  # GDPR). A P-LIST over Identity::DataRequest, one screen per kind. export-personal-data
  # gates on `export_others_personal_data`, erase on `erase_others_personal_data`; both
  # map to `manage_options` on a single site (Access::SitePolicy, capabilities.php:795).
  #
  # The columns are WP_Privacy_Requests_Table's, LITERAL: Requester, Status, Requested,
  # Next steps (class-wp-privacy-requests-table.php:43-46). Rendered through the shared
  # P-LIST (Console::ListModel + console/shared/_list): the cb column, the three core bulk
  # actions (Resend confirmation requests / Mark requests as completed / Delete requests,
  # get_bulk_actions :214-220), the get_views() status filter tabs (:151-205) and the
  # Search Requests box (export-personal-data.php:147-154) all come from that partial. The
  # "Add … Request" form issues a confirmation request, or — when the confirmation-email
  # box is unchecked — creates the request directly `confirmed` (privacy-tools.php:116-118).
  class DataRequestsController < BaseController
    include Chrome
    include Console::ListActions

    EXPORT_DENIED = "Sorry, you are not allowed to export personal data on this site."
    ERASE_DENIED  = "Sorry, you are not allowed to erase personal data on this site."

    # class-wp-privacy-requests-table.php status labels (get_request_data / STATUS map).
    STATUS_LABELS = {
      "pending" => "Pending", "confirmed" => "Confirmed",
      "failed" => "Failed", "completed" => "Completed",
    }.freeze

    # _wp_privacy_statuses() order (wp-includes/post.php:1399-1405), keyed to the model's
    # prefix-stripped status names and the register_post_status label_count markup
    # (post.php:767-820) — LITERAL, already interpolated with the count.
    STATUS_ORDER = %w[pending confirmed failed completed].freeze

    before_action :guard

    def export
      @kind = "export"
      render_index
    end

    def erase
      @kind = "erasure"
      render_index
    end

    # export-personal-data.php:114 "Add Data Export Request" /
    # erase-personal-data.php:114 "Add Data Erasure Request": create a request for an
    # email. With the "Send … confirmation email" box checked (default) a pending request
    # is created and a confirmation link issued; with it UNCHECKED the request is created
    # directly in `confirmed` status (privacy-tools.php:116-118).
    def create
      kind = params[:kind].to_s.presence_in(Identity::DataRequest::KINDS) || kind_from_request
      # export-personal-data.php:117 — the field accepts a USERNAME OR an email, and
      # _wp_privacy_resolve_request_user resolves a username to its account email
      # (privacy-tools.php). Not narrowed to an email input.
      identifier = params[:username_or_email].to_s.strip
      by_login = identifier.empty? ? nil : Identity::User.where("login = ? OR email = ?", identifier, identifier).first
      email = by_login ? by_login.email.to_s : identifier

      if identifier.empty? || (!identifier.include?("@") && by_login.nil?)
        # privacy-tools.php:135, verbatim.
        redirect_after_submit(path_for(kind), notice: "Unable to add this request. A valid email address or username must be supplied.")
        return
      end

      # privacy-tools.php:116-118 — the box is a checkbox named `send_confirmation_email`;
      # when it is not posted the status is created `confirmed` instead of `pending`.
      send_email = params[:send_confirmation_email].present?
      status = send_email ? "pending" : "confirmed"

      request = Identity::DataRequest.new(kind: kind, email: email, status: status,
                                          user: by_login || Identity::User.find_by(email: email))
      request.confirmed_at = Time.current unless send_email

      unless request.save
        redirect_after_submit(path_for(kind), notice: "Unable to initiate confirmation request.")
        return
      end

      if send_email
        request.issue_confirm_key!
        # privacy-tools.php:169-170, verbatim.
        redirect_after_submit(path_for(kind), notice: "Confirmation request initiated successfully.")
      else
        # privacy-tools.php:172-173, verbatim.
        redirect_after_submit(path_for(kind), notice: "Request added successfully.")
      end
    end

    # POST /console/tools/{export,erase}-personal-data/bulk — the three core, non-plugin
    # lifecycle bulk actions (class-wp-privacy-requests-table.php:214-220, :228-358). The
    # single-row "Complete request" / "Remove request" links reuse this endpoint with one
    # id, as the legacy's row actions do (action=complete / action=delete).
    def bulk
      @kind = kind_from_request
      action = bulk_action_name
      unless bulk_action_chosen? && bulk_ids.any?
        redirect_to path_for(@kind), status: :see_other
        return
      end

      requests = Identity::DataRequest.where(kind: @kind, id: bulk_ids).to_a

      if action == "delete" && !bulk_confirmed?
        confirm_delete(requests)
        return
      end

      count = run_bulk(action, requests)
      redirect_after_submit(path_for(@kind), notice: bulk_notice(action, count))
    end

    private

    def render_index
      @requests_table = build_list
      render "console/data_requests/index"
    end

    def guard
      cap, msg =
        if erase_screen?
          ["erase_others_personal_data", ERASE_DENIED]
        else
          ["export_others_personal_data", EXPORT_DENIED]
        end
      require_capability!(cap, msg)
    end

    # Which screen this request is for — GET export/erase name it directly; create/bulk
    # derive it from the request path, which encodes the kind (…/erase-personal-data…).
    def erase_screen?
      return @kind == "erasure" if @kind
      return true if action_name == "erase"

      kind_from_request == "erasure"
    end

    # The screen kind, read from the path so it survives a form (the confirm interstitial)
    # that does not re-post `kind`. /console/tools/erase-personal-data[...] → erasure.
    def kind_from_request
      request.path.include?("erase-personal-data") ? "erasure" : "export"
    end

    # ── P-LIST assembly (Console::ListModel → console/shared/_list) ──────────────────

    def build_list
      export = @kind == "export"
      relation = filtered(Identity::DataRequest.where(kind: @kind))
      page = list_page(relation, strategy: :exact)

      ListModel.new(
        screen: export ? "console.export-personal-data" : "console.erase-personal-data",
        title: export ? "Export Personal Data" : "Erase Personal Data",
        tabs: status_tabs,
        filters: [ListModel::Filter.new(kind: :search, name: "s", label: "Search Requests", value: params[:s].to_s)],
        bulk_actions: bulk_actions,
        columns: columns,
        rows: page.records.map { |req| row_for(req) },
        page: page,
        strategy: :exact,
        base_path: path_for(@kind),
        bulk_path: bulk_path_for(@kind),
        empty_message: "No items found.",
        query: list_query,
        order: list_order,
        orderby: list_orderby(%w[requester requested], default: "requested"),
        search_query: params[:s].presence
      )
    end

    # prepare_items (class-wp-privacy-requests-table.php:367-412): filter-status, search,
    # orderby/order. filter-status arrives as ?status= so it threads through the shared
    # partial's permitted list-query params (pagination, sort, search hidden fields).
    def filtered(scope)
      status = params[:status].to_s
      scope = scope.where(status: status) if Identity::DataRequest::STATUSES.include?(status)
      if (term = params[:s].to_s.strip).present?
        scope = scope.where("email ILIKE ?", "%#{term}%")
      end
      scope.order(order_clause)
    end

    def order_clause
      col = params[:orderby].to_s == "requester" ? "email" : "created_at"
      dir = list_order == "asc" ? "asc" : "desc"
      Arel.sql("#{col} #{dir}, id #{dir}")
    end

    # get_columns() :39-47 — LITERAL. cb is supplied by the shared partial (bulk_actions?).
    def columns
      [
        ListModel::Column.new(key: "email", label: "Requester", sortable: true, sort_key: "requester"),
        ListModel::Column.new(key: "status", label: "Status", sortable: false),
        ListModel::Column.new(key: "created_timestamp", label: "Requested", sortable: true, sort_key: "requested"),
        ListModel::Column.new(key: "next_steps", label: "Next steps", sortable: false)
      ]
    end

    # get_bulk_actions() :214-220 — LITERAL. Delete is destructive (DEV-004 confirmation).
    def bulk_actions
      [
        ListModel::BulkAction.new(value: "resend", label: "Resend confirmation requests", destructive: false),
        ListModel::BulkAction.new(value: "complete", label: "Mark requests as completed", destructive: false),
        ListModel::BulkAction.new(value: "delete", label: "Delete requests", destructive: true)
      ]
    end

    # get_views() :151-205 — All + one tab per status that has a request, each label the
    # register_post_status label_count markup already interpolated with the count.
    def status_tabs
      counts = Identity::DataRequest.where(kind: @kind).group(:status).count
      total = counts.values.sum
      cur = params[:status].to_s
      tabs = [tab("all", "All", total, cur.empty?, nil)]
      STATUS_ORDER.each do |status|
        n = counts[status].to_i
        next if n.zero?

        tabs << tab(status, STATUS_LABELS.fetch(status), n, cur == status, status)
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

    def row_for(req)
      ListModel::Row.new(
        id: req.id,
        cells: {
          "email" => email_cell(req),
          "status" => ERB::Util.html_escape(status_label(req.status)),
          "created_timestamp" => ERB::Util.html_escape(req.created_at&.strftime("%Y/%m/%d").to_s),
          "next_steps" => next_steps_cell(req)
        },
        actions: row_actions(req)
      )
    end

    # column_email :46-102 / :100 — a mailto link on the email address.
    def email_cell(req)
      %(<a href="mailto:#{ERB::Util.html_escape(req.email)}">#{ERB::Util.html_escape(req.email)}</a>).html_safe
    end

    # column_email's "Complete request" row action (:70-102 / removal :75-108): shown for
    # any non-completed request, marks it completed. Reuses the bulk endpoint with one id.
    def row_actions(req)
      return [] if req.status == "completed"

      [ListModel::RowAction.new(label: "Complete request", path: bulk_path_for(@kind), method: :post,
                                params: { bulk_action: "complete", confirmed: "1", "ids[]" => req.id },
                                destructive: false, key: "complete-request")]
    end

    # column_next_steps :104-160 (export) / :110-168 (removal) — the per-status label.
    # pending → Waiting for confirmation; confirmed → Send export link / Erase personal
    # data; failed → Retry; completed → the "Remove request" link (deletes the request).
    def next_steps_cell(req)
      case req.status
      when "pending"   then "Waiting for confirmation"
      when "confirmed" then @kind == "export" ? "Send export link" : "Erase personal data"
      when "failed"    then "Retry"
      when "completed" then remove_request_control(req)
      else ""
      end
    end

    # column_next_steps request-completed (:155-160 / :161-167): a link that deletes the
    # request. A POST to the bulk endpoint (delete), so it goes through the same lifecycle
    # as the "Delete requests" bulk action; confirmed=1 so the single link acts at once,
    # as the legacy's nonce link does (no interstitial).
    def remove_request_control(req)
      token = ERB::Util.html_escape(form_authenticity_token)
      <<~HTML.html_safe
        <form method="post" action="#{bulk_path_for(@kind)}" class="button-link-form" data-turbo="false" style="display:inline;margin:0;">
          <input type="hidden" name="authenticity_token" value="#{token}">
          <input type="hidden" name="kind" value="#{@kind}">
          <input type="hidden" name="bulk_action" value="delete">
          <input type="hidden" name="confirmed" value="1">
          <input type="hidden" name="ids[]" value="#{req.id}">
          <button type="submit" class="button-link">Remove request</button>
        </form>
      HTML
    end

    def run_bulk(action, requests)
      count = 0
      requests.each do |req|
        case action
        when "resend"
          req.issue_confirm_key!
        when "complete"
          req.update!(status: "completed", completed_at: Time.current)
        when "delete"
          req.destroy!
        else next
        end
        count += 1
      end
      count
    end

    def confirm_delete(requests)
      render_bulk_confirmation(
        title: @kind == "export" ? "Export Personal Data" : "Erase Personal Data",
        prompt: "You are about to apply “Delete requests” to #{requests.length} request(s).",
        button: "Delete requests",
        action: "delete",
        ids: requests.map(&:id),
        items: requests.map(&:email),
        post_path: bulk_path_for(@kind),
        cancel_path: path_for(@kind)
      )
    end

    # class-wp-privacy-requests-table.php:246-357 success strings (singular/plural).
    def bulk_notice(action, count)
      case action
      when "resend"
        count == 1 ? "1 confirmation request re-sent successfully." : "#{count} confirmation requests re-sent successfully."
      when "complete"
        count == 1 ? "1 request marked as complete." : "#{count} requests marked as complete."
      when "delete"
        count == 1 ? "1 request deleted successfully." : "#{count} requests deleted successfully."
      else "Done."
      end
    end

    def path_for(kind)
      kind == "erasure" ? "/console/tools/erase-personal-data" : "/console/tools/export-personal-data"
    end
    helper_method :path_for

    def bulk_path_for(kind)
      "#{path_for(kind)}/bulk"
    end

    def status_label(status) = STATUS_LABELS.fetch(status.to_s, status.to_s.capitalize)
    helper_method :status_label
  end
end
