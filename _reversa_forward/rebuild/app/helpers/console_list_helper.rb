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

  # ── print_column_headers / render_screen_reader_content support ──────────────────

  # WP_Screen::set_screen_reader_content's three headings, rendered by
  # render_screen_reader_content() as `<h2 class="screen-reader-text">` before the status
  # tabs, before the top pager and before the table (class-wp-list-table.php display(),
  # views(), pagination()). The screens whose LITERAL strings are not a plain function of
  # the list title are listed verbatim; every other screen derives them exactly as
  # get_post_type_labels() / get_taxonomy_labels() do — "Posts list", "Posts list
  # navigation", "Filter posts list".
  SCREEN_READER_HEADINGS = {
    # upload.php:406-412
    "console.upload" => {
      views: "Filter media items list", pagination: "Media items list navigation",
      list: "Media items list"
    },
    # export-personal-data.php:92-98
    "console.export-personal-data" => {
      views: "Filter export personal data list", pagination: "Export personal data list navigation",
      list: "Export personal data list"
    },
    # erase-personal-data.php:92-98
    "console.erase-personal-data" => {
      views: "Filter erase personal data list", pagination: "Erase personal data list navigation",
      list: "Erase personal data list"
    },
    # network/sites.php:48-53 sets only the two; heading_views keeps WP_Screen's default
    # (class-wp-screen.php:762 'Filter items list').
    "console.ms-sites" => {
      views: "Filter items list", pagination: "Sites list navigation", list: "Sites list"
    }
  }.freeze

  def list_headings(list)
    SCREEN_READER_HEADINGS.fetch(list.screen) do
      { views: "Filter #{list.title.downcase} list",
        pagination: "#{list.title} list navigation",
        list: "#{list.title} list" }
    end
  end

  # search_box( $text, $input_id ) builds the input id as "$input_id-search-input"; these
  # are the per-screen `$input_id` arguments the legacy passes (edit.php:490 'post',
  # users.php:865 'user', edit-tags.php:374 'tag', edit-comments.php:436 'comment',
  # class-wp-media-list-table.php:347 'media', export/erase-personal-data.php:150
  # 'requests'). A unique id per screen is what keeps its <label for> unambiguous.
  SEARCH_INPUT_BASE = {
    "console.edit" => "post",
    "console.users" => "user",
    "console.edit-tags" => "tag",
    "console.edit-comments" => "comment",
    "console.upload" => "media",
    "console.export-personal-data" => "requests",
    "console.erase-personal-data" => "requests",
    "console.ms-sites" => "site",
    "console.ms-users" => "all-user",
    "console.ms-themes" => "theme"
  }.freeze

  def list_search_input_id(list) = "#{SEARCH_INPUT_BASE.fetch(list.screen, 'post')}-search-input"

  # The id of the GET form that carries the screen's filter controls (search box, the
  # months/category selects and the pager's Current Page input). Those controls sit inside
  # the bulk POST form's tablenav in the legacy because there the whole screen is ONE GET
  # form; here bulk actions POST, so the GET form is a sibling and the controls associate
  # with it through the HTML `form` attribute — same information architecture, valid markup
  # (a nested <form> is dropped by the HTML parser).
  def list_filter_form_id(list) = "#{list.screen.tr('.', '-')}-filter"

  # The hidden inputs that keep the current view when a filter control submits: every list
  # control except the ones with a visible widget in the form.
  def list_filter_carry(list)
    list.query.reject { |k, _| %w[s paged m cat].include?(k.to_s) }
  end

  # print_column_headers' sort state for one column (class-wp-list-table.php:1188-1290).
  # The sorted column carries `aria-sort` and the `sorted <direction>` classes and NO
  # order text; every other sortable column carries `sortable` plus the class for the
  # direction it is NOT about to apply, and the hidden "Sort ascending." announcement.
  def column_sort_state(list, col)
    return nil unless col.sortable?

    if list.orderby.to_s == col.sort_key.to_s
      direction = list.order.to_s.downcase == "asc" ? "asc" : "desc"
      { classes: ["sorted", direction],
        aria_sort: direction == "asc" ? "ascending" : "descending",
        order_text: nil }
    else
      { classes: %w[sortable desc], aria_sort: nil, order_text: "Sort ascending." }
    end
  end
end
