# frozen_string_literal: true

# Composition — split out of wp_posts (AD-02): wp_template, wp_template_part, wp_block.
class CreateCompositionTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE templates (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          theme_slug text NOT NULL,
          slug       text NOT NULL,
          area       text,                       -- template parts only
          kind       text NOT NULL CHECK (kind IN ('template','part')),
          content    text NOT NULL DEFAULT '',
          updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX templates_unique ON templates (theme_slug, kind, slug);

      CREATE TABLE patterns (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          slug       text NOT NULL,
          title      text NOT NULL,
          content    text NOT NULL DEFAULT '',
          categories text[] NOT NULL DEFAULT '{}',
          updated_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX patterns_slug_key ON patterns (slug);
    SQL
  end

  def down
    execute "DROP TABLE patterns, templates CASCADE;"
  end
end
