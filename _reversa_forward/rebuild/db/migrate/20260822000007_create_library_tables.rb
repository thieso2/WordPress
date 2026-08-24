# frozen_string_literal: true

# AGG-Asset — Library context. Split out of wp_posts by AD-02; in the legacy the
# whole model lived in four _wp_attachment* / _thumbnail_id postmeta keys.
class CreateLibraryTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE assets (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          uploader_id  bigint REFERENCES users(id) ON DELETE SET NULL,
          attached_to_id bigint REFERENCES posts(id) ON DELETE SET NULL,
          title        text   NOT NULL DEFAULT '',
          slug         text   NOT NULL,
          alt_text     text   NOT NULL DEFAULT '',   -- postmeta '_wp_attachment_image_alt'
          caption      text   NOT NULL DEFAULT '',
          mime_type    text   NOT NULL,
          byte_size    bigint NOT NULL,
          width        integer,
          height       integer,
          metadata     jsonb  NOT NULL DEFAULT '{}'::jsonb,  -- EXIF etc.
          created_at   timestamptz NOT NULL DEFAULT now(),
          updated_at   timestamptz NOT NULL DEFAULT now()
      );
      -- BR-MIGRATE-033: attachment slugs are unique across ALL types in the legacy.
      CREATE UNIQUE INDEX assets_slug_key ON assets (slug);
      CREATE INDEX assets_attached_to ON assets (attached_to_id);

      CREATE TABLE asset_variants (
          id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          asset_id  bigint NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
          size_name text   NOT NULL,
          width     integer NOT NULL,
          height    integer NOT NULL,
          mime_type text   NOT NULL
      );
      CREATE UNIQUE INDEX asset_variants_unique ON asset_variants (asset_id, size_name);

      -- Deferred FK: posts.featured_asset_id -> assets.id (replaces postmeta '_thumbnail_id').
      ALTER TABLE posts ADD CONSTRAINT posts_featured_asset_fk
          FOREIGN KEY (featured_asset_id) REFERENCES assets(id) ON DELETE SET NULL;
    SQL
  end

  def down
    execute "ALTER TABLE posts DROP CONSTRAINT posts_featured_asset_fk; DROP TABLE asset_variants, assets CASCADE;"
  end
end
