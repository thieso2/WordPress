# frozen_string_literal: true

# View helpers for the P-LIST partial (console/shared/_list). Pure URL/query assembly —
# no data, no Access; the controller resolved all of that into the Console::ListModel.
module ConsoleListHelper
  # A list URL with a merged query. Blank values are dropped so a cleared filter leaves
  # the URL clean, matching the legacy's add_query_arg / remove_query_arg behaviour.
  def list_url(list, query = {})
    merged = query.transform_keys(&:to_s).reject { |_, v| v.nil? || v == "" }
    return list.base_path if merged.empty?

    "#{list.base_path}?#{merged.to_query}"
  end

  # The query for a sortable column header: keep the current filters, set orderby to the
  # column, and toggle asc/desc if this column is already the sort (WP_List_Table's
  # sortable link). paged resets to 1 on a re-sort, as the legacy does.
  def sort_query(list, sort_key)
    current = list.query.transform_keys(&:to_s)
    next_order = if current["orderby"].to_s == sort_key.to_s && current["order"].to_s.downcase == "asc"
                   "desc"
                 else
                   "asc"
                 end
    current.merge("orderby" => sort_key.to_s, "order" => next_order, "paged" => nil)
  end
end
