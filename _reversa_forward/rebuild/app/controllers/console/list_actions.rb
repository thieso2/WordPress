# frozen_string_literal: true

module Console
  # Shared plumbing for the P-LIST instantiations (target_screens.md § Part 5): pagination
  # (Retrieval::Page, exact or estimated per DEV-003), bulk-selection parsing, and the
  # DEV-004 destructive-action confirmation step. Owned by the list track; mixed into each
  # list controller so the six screens share one bulk code path and one confirmation.
  #
  # This is a surface concern — it reaches Access only through the including controller's
  # BaseController helpers (site_can?, can?), never directly.
  module ListActions
    extend ActiveSupport::Concern

    # per_page is a per-user screen option in the legacy (wp_user_settings). Preserved as a
    # Configuration value in the full spec; the constant is the default page size until the
    # per-user preference is wired. class-wp-screen defaults edit.php to 20.
    DEFAULT_PER_PAGE = 20

    included do
      helper ConsoleListHelper
    end

    private

    # BR-MIGRATE-047 sibling: a page of `relation` with the screen's counting strategy.
    # `relation` already carries its ORDER BY so sortable columns work.
    def list_page(relation, strategy: :exact, per_page: DEFAULT_PER_PAGE)
      Retrieval::Page.new(relation, page: current_page_number, per_page: per_page, strategy: strategy)
    end

    def current_page_number = [params[:paged].to_i, 1].max

    # The selected ids (`$_REQUEST['ids']` / the checkbox column). Non-numeric and zero
    # entries are dropped, as the legacy's `array_map( 'absint', … )` does.
    def bulk_ids
      Array(params[:ids]).map { |id| id.to_s.to_i }.reject(&:zero?)
    end

    def bulk_action_name = params[:bulk_action].to_s

    # The legacy select's "-1" sentinel means "no action chosen".
    def bulk_action_chosen? = bulk_action_name.present? && bulk_action_name != "-1"

    def bulk_confirmed? = params[:confirmed].to_s == "1"

    # DEV-004: render the interstitial instead of running the destructive action. The
    # caller supplies the LITERAL prompt/button and the item descriptions (the records'
    # own titles), and the paths to re-post to and to cancel back to.
    # rubocop:disable Metrics/ParameterLists
    def render_bulk_confirmation(title:, prompt:, button:, action:, ids:, items:, post_path:, cancel_path:)
      @confirm_title = title
      @confirm_prompt = prompt
      @confirm_button = button
      @confirm_action = action
      @confirm_ids = ids
      @confirm_items = items
      @confirm_path = post_path
      @confirm_cancel_path = cancel_path
      render "console/shared/confirm", status: :ok
    end
    # rubocop:enable Metrics/ParameterLists

    # The query hash the P-LIST partial threads through every self-link (tabs, sort
    # headers, pager). Only the whitelisted list controls travel; nothing else from the
    # URL is echoed back into a link.
    def list_query
      params.permit(:status, :s, :orderby, :order, :paged, :taxonomy, :role).to_h.reject { |_, v| v.blank? }
    end

    # WP_List_Table sort inputs, normalized. orderby is validated against the screen's
    # sortable keys by the caller; order is asc/desc only.
    def list_order = params[:order].to_s.downcase == "asc" ? "asc" : "desc"

    def list_orderby(allowed, default:)
      key = params[:orderby].to_s
      allowed.include?(key) ? key : default
    end
  end
end
