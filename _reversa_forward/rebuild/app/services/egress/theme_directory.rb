# frozen_string_literal: true

require "json"

module Egress
  # console.theme-install's remote directory listing — the wordpress.org themes API
  # (themes_api(), wp-admin/includes/theme.php:520) reduced to what the modernized screen
  # renders: name, slug, version, the package install URL, and a screenshot.
  #
  # ⚠️ Every fetch goes through Egress::Client, so SSRF validation is DEFAULT-ON
  # (DEVIATION BR-HTTP-01): a directory URL that names a private range, a userinfo host,
  # a forbidden port or an unresolvable name is refused BEFORE any socket is opened, and
  # the only way past is Egress::UnsafeClient. There is no `wp_remote_get()` here that
  # skips the check.
  class ThemeDirectory
    Entry = Struct.new(:name, :slug, :version, :install_url, :screenshot_url, keyword_init: true)

    class Unavailable < StandardError; end

    def initialize(client: Client.new)
      @client = client
    end

    # Raises Egress::UrlPolicy::Refused for an unsafe/invalid URL (the controller turns
    # that into the legacy "A valid URL was not provided." message), or Unavailable when
    # the directory answers with a non-2xx or unparseable body.
    def list(url)
      response = @client.get(url)
      raise Unavailable, "the theme directory did not answer" unless response.success?

      parse(response.body)
    end

    private

    def parse(body)
      data = JSON.parse(body.to_s)
      themes = data.is_a?(Hash) ? Array(data["themes"]) : Array(data)
      themes.filter_map do |raw|
        next unless raw.is_a?(Hash)

        Entry.new(
          name: raw["name"].to_s, slug: raw["slug"].to_s,
          version: raw["version"].to_s,
          install_url: raw["download_link"].presence || raw["install_url"].to_s,
          screenshot_url: raw["screenshot_url"].presence
        )
      end
    rescue JSON::ParserError
      raise Unavailable, "the theme directory returned an unparseable body"
    end
  end
end
