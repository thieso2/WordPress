# frozen_string_literal: true

module Publishing
  # AD-02: a content subtype. Legacy post_type = 'page'. Hierarchical: slugs are
  # unique within (type, parent), which is why `child-page` may legally appear twice
  # under different parents. BR-MIGRATE-033.
  class Page < Post
    def self.hierarchical? = true
  end
end
