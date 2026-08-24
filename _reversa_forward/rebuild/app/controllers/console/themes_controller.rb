# frozen_string_literal: true

module Console
  # console.themes — themes.php in modernized mode (P-LIST over Presentation::Theme).
  # DEV-011 resolved: themes YES (data + template files, no hook registry), plugins NO.
  # Columns: screenshot, name, version, active. Row actions: activate, delete, and the
  # per-theme auto-update toggle. The legacy renders a JS theme-browser; the modernized
  # contract keeps the LITERAL strings and the DATA (which themes exist, which one is
  # active, which have auto-updates enabled), not the markup.
  #
  # AD-04: index/activate are :policy on `switch_themes`; destroy on `delete_themes`; the
  # auto-update toggle on `update_themes` — real capability names through Access::SitePolicy,
  # so owner override 1 (BR-CAP-05) does not soften them; a non-administrator is refused.
  class ThemesController < BaseController
    # themes.php stores per-theme auto-update opt-in in the `auto_update_themes` site
    # option (a list of stylesheet slugs). AD-01 removes WP-Cron's executor, but the
    # SCREEN's behaviour is only this preference write plus its notice (themes.php:83-124);
    # that is reproduced faithfully here over Configuration::Setting.
    AUTO_UPDATE_OPTION = "auto_update_themes"

    # GET /console/themes — themes.php:254, title "Themes".
    def index
      @page_title = "Themes"
      @screen = "console.themes"
      @themes = Presentation::Theme.order(active: :desc, slug: :asc).to_a
      @active = @themes.find(&:active?)
      @auto_updates = auto_update_slugs
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
        # themes.php:76-82 — the active theme cannot be deleted; the legacy redirects to
        # `delete-active-child=true`, whose notice (themes.php:304) is the verbatim string.
        flash[:error] = "You cannot delete a theme while it has an active child theme."
        return redirect_to "/console/themes", status: :see_other
      end
      theme.delete!
      flash[:success] = "Theme deleted."   # themes.php:294
      redirect_to "/console/themes", status: :see_other
    end

    # POST /console/themes/:slug/enable-auto-update — themes.php:84 `?action=enable-auto-update`.
    def enable_auto_update
      theme = Presentation::Theme.find_by(slug: params[:slug])
      return theme_not_found if theme.nil?

      set_auto_update_slugs(auto_update_slugs | [theme.slug])
      flash[:success] = "Theme will be auto-updated."   # themes.php:329
      redirect_to "/console/themes", status: :see_other
    end

    # POST /console/themes/:slug/disable-auto-update — themes.php:104 `?action=disable-auto-update`.
    def disable_auto_update
      theme = Presentation::Theme.find_by(slug: params[:slug])
      return theme_not_found if theme.nil?

      set_auto_update_slugs(auto_update_slugs - [theme.slug])
      flash[:success] = "Theme will no longer be auto-updated."   # themes.php:338
      redirect_to "/console/themes", status: :see_other
    end

    private

    # themes.php:27 — "The requested theme does not exist."
    def theme_not_found = not_found!("The requested theme does not exist.")

    def auto_update_slugs
      stored = Configuration::Setting[AUTO_UPDATE_OPTION]
      stored.is_a?(Array) ? stored : []
    end

    # themes.php:95/114 — the list is de-duplicated and intersected with the themes that
    # still exist, so a deleted theme never lingers in the option.
    def set_auto_update_slugs(slugs)
      existing = Presentation::Theme.pluck(:slug)
      Configuration::Setting.set(AUTO_UPDATE_OPTION, (slugs & existing).uniq)
    end
  end
end
