# frozen_string_literal: true

# AGG-Setting — Configuration context.
# AD-06: settings ONLY. The routing table and the job queue are structurally
# barred from this table; transients live in Rails.cache.
class CreateConfigurationTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE settings (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          name       text        NOT NULL,
          value      jsonb       NOT NULL,
          autoload   boolean     NOT NULL DEFAULT false,   -- explicit policy, never a size heuristic
          created_at timestamptz NOT NULL DEFAULT now(),
          updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX settings_name_key ON settings (name);
      CREATE INDEX settings_autoload ON settings (autoload) WHERE autoload;  -- cf. F-DD-09
    SQL
  end

  def down
    execute "DROP TABLE settings CASCADE;"
  end
end
