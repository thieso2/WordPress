# frozen_string_literal: true

module Console
  # console.about / .credits / .freedoms / .contribute / .privacy (target_screens.md:559).
  # In the legacy these described WordPress the PROJECT. DEV-009 resolved them: the routes
  # are retained, carrying the REBUILD's own content. The WordPress-project text is not
  # migrated — reproducing it would be a false claim about what this system is.
  #
  # ⚠️ The one place DEV-009 is a *scalpel*, not a blanket. Two kinds of string survive:
  #   · SCREEN FURNITURE that is not project identity — the page titles ("About",
  #     "Credits", "Freedoms", "Get Involved"), the secondary tab labels
  #     (about.php:52-58), the nav's aria-label ("Secondary menu") and about.php's
  #     "Go to Dashboard &rarr; Home" return link. Verbatim.
  #   · The FOUR FREEDOMS themselves (freedoms.php:62-83). Those four sentences are a
  #     statement of the GPL's freedoms, not WordPress branding, so the headings and the
  #     statements are carried across verbatim; only the WordPress-specific framing around
  #     them (the wordpress.org license link, the Foundation trademark paragraph, the
  #     plugin/theme-directory paragraph) is dropped.
  # Everything else on these four screens is authored HERE, about THIS build, and must be
  # true of it. credits.php fetches its contributor list from wordpress.org over the
  # network (wp_credits() → api.wordpress.org); this build makes no such call and does not
  # invent one — see console/info/credits.html.erb.
  #
  # Gate: `:authenticated`. about.php et al. sit under the dashboard and require only a
  # logged-in reader (the `read` capability every role holds); auth_redirect is the whole
  # gate, so the declaration is `:authenticated` and BR-CAP-05 would allow it anyway.
  class InfoController < BaseController
    include Chrome

    PAGES = %w[about credits freedoms contribute privacy].freeze

    # credits.php's `External Libraries` group, told the truth: the DIRECT runtime
    # dependencies this application declares in its Gemfile. The version is not written
    # down here — it is read from the gem actually loaded into this process, so the page
    # cannot drift into claiming a version that is not running.
    RUNTIME_LIBRARIES = %w[
      rails propshaft pg puma importmap-rails turbo-rails stimulus-rails
      solid_cache solid_queue solid_cable bootsnap thruster image_processing
      bcrypt nokogiri
    ].freeze

    helper_method :info_tab_path

    def show
      @page = params[:page].to_s
      @page = "about" unless PAGES.include?(@page)
      @screen = "console.#{@page}"

      if @page == "about"
        @runtime = runtime_facts
        # BR-CAP-05: the CONTROLLER asks Access, never the view. site-health-info gates on
        # `install_plugins`, so the pointer to it is only offered to someone who may follow
        # it — this screen itself needs no more than `read`.
        @can_view_site_health = site_can?("install_plugins")
      end
      @libraries = runtime_libraries if @page == "credits"

      render "console/info/#{@page}"
    end

    private

    # The tab bar's targets. `contribute` is reached at /console/get-involved (the legacy
    # screen is titled "Get Involved"; the file name is the thing that says "contribute").
    # That route is the integrator's to wire, so until the named helper exists the tab
    # falls back to the slug route that is already in config/routes.rb — the link is never
    # dead in either state.
    def info_tab_path(page)
      return "/console/#{page}" unless page == "contribute"

      helpers = Rails.application.routes.url_helpers
      if helpers.respond_to?(:console_get_involved_path)
        helpers.console_get_involved_path
      else
        "/console/contribute"
      end
    end

    # about.php prints a version number. This build's honest equivalent is what is
    # actually running — read from the process and the live connection, never asserted.
    def runtime_facts
      {
        "Ruby" => RUBY_VERSION,
        "Rails" => Rails.version,
        "Database" => database_fact,
        "Environment" => Rails.env
      }.compact
    end

    def database_fact
      connection = ActiveRecord::Base.connection
      name = connection.adapter_name.to_s
      version = connection.select_value("SHOW server_version").to_s.split(" ").first
      version.present? ? "#{name} #{version}" : name.presence
    rescue StandardError
      nil
    end

    def runtime_libraries
      RUNTIME_LIBRARIES.filter_map do |name|
        spec = Gem.loaded_specs[name]
        [name, spec.version.to_s] if spec
      end
    end
  end
end
