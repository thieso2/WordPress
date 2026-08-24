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
  #
  # Beyond the read list this controller also carries the taxonomy's write affordances that
  # live ON the list screen in the legacy: the inline "Add New" form (edit-tags.php
  # `case 'add-tag'` → wp_insert_term) and Quick Edit (WP_Terms_List_Table::inline_edit /
  # wp_ajax_inline_save_tag). Both resolve Access through the controller, never the view.
  class TermsListController < BaseController
    include Console::ListActions

    before_action :load_taxonomy

    # GET /console/terms/:taxonomy
    def index
      @page_title = taxonomy_label(:name)
      @screen = "console.edit-tags"
      render_index
    end

    # POST /console/terms/:taxonomy — edit-tags.php `case 'add-tag'` → wp_insert_term().
    # `current_user_can( $tax->cap->edit_terms )` = TermPolicy(:create) → manage_categories;
    # a refusal is the legacy's verbatim wp_die (edit-tags.php:83-89) at 403.
    def create
      # edit-tags.php:83 — "Sorry, you are not allowed to create terms in this taxonomy."
      authorize!(Access::TermPolicy, nil, :create,
                 "Sorry, you are not allowed to create terms in this taxonomy.")
      return if performed?

      @new_term = @taxonomy.terms.new(name: params[:name].to_s)
      # wp_insert_term(): an empty slug is derived from the name via sanitize_title().
      @new_term.slug = params[:slug].presence || Sanitizing::Formatting.sanitize_title(params[:name].to_s)
      @new_term.description = params[:description].to_s if params.key?(:description)
      apply_parent(@new_term)

      if @new_term.save
        # edit-tags.php:96 message 1 — edit-tag-messages.php: "Category added." / "Tag added."
        flash[:success] = "#{singular} added."
        redirect_to list_path, status: :see_other
      else
        # edit-tags.php:98-104 sets message 4; here the model's own message is surfaced so a
        # (taxonomy,parent,slug) collision is visible, as the P-EDIT update action does.
        flash.now[:error] = @new_term.errors.full_messages.to_sentence
        render_index(status: :unprocessable_content)
      end
    end

    # POST /console/terms/:taxonomy/:id/inline — wp_ajax_inline_save_tag(). Quick Edit's
    # save: name / slug / parent through the same wp_update_term() path the P-EDIT screen
    # uses. `current_user_can( 'edit_term', $id )` = TermPolicy(:edit).
    def inline_save
      term = @taxonomy.terms.find_by(id: params[:id])
      not_found!("You attempted to edit an item that does not exist. Perhaps it was deleted?") if term.nil?
      return if performed?

      authorize!(Access::TermPolicy, term, :edit, "Sorry, you are not allowed to edit this item.")
      return if performed?

      term.name = params[:name].to_s if params.key?(:name)
      term.slug = params[:slug].to_s if params[:slug].present?
      apply_parent(term)

      if term.save
        render_inline_row(term)
      else
        render plain: term.errors.full_messages.to_sentence, status: :unprocessable_content
      end
    end

    # POST /console/terms/:taxonomy/bulk
    def bulk
      return redirect_to(list_path, status: :see_other) unless bulk_action_chosen? && bulk_ids.any?

      action = bulk_action_name
      terms = @taxonomy.terms.where(id: bulk_ids).to_a
      single = single_delete?

      if action == "delete" && !bulk_confirmed?
        return confirm_bulk(terms, single: single)
      end

      run_bulk(action, terms)
      # edit-tags.php:129 message 2 (single Delete row action) vs :148 message 6 (bulk
      # Delete). edit-tag-messages.php: 2 = "Category deleted." / "Tag deleted."; 6 =
      # "Categories deleted." / "Tags deleted." — fixed, taxonomy-specific, NOT count-based.
      flash[:success] = single ? "#{singular} deleted." : "#{plural} deleted."
      redirect_to list_path, status: :see_other
    end

    private

    # name / slug / count are sortable in get_sortable_columns(); DEV: `description` is a
    # sortable column too (class-wp-terms-list-table.php:220 'description').
    SORTABLE = %w[name description slug count].freeze

    # ⚠️ Only the two built-in content taxonomies are listed here; a request for an unknown
    # taxonomy is a 404, not a 500.
    def load_taxonomy
      name = params[:taxonomy].to_s
      @taxonomy = Classification::Taxonomy.find_by(name: name)
      not_found!("Invalid taxonomy.") if @taxonomy.nil?
    end

    def render_index(status: :ok)
      @page_title ||= taxonomy_label(:name)
      @screen ||= "console.edit-tags"
      @can_create = can?(Access::TermPolicy, nil, :create)
      relation = ordered(@taxonomy.terms)
      page = list_page(relation, strategy: :exact)
      @list = build_list(page)
      render "console/terms_list/index", status: status
    end

    def render_inline_row(term)
      render partial: "console/terms_list/row",
             locals: {
               term: term,
               name_html: name_cell(term),
               description_html: ERB::Util.html_escape(term.description.to_s),
               slug_html: ERB::Util.html_escape(term.slug.to_s),
               count_html: count_cell(term)
             }
    end

    # edit-tags.php / edit-tag-form.php: an empty parent select value (-1/0) means "None";
    # a positive id is honoured only when the taxonomy is hierarchical.
    def apply_parent(term)
      return unless @taxonomy.hierarchical? && params.key?(:parent)

      parent = params[:parent].to_i
      term.parent_id = parent.positive? ? parent : nil
    end

    def ordered(scope)
      orderby = list_orderby(SORTABLE, default: "name")
      dir = list_order.upcase
      column = { "name" => "terms.name", "description" => "terms.description",
                 "slug" => "terms.slug", "count" => "terms.count" }.fetch(orderby, "terms.name")
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
    # _x('Count','Number/count of items'); the header text is "Count". get_sortable_columns()
    # (:216-224) makes name / description / slug / posts(count) all sortable.
    def columns
      [
        ListModel::Column.new(key: "name", label: "Name", sortable: true, sort_key: "name"),
        ListModel::Column.new(key: "description", label: "Description", sortable: true, sort_key: "description"),
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
          "count" => count_cell(term)
        },
        actions: row_actions(term)
      )
    end

    # column_name(), class-wp-terms-list-table.php:383-441. The <strong><a class="row-title">
    # link, PLUS the hidden `inline_<id>` data block Quick Edit reads (name / slug / parent).
    def name_cell(term)
      name = ERB::Util.html_escape(term.name)
      slug = ERB::Util.html_escape(term.slug.to_s)
      link = %(<strong><a class="row-title" href="/console/terms/#{@taxonomy.name}/#{term.id}/edit">#{name}</a></strong>)
      data = %(<div class="hidden" id="inline_#{term.id}"><div class="name">#{name}</div>) +
             %(<div class="slug">#{slug}</div><div class="parent">#{term.parent_id.to_i}</div></div>)
      (link + data).html_safe
    end

    # column_posts(), class-wp-terms-list-table.php:595-622 — the count is an anchor to the
    # posts screen filtered by this term's taxonomy query_var (`category_name` / `tag`).
    def count_cell(term)
      count = term.count.to_i.to_s
      query_var = @taxonomy.name == "post_tag" ? "tag" : "category_name"
      href = "/console/posts?#{query_var}=#{ERB::Util.url_encode(term.slug.to_s)}"
      %(<a href="#{ERB::Util.html_escape(href)}">#{count}</a>).html_safe
    end

    # handle_row_actions(), class-wp-terms-list-table.php:465-537 — Edit, Quick Edit, Delete,
    # View, in that order. Each is gated through Access (the view never asks, BR-CAP-05).
    def row_actions(term)
      actions = []
      if can?(Access::TermPolicy, term, :edit)
        actions << ListModel::RowAction.new(label: "Edit", path: "/console/terms/#{@taxonomy.name}/#{term.id}/edit", method: :get, key: "edit")
        # class-wp-terms-list-table.php:504-508 — "Quick&nbsp;Edit", a JS affordance that
        # opens the inline editor and posts to #inline_save.
        actions << ListModel::RowAction.new(label: "Quick&nbsp;Edit".html_safe, path: "#inline-#{term.id}", method: :get, key: "editinline")
      end
      if can?(Access::TermPolicy, term, :delete)
        actions << ListModel::RowAction.new(label: "Delete", path: bulk_path, method: :post,
                                            params: { bulk_action: "delete", confirmed: "0", single: "1", "ids[]" => term.id },
                                            destructive: true, key: "delete")
      end
      if publicly_viewable?
        # class-wp-terms-list-table.php:527-537 — View link to the term's public archive.
        actions << ListModel::RowAction.new(label: "View", path: term_archive_path(term), method: :get, key: "view")
      end
      actions
    end

    # is_term_publicly_viewable( $tag ) — true when the taxonomy is publicly queryable. Both
    # built-in content taxonomies (category, post_tag) are; they own public archive routes
    # (config/routes.rb /category/*path and /tag/:slug).
    def publicly_viewable?
      %w[category post_tag].include?(@taxonomy.name)
    end

    def term_archive_path(term)
      slug = ERB::Util.url_encode(term.slug.to_s)
      @taxonomy.name == "post_tag" ? "/tag/#{slug}" : "/category/#{slug}"
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

    # A single-row Delete (edit-tags.php `case 'delete'`, message 2) is marked so it survives
    # the DEV-004 confirmation round-trip as a query param; a genuine bulk Delete
    # (`case 'bulk-delete'`, message 6) carries no marker.
    def single_delete? = params[:single].to_s == "1"

    def confirm_bulk(terms, single:)
      terms = terms.select { |t| can?(Access::TermPolicy, t, :delete) }
      render_bulk_confirmation(
        title: taxonomy_label(:name),
        prompt: "You are about to delete #{terms.length} item(s). This cannot be undone.",
        button: "Delete",
        action: "delete",
        ids: terms.map(&:id),
        items: terms.map(&:name),
        post_path: single ? "#{bulk_path}?single=1" : bulk_path,
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

    # singular_name / add_new_item / update_item / parent_item defaults (class-wp-taxonomy.php
    # :613-628). post_tag → Tag family, category (and custom) → Category family.
    def singular = @taxonomy.name == "post_tag" ? "Tag" : "Category"
    def plural = taxonomy_label(:name)
    def add_new_item = @taxonomy.name == "post_tag" ? "Add Tag" : "Add Category"
    def update_item = @taxonomy.name == "post_tag" ? "Update Tag" : "Update Category"
    def parent_item = "Parent Category"
    helper_method :add_new_item, :update_item, :parent_item, :taxonomy_label

    def list_path = "/console/terms/#{@taxonomy.name}"
    def bulk_path = "/console/terms/#{@taxonomy.name}/bulk"
    def create_path = "/console/terms/#{@taxonomy.name}"
    def inline_path(term) = "/console/terms/#{@taxonomy.name}/#{term.id}/inline"
    helper_method :list_path, :create_path
  end
end
