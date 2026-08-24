# frozen_string_literal: true

module PublicApi
  # /wp/v2/categories and /wp/v2/tags — WP_REST_Terms_Controller. Public collection
  # (BR-REST-05); the item registers a `read_item` callback so a missing id is
  # rest_term_invalid (404). REST default is orderby=name asc, hide_empty=false — every
  # term, count-0 included.
  #
  # ── The WRITE surface ────────────────────────────────────────────────────────────
  # Gutenberg's Post sidebar creates a category or a tag INLINE, so POST here is on the
  # editor's critical path. The three write actions are wp_insert_term() /
  # wp_update_term() / wp_delete_term() (wp-includes/taxonomy.php) reached through
  # Classification::Term — the model owns uniqueness, the acyclic-parent guard and the
  # cross-taxonomy parent rule, and this controller only translates its refusals into
  # the legacy's WP_Error envelope.
  #
  # Terms have NO trash state, so DELETE requires `force=true` and answers 501 without it.
  class TermsController < BaseController
    include CollectionPagination
    include WriteSupport

    permission :show,    :read_item
    permission :create,  :create_item
    permission :update,  :update_item
    permission :destroy, :delete_item

    TAXONOMY = nil # subclass sets it.

    def index
      scope = term_scope.order(Arel.sql("LOWER(terms.name) ASC"), :id)
      total = scope.count
      records = scope.offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/#{rest_base}")
      set_allow_header(collection_allow)
      render_json(records.map { |t| TermSerializer.new(t, allow: item_allow(t)).as_json })
    end

    def show
      term = loaded_term
      set_allow_header(item_allow(term))
      render_json(TermSerializer.new(term, allow: item_allow(term)).as_json)
    end

    # POST /wp/v2/<rest_base> — create_item(), class-wp-rest-terms-controller.php:390.
    def create
      # `name` is `'required' => true` in the endpoint args, so it is checked by
      # has_valid_params() before the callback runs.
      require_params!(:name)
      name = sanitized_name(params[:name])
      parent = resolve_parent!
      guard_duplicate!(name, parent, nil)

      term = Classification::Term.new(
        taxonomy: taxonomy_record, name: name, parent_id: parent&.id,
        description: sent?(:description) ? params[:description].to_s : ""
      )
      term.slug = unique_slug(requested_slug(name), parent, nil)
      save_term!(term)
      set_allow_header(item_allow(term))
      render_created(TermSerializer.new(term, allow: item_allow(term)).as_json,
                     location: Url.rest("/wp/v2/#{rest_base}/#{term.id}"))
    end

    # POST|PUT|PATCH /wp/v2/<rest_base>/:id — update_item(), :460.
    def update
      term = loaded_term
      parent = sent?(:parent) ? resolve_parent! : term.parent
      if sent?(:name) && params[:name].to_s.present?
        term.name = sanitized_name(params[:name])
        guard_duplicate!(term.name, parent, term)
      end
      term.description = params[:description].to_s if sent?(:description)
      term.parent_id = parent&.id if sent?(:parent)
      # edit-tag-form.php sends an empty slug to mean "regenerate from the name"; an
      # absent one leaves the stored slug alone (wp_update_term:, taxonomy.php:2760).
      term.slug = unique_slug(Sanitizing::Formatting.sanitize_title(params[:slug].to_s), parent, term) if params[:slug].present?
      save_term!(term)
      set_allow_header(item_allow(term))
      render_json(TermSerializer.new(term, allow: item_allow(term)).as_json)
    end

    # DELETE /wp/v2/<rest_base>/:id — delete_item(), :540. "Terms do not support
    # trashing." (:548)
    def destroy
      term = loaded_term
      unless force_param?
        raise PublicApi::RestError.new("rest_trash_not_supported",
                                       "Terms do not support trashing. Set 'force=true' to delete.",
                                       501)
      end
      previous = TermSerializer.new(term, allow: item_allow(term)).as_json.except(:_links)
      term.destroy!
      set_allow_header(%w[GET POST PUT PATCH DELETE])
      render_json({ deleted: true, previous: previous })
    end

    private

    def term_scope
      Classification::Term.joins(:taxonomy).where(taxonomies: { name: self.class::TAXONOMY })
                          .includes(:taxonomy)
    end

    def taxonomy_record
      @taxonomy_record ||= Classification::Taxonomy.find_by(name: self.class::TAXONOMY) ||
                           raise(PublicApi::RestError.new("rest_taxonomy_invalid",
                                                          "Invalid taxonomy.", 404))
    end

    def rest_base = TermSerializer::REST_BASE.fetch(self.class::TAXONOMY)

    # ── writing ─────────────────────────────────────────────────────────────────

    # sanitize_term_field( 'name', …, 'db' ) — the name is stored HTML-escaped-free of
    # tags; wp_filter_kses is the unfiltered_html arm and neither built-in taxonomy
    # keeps markup in a name.
    def sanitized_name(value) = Sanitizing::Formatting.strip_tags(value.to_s).strip

    def requested_slug(name)
      raw = params[:slug].present? ? params[:slug].to_s : name
      Sanitizing::Formatting.sanitize_title(raw)
    end

    # `parent` is rejected outright on a flat taxonomy (:435), and a parent that names
    # nothing is rest_term_invalid with the PARENT message (:444).
    def resolve_parent!
      return nil unless sent?(:parent)

      parent_id = params[:parent].to_i
      unless taxonomy_record.hierarchical?
        if params[:parent].present? && parent_id.positive?
          raise PublicApi::RestError.new("rest_taxonomy_not_hierarchical",
                                         "Cannot set parent term, taxonomy is not hierarchical.", 400)
        end
        return nil
      end
      return nil unless parent_id.positive?

      term_scope.find_by(id: parent_id) ||
        raise(PublicApi::RestError.new("rest_term_invalid", "Parent term does not exist.", 400))
    end

    # wp_insert_term()'s duplicate rules (taxonomy.php:2340): a HIERARCHICAL taxonomy
    # allows the same name under a DIFFERENT parent, a flat one does not allow it at all.
    # Verified against the oracle, including the two distinct messages.
    def guard_duplicate!(name, parent, current)
      scope = term_scope.where("LOWER(terms.name) = ?", name.downcase)
      scope = scope.where.not(id: current.id) if current&.id
      if taxonomy_record.hierarchical?
        scope = scope.where(parent_id: parent&.id)
        message = "A term with the name provided already exists with this parent."
      else
        message = "A term with the name provided already exists in this taxonomy."
      end
      existing = scope.first
      return if existing.nil?

      raise PublicApi::RestError.new("term_exists", message, 400, { term_id: existing.id })
    end

    # wp_unique_term_slug(), taxonomy.php:3103: a taken slug takes the parent's slug as a
    # suffix on a hierarchical taxonomy, and a numeric suffix after that.
    def unique_slug(base, parent, current)
      base = "term" if base.blank?
      return base unless slug_taken?(base, parent, current)

      if taxonomy_record.hierarchical? && parent
        with_parent = "#{base}-#{parent.slug}"
        return with_parent unless slug_taken?(with_parent, parent, current)

        base = with_parent
      end
      suffix = 2
      suffix += 1 while slug_taken?("#{base}-#{suffix}", parent, current)
      "#{base}-#{suffix}"
    end

    # The unique index is on (taxonomy_id, parent_id, slug) (AD-05), but the legacy's
    # slugs are unique across the whole taxonomy, so that is what is probed for.
    def slug_taken?(slug, _parent, current)
      scope = term_scope.where(slug: slug)
      scope = scope.where.not(id: current.id) if current&.id
      scope.exists?
    end

    # The model's own invariants (acyclic parent, cross-taxonomy parent, uniqueness)
    # answer as the legacy's insert failure does.
    def save_term!(term)
      term.save!
    rescue ActiveRecord::RecordInvalid => e
      raise PublicApi::RestError.new("rest_term_invalid", e.record.errors.full_messages.join(" "), 400)
    end

    # ── permission callbacks ────────────────────────────────────────────────────

    def read_item
      loaded_term
      true
    end

    # create_item_permissions_check(), :370 — `$taxonomy->cap->edit_terms`.
    def create_item
      return true if Access::TermPolicy.new(current_actor, nil).permit?(:create)

      raise rest_denied("rest_cannot_create", "Sorry, you are not allowed to create terms in this taxonomy.")
    end

    def update_item
      term = loaded_term
      return true if Access::TermPolicy.new(current_actor, term).permit?(:edit)

      raise rest_denied("rest_cannot_update", "Sorry, you are not allowed to edit this term.")
    end

    # delete_item_permissions_check(), :525. Access::TermPolicy#delete is the arm that
    # refuses the taxonomy's DEFAULT term outright (capabilities.php:738-744), which is
    # why deleting category 1 is a 403 for an administrator too.
    def delete_item
      term = loaded_term
      return true if Access::TermPolicy.new(current_actor, term).permit?(:delete)

      raise rest_denied("rest_cannot_delete", "Sorry, you are not allowed to delete this term.")
    end

    # ── rest_send_allow_header() / targetHints ──────────────────────────────────

    def item_allow(term)
      allow = %w[GET]
      return allow if current_actor.nil?

      allow.concat(%w[POST PUT PATCH]) if Access::TermPolicy.new(current_actor, term).permit?(:edit)
      allow << "DELETE" if Access::TermPolicy.new(current_actor, term).permit?(:delete)
      allow
    end

    def collection_allow
      allow = %w[GET]
      allow << "POST" if Access::TermPolicy.new(current_actor, nil).permit?(:create)
      allow
    end

    def loaded_term
      @loaded_term ||= term_scope.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_term_invalid", "Term does not exist.", 404))
    end
  end
end
