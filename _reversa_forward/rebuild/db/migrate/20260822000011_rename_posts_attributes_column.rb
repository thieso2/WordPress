# frozen_string_literal: true

# ⚠️ SCHEMA DEVIATION from target_data_model.md § PUBLISHING — found in Wave 0.
#
# The spec's DDL names AD-03's residual metadata bucket `posts.attributes`. That column
# name cannot be used under the chosen paradigm: `attributes` is an ActiveRecord::Base
# instance method, and defining an attribute over it raises
# ActiveRecord::DangerousAttributeError at class-definition time. Publishing::Post is
# unloadable with the column as specified.
#
# This is exactly the class of finding data_migration_plan.md § Notes predicts:
#
#   > Its more valuable job is to be the first honest test of target_data_model.md ...
#   > A constraint that is wrong ... fails here, in Wave 0, rather than in Wave 3.
#
# The column is renamed; nothing else about AD-03 changes. The GIN index
# (TD-07 / F-DD-02 — the legacy never indexes meta_value, this one does) follows the
# column and keeps its jsonb_path_ops operator class.
class RenamePostsAttributesColumn < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE posts RENAME COLUMN attributes TO residual_attributes;
      ALTER INDEX posts_attributes_gin RENAME TO posts_residual_attributes_gin;
    SQL
  end

  def down
    execute <<~SQL
      ALTER INDEX posts_residual_attributes_gin RENAME TO posts_attributes_gin;
      ALTER TABLE posts RENAME COLUMN residual_attributes TO attributes;
    SQL
  end
end
