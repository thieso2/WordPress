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
    def self.set(classifiable, term_ids, append: false)
      transaction do
        existing = where(classifiable: classifiable)
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
