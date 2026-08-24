# frozen_string_literal: true

# Wave 0 · target_data_model.md § Schema (DDL)
# `citext` backs the case-insensitive uniqueness the legacy enforced in PHP
# (users.login, users.email, comments.author_email); `pgcrypto` backs
# gen_random_uuid() for posts.guid (deviation BR-POST-10 / BR-MIGRATE-037).
class EnableExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext"
    enable_extension "pgcrypto"
  end
end
