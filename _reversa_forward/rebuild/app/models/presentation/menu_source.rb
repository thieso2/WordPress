# frozen_string_literal: true

module Presentation
  # The role `core/navigation` needs, so that Composition does not have to name
  # Presentation to render a menu.
  #
  # ⚠️ topology_decision.md, the rule bin/check_cycles enforces: Presentation may depend
  # on Composition (the theme resolves a template and renders it); Composition may not
  # depend back. But `core/navigation` genuinely needs AGG-Menu — T-04 pivoted the
  # legacy's `wp_navigation` posts and nine `_menu_item_*` postmeta keys into it — so the
  # need is real and the direction is wrong.
  #
  # Composition::RenderContext#context is the seam that already exists for exactly this:
  # the block schemas' `usesContext` is the legacy's own way of saying "a renderer is
  # HANDED what it needs rather than fetching it". Presentation::Page puts this object in
  # under the key `menuSource`; the navigation renderer asks it for a menu and never
  # learns which namespace answered. No `Presentation::` constant appears in Composition,
  # and the dependency points the way the topology says it must.
  class MenuSource
    # `WP_Navigation_Fallback::get_fallback()`, wp-includes/class-wp-navigation-fallback.php:70.
    # The legacy's fallback chain is:
    #   1. the most recently published `wp_navigation` POST;
    #   2. else convert the classic `nav_menu` term into one — which WRITES a post;
    #   3. else create a default one whose content is `<!-- wp:page-list /-->`.
    #
    # Step 1 no longer resolves HERE: `wp_navigation` posts are documents of block
    # markup, not menus (a label-only item has neither target nor URL, which AGG-Menu's
    # `menu_items_one_target` forbids), so AD-02 pivots them into `Composition::Template`
    # kind "navigation" and the navigation renderer reads them itself
    # (navigation_blocks.rb `fallback_blocks`). The reseeded corpus keeps exactly one —
    # the seeded `block-navigation` Home link — so step 1 answers on every screen.
    #
    # This method is step 2's read-only stand-in: the classic menu that WOULD be
    # converted if no navigation document existed. In the oracle, step 1 always answers,
    # so the classic `Oracle Primary Menu` is never converted and never rendered —
    # returning nil reproduces that, and step 2's write stays unwritten
    # (migration_strategy.md: the fallback conversion is not a front-end concern).
    def default = nil

    # A `ref`/`navigationMenuId` attribute, which in the legacy is a `wp_navigation`
    # post id. Both the id and the slug are accepted because AD-02 gave menus a slug.
    def find(ref)
      return nil if ref.blank?

      Menu.find_by(id: ref) || Menu.find_by(slug: ref.to_s)
    end
  end
end
