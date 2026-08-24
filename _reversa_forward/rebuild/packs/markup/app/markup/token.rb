# frozen_string_literal: true

module Markup
  # An element on the stack of open elements or the list of active formatting elements.
  #
  # BR-MIGRATE-223. The `bookmark_name` is the only link back to the source document:
  # the element itself is not stored, only a bookmark naming where its tag was found.
  #
  # Legacy: wp-includes/html-api/class-wp-html-token.php:22.
  class Token
    attr_accessor :bookmark_name, :node_name, :has_self_closing_flag, :namespace,
                  :integration_node_type

    def initialize(bookmark_name, node_name, has_self_closing_flag)
      @bookmark_name = bookmark_name
      @node_name = node_name
      @has_self_closing_flag = has_self_closing_flag
      @namespace = "html"
      @integration_node_type = nil
    end
  end
end
