# frozen_string_literal: true

# AD-02 completes for `wp_navigation`: the corpus's `wp_navigation` post (a document of
# block markup — tools/seed.php seeds `block-navigation`, content
# `<!-- wp:navigation-link {"label":"Home"} /-->`) is what
# `WP_Navigation_Fallback::get_fallback()` (wp-includes/class-wp-navigation-fallback.php:70)
# hands `core/navigation` on every screen whose navigation carries no `ref`. The earlier
# pivot dropped those rows because the then-current corpus's most recent `wp_navigation`
# was the auto-created `<!-- wp:page-list /-->` default, which the page-list fallback
# already reproduced. The reseeded corpus keeps only the seeded `Home` document, so the
# rows are content, not machinery, and they land where the other block documents landed:
# `templates`, with their own `kind`.
#
# It is NOT a menu: AGG-Menu items require a target or a URL
# (`menu_items_one_target`), and `<!-- wp:navigation-link {"label":"Home"} /-->` has
# neither — the legacy renders it as a label-only `<a>` with no href.
class AllowNavigationKindInTemplates < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE templates DROP CONSTRAINT templates_kind_check;
      ALTER TABLE templates ADD CONSTRAINT templates_kind_check
        CHECK (kind = ANY (ARRAY['template'::text, 'part'::text, 'navigation'::text]));
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM templates WHERE kind = 'navigation';
      ALTER TABLE templates DROP CONSTRAINT templates_kind_check;
      ALTER TABLE templates ADD CONSTRAINT templates_kind_check
        CHECK (kind = ANY (ARRAY['template'::text, 'part'::text]));
    SQL
  end
end
