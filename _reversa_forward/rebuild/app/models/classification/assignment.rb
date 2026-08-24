# frozen_string_literal: true

module Classification
  # Legacy `term_relationships`. object_id becomes a polymorphic classifiable_*, since
  # AD-02 split the single wp_posts target into posts and assets.
  #
  # ⚠️ This is the ONE relationship in the schema that cannot carry a foreign key, so
  # data_migration_plan.md § Quality validation requires an explicit orphan audit query
  # for it. Everything else is structural.
  class Assignment < ApplicationRecord
    self.table_name = "term_assignments"
    belongs_to :term, class_name: "Classification::Term"
    belongs_to :classifiable, polymorphic: true
    validates :term_id, uniqueness: { scope: %i[classifiable_type classifiable_id] }

    # BR-MIGRATE-058 (BR-TAX-08): with append = false, terms present before but absent
    # from the new list are removed.
    # `taxonomy:` scopes the REPLACE half. wp_set_object_terms() replaces within ONE taxonomy
    # (it is called per taxonomy), so writing a post's categories must not disturb its tags.
    # Without the scope the REST `categories` parameter would silently delete every tag on the
    # record — which is why the editor's category box was left inert until now.
    def self.set(classifiable, term_ids, append: false, taxonomy: nil)
      transaction do
        existing = where(classifiable: classifiable)
        if taxonomy
          tax_id = taxonomy.is_a?(Taxonomy) ? taxonomy.id : Taxonomy.find_by(name: taxonomy)&.id
          existing = existing.where(term_id: Term.where(taxonomy_id: tax_id).select(:id))
        end
        unless append
          existing.where.not(term_id: term_ids).destroy_all
        end
        term_ids.each_with_index do |term_id, position|
          # BR-MIGRATE-057 (BR-TAX-07): assigning a term already related to the object
          # is a no-op. The legacy checks with one query per term; the unique index
          # makes the upsert atomic instead.
          find_or_create_by!(classifiable: classifiable, term_id: term_id) do |a|
            a.position = position
          end
        end
      end
    end
  end
end
