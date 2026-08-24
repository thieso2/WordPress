# frozen_string_literal: true

module Publishing
  # AD-02: a content subtype. Legacy post_type = 'post'. Flat: slugs are unique
  # within (type) alone. BR-MIGRATE-033.
  class Article < Post
    def self.hierarchical? = false
  end
end
