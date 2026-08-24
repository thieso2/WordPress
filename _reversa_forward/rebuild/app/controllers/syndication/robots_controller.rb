# frozen_string_literal: true

module Syndication
  # do_robots(), wp-includes/functions.php:1713 — "User-agent: *", Disallow/Allow over
  # the admin paths, then the sitemap index line that WP_Sitemaps#add_robots appends
  # for a public site (wp-includes/sitemaps/class-wp-sitemaps.php:259-263).
  #
  # ⚠️ Rails' scaffold public/robots.txt would shadow this route — the static file was
  # removed so the dynamic response (the legacy behaviour) is the one that serves.
  class RobotsController < ApplicationController
    include LegacyHeaders

    # functions.php:1715 — the one legacy header whose charset is already lowercase.
    CONTENT_TYPE = "text/plain; charset=utf-8"

    def show
      render_with_legacy_content_type "syndication/robots/show", formats: [:text],
                                      content_type: CONTENT_TYPE
    end
  end
end
