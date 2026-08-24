# frozen_string_literal: true

# AGG-Comment — Discussion context. BR-CMT-12: status is an enum, not a varchar.
# comment_rate_limits is NEW: deviation BR-CMT-04, the legacy enforces no rate limit at all.
class CreateDiscussionTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TYPE comment_status AS ENUM ('pending','approved','spam','trashed');

      CREATE TABLE comments (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          post_id      bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
          parent_id    bigint REFERENCES comments(id) ON DELETE CASCADE,
          user_id      bigint REFERENCES users(id) ON DELETE SET NULL,
          author_name  text   NOT NULL DEFAULT '',
          author_email citext,
          author_url   text,
          author_ip    inet,
          user_agent   text,
          content      text   NOT NULL,
          status       comment_status NOT NULL DEFAULT 'pending',   -- BR-CMT-12: enum, not varchar
          kind         text   NOT NULL DEFAULT 'comment',
          submitted_at timestamptz NOT NULL DEFAULT now(),
          created_at   timestamptz NOT NULL DEFAULT now(),
          updated_at   timestamptz NOT NULL DEFAULT now()
      );
      CREATE INDEX comments_post_status ON comments (post_id, status, submitted_at DESC);
      CREATE INDEX comments_parent      ON comments (parent_id);
      -- F-DD-06: the legacy indexes comment_author_email to only 10 characters. Full index here.
      CREATE INDEX comments_author_email ON comments (author_email);

      CREATE TABLE moderation_verdicts (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          comment_id bigint NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
          outcome    text   NOT NULL,
          reason     text   NOT NULL,
          decided_by bigint REFERENCES users(id) ON DELETE SET NULL,
          decided_at timestamptz NOT NULL DEFAULT now()
      );

      -- NEW: deviation BR-CMT-04.
      CREATE TABLE comment_rate_limits (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          author_key   text        NOT NULL,
          window_start timestamptz NOT NULL,
          count        integer     NOT NULL DEFAULT 0
      );
      CREATE UNIQUE INDEX comment_rate_limits_key ON comment_rate_limits (author_key, window_start);
    SQL
  end

  def down
    execute "DROP TABLE comment_rate_limits, moderation_verdicts, comments CASCADE; DROP TYPE comment_status;"
  end
end
