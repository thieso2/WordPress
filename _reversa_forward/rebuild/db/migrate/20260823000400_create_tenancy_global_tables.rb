# frozen_string_literal: true

# Wave 5 — the GLOBAL tenancy registry (target_data_model.md :583: `wp_blogs`, `wp_blogmeta`,
# `wp_site`, `wp_sitemeta`, `wp_signups` were "deferred to Wave 5 tenancy; the schema-per-site
# model replaces most of them"). These three tables live in the shared/global schema and are
# read/written before any tenant is known, so they are never tenant-scoped.
#
# ⚠️ STRICTLY ADDITIVE: this migration only CREATEs new tables. It touches nothing in Waves
# 0–4, so applying it leaves single-site parity untouched — with multisite off these tables
# simply sit unused in `public`.
class CreateTenancyGlobalTables < ActiveRecord::Migration[8.1]
  def change
    # A site = a PostgreSQL schema (BR-MS-01). Replaces wp_blogs + wp_site.
    create_table :sites do |t|
      t.string  :schema_name, null: false
      t.string  :domain,      null: false
      t.string  :path,        null: false, default: "/"
      t.string  :name,        null: false, default: ""
      t.boolean :public,      null: false, default: true   # privacy (blog_public)
      t.boolean :archived,    null: false, default: false
      t.boolean :deleted,     null: false, default: false
      t.boolean :spam,        null: false, default: false
      t.timestamp :registered_at
      t.timestamps
    end
    add_index :sites, :schema_name, unique: true
    add_index :sites, %i[domain path], unique: true

    # Pending signups — replaces wp_signups. Consumed by /activate (Tenancy::Signup#activate!).
    create_table :signups do |t|
      t.string  :kind,           null: false, default: "blog"   # "user" | "blog"
      t.string  :user_login,     null: false
      t.string  :user_email,     null: false
      t.string  :domain
      t.string  :path
      t.string  :title
      t.string  :activation_key, null: false
      t.datetime :activated_at
      t.references :site, foreign_key: true, null: true
      t.jsonb   :meta, null: false, default: {}
      t.timestamps
    end
    add_index :signups, :activation_key, unique: true
    add_index :signups, :user_login

    # Network-wide options — replaces wp_sitemeta (BR-MS-08). The per-site half (wp_blogmeta)
    # is just Configuration::Setting inside each tenant schema, so it needs nothing new.
    create_table :network_settings do |t|
      t.string :name, null: false
      t.jsonb  :value
      t.timestamps
    end
    add_index :network_settings, :name, unique: true
  end
end
