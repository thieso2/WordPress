# frozen_string_literal: true

module Console
  # console.edit-tags — the Terms list (wp-admin/edit-tags.php, WP_Terms_List_Table). One
  # P-LIST over Classification::Term scoped to a taxonomy, EXACT pagination
  # (target_screens.md § Part 5). Route: /console/terms/:taxonomy.
  #
  # ⚠️ The `count` column is PUBLISHED CONTENT ONLY (BR-MIGRATE-061). It is the stored
  # `terms.count`, maintained by the db trigger against published posts (Classification::Term
  # note) — so the console reads exactly what the front-end taxonomy queries read, with no
  # separate recomputation here.
  #
  # LITERAL strings verbatim from WP_Terms_List_Table / WP_Taxonomy default labels: columns
  # "Name / Description / Slug / Count", bulk "Delete", "No categories found." / "No tags
  # found." A distinct controller from the P-EDIT track's Console::TermsController (the
  # single-term editor at /console/terms/:taxonomy/:id/edit).
  class TermsListController < BaseController
    include Console::ListActions

    before_action :load_taxonomy

    # GET /console/terms/:taxonomy
    def index
      @page_title = taxonomy_label(:name)
      @screen = "console.edit-tags"

      relation = ordered(@taxonomy.terms)
      page = list_page(relation, strategy: :exact)
      @list = build_list(page)
      render "console/terms_list/index"
    end

    # POST /console/terms/:taxonomy/bulk
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      terms = @taxonomy.terms.where(id: bulk_ids).to_a

      if action == "delete" && !bulk_confirmed?
        return confirm_bulk(terms)
      end

      count = run_bulk(action, terms)
      redirect_to list_path, notice: "#{count} item(s) deleted.", status: :see_other
    end

    private

    SORTABLE = %w[name slug count].freeze

    # ⚠️ Only the two built-in content taxonomies are listed here; a request for an unknown
    # taxonomy is a 404, not a 500.
    def load_taxonomy
      name = params[:taxonomy].to_s
      @taxonomy = Classification::Taxonomy.find_by(name: name)
      not_found!("Invalid taxonomy.") if @taxonomy.nil?
    end

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "name")
      dir = list_order.upcase
      column = { "name" => "terms.name", "slug" => "terms.slug", "count" => "terms.count" }.fetch(orderby, "terms.name")
      # WP defaults the terms table to name ASC; keep that as the default direction.
      dir = "ASC" if params[:order].blank? && params[:orderby].blank?
      scope.order(Arel.sql("#{column} #{dir}, terms.id #{dir}"))
    end

    def build_list(page)
      ListModel.new(
        screen: "console.edit-tags",
        title: taxonomy_label(:name),
        primary_action: nil,
        tabs: [],
        filters: [ListModel::Filter.new(kind: :search, name: "s", label: taxonomy_label(:search_items), value: params[:s].to_s)],
        bulk_actions: bulk_actions,
        columns: columns,
        rows: page.records.map { |term| row_for(term) },
        page: page,
        strategy: :exact,
        base_path: list_path,
        bulk_path: bulk_path,
        empty_message: taxonomy_label(:not_found),
        query: list_query.merge("taxonomy" => @taxonomy.name),
        order: list_order,
        orderby: list_orderby(SORTABLE, default: "name"),
        search_query: params[:s].presence
      )
    end

    # get_columns(), class-wp-terms-list-table.php:189 — LITERAL. "Count" is
    # _x('Count','Number/count of items'); the header text is "Count".
    def columns
      [
        ListModel::Column.new(key: "name", label: "Name", sortable: true, sort_key: "name"),
        ListModel::Column.new(key: "description", label: "Description", sortable: false),
        ListModel::Column.new(key: "slug", label: "Slug", sortable: true, sort_key: "slug"),
        ListModel::Column.new(key: "count", label: "Count", sortable: true, sort_key: "count")
      ]
    end

    # get_bulk_actions(), class-wp-terms-list-table.php:165 — Delete only, DEV-004-confirmed.
    def bulk_actions
      return [] unless site_can?("manage_categories")

      [ListModel::BulkAction.new(value: "delete", label: "Delete", destructive: true)]
    end

    def row_for(term)
      ListModel::Row.new(
        id: term.id,
        cells: {
          "name" => name_cell(term),
          "description" => ERB::Util.html_escape(term.description.to_s),
          "slug" => ERB::Util.html_escape(term.slug.to_s),
          "count" => term.count.to_i.to_s
        },
        actions: row_actions(term)
      )
    end

    def name_cell(term)
      %(<strong><a href="/console/terms/#{@taxonomy.name}/#{term.id}/edit">#{ERB::Util.html_escape(term.name)}</a></strong>).html_safe
    end

    def row_actions(term)
      actions = []
      actions << ListModel::RowAction.new(label: "Edit", path: "/console/terms/#{@taxonomy.name}/#{term.id}/edit", method: :get, key: "edit") if can?(Access::TermPolicy, term, :edit)
      if can?(Access::TermPolicy, term, :delete)
        actions << ListModel::RowAction.new(label: "Delete", path: bulk_path, method: :post,
                                            params: { bulk_action: "delete", confirmed: "0", "ids[]" => term.id },
                                            destructive: true, key: "delete")
      end
      actions
    end

    def run_bulk(action, terms)
      return 0 unless action == "delete"

      count = 0
      terms.each do |term|
        next unless can?(Access::TermPolicy, term, :delete)

        term.destroy!
        count += 1
      end
      count
    end

    def confirm_bulk(terms)
      terms = terms.select { |t| can?(Access::TermPolicy, t, :delete) }
      render_bulk_confirmation(
        title: taxonomy_label(:name),
        prompt: "You are about to delete #{terms.length} item(s). This cannot be undone.",
        button: "Delete",
        action: "delete",
        ids: terms.map(&:id),
        items: terms.map(&:name),
        post_path: bulk_path,
        cancel_path: list_path
      )
    end

    # WP_Taxonomy default labels for the two built-in taxonomies (class-wp-taxonomy.php),
    # LITERAL. `post_tag` → Tags family, everything else (category and custom) → Categories.
    TAG_LABELS = { name: "Tags", search_items: "Search Tags", not_found: "No tags found." }.freeze
    CATEGORY_LABELS = { name: "Categories", search_items: "Search Categories", not_found: "No categories found." }.freeze

    def taxonomy_label(key)
      (@taxonomy.name == "post_tag" ? TAG_LABELS : CATEGORY_LABELS).fetch(key)
    end

    def list_path = "/console/terms/#{@taxonomy.name}"
    def bulk_path = "/console/terms/#{@taxonomy.name}/bulk"
  end
end
