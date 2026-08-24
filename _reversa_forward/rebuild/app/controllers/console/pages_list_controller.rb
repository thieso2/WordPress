# frozen_string_literal: true

module Console
  # console.edit (pages variant) — the Pages list (wp-admin/edit.php?post_type=page,
  # WP_Posts_List_Table for a hierarchical type). P-LIST over Publishing::Page, EXACT
  # pagination. Identical to the Posts list except the STI class, the LITERAL labels
  # ("Pages", "Add Page", "No pages found."), and the absence of category/tag columns —
  # the page type registers no taxonomies (class-wp-posts-list-table.php:669).
  class PagesListController < PostsListController
    private

    def content_class = Publishing::Page
    def type_labels = { name: "Pages", add: "Add Page", add_path: "/console/posts/new?post_type=page" }
    def taxonomy_columns? = false

    def list_path = "/console/pages"
    def bulk_path = "/console/pages/bulk"
  end
end
