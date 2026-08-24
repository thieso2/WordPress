# frozen_string_literal: true

module Console
  # console.tools (link index), console.export (form -> file download) and
  # console.import (target_screens.md:550-552). tools.php gates the index on `edit_posts`;
  # export gates on `export`.
  class ToolsController < BaseController
    include Chrome

    EXPORT_DENIED = "Sorry, you are not allowed to export the content of this site."

    # tools.php:15 requires a logged-in user; the individual tools carry their own caps.
    def index; end

    # export.php:14 `current_user_can( 'export' )`.
    def export
      require_capability!("export", EXPORT_DENIED)
    end

    # export.php's WXR download. A real, valid subset (Platform::Export); the screen
    # names what it omits.
    def export_download
      require_capability!("export", EXPORT_DENIED)
      return if performed?

      xml = Platform::Export.wxr(site_url: site_url, site_name: site_name,
                                 site_description: site_description)
      filename = "#{export_slug}.#{Time.current.strftime("%Y-%m-%d")}.xml"
      send_data xml, filename: filename, type: "text/xml; charset=UTF-8", disposition: "attachment"
    end

    private

    # sanitize_title( get_bloginfo( 'name' ) ) — the export filename stem, export.php:158.
    def export_slug
      slug = CGI.unescapeHTML(Configuration::Setting["blogname"].to_s).downcase
                .gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
      slug.presence || "site"
    end
  end
end
