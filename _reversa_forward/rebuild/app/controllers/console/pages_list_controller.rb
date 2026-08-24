# frozen_string_literal: true

module Console
  # console.edit (pages variant) — the Pages list (wp-admin/edit.php?post_type=page,
  # WP_Posts_List_Table for a hierarchical type). P-LIST over Publishing::Page, EXACT
  # pagination. Like the Posts list except the STI class, the LITERAL labels ("Pages",
  # "Add Page", "No pages found." and the page/pages bulk nouns), the absence of
  # category/tag columns (class-wp-posts-list-table.php:669), and the HIERARCHICAL default
  # display — pages sort by 'menu_order title' and nest under their parents.
  class PagesListController < PostsListController
    private

    def content_class = Publishing::Page
    def type_labels = { name: "Pages", add: "Add Page", add_path: "/console/posts/new?post_type=page" }
    def taxonomy_columns? = false

    # edit.php:372-381 ($bulk_messages['page']): "%s page moved to the Trash." etc.
    def type_noun_singular = "page"
    def type_noun_plural = "pages"

    # set_hierarchical_display (class-wp-posts-list-table.php:167): the page type's default
    # query orderby is 'menu_order title' ascending, which triggers hierarchical display —
    # _display_rows_hierarchical / get_pages(sort_column=menu_order), :849-855. Each parent
    # is followed by its own descendants (a pre-order walk), the siblings at every level
    # ordered by 'menu_order title'. An explicit ?orderby=title/date still sorts flat.
    def ordered(scope)
      return super if SORTABLE.include?(params[:orderby].to_s)

      ids = hierarchical_id_order(scope)
      return scope if ids.empty?

      # Re-impose the pre-order sequence as the SQL ORDER so EXACT pagination still slices
      # the hierarchy correctly rather than a flat menu_order sort that separates a child
      # from its parent (a child's title can sort ahead of its parent's).
      scope.order(Arel.sql("array_position(ARRAY[#{ids.join(',')}]::bigint[], posts.id)"))
    end

    # The pre-order id sequence over the filtered page set: each level's siblings sorted by
    # 'menu_order title', every parent immediately followed by its descendants. A page
    # whose parent is filtered out of the set is treated as a root.
    def hierarchical_id_order(scope)
      rows = scope.reorder(Arel.sql("posts.menu_order ASC, posts.title ASC, posts.id ASC")).pluck(:id, :parent_id)
      present = rows.map(&:first).to_set
      children = Hash.new { |h, k| h[k] = [] }
      rows.each { |id, parent| children[present.include?(parent) ? parent : nil] << id }

      ordered = []
      walk = lambda do |parent|
        children[parent].each do |id|
          ordered << id
          walk.call(id)
        end
      end
      walk.call(nil)
      ordered
    end

    # get_pages/page_row indentation: a child page's title is prefixed with "&#8212; " per
    # ancestor level so the parent/child structure reads in the flat table.
    def title_cell(post)
      inner = super
      depth = page_depth(post.id)
      return inner if depth.zero?

      (("&#8212; " * depth) + inner).html_safe
    end

    # Absolute nesting level of a page, walking parent_id up through the whole page set.
    def page_depth(id)
      @parent_map ||= content_class.all.pluck(:id, :parent_id).to_h
      depth = 0
      pid = @parent_map[id]
      while pid && @parent_map.key?(pid)
        depth += 1
        pid = @parent_map[pid]
      end
      depth
    end

    def list_path = "/console/pages"
    def bulk_path = "/console/pages/bulk"
  end
end
