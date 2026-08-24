# frozen_string_literal: true

# Companion to 20260822000060, which dropped the assets.attached_to_id foreign key to
# break the Publishing <-> Library cycle.
#
# ⚠️ Dropping the constraint also dropped its ON DELETE SET NULL, and that was NOT part of
# the ruling. The two are separable and should be separated:
#
#   * The FK was creating a dependency EDGE. That is what had to go.
#   * The SET NULL was specified BEHAVIOUR. target_data_model.md's opening claim is that
#     "foreign keys exist — the legacy has none anywhere (F-DD-01); all 18 relationships
#     are enforced in PHP or not at all", and a declared delete rule is the whole point.
#
# Verified against the oracle: WordPress does NOT null it. Deleting a post leaves its
# attachment with a dangling `post_parent` pointing at a row that no longer exists — the
# legacy behaviour F-DD-01 predicts. So nulling is a deliberate DEVIATION the data model
# chose, and losing it would have been a silent regression to the legacy's defect, dressed
# up as a topology fix.
#
# A trigger restores the behaviour without restoring the edge: it lives in the database,
# so no Ruby constant in Library ever names Publishing.
class RestoreAssetDetachOnPostDelete < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION detach_assets_from_deleted_post() RETURNS trigger AS $$
      BEGIN
        UPDATE assets SET attached_to_id = NULL WHERE attached_to_id = OLD.id;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER posts_detach_assets
        BEFORE DELETE ON posts
        FOR EACH ROW EXECUTE FUNCTION detach_assets_from_deleted_post();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS posts_detach_assets ON posts;
      DROP FUNCTION IF EXISTS detach_assets_from_deleted_post();
    SQL
  end
end
