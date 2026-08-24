# frozen_string_literal: true

# AGG-Menu + Presentation::Theme.
# BR-MENU-02: the nine _menu_item_* postmeta keys become columns; the real FK to
# menus deletes both the orphan problem and the _menu_item_orphaned tombstone (BR-MENU-05).
class CreatePresentationTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE menus (
          id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          name     text NOT NULL,
          slug     text NOT NULL,
          location text
      );
      CREATE UNIQUE INDEX menus_slug_key ON menus (slug);

      CREATE TABLE menu_items (
          id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          menu_id     bigint  NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
          parent_id   bigint  REFERENCES menu_items(id) ON DELETE CASCADE,
          position    integer NOT NULL DEFAULT 0,
          target_type text,           -- 'Publishing::Post' | 'Classification::Term' | NULL for custom
          target_id   bigint,
          url         text,
          label       text NOT NULL DEFAULT '',
          title       text NOT NULL DEFAULT '',
          css_classes text[] NOT NULL DEFAULT '{}',
          xfn         text NOT NULL DEFAULT '',
          -- Exactly one of: an internal target, or a custom URL. Never both, never neither.
          CONSTRAINT menu_items_one_target CHECK (
              (target_type IS NOT NULL AND target_id IS NOT NULL AND url IS NULL) OR
              (target_type IS NULL     AND target_id IS NULL     AND url IS NOT NULL))
      );
      CREATE INDEX menu_items_menu ON menu_items (menu_id, position);

      CREATE TABLE themes (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          slug         text NOT NULL,
          parent_slug  text,
          version      text NOT NULL,
          active       boolean NOT NULL DEFAULT false
      );
      CREATE UNIQUE INDEX themes_slug_key ON themes (slug);
    SQL
  end

  def down
    execute "DROP TABLE themes, menu_items, menus CASCADE;"
  end
end
