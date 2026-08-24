# frozen_string_literal: true

module Classification
  # AGG-Term — target_domain_model.md § AGG-Term.
  #
  # T-06: `wp_terms` + `wp_term_taxonomy` collapse into ONE row per (term, taxonomy)
  # pair. ⚠️ This is a behavioural change, not a reshaping: in the legacy one wp_terms
  # row can serve several taxonomies — the same word being both a category and a tag,
  # sharing a term_id (BR-MIGRATE-052). Here it becomes two independent rows. Any
  # oracle diff that depends on term-id sharing is EXPECTED and is a recorded deviation.
  class Term < ApplicationRecord
    self.table_name = "terms"

    belongs_to :taxonomy, class_name: "Classification::Taxonomy"
    belongs_to :parent, class_name: "Classification::Term", optional: true
    has_many :children, class_name: "Classification::Term", foreign_key: :parent_id, dependent: :destroy
    has_many :assignments, class_name: "Classification::Assignment", dependent: :destroy

    # BR-MIGRATE-053 (BR-TAX-02): the term name is validated for emptiness twice, before
    # and after sanitization. One validation covers both here because sanitization is a
    # pure function applied before validation rather than a filter chain.
    validates :name, presence: true
    validates :slug, presence: true,
                     uniqueness: { scope: %i[taxonomy_id parent_id],
                                   message: "must be unique within its taxonomy and parent" }
    validate :hierarchy_is_acyclic
    validate :parent_shares_taxonomy

    # BR-MIGRATE-054 (BR-TAX-03): a null description is coerced to empty string.
    before_validation { self.description = "" if description.nil? }

    def self.hierarchical_for?(taxonomy) = taxonomy.hierarchical?

    # BR-MIGRATE-061 (BR-TAX-11): the count reflects PUBLISHED content only.
    # BR-MIGRATE-062 (BR-TAX-12): padding deduplicates by object id, so a post in both a
    # child and its parent is counted once for the parent.
    #
    # The legacy computes this at read time in _pad_term_counts(), joining
    # term_relationships to posts on every render (F-TAX-05). Here it is a stored
    # counter maintained on write — implication 4.
    #
    # ⚠️ This is the surviving one-directional edge: Classification READS Publishing,
    # and Publishing never reads Classification. That single direction is what keeps the
    # legacy posts<->taxonomy cycle from re-forming.
    #
    # ⚠️ Where the maintenance lives. The counter has to react to a post being published,
    # unpublished or deleted, and in Ruby that reaction could only be installed on
    # Publishing::Post — the exact reference risk_register.md RISK-017 names as its
    # warning signal. So it is kept in the schema instead: see
    # db/migrate/20260822000052_maintain_term_counts.rb, which mirrors the query below
    # as a trigger. No Ruby constant crosses the boundary, and the counter cannot drift
    # on update_all or a raw statement either.
    #
    # This method is therefore the RECONCILIATION command, not the maintenance path —
    # data_migration_plan.md § Quality validation asks for exactly this:
    # "terms.count ... equal the recomputed values — recompute-and-compare".
    # ⚠️ `hide_empty` IS NOT `count > 0` HERE, and that is a consequence of a decision
    # taken further up: `terms.count` in the target stores the PADDED count
    # (BR-MIGRATE-062), which the legacy computes at READ time in _pad_term_counts() and
    # never stores. The legacy's `wp_term_taxonomy.count` is the RAW, direct count —
    # wp_update_term_count_now() counts term_relationships rows whose post is published
    # and nothing else — and `get_terms( hide_empty => true )` filters on THAT column,
    # without padding, unless the caller also asks for `pad_counts`.
    #
    # So an ancestor category with no posts of its own is EMPTY to get_terms() and
    # non-empty to this model. The sitemap's taxonomy provider is the surface where the
    # difference is observable: WP_Sitemaps_Taxonomies passes `hide_empty => true` and no
    # `pad_counts`, so /wp-sitemap-taxonomies-category-1.xml lists `uncategorized` and
    # `leaf-category` — not `top-category` and `middle-category`, which hold posts only
    # through their descendants. Found by the corpus-widening pass.
    #
    # ⚠️ KNOWN GAP, recorded rather than papered over: one stored counter cannot answer
    # both questions. Restoring the raw count as a second column is a schema change and
    # a migration, which is out of scope for a corpus pass; this scope answers the raw
    # question directly from the assignments instead, which is the same set the legacy's
    # counter would hold.
    scope :with_direct_published_posts, lambda {
      where(id: Classification::Assignment
                  .where(classifiable_type: "Publishing::Post")
                  .joins("INNER JOIN posts ON posts.id = term_assignments.classifiable_id")
                  .where(posts: { status: "published" })
                  .select(:term_id))
    }

    def recompute_count!
      ids = self_and_descendant_ids
      published = Classification::Assignment
                  .where(term_id: ids, classifiable_type: "Publishing::Post")
                  .joins("INNER JOIN posts ON posts.id = term_assignments.classifiable_id")
                  .where(posts: { status: "published" })
                  .distinct
                  .count(:classifiable_id)
      update_column(:count, published)
      published
    end

    # BR-MIGRATE-063 (BR-TAX-13): the legacy needs an explicit cycle guard when walking
    # ancestors, because nothing prevents a corrupted parent chain. Here the guard is a
    # save-time validation plus a foreign key — the corrupted chain is unrepresentable.
    # The guard is kept anyway: it costs nothing and the legacy's data may still carry one.
    #
    # One recursive CTE rather than a breadth-first walk issuing a query per node. The
    # walk was measured (bin/benchmark) at 9 invocations on a single category screen —
    # the archive asks for the term's subtree once to count, once to paginate and once per
    # rendered loop — each invocation costing a query per level of the hierarchy. The
    # answer is a SET (both callers feed it straight into `where(term_id: ids)`), so
    # descending in the database instead of in Ruby changes nothing observable.
    #
    # `UNION`, not `UNION ALL`: the deduplication is what terminates a corrupted parent
    # chain, so the cycle guard described above survives the rewrite rather than being
    # traded away for it.
    def self_and_descendant_ids
      sql = <<~SQL.squish
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM #{self.class.quoted_table_name} WHERE id = #{self.class.connection.quote(id)}
          UNION
          SELECT t.id FROM #{self.class.quoted_table_name} t
            INNER JOIN subtree s ON t.parent_id = s.id
        )
        SELECT id FROM subtree
      SQL
      self.class.connection.select_values(sql).map(&:to_i)
    end

    def ancestors
      chain = []
      seen = Set.new([id])
      node = parent
      while node && !seen.include?(node.id)
        seen << node.id
        chain << node
        node = node.parent
      end
      chain
    end

    private

    def hierarchy_is_acyclic
      return if parent_id.nil?

      if parent_id == id
        errors.add(:parent_id, "a term may not be its own parent")
        return
      end
      seen = Set.new([id])
      node = self.class.find_by(id: parent_id)
      while node
        if seen.include?(node.id)
          errors.add(:parent_id, "a term may not be its own ancestor")
          return
        end
        seen << node.id
        node = node.parent_id ? self.class.find_by(id: node.parent_id) : nil
      end
    end

    # BR-MIGRATE-055 (BR-TAX-04): a non-existent parent rejects the insert with the
    # missing_parent error. The FK covers non-existence; this covers the cross-taxonomy
    # case, which T-06 says the legacy also permits by accident.
    def parent_shares_taxonomy
      return if parent.nil? || parent.taxonomy_id == taxonomy_id

      errors.add(:parent_id, "missing_parent: parent belongs to a different taxonomy")
    end
  end
end
