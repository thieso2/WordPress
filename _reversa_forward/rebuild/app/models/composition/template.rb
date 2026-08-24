# frozen_string_literal: true

module Composition
  # AD-02: split out of wp_posts, where these lived as post_type = 'wp_template',
  # 'wp_template_part' and 'wp_navigation'. `kind` is derived from the source type by
  # the pipeline.
  #
  # `kind: "navigation"` is a `wp_navigation` post: a document of block markup, exactly
  # like a part, that `core/navigation` renders as its fallback when it carries no `ref`
  # (WP_Navigation_Fallback::get_fallback(), class-wp-navigation-fallback.php:70). It is
  # NOT an AGG-Menu — a navigation document's item can be a bare label with neither
  # target nor URL, which `menu_items_one_target` rightly forbids a menu item to be.
  class Template < ApplicationRecord
    self.table_name = "templates"
    KINDS = %w[template part navigation].freeze
    validates :kind, inclusion: { in: KINDS }
    validates :slug, presence: true, uniqueness: { scope: %i[theme_slug kind] }
    validates :theme_slug, presence: true
    scope :parts, -> { where(kind: "part") }
    scope :navigations, -> { where(kind: "navigation") }
  end
end
