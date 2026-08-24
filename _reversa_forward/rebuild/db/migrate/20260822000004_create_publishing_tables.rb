# frozen_string_literal: true

# AGG-Post — Publishing context.
# AD-02: STI over CONTENT types only; the eleven machinery post types get tables
# shaped like what they are. AD-03: core-owned postmeta keys became columns.
# AD-07: one UTC timestamptz per event; NULL replaces '0000-00-00 00:00:00'.
class CreatePublishingTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TYPE post_status AS ENUM
          ('auto_draft','draft','pending','scheduled','published','private','trashed');

      CREATE TABLE posts (
          id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          type                text        NOT NULL DEFAULT 'Publishing::Article',  -- STI discriminator
          author_id           bigint      REFERENCES users(id) ON DELETE SET NULL,
          parent_id           bigint      REFERENCES posts(id) ON DELETE CASCADE,
          featured_asset_id   bigint,     -- FK added after assets; replaces postmeta '_thumbnail_id'
          title               text        NOT NULL DEFAULT '',
          slug                text,       -- NULL until allocated: drafts have none (BR-MIGRATE-032)
          content             text        NOT NULL DEFAULT '',
          excerpt             text        NOT NULL DEFAULT '',
          status              post_status NOT NULL DEFAULT 'draft',
          published_at        timestamptz,
          modified_at         timestamptz NOT NULL DEFAULT now(),
          trashed_at          timestamptz,
          status_before_trash post_status,               -- replaces postmeta '_wp_trash_meta_status'
          comment_status      text        NOT NULL DEFAULT 'open',
          password_digest     text,
          menu_order          integer     NOT NULL DEFAULT 0,
          guid                uuid        NOT NULL DEFAULT gen_random_uuid(),  -- DEVIATION BR-POST-10
          template_slug       text,                       -- replaces postmeta '_wp_page_template'
          comment_count       integer     NOT NULL DEFAULT 0,   -- counter cache
          attributes          jsonb       NOT NULL DEFAULT '{}'::jsonb,
          created_at          timestamptz NOT NULL DEFAULT now(),
          updated_at          timestamptz NOT NULL DEFAULT now(),

          -- Trash state is all-or-nothing.
          CONSTRAINT posts_trash_consistent CHECK (
              (trashed_at IS NULL     AND status_before_trash IS NULL) OR
              (trashed_at IS NOT NULL AND status_before_trash IS NOT NULL)),
          -- A published or scheduled record has a publication instant; a draft need not.
          CONSTRAINT posts_published_at_present CHECK (
              status NOT IN ('published','scheduled') OR published_at IS NOT NULL),
          -- BR-MIGRATE-035: 200 bytes INCLUDING any numeric suffix.
          CONSTRAINT posts_slug_length CHECK (slug IS NULL OR octet_length(slug) <= 200)
      );

      -- AD-05: replaces wp_unique_post_slug()'s query-per-attempt loop (F-POST-03).
      CREATE UNIQUE INDEX posts_slug_hierarchical
          ON posts (type, coalesce(parent_id, 0), slug) WHERE slug IS NOT NULL;

      -- Legacy's two composite indexes, kept: the schema was tuned for exactly these clauses (F-DD-04).
      CREATE INDEX posts_type_status_published ON posts (type, status, published_at DESC NULLS LAST, id);
      CREATE INDEX posts_type_status_author    ON posts (type, status, author_id);
      CREATE INDEX posts_parent                ON posts (parent_id);
      -- TD-07 / F-DD-02: the legacy never indexes meta_value. This one does.
      CREATE INDEX posts_attributes_gin        ON posts USING gin (attributes jsonb_path_ops);

      -- AD-02: split out of wp_posts. A revision is an audit record, not content.
      CREATE TABLE revisions (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          post_id    bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
          author_id  bigint REFERENCES users(id) ON DELETE SET NULL,
          title      text   NOT NULL DEFAULT '',
          content    text   NOT NULL DEFAULT '',
          excerpt    text   NOT NULL DEFAULT '',
          autosave   boolean NOT NULL DEFAULT false,
          created_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX revisions_post ON revisions (post_id, created_at DESC);

      -- AD-03: the RESIDUAL bucket only. Every core-owned key became a column above.
      CREATE TABLE post_attributes (
          id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          post_id bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
          key     text   NOT NULL,
          value   jsonb  NOT NULL
      );
      -- AD-05: replaces add_metadata()'s SELECT COUNT(*) then INSERT with nothing behind it (F-META-02).
      CREATE UNIQUE INDEX post_attributes_unique ON post_attributes (post_id, key);

      -- Replaces the transition_post_status action: a row, not a broadcast (AD-01).
      CREATE TABLE post_status_transitions (
          id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          post_id     bigint      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
          from_status post_status,
          to_status   post_status NOT NULL,
          actor_id    bigint      REFERENCES users(id) ON DELETE SET NULL,
          occurred_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX post_status_transitions_post ON post_status_transitions (post_id, occurred_at DESC);
    SQL
  end

  def down
    execute "DROP TABLE post_status_transitions, post_attributes, revisions, posts CASCADE; DROP TYPE post_status;"
  end
end
