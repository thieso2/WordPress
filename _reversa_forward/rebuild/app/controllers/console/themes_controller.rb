# frozen_string_literal: true

module Console
  # console.themes — themes.php in modernized mode (P-LIST over Presentation::Theme).
  # DEV-011 resolved: themes YES (data + template files, no hook registry), plugins NO.
  # Columns: screenshot, name, version, active. Row actions: activate, delete. The legacy
  # renders a JS theme-browser; the modernized contract keeps the LITERAL strings and the
  # DATA (which themes exist, which one is active), not the markup.
  #
  # AD-04: index/activate are :policy on `switch_themes`; destroy on `delete_themes` —
  # real capability names through Access::SitePolicy, so owner override 1 (BR-CAP-05)
  # does not soften them; a non-administrator is refused.
  class ThemesController < BaseController
    # GET /console/themes — themes.php:254, title "Themes".
    def index
      @page_title = "Themes"
      @screen = "console.themes"
      @themes = Presentation::Theme.order(active: :desc, slug: :asc).to_a
      @active = @themes.find(&:active?)
    end

    # POST /console/themes/:slug/activate — themes.php `?action=activate`.
    def activate
      theme = Presentation::Theme.find_by(slug: params[:slug])
      return theme_not_found if theme.nil?

      theme.activate!
      flash[:success] = "New theme activated."   # themes.php:285
      redirect_to "/console/themes", status: :see_other
    end

    # DELETE /console/themes/:slug — themes.php `?action=delete`.
    def destroy
      theme = Presentation::Theme.find_by(slug: params[:slug])
      return theme_not_found if theme.nil?

      unless theme.deletable?
        # delete_theme(): the active theme has no Delete link and cannot be removed.
        flash[:error] = "Sorry, you cannot delete the active theme."
        return redirect_to "/console/themes", status: :see_other
      end
      theme.delete!
      flash[:success] = "Theme deleted."   # themes.php:294
      redirect_to "/console/themes", status: :see_other
    end

    private

    # themes.php:27 — "The requested theme does not exist."
    def theme_not_found = not_found!("The requested theme does not exist.")
  end
end
