# frozen_string_literal: true

# AGG-Term — Classification context. `terms` + `term_taxonomy` collapse into one model;
# `taxonomy` is promoted from a string column to a record.
class CreateClassificationTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE taxonomies (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          name         text    NOT NULL,
          hierarchical boolean NOT NULL DEFAULT false,
          object_types text[]  NOT NULL DEFAULT '{}'
      );
      CREATE UNIQUE INDEX taxonomies_name_key ON taxonomies (name);

      CREATE TABLE terms (
          id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          taxonomy_id bigint NOT NULL REFERENCES taxonomies(id) ON DELETE CASCADE,
          parent_id   bigint REFERENCES terms(id) ON DELETE CASCADE,
          name        text   NOT NULL,
          slug        text   NOT NULL,
          description text   NOT NULL DEFAULT '',
          count       integer NOT NULL DEFAULT 0,   -- counter cache: PUBLISHED only (BR-TAX-11)
          created_at  timestamptz NOT NULL DEFAULT now(),
          updated_at  timestamptz NOT NULL DEFAULT now(),
          CONSTRAINT terms_not_self_parent CHECK (parent_id IS DISTINCT FROM id)
      );
      -- AD-05: the constraint wp_insert_term() guards but the legacy schema does NOT have (F-DD-05).
      CREATE UNIQUE INDEX terms_unique ON terms (taxonomy_id, coalesce(parent_id, 0), slug);
      CREATE INDEX terms_parent ON terms (parent_id);

      CREATE TABLE term_assignments (
          id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          term_id           bigint NOT NULL REFERENCES terms(id) ON DELETE CASCADE,
          classifiable_type text   NOT NULL,   -- 'Publishing::Post' | 'Library::Asset'
          classifiable_id   bigint NOT NULL,
          position          integer NOT NULL DEFAULT 0
      );
      CREATE UNIQUE INDEX term_assignments_unique
          ON term_assignments (term_id, classifiable_type, classifiable_id);
      CREATE INDEX term_assignments_target ON term_assignments (classifiable_type, classifiable_id);
    SQL
  end

  def down
    execute "DROP TABLE term_assignments, terms, taxonomies CASCADE;"
  end
end
