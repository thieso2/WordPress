# frozen_string_literal: true

# Owner ruling, 2026-08-22 — resolves the conflict bin/check_cycles surfaced in Wave 0.
#
# target_data_model.md specifies foreign keys in BOTH directions between posts and assets:
#   * posts.featured_asset_id -> assets.id   (AD-03: postmeta '_thumbnail_id' promoted)
#   * assets.attached_to_id   -> posts.id    (the legacy attachment's post_parent)
# target_architecture.md's dependency graph has no room for both, and no amount of code
# arrangement removes a cycle that the schema itself asserts.
#
# The ruling keeps `posts.featured_asset_id`, because AD-03 names it explicitly and it is a
# real structural relationship: a post displays one asset. `assets.attached_to_id` becomes a
# plain column — it records the legacy's `post_parent`, which for an attachment means only
# "uploaded while editing this post". That is provenance, not structure, and it is exactly
# the weaker of the two.
#
# ⚠️ Consequence for target_architecture.md: the surviving arrow is Publishing -> Library,
# which is the REVERSE of the direction its prose lists ("Classification, Discussion,
# Library, Routing -> Publishing"). The graph is acyclic either way; the document is
# amended rather than the schema, because AD-03 is the more specific decision.
class DropAssetsAttachedToForeignKey < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE assets DROP CONSTRAINT IF EXISTS assets_attached_to_id_fkey;
      COMMENT ON COLUMN assets.attached_to_id IS
        'Legacy post_parent: the post being edited at upload time. Provenance, not structure. '
        'Deliberately NOT a foreign key — see db/migrate/20260822000060 and the owner ruling '
        'that broke the Publishing <-> Library cycle.';
    SQL
  end

  def down
    execute <<~SQL
      COMMENT ON COLUMN assets.attached_to_id IS NULL;
      ALTER TABLE assets ADD CONSTRAINT assets_attached_to_id_fkey
        FOREIGN KEY (attached_to_id) REFERENCES posts(id) ON DELETE SET NULL;
    SQL
  end
end
