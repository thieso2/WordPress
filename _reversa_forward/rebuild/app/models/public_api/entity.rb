# frozen_string_literal: true

module PublicApi
  # Shared helpers for the entity serialisers: the three `wp-includes/formatting.php`
  # + block-rendering functions the REST `prepare_item_for_response` methods lean on,
  # reached through the SAME ports the front-end renders with, so a field here is
  # byte-identical to the same value on a golden page.
  module Entity
    module_function

    def text = Composition::Renderers::PostBlocks::Text
    def links = Composition::Renderers::PostBlocks::Links
    def site = Composition::Renderers::PostBlocks::Site

    # mysql_to_rfc3339(), wp-includes/rest-api.php — `Y-m-d\TH:i:s`, no zone suffix. AD-07
    # keeps only the GMT instant; this corpus's oracle rows have post_date == post_date_gmt
    # (the seed stored them equal), so the local and GMT fields print the same instant.
    def iso(instant) = instant&.utc&.strftime("%Y-%m-%dT%H:%M:%S")

    # sanitize_html_class(), wp-includes/formatting.php:2340 — used by get_post_class().
    def sanitize_html_class(value, fallback = "")
      sanitized = value.to_s.gsub(/%[a-f0-9]{2}/i, "").gsub(/[^A-Za-z0-9_-]/, "")
      sanitized.empty? ? fallback.to_s : sanitized
    end

    # The `curies` block every collection/item `_links` ends with (rest_get_server()'s
    # add_link default, class-wp-rest-server.php).
    def curies
      [{ name: "wp", href: "https://api.w.org/{rel}", templated: true }]
    end
  end
end
