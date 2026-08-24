# frozen_string_literal: true

module Presentation
  # AD-02 split `wp_posts` into one table per aggregate, so the legacy's `post_type`
  # column is gone. The strings it held have NOT gone: they are baked into template slugs
  # (`single-post.html`), into body classes (`single-post`, `post-template-default`) and
  # into the block schemas' `postType` context. This is the one place that translates.
  #
  # It is a lookup, not a method on the record, because it is a fact about the LEGACY
  # naming scheme rather than about the aggregate.
  module PostType
    LEGACY_NAMES = {
      "Publishing::Article" => "post",
      "Publishing::Page" => "page",
    }.freeze

    module_function

    def legacy_name(record)
      return nil if record.nil?

      LEGACY_NAMES.fetch(record.class.name, "post")
    end
  end
end
