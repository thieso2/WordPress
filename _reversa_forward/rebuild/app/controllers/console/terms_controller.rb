# frozen_string_literal: true

module Console
  # console.term — the single-term edit screen (P-EDIT). Legacy origin:
  # wp-admin/edit-tags.php `case 'edit'` (:151) rendering edit-tag-form.php, and
  # `case 'editedtag'` calling wp_update_term() (wp-includes/taxonomy.php). Route carries
  # the taxonomy: /console/terms/:taxonomy/:id/edit.
  #
  # T-06: a term is unique on (taxonomy, parent, slug) — the model enforces it; this screen
  # surfaces the model's verbatim message on collision.
  #
  # Authorization: current_user_can( 'edit_term', $id ) — Access::TermPolicy(:edit), which
  # maps to manage_categories (capabilities.php:708-760).
  class TermsController < BaseController
    before_action :load_taxonomy
    before_action :load_term
    before_action :authorize_edit

    # get_taxonomy_labels() edit_item / parent_item, verbatim for the two built-in
    # taxonomies. A custom taxonomy falls back to the generic default labels.
    LABELS = {
      "category" => { edit_item: "Edit Category", parent_item: "Parent Category" },
      "post_tag" => { edit_item: "Edit Tag",      parent_item: "Parent Tag" }
    }.freeze
    DEFAULT_LABELS = { edit_item: "Edit Item", parent_item: "Parent Item" }.freeze

    # GET /console/terms/:taxonomy/:id/edit — edit-tag-form.php.
    def edit
      @page_title = labels[:edit_item] # <h1>, edit-tag-form.php:72 (LITERAL)
      render :edit
    end

    # PATCH/PUT /console/terms/:taxonomy/:id — wp_update_term().
    def update
      @term.name        = params[:name].to_s if params.key?(:name)
      # edit-tag-form.php sends an empty slug to mean "regenerate from the name"
      # (wp_update_term: an empty slug is re-derived). Preserve the existing slug when the
      # field is blank rather than failing presence.
      @term.slug        = params[:slug].to_s if params[:slug].present?
      @term.description = params[:description].to_s if params.key?(:description)
      if @term.taxonomy.hierarchical? && params.key?(:parent)
        parent = params[:parent].to_i
        @term.parent_id = parent.positive? ? parent : nil # -1/0 = "None"
      end

      if @term.save
        flash[:success] = "#{singular} updated." # edit-tags.php messages[3]
        redirect_to edit_console_term_path(@taxonomy.name, @term), status: :see_other
      else
        @page_title = labels[:edit_item]
        flash.now[:error] = @term.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    private

    def labels = LABELS.fetch(@taxonomy.name, DEFAULT_LABELS)
    def singular = @taxonomy.name == "post_tag" ? "Tag" : "Category"
    helper_method :labels

    def load_taxonomy
      @taxonomy = Classification::Taxonomy.find_by(name: params[:taxonomy])
      # edit-tags.php:47 — an unknown taxonomy is wp_die( 'Invalid taxonomy.' ).
      not_found!("Invalid taxonomy.") if @taxonomy.nil?
    end

    def load_term
      return if performed?

      @term = Classification::Term.find_by(id: params[:id], taxonomy_id: @taxonomy.id)
      # edit-tags.php:155 — wp_die on a term id that names nothing in this taxonomy.
      not_found!("You attempted to edit an item that does not exist. Perhaps it was deleted?") if @term.nil?
    end

    def authorize_edit
      return if performed?

      # edit-tags.php:80 — wp_die when the actor may not edit terms in this taxonomy.
      authorize!(Access::TermPolicy, @term, :edit,
                 "Sorry, you are not allowed to edit this item.")
    end
  end
end
