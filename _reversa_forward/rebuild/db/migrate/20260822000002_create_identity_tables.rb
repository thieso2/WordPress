# frozen_string_literal: true

# AGG-User — Identity context. Global scope: shared across sites under multisite
# (Wave 5, BR-MS-01). target_data_model.md § IDENTITY.
class CreateIdentityTables < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE users (
          id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          login           citext      NOT NULL,
          email           citext      NOT NULL,
          password_digest text        NOT NULL,
          nicename        citext      NOT NULL,
          display_name    text        NOT NULL DEFAULT '',
          url             text,
          status          text        NOT NULL DEFAULT 'active',
          registered_at   timestamptz NOT NULL DEFAULT now(),
          activation_key_digest text,
          locale          text,
          created_at      timestamptz NOT NULL DEFAULT now(),
          updated_at      timestamptz NOT NULL DEFAULT now()
      );
      -- Legacy has only non-unique KEYs on user_login / user_email. These are UNIQUE.
      CREATE UNIQUE INDEX users_login_key    ON users (login);
      CREATE UNIQUE INDEX users_email_key    ON users (email);
      CREATE UNIQUE INDEX users_nicename_key ON users (nicename);

      -- Replaces usermeta['{prefix}capabilities'], a serialized role=>true map (BR-CAP-13, F-MS-04).
      CREATE TABLE role_assignments (
          id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          user_id  bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          role     text   NOT NULL,
          site_id  bigint,                       -- NULL = single-site / network-wide
          granted_at timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX role_assignments_unique ON role_assignments (user_id, role, coalesce(site_id, 0));

      -- Replaces usermeta['session_tokens'] (BR-AUTH-15).
      CREATE TABLE sessions (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          user_id      bigint      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          token_digest text        NOT NULL,
          ip           inet,
          user_agent   text,
          expires_at   timestamptz NOT NULL,
          created_at   timestamptz NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX sessions_token_key ON sessions (token_digest);
      CREATE INDEX sessions_user_expiry ON sessions (user_id, expires_at);

      CREATE TABLE application_passwords (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          user_id      bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          name         text   NOT NULL,
          digest       text   NOT NULL,
          last_used_at timestamptz,
          last_ip      inet,
          created_at   timestamptz NOT NULL DEFAULT now()
      );

      CREATE TABLE data_requests (
          id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
          user_id      bigint REFERENCES users(id) ON DELETE SET NULL,
          email        citext NOT NULL,
          kind         text   NOT NULL CHECK (kind IN ('export','erasure')),
          status       text   NOT NULL DEFAULT 'pending',
          confirmed_at timestamptz,
          completed_at timestamptz,
          created_at   timestamptz NOT NULL DEFAULT now()
      );
    SQL
  end

  def down
    execute "DROP TABLE data_requests, application_passwords, sessions, role_assignments, users CASCADE;"
  end
end
