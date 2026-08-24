# frozen_string_literal: true

require "rails_helper"

# `wp_enqueue_stored_styles()`, wp-includes/script-loader.php:3307 — the seam between the
# block supports that WRITE layout rules while a template renders and the `<head>` that
# PRINTS them once, as `<style id="core-block-supports-inline-css">`.
#
# ⚠️ This file exists because that seam failed silently, and silently is the whole problem.
# `Presentation::Page#block_supports_css` reached for a process-global store registry that
# paradigm_decision.md implication 1 had removed, wrapped the call in `rescue StandardError
# => nil`, and so returned nil on every screen for every reason — including "the store is
# genuinely empty" and "the method you called does not exist". The rules were being
# collected correctly the whole time (layout_blocks_spec.rb:168 proves it against the
# oracle); nothing read them. 891 bytes per screen, on 16 of the 18 `web.*` screens, with
# no error anywhere.
#
# So the two halves are pinned separately: the writer→reader handoff without a database,
# and the exact bytes of the element against the oracle's own captured `<head>`.
RSpec.describe "the core-block-supports stylesheet element" do
  GOLDEN_DIR = Rails.root.join("spec/parity/golden")

  # Every `web.*` golden, and the element each one carries — nil where the oracle emits
  # none. Reading them rather than listing them keeps this honest if a golden is recaptured.
  def golden_element(name)
    html = File.read(GOLDEN_DIR.join("golden-web-#{name}.html"))
    html[/<style id="core-block-supports-inline-css">\n(.*?)\n\/\*# sourceURL=core-block-supports-inline-css \*\/\n<\/style>/m, 1]
  end

  # ── the writer → reader handoff ───────────────────────────────────────────────────
  #
  # No database: `theme_slug` is passed so the constructor never asks `Theme.active`, and
  # the screen is only ever read for `#post`. What is under test is one edge — that the
  # store `Page` reads is the store the supports wrote into — and that edge needs neither.
  describe "Presentation::Page#block_supports_css" do
    # `Page#context` now folds the conditional tags into the block context
    # (page.rb `screen_facts`), so the double answers every predicate it reads — all
    # false/nil, the 404-shaped screen, which is also the one with no queried object.
    let(:screen) do
      instance_double("Presentation::Screen", post: nil, archive?: false, search?: false,
                                              front_page?: false, home?: false, paged?: false,
                                              singular?: false, date?: false, queried_object: nil,
                                              search_query: nil)
    end
    let(:page) do
      Presentation::Page.new(screen: screen, site_url: "http://127.0.0.1:3100",
                             theme_slug: "twentytwentyfive")
    end

    it "reads the store the block supports write into during THIS render" do
      store = Composition::Renderers::LayoutBlocks.block_supports_store(page.context)
      store.add_rule(".wp-container-core-group-is-layout-2ab8c7fb")
           .add_declarations("gap" => "var(--wp--preset--spacing--20)")

      expect(page.send(:block_supports_css))
        .to eq(".wp-container-core-group-is-layout-2ab8c7fb{gap:var(--wp--preset--spacing--20);}")
    end

    # BR-MIGRATE-217: the store is per-render, keyed on the render's StyleCollector. Two
    # pages must not see each other's rules — the legacy gets this from php-fpm tearing
    # the interpreter down between requests, and a long-lived Ruby process does not.
    it "does not leak rules between two pages rendered in the same process" do
      Composition::Renderers::LayoutBlocks
        .block_supports_store(page.context)
        .add_rule(".wp-container-a").add_declarations("gap" => "1px")

      other = Presentation::Page.new(screen: screen, site_url: "http://127.0.0.1:3100",
                                     theme_slug: "twentytwentyfive")
      expect(other.send(:block_supports_css)).to be_nil
    end

    # An empty store must produce no element at all, not `<style id="…"></style>`. The
    # legacy's guard is `if ( ! empty( $compiled_core_stylesheet ) )`, script-loader.php:3338.
    it "is nil, not the empty string, when nothing was stored" do
      expect(page.send(:block_supports_css)).to be_nil
    end
  end

  # ── the exact bytes ───────────────────────────────────────────────────────────────
  describe "Presentation::Head" do
    # ⚠️ `$options` is `array()` at script-loader.php:3334 — `wp_enqueue_stored_styles` is
    # registered bare at default-filters.php:655 — so `prettify` is false and there is no
    # `/**\n * Core styles: block-supports\n */` banner (:3330). Asserting the golden has
    # none is asserting that this rebuild must not add one.
    it "carries no prettify banner in any golden" do
      %w[index single not-found-404].each do |name|
        expect(golden_element(name)).not_to include("Core styles:"), name
      end
    end

    it "wraps the stylesheet exactly as the oracle does" do
      css = golden_element("index")
      expect(css).not_to be_nil

      element = Presentation::Assets.inline("core-block-supports", css,
                                            "core-block-supports-inline-css")
      expect(element).to eq(<<~HTML.chomp)
        <style id="core-block-supports-inline-css">
        #{css}
        /*# sourceURL=core-block-supports-inline-css */
        </style>
      HTML
    end

    # `wp_enqueue_stored_styles` runs on `wp_enqueue_scripts` for a block theme, after
    # `wp_enqueue_global_styles` and before the skip-link style. Position is observable
    # and is asserted from the golden rather than from memory.
    it "sits between global-styles and wp-block-template-skip-link" do
      ids = File.read(GOLDEN_DIR.join("golden-web-index.html"))
                .scan(/<style id="([^"]+)-inline-css">/).flatten
      expect(ids.each_cons(3).to_a)
        .to include(%w[global-styles core-block-supports wp-block-template-skip-link])
    end
  end
end
