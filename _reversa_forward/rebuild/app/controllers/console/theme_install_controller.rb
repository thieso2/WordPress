# frozen_string_literal: true

module Console
  # console.theme-install — theme-install.php (`/console/themes/new`) in modernized mode.
  # Title "Add Themes", the "Install" action, "Version: %s". A remote directory listing
  # through Egress, with SSRF validation DEFAULT-ON (DEVIATION BR-HTTP-01): a directory
  # or package URL that fails Egress::UrlPolicy is refused before any socket is opened,
  # and the refusal carries the legacy's "A valid URL was not provided." message.
  #
  # AD-04: :policy on `install_themes` (theme-install.php:15) — a real capability, so an
  # actor without it is refused (owner override 1 does not apply to a named primitive).
  class ThemeInstallController < BaseController
    # GET /console/themes/new
    def new
      @page_title = "Add Themes"
      @screen = "console.theme-install"
      @themes = []
      @directory_url = params[:directory].presence || directory_url
      @directory_error = nil
      return if @directory_url.blank?

      @themes = Egress::ThemeDirectory.new(client: egress_client).list(@directory_url)
    rescue Egress::UrlPolicy::Refused => e
      @directory_error = e.message   # "A valid URL was not provided."
    rescue Egress::ThemeDirectory::Unavailable
      @directory_error = "An unexpected error occurred. Something may be wrong with the theme directory."
    end

    # POST /console/themes — install the package named by `install_url`.
    def create
      theme = Egress::ThemeInstaller.new(client: egress_client).install(params[:install_url].to_s)
      flash[:success] = "Theme installed successfully."   # class-theme-upgrader.php:82
      redirect_to "/console/themes", status: :see_other
    rescue Egress::UrlPolicy::Refused,
           Egress::Package::Rejected,
           Egress::ThemeInstaller::InvalidPackage => e
      flash[:error] = e.message
      redirect_to "/console/themes/new", status: :see_other
    end

    private

    # The directory the screen browses — configuration, not a hardcoded host, so a test
    # can point it at a stubbed origin. Empty by default: the screen then renders its idle
    # state and asks for a URL.
    def directory_url = Configuration::Setting["theme_directory_url"].presence

    # One door. Overridable in a test to supply a stubbed transport; the parity suite
    # NEVER makes a real external call.
    def egress_client = Egress::Client.new
  end
end
