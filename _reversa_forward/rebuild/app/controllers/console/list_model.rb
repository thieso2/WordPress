# frozen_string_literal: true

module Console
  # P-LIST as one reusable contract (target_screens.md § Part 1, spec.pattern: P-LIST).
  #
  # A data holder, deliberately: the controller — the only layer allowed to touch Access
  # — resolves every policy question (which bulk actions, which row actions, which status
  # tabs) and hands the answers here as plain values. The shared partial
  # (console/shared/_list) renders this and nothing else, so the panel structure lives in
  # exactly one place and every P-LIST instantiation is consistent by construction rather
  # than by 40 near-identical views (target_screens.md's own argument for the pattern).
  #
  # Every LITERAL-marked string — the title, the column headers, the bulk-action labels,
  # the status-tab labels, the empty-state — is passed in verbatim from the legacy; this
  # class never invents copy.
  class ListModel
    # A sortable, labelled column. `label` is LITERAL (may be HTML-safe markup, e.g. the
    # comments bubble). `sort_key` drives the ?orderby link when `sortable`.
    Column = Struct.new(:key, :label, :sortable, :sort_key, keyword_init: true) do
      def sortable? = sortable
    end

    # A status filter link — the legacy "All | Published | Draft | Trash" family
    # (WP_List_Table::get_views). `label` is the LITERAL nooped-plural markup already
    # interpolated with the count. `current` marks the active tab.
    Tab = Struct.new(:key, :label, :count, :query, :current, keyword_init: true) do
      def current? = current
    end

    # A bulk action. `label` is LITERAL. `destructive` triggers the DEV-004 confirmation
    # step before it runs.
    BulkAction = Struct.new(:value, :label, :destructive, keyword_init: true) do
      def destructive? = destructive
    end

    # One row. `cells` maps a column key to its (already-escaped or html_safe) content.
    # `actions` are the row actions the controller resolved from Access::*Policy for THIS
    # record — a missing policy would render them all (BR-CAP-05), which is why the
    # controller, not the view, decides.
    Row = Struct.new(:id, :cells, :actions, :selectable, keyword_init: true) do
      def selectable? = selectable.nil? ? true : selectable
      def cell(key) = cells[key]
    end

    # A row action. A GET link (edit, view) sets `path`/`method: :get`; a state-changing
    # action (trash, approve, spam…) reuses the bulk endpoint with `method: :post` and
    # `params` naming the single id, so single-row and bulk actions share one code path
    # and one DEV-004 confirmation. `key` groups the action for row-action CSS colouring.
    RowAction = Struct.new(:label, :path, :method, :params, :destructive, :key, keyword_init: true) do
      def destructive? = destructive
      def get? = (method || :get).to_sym == :get
      def http_method = (method || :get).to_sym
      def parameters = params || {}
    end

    # A filter control on the FilterBar. Only `:search` is used by the core screens; the
    # struct keeps the door open for the select filters the legacy months/category
    # dropdowns become.
    Filter = Struct.new(:kind, :name, :label, :value, :options, keyword_init: true)

    attr_reader :screen, :title, :primary_action, :tabs, :filters, :bulk_actions,
                :columns, :rows, :page, :strategy, :empty_message, :base_path,
                :bulk_path, :query, :order, :orderby, :search_query

    # rubocop:disable Metrics/ParameterLists
    def initialize(screen:, title:, columns:, rows:, page:, base_path:, bulk_path:,
                   empty_message:, tabs: [], filters: [], bulk_actions: [],
                   primary_action: nil, strategy: :exact, query: {},
                   order: nil, orderby: nil, search_query: nil)
      @screen = screen
      @title = title
      @primary_action = primary_action
      @tabs = tabs
      @filters = filters
      @bulk_actions = bulk_actions
      @columns = columns
      @rows = rows
      @page = page
      @strategy = strategy
      @base_path = base_path
      @bulk_path = bulk_path
      @empty_message = empty_message
      @query = query
      @order = order
      @orderby = orderby
      @search_query = search_query
    end
    # rubocop:enable Metrics/ParameterLists

    def any_rows? = rows.any?
    def bulk_actions? = bulk_actions.any?
    def tabs? = tabs.any?

    # The count line the legacy prints at the pager: "N items". On an `estimated` screen
    # the total is out of parity scope (DEV-003); the caller renders it as an estimate.
    def total = page.total
  end
end
