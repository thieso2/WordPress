# frozen_string_literal: true

# AGG-Term's counter cache. BR-MIGRATE-061 (BR-TAX-11) and BR-MIGRATE-062 (BR-TAX-12).
#
# target_data_model.md: "Counter caches replace read-time computation. `terms.count` and
# `posts.comment_count` are maintained on write. The legacy pads term counts at read time
# by joining `term_relationships` to `posts` filtered on `post_status='publish'` -- on
# every render (F-TAX-05, BR-TAX-11)."
#
# ⚠️ Why the maintenance lives in the DATABASE rather than in an Active Record callback.
# The count is derived from `posts`, so *something* has to react when a post's status
# changes or a post is deleted. In Ruby that reaction can only be installed on
# `Publishing::Post`, and target_architecture.md Note 2 / BC-02 are unambiguous that the
# arrow runs one way only: "`Classification` reads `Publishing` and never the reverse".
# risk_register.md RISK-017 lists the warning signal in those exact terms. A trigger
# reacts on the `posts` table without any Ruby constant crossing the boundary, so
# bin/check_cycles still sees a DAG -- and the counter cannot drift on `update_all`,
# `delete_all` or a raw statement either. It is AD-05's principle applied to derived
# state: what the legacy did with a compensating procedure, the schema does itself.
#
# It also supplies the one cascade no foreign key can express. `term_assignments.
# classifiable_*` is polymorphic across `posts` and `assets`, so target_data_model.md
# records it as "the one exception ... no FK is expressible" with "a nightly orphan-audit
# job" as the mitigation. Deleting the post here removes its assignments in the same
# statement, so the audit has nothing to find on this path.
class MaintainTermCounts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      -- The padded count for ONE term: distinct published records in the term or any
      -- of its descendants. BR-MIGRATE-061 (published only) and BR-MIGRATE-062
      -- (deduplicated by object id, so a record in both a child and its parent counts
      -- once for the parent) are both in this single expression.
      CREATE FUNCTION classification_term_count(p_term_id bigint) RETURNS integer AS $fn$
        WITH RECURSIVE subtree(id) AS (
          SELECT p_term_id
          UNION ALL
          SELECT t.id FROM terms t JOIN subtree s ON t.parent_id = s.id
        )
        SELECT count(DISTINCT a.classifiable_id)::integer
        FROM term_assignments a
        JOIN subtree s ON s.id = a.term_id
        JOIN posts p ON p.id = a.classifiable_id
        WHERE a.classifiable_type = 'Publishing::Post'
          AND p.status = 'published';
      $fn$ LANGUAGE sql STABLE;

      -- Refresh each named term and every ancestor above it, because a descendant's
      -- assignments are part of an ancestor's padded count.
      --
      -- BR-MIGRATE-063 (BR-TAX-13): the legacy walks ancestors with an explicit cycle
      -- guard against a corrupted parent chain. Here the chain cannot be corrupted --
      -- terms_not_self_parent plus Classification::Term's ancestry validation see to
      -- that -- but the guard is kept, for the same reason the legacy has one: a walk
      -- that trusts its data is a walk that can hang the write path.
      CREATE FUNCTION classification_refresh_term_counts(p_term_ids bigint[]) RETURNS void AS $fn$
      DECLARE
        seed  bigint;
        node  bigint;
        steps integer;
      BEGIN
        FOREACH seed IN ARRAY coalesce(p_term_ids, ARRAY[]::bigint[]) LOOP
          node  := seed;
          steps := 0;
          WHILE node IS NOT NULL AND steps < 1000 LOOP
            UPDATE terms SET count = classification_term_count(node) WHERE id = node;
            SELECT parent_id INTO node FROM terms WHERE id = node;
            steps := steps + 1;
          END LOOP;
        END LOOP;
      END;
      $fn$ LANGUAGE plpgsql;

      -- Classifying, reclassifying or unclassifying a record.
      CREATE FUNCTION classification_assignment_counts() RETURNS trigger AS $fn$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          PERFORM classification_refresh_term_counts(ARRAY[OLD.term_id]);
          RETURN OLD;
        ELSIF TG_OP = 'UPDATE' THEN
          PERFORM classification_refresh_term_counts(ARRAY[OLD.term_id, NEW.term_id]);
          RETURN NEW;
        ELSE
          PERFORM classification_refresh_term_counts(ARRAY[NEW.term_id]);
          RETURN NEW;
        END IF;
      END;
      $fn$ LANGUAGE plpgsql;

      CREATE TRIGGER term_assignments_maintain_counts
        AFTER INSERT OR UPDATE OR DELETE ON term_assignments
        FOR EACH ROW EXECUTE FUNCTION classification_assignment_counts();

      -- A record being published, unpublished, trashed or deleted. This is the edge
      -- BC-02 calls "counter cache only": it reads `posts`, and `posts` never learns
      -- that classification exists.
      CREATE FUNCTION classification_post_counts() RETURNS trigger AS $fn$
      DECLARE affected bigint[];
      BEGIN
        IF TG_OP = 'DELETE' THEN
          -- The polymorphic cascade no FK can carry. Removing the rows fires the
          -- assignment trigger above, which is what decrements the counts.
          DELETE FROM term_assignments
           WHERE classifiable_type = 'Publishing::Post' AND classifiable_id = OLD.id;
          RETURN OLD;
        END IF;

        IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
          RETURN NEW;
        END IF;

        SELECT array_agg(term_id) INTO affected FROM term_assignments
         WHERE classifiable_type = 'Publishing::Post' AND classifiable_id = NEW.id;
        PERFORM classification_refresh_term_counts(affected);
        RETURN NEW;
      END;
      $fn$ LANGUAGE plpgsql;

      CREATE TRIGGER posts_maintain_term_counts
        AFTER INSERT OR UPDATE OR DELETE ON posts
        FOR EACH ROW EXECUTE FUNCTION classification_post_counts();

      -- Reparenting a term moves a whole subtree's contribution from one ancestor
      -- chain to another. Declared `OF parent_id` so that writing `count` itself does
      -- not re-enter the trigger.
      CREATE FUNCTION classification_term_reparent_counts() RETURNS trigger AS $fn$
      BEGIN
        PERFORM classification_refresh_term_counts(ARRAY[NEW.id]);
        IF OLD.parent_id IS NOT NULL THEN
          PERFORM classification_refresh_term_counts(ARRAY[OLD.parent_id]);
        END IF;
        RETURN NEW;
      END;
      $fn$ LANGUAGE plpgsql;

      CREATE TRIGGER terms_maintain_counts_on_reparent
        AFTER UPDATE OF parent_id ON terms
        FOR EACH ROW WHEN (OLD.parent_id IS DISTINCT FROM NEW.parent_id)
        EXECUTE FUNCTION classification_term_reparent_counts();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS terms_maintain_counts_on_reparent ON terms;
      DROP TRIGGER IF EXISTS posts_maintain_term_counts ON posts;
      DROP TRIGGER IF EXISTS term_assignments_maintain_counts ON term_assignments;
      DROP FUNCTION IF EXISTS classification_term_reparent_counts();
      DROP FUNCTION IF EXISTS classification_post_counts();
      DROP FUNCTION IF EXISTS classification_assignment_counts();
      DROP FUNCTION IF EXISTS classification_refresh_term_counts(bigint[]);
      DROP FUNCTION IF EXISTS classification_term_count(bigint);
    SQL
  end
end
