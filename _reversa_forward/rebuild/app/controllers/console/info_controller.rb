# frozen_string_literal: true

module Console
  # console.about / .credits / .freedoms / .contribute / .privacy (target_screens.md:559).
  # In the legacy these described WordPress the PROJECT. DEV-009 resolved them: the routes
  # are retained, carrying the REBUILD's own content. The WordPress-project text is not
  # migrated — reproducing it would be a false claim about what this system is.
  #
  # Gate: `:authenticated`. about.php et al. sit under the dashboard and require only a
  # logged-in reader (the `read` capability every role holds); auth_redirect is the whole
  # gate, so the declaration is `:authenticated` and BR-CAP-05 would allow it anyway.
  class InfoController < BaseController
    include Chrome

    PAGES = %w[about credits freedoms contribute privacy].freeze

    def show
      @page = params[:page].to_s
      @page = "about" unless PAGES.include?(@page)
      render "console/info/#{@page}"
    end
  end
end
