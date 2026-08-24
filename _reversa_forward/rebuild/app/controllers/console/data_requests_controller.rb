# frozen_string_literal: true

module Console
  # console.export-personal-data + console.erase-personal-data (target_screens.md:555-556,
  # GDPR). A P-LIST over Identity::DataRequest, one screen per kind. export-personal-data
  # gates on `export_others_personal_data`, erase on `erase_others_personal_data`; both
  # map to `manage_options` on a single site (Access::SitePolicy, capabilities.php:795).
  #
  # The columns are WP_Privacy_Requests_Table's, LITERAL: Requester, Status, Requested,
  # Next steps (class-wp-privacy-requests-table.php:43-46). The "Add … Request" form
  # issues a confirmation request (Identity::DataRequest#issue_confirm_key!), the model's
  # existing command.
  class DataRequestsController < BaseController
    include Chrome

    EXPORT_DENIED = "Sorry, you are not allowed to export personal data on this site."
    ERASE_DENIED  = "Sorry, you are not allowed to erase personal data on this site."

    # class-wp-privacy-requests-table.php status labels (get_request_data / STATUS map).
    STATUS_LABELS = {
      "pending" => "Pending", "confirmed" => "Confirmed",
      "failed" => "Failed", "completed" => "Completed",
    }.freeze

    before_action :guard

    def export
      @kind = "export"
      @requests = requests_for("export")
      render "console/data_requests/index"
    end

    def erase
      @kind = "erasure"
      @requests = requests_for("erasure")
      render "console/data_requests/index"
    end

    # export-personal-data.php:114 "Add Data Export Request" /
    # erase-personal-data.php:114 "Add Data Erasure Request": create a request for an
    # email and send the confirmation link.
    def create
      kind = params[:kind].to_s
      kind = "export" unless Identity::DataRequest::KINDS.include?(kind)
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

      request = Identity::DataRequest.new(kind: kind, email: email, status: "pending",
                                          user: by_login || Identity::User.find_by(email: email))
      if request.save
        request.issue_confirm_key!
        redirect_after_submit(path_for(kind), notice: "Confirmation request initiated successfully.")
      else
        redirect_after_submit(path_for(kind), notice: "Unable to initiate confirmation request.")
      end
    end

    private

    def guard
      if action_name == "erase"
        require_capability!("erase_others_personal_data", ERASE_DENIED)
      elsif action_name == "export"
        require_capability!("export_others_personal_data", EXPORT_DENIED)
      else
        kind = params[:kind].to_s == "erasure" ? :erase : :export
        cap = kind == :erase ? "erase_others_personal_data" : "export_others_personal_data"
        msg = kind == :erase ? ERASE_DENIED : EXPORT_DENIED
        require_capability!(cap, msg)
      end
    end

    def requests_for(kind)
      Identity::DataRequest.where(kind: kind).order(created_at: :desc).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def path_for(kind)
      kind == "erasure" ? "/console/tools/erase-personal-data" : "/console/tools/export-personal-data"
    end
    helper_method :path_for

    def status_label(status) = STATUS_LABELS.fetch(status.to_s, status.to_s.capitalize)
    helper_method :status_label
  end
end
