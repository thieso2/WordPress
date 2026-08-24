# frozen_string_literal: true

# Routing::Redirect replaces postmeta '_wp_old_slug' / '_wp_old_date' (AD-03).
# Syndication::EmbedCache: the oEmbed cache was a POST TYPE in the legacy. It is a cache.
class CreateRoutingAndSyndicationTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE redirects (
          id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          from_path   text   NOT NULL,
          post_id     bigint REFERENCES posts(id) ON DELETE CASCADE,
          recorded_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX redirects_from_key ON redirects (from_path);

      CREATE TABLE embed_caches (
          id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          url_digest text  NOT NULL,
          payload    jsonb NOT NULL,
          fetched_at timestamptz NOT NULL DEFAULT now(),
          expires_at timestamptz NOT NULL
      );
      CREATE UNIQUE INDEX embed_caches_url_key ON embed_caches (url_digest);
      CREATE INDEX embed_caches_expiry ON embed_caches (expires_at);
    SQL
  end

  def down
    execute "DROP TABLE embed_caches, redirects CASCADE;"
  end
end
