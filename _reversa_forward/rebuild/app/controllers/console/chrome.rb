# frozen_string_literal: true

module Console
  # Shared helpers for the settings / dashboard / tools / GDPR / informational screens.
  # These sit ON TOP of Console::BaseController (the reconciled foundation base, tasks
  # #9/#20) and add only what this track needs beyond it — a site-capability GATE that
  # renders the legacy's LITERAL wp_die() string, a save-and-redirect helper keyed on the
  # shared notices partial's flash slot, and `site_url` as a view helper.
  #
  # It deliberately reuses the base's `site_can?` (Access::SitePolicy record-less arm) and
  # `deny!` (renders console/shared/forbidden with the verbatim message at 403) rather
  # than re-implementing them, so this track and the P-LIST/P-EDIT tracks refuse through
  # one door.
  module Chrome
    extend ActiveSupport::Concern

    included do
      helper_method :site_url
    end

    private

    # The `if ( ! current_user_can( $cap ) ) wp_die( __( '…' ) );` guard every options
    # screen opens with (options-general.php:15, options-privacy.php:13). A logged-in
    # actor without the capability sees the legacy's LITERAL refusal at 403; a logged-OUT
    # one never reaches here (auth_redirect ran first). `site_can?`/`deny!` are the base's.
    def require_capability!(capability, message)
      deny!(message) unless site_can?(capability)
    end

    # A successful save: the LITERAL notice into the shared notices partial's `success`
    # slot, then a Turbo-aware 303 (DEV-006). `flash[:success]` is what
    # console/shared/_notices.html.erb renders.
    def redirect_after_submit(target, notice: nil)
      flash[:success] = notice if notice
      redirect_to target, status: :see_other
    end
  end
end
