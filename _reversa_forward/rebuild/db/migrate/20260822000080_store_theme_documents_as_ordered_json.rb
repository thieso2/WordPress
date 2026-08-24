# frozen_string_literal: true

# A theme.json is an ORDERED document, and `jsonb` is not.
#
# PostgreSQL's `jsonb` normalizes every object: duplicate keys collapse and the remaining
# keys are re-ordered by (length, byte value). For most documents that is a feature. For
# this one it is data loss, because `WP_Theme_JSON::get_stylesheet()` walks
# `styles.blocks` in the order the file declares and emits one CSS ruleset per key in that
# order (class-wp-theme-json.php:3534). Round-tripping twentytwentyfive's theme.json
# through `jsonb` turns
#
#   core/avatar, core/button, core/columns, …, core/site-tagline, core/site-title
#
# into
#
#   core/code, core/list, core/quote, core/avatar, …
#
# and the global-styles stylesheet comes out in that order — same bytes, wrong sequence,
# which in CSS is a different stylesheet. It is visible in `bin/parity_diff web.index`
# the moment the generator exists to produce those rulesets at all.
#
# `json` stores the text as given, so insertion order survives Rails' round trip. Nothing
# queries either column with a `jsonb` operator (both are read whole, by
# `Presentation::Theme#resolver`), so the containment/indexing that `jsonb` buys is not
# being given up — it was never used.
#
# ⚠️ The cast preserves the CURRENT bytes, which for any row written before this migration
# are already in `jsonb` order. `rake theme:load` must be re-run to restore the file's
# order; it is idempotent and reads `db/theme/theme.json`, which is generated straight
# from the theme directory and does preserve it.
class StoreThemeDocumentsAsOrderedJson < ActiveRecord::Migration[8.1]
  def up
    change_column :themes, :theme_json, :json, null: false, default: {}
    change_column :themes, :user_styles, :json, null: true
  end

  def down
    change_column :themes, :theme_json, :jsonb, null: false, default: {}
    change_column :themes, :user_styles, :jsonb, null: true
  end
end
