# frozen_string_literal: true

require "rails_helper"
require_relative "navigation_oracle"

# DIFFERENTIAL specs for the navigation + search + media family.
#
# Every expectation below is `rebuild == oracle`, byte for byte. None of them encodes
# this agent's reading of the PHP, which is the point: parity_specs.md sets the bar at
# "zero unexplained divergence", and a hand-written expectation can only ever assert that
# the code does what the person who wrote both thought it did.
# ⚠️ Run this file against a PRIVATE database when anything else may be running:
#
#     RAILS_ENV=test DATABASE_URL=postgres:///rebuild_test_mine bundle exec rspec \
#       spec/models/composition/navigation_blocks_spec.rb
#
# `bin/parity_worker` records the reason — two suites sharing `rebuild_test` deadlock each
# other and invent divergences the code does not have. This file's `seed!` takes a lock on
# `posts`, which is exactly the shape that collides.
RSpec.describe Composition::Renderers::NavigationBlocks do
  before do
    skip "oracle not reachable (php + tools/_bootstrap.php)" unless NavigationOracle.available?

    # ⚠️ before(:each), never before(:all): `use_transactional_fixtures` wraps each
    # EXAMPLE in a transaction, so a before(:all) load lands outside it and leaks.
    NavigationOracle.seed!
  end

  # Renders `markup` through both systems in the same starting state and compares.
  #
  # `page_path` puts both on the same queried page — the oracle by setting
  # `$wp_query->queried_object`, the rebuild by handing the record to RenderContext. That
  # is what `current-menu-item` and `current-menu-ancestor` depend on, and the two systems
  # assign different primary keys, so the page is named by PATH rather than by id.
  def expect_identical(markup, query: nil, page_path: nil)
    post = page_path && Publishing::Page.find_by(slug: page_path.split("/").last)
    oracle = NavigationOracle.render(markup, query: query, page_path: page_path)
    rebuild = NavigationOracle.rebuild(markup, query: query, post: post)
    expect(rebuild).to eq(oracle)
  end

  describe "core/template-part" do
    it "renders the theme's header part, tag and wrapper included" do
      expect_identical('<!-- wp:template-part {"slug":"header"} /-->')
    end

    it "renders the theme's footer part, including its two sibling navigations" do
      expect_identical('<!-- wp:template-part {"slug":"footer"} /-->')
    end

    # template-part.php:155 — an explicit tagName replaces the area's tag.
    it "honours tagName" do
      expect_identical('<!-- wp:template-part {"slug":"header","tagName":"section"} /-->')
    end

    # template-part.php:27 — a part belonging to another theme is not rendered at all.
    it "renders nothing for a foreign theme" do
      expect_identical('<!-- wp:template-part {"slug":"header","theme":"other"} /-->')
    end

    # template-part.php:118 — WP_DEBUG is off, so a missing part is silent.
    it "renders nothing for a missing slug" do
      expect_identical('<!-- wp:template-part {"slug":"nope"} /-->')
    end
  end

  describe "core/pattern" do
    it "renders a theme pattern whose PHP printed translated strings" do
      expect_identical('<!-- wp:pattern {"slug":"twentytwentyfive/hidden-404"} /-->')
    end

    it "renders the hidden-search pattern" do
      expect_identical('<!-- wp:pattern {"slug":"twentytwentyfive/hidden-search"} /-->')
    end

    it "renders the hidden blog heading" do
      expect_identical('<!-- wp:pattern {"slug":"twentytwentyfive/hidden-blog-heading"} /-->')
    end

    # pattern.php:43 — an unregistered slug renders as nothing.
    it "renders nothing for an unregistered slug" do
      expect_identical('<!-- wp:pattern {"slug":"nope/nope"} /-->')
    end
  end

  describe "core/navigation" do
    # The header of every one of the 18 screens. No `ref`, so the block renders the
    # fallback chain (navigation.php:1479): the corpus's most recently published
    # `wp_navigation` document — the seeded `block-navigation`, one label-only Home
    # link — with the page-list only as the further fallback behind it.
    it "renders the responsive overlay navigation with the navigation-document fallback" do
      expect_identical('<!-- wp:navigation {"overlayBackgroundColor":"base",' \
                       '"overlayTextColor":"contrast","layout":{"type":"flex",' \
                       '"justifyContent":"right","flexWrap":"wrap"}} /-->')
    end

    # navigation.php:962 — the second navigation on a page is ' 2', the third ' 3'. This
    # is the $seen_menu_names static, and it only shows up with more than one block.
    it "numbers repeated navigation names across sibling blocks" do
      link = ->(label) { %(<!-- wp:navigation-link {"label":"#{label}","url":"#"} /-->) }
      nav = ->(inner) do
        '<!-- wp:navigation {"overlayMenu":"never","layout":{"type":"flex",' \
          "\"orientation\":\"vertical\"}} -->#{inner}<!-- /wp:navigation -->"
      end
      expect_identical(nav.call(link.call("Blog") + link.call("About")) + nav.call(link.call("Events")))
    end

    it "renders submenus opened on click" do
      expect_identical('<!-- wp:navigation {"submenuVisibility":"click","overlayMenu":"never"} -->' \
                       '<!-- wp:navigation-submenu {"label":"P","url":"#"} -->' \
                       '<!-- wp:navigation-link {"label":"C","url":"#"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation -->')
    end

    it "renders submenus that are always open, in an always-shown overlay" do
      expect_identical('<!-- wp:navigation {"submenuVisibility":"always","overlayMenu":"always",' \
                       '"hasIcon":false,"icon":"menu"} -->' \
                       '<!-- wp:navigation-submenu {"label":"P","url":"#"} -->' \
                       '<!-- wp:navigation-link {"label":"C","url":"#"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation -->')
    end

    it "omits the submenu indicator when showSubmenuIcon is false" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never","showSubmenuIcon":false} -->' \
                       '<!-- wp:navigation-submenu {"label":"P","url":"#"} -->' \
                       '<!-- wp:navigation-link {"label":"C","url":"#"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation -->')
    end

    # navigation.php:98 — core/site-title is one of the three blocks that get an <li>,
    # and the ariaLabel support puts aria-label on the inner <ul> as well as the <nav>.
    it "wraps a site-title child in a list item and labels both wrappers" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never","ariaLabel":"Main"} -->' \
                       '<!-- wp:site-title /-->' \
                       '<!-- wp:navigation-link {"label":"A","url":"#"} /-->' \
                       '<!-- /wp:navigation -->')
    end

    # The colour attributes are read with array_key_exists, and the overlay colours reach
    # the submenu <ul> through the block's context.
    it "applies named colours, overlay colours and a named font size" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never","textColor":"contrast",' \
                       '"backgroundColor":"base","overlayTextColor":"accent-1","fontSize":"small"} -->' \
                       '<!-- wp:navigation-submenu {"label":"Parent","url":"/p/","kind":"custom"} -->' \
                       '<!-- wp:navigation-link {"label":"Kid","url":"/k/"} /-->' \
                       '<!-- wp:navigation-submenu {"label":"Sub","url":"/s/"} -->' \
                       '<!-- wp:navigation-link {"label":"Deep","url":"/d/","opensInNewTab":true,' \
                       '"rel":"nofollow","title":"T","description":"D"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation-submenu -->' \
                       '<!-- wp:navigation-link {"label":"Top","url":"https://x.test/?q=%C3%A9"} /-->' \
                       '<!-- /wp:navigation -->')
    end

    # ⚠️ REGRESSION. get_block_wrapper_attributes() serializes the typography support
    # into a `style` attribute on BOTH the <nav> and the inner <ul>; a wrapper port that
    # implements only align/className/anchor drops it silently. `twentytwentyfive/
    # footer-social` ships exactly this shape, so it is theme content, not a synthetic.
    it "serializes the typography support onto both wrappers" do
      expect_identical('<!-- wp:navigation {"align":"wide","className":"my-nav","anchor":"nav1",' \
                       '"overlayMenu":"never","style":{"typography":{"textDecoration":"underline",' \
                       '"fontStyle":"italic","fontWeight":"700","letterSpacing":"2px",' \
                       '"textTransform":"uppercase"}}} -->' \
                       '<!-- wp:navigation-link {"label":"A","url":"#"} /-->' \
                       '<!-- /wp:navigation -->')
    end
  end

  describe "core/page-list" do
    # ⚠️ REGRESSION, same cause as the navigation typography case above: the colour and
    # font-size supports reach the <ul> only through get_block_wrapper_attributes().
    it "serializes the colour and font-size supports onto the list" do
      expect_identical('<!-- wp:page-list {"style":{"typography":{"fontSize":"18px"}},' \
                       '"className":"pl","fontSize":"small","textColor":"accent-1"} /-->')
    end

    it "renders the whole page tree standalone" do
      expect_identical("<!-- wp:page-list /-->")
    end

    # page-list.php:155 — the queried page is `current-menu-item` and carries
    # aria-current="page". This is the one thing on web.page that the home screen's
    # header does not exercise.
    it "marks the queried page as the current item" do
      expect_identical("<!-- wp:page-list /-->", page_path: "parent-page")
    end

    # page-list.php:159 — and every ancestor of it is `current-menu-ancestor`.
    it "marks the ancestors of the queried page" do
      expect_identical("<!-- wp:page-list /-->", page_path: "parent-page/child-page/grandchild-page")
    end

    it "renders only the children of parentPageID when one is given" do
      parent = Publishing::Page.find_by(slug: "parent-page")
      oracle_id = NavigationOracle.corpus["pages"].find { |p| p["slug"] == "parent-page" }["id"]
      oracle = NavigationOracle.render(%(<!-- wp:page-list {"parentPageID":#{oracle_id}} /-->))
      rebuild = NavigationOracle.rebuild(%(<!-- wp:page-list {"parentPageID":#{parent.id}} /-->))
      expect(rebuild).to eq(oracle)
    end
  end

  describe "core/navigation, on a page screen" do
    it "renders the theme header's navigation with the current page marked" do
      expect_identical('<!-- wp:navigation {"overlayBackgroundColor":"base",' \
                       '"overlayTextColor":"contrast","layout":{"type":"flex",' \
                       '"justifyContent":"right","flexWrap":"wrap"}} /-->', page_path: "parent-page")
    end
  end

  describe "core/navigation-submenu" do
    # navigation-submenu.php:275 — the submenu <ul> gets its colours from a colour
    # support applied to a block type whose schema does not declare one.
    it "applies NAMED overlay colours to the submenu container" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never","overlayTextColor":"contrast",' \
                       '"overlayBackgroundColor":"base"} -->' \
                       '<!-- wp:navigation-submenu {"label":"P","url":"#"} -->' \
                       '<!-- wp:navigation-link {"label":"C","url":"#"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation -->')
    end

    it "applies CUSTOM overlay colours as inline styles" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never","customTextColor":"#123456",' \
                       '"customOverlayBackgroundColor":"#abcdef","customFontSize":19} -->' \
                       '<!-- wp:navigation-submenu {"label":"P","url":"#"} -->' \
                       '<!-- wp:navigation-link {"label":"C","url":"#"} /-->' \
                       '<!-- /wp:navigation-submenu --><!-- /wp:navigation -->')
    end
  end

  describe "core/navigation-link" do
    # navigation-link/shared/item-should-render.php:17 — a post-type item whose target
    # does not exist (or is not published) drops out of the menu entirely.
    it "renders nothing for a post-type item whose target is missing" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never"} -->' \
                       '<!-- wp:navigation-link {"label":"Gone","kind":"post-type","type":"page",' \
                       '"id":99999,"url":"/x/"} /-->' \
                       '<!-- wp:navigation-link {"label":"Ok","url":"#"} /-->' \
                       '<!-- /wp:navigation -->')
    end

    # navigation.php:1017 — a navigation containing a navigation renders as nothing.
    it "refuses to render a nested navigation" do
      expect_identical('<!-- wp:navigation {"overlayMenu":"never"} -->' \
                       '<!-- wp:navigation {"overlayMenu":"never"} -->' \
                       '<!-- wp:navigation-link {"label":"x","url":"#"} /-->' \
                       '<!-- /wp:navigation --><!-- /wp:navigation -->')
    end
  end

  describe "core/search" do
    it "renders the theme's search block" do
      expect_identical('<!-- wp:search {"label":"Search","showLabel":false,' \
                       '"placeholder":"Type here...","buttonText":"Search"} /-->')
    end

    # search.php:21 — `<!-- wp:search /-->` still says "Search" twice.
    it "defaults label and buttonText when the block carries no attributes" do
      expect_identical("<!-- wp:search /-->")
    end

    it "puts the search query in the input's value" do
      expect_identical('<!-- wp:pattern {"slug":"twentytwentyfive/hidden-search"} /-->', query: { "s" => "article" })
    end

    it "renders the no-button variant" do
      expect_identical('<!-- wp:search {"buttonPosition":"no-button","label":"L"} /-->')
    end

    it "renders the expandable button-only variant with its directives" do
      expect_identical('<!-- wp:search {"buttonPosition":"button-only","buttonUseIcon":true} /-->')
    end

    # Exercises styles_for_block_core_search() end to end: width, borders, radius,
    # colours, and the FLUID font size that theme.json turns 20px into.
    it "renders the button-inside variant with borders, colours and typography" do
      expect_identical('<!-- wp:search {"showLabel":true,"label":"Find",' \
                       '"buttonPosition":"button-inside","buttonUseIcon":true,"width":50,' \
                       '"widthUnit":"%","style":{"border":{"radius":"8px","width":"2px",' \
                       '"color":"#ff0000"},"color":{"text":"#112233","background":"#eeeeee"},' \
                       '"typography":{"fontSize":"20px","letterSpacing":"1px",' \
                       '"textDecoration":"underline"}},"fontSize":"large",' \
                       '"borderColor":"accent-2"} /-->')
    end
  end

  describe "core/image" do
    # image.php:92 — an empty <figcaption> is removed, comments and all.
    it "drops an empty figcaption" do
      expect_identical('<!-- wp:image {"sizeSlug":"full","linkDestination":"none"} -->' \
                       '<figure class="wp-block-image size-full">' \
                       '<img src="http://127.0.0.1:8099/a.png" alt="x"/>' \
                       '<figcaption class="wp-element-caption"></figcaption></figure>' \
                       "<!-- /wp:image -->")
    end

    it "keeps a caption, a link and the align/className supports" do
      expect_identical('<!-- wp:image {"id":5,"sizeSlug":"large","linkDestination":"custom",' \
                       '"align":"center","className":"is-style-rounded"} -->' \
                       '<figure class="wp-block-image aligncenter size-large is-style-rounded">' \
                       '<a href="http://x/"><img src="http://127.0.0.1:8099/b.png" alt="" ' \
                       'class="wp-image-5"/></a>' \
                       '<figcaption class="wp-element-caption">Cap</figcaption></figure>' \
                       "<!-- /wp:image -->")
    end
  end

  describe "core/gallery" do
    # gallery.php:21 — the gallery stamps data-id on each inner image before it renders.
    it "passes data-id down to its inner image blocks" do
      expect_identical('<!-- wp:gallery {"columns":2,"linkTo":"none"} -->' \
                       '<figure class="wp-block-gallery has-nested-images columns-2 is-cropped">' \
                       '<!-- wp:image {"id":5,"sizeSlug":"large"} -->' \
                       '<figure class="wp-block-image size-large">' \
                       '<img src="http://127.0.0.1:8099/b.png" alt="" class="wp-image-5"/>' \
                       "</figure><!-- /wp:image --></figure><!-- /wp:gallery -->")
    end
  end

  # The whole 404 template: header template-part → pattern → columns → image → search →
  # footer template-part. It is the one screen in the corpus that exercises every block
  # in this family at once, and it is also what proves the shared wp_unique_id counter:
  # the navigation takes `modal-1`, so the search input further down the page is
  # `wp-block-search__input-2`.
  describe "the 404 template, end to end" do
    it "matches the oracle byte for byte" do
      path = "/workspace/WordPress/wp-content/themes/twentytwentyfive/templates/404.html"
      skip "theme not present" unless File.exist?(path)

      expect_identical(File.read(path))
    end
  end
end
