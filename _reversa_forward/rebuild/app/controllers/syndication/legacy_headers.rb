# frozen_string_literal: true

module Syndication
  # The legacy writes each syndication Content-Type through a literal header() call,
  # charset parameter included:
  #
  #   feeds    — wp-includes/feed-rss2.php:8, feed-atom.php:13, feed-rss2-comments.php:8:
  #              feed_content_type($type) . '; charset=' . get_option('blog_charset')
  #              (feed.php:768 maps rss2 → application/rss+xml, atom → application/atom+xml)
  #   sitemaps — wp-includes/sitemaps/class-wp-sitemaps-renderer.php:126,190:
  #              'application/xml; charset=UTF-8'
  #   robots   — wp-includes/functions.php:1715: 'text/plain; charset=utf-8'
  #
  # Rails' ActionDispatch::Response#set_content_type downcases the charset parameter, so
  # `render content_type: "…; charset=UTF-8"` reaches the wire as `utf-8`. The parameter
  # is case-insensitive per RFC 2046 §4.1.2, so no consumer can tell — but the header is
  # part of what the oracle emits, and the cheapest faithful transcription is to write
  # it verbatim once the body has been rendered.
  module LegacyHeaders
    private

    def render_with_legacy_content_type(template, content_type:, formats:)
      render template, formats: formats, layout: false
      response.headers["Content-Type"] = content_type
    end

    # get_option('blog_charset') — the stored option value, 'UTF-8' on a default install.
    def blog_charset
      Configuration::Setting["blog_charset"].presence || "UTF-8"
    end
  end
end
