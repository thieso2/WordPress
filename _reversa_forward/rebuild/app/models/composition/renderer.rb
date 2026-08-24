# frozen_string_literal: true

module Composition
  # BR-MIGRATE-194..199. Walks a parsed block tree and produces HTML.
  #
  # AD-01 in one sentence: there is no `render_block` filter, no `pre_render_block`
  # short-circuit and no `render_block_data`. What this method returns IS the output.
  class Renderer
    def self.render(document, ctx = RenderContext.new)
      blocks = document.is_a?(String) ? Parser.parse(document) : document
      blocks.map { |b| render_block(b, ctx) }.join
    end

    def self.render_block(block, ctx)
      return "" if block.nil?
      # Freeform content is emitted verbatim. It is how classic-editor posts survive, and
      # rewriting it would silently edit user content.
      return block.inner_html.to_s if block.freeform?

      # Block style variations (section styles) — the two `render_block_data` /
      # `render_block` filters core registers unconditionally in
      # wp-includes/block-supports/block-style-variations.php:265-266, folded in per
      # AD-01. A no-op unless the block's `className` names a variation the theme
      # defines data for. See Renderers::CommentBlocks::StyleVariations.
      block = Renderers::CommentBlocks::StyleVariations.apply(block, ctx)

      # BR-MIGRATE-200: an UNREGISTERED block receives nothing — no supports, no
      # stylesheet. Its saved markup still renders, because the alternative is losing
      # content for the sake of a registry.
      type = Registry[block.block_name]
      renderer = Renderers.for(block.block_name) || Renderers::Base
      # Remember what was enqueued before this block ran, so an empty render can be
      # rolled back — class-wp-block.php:757 dequeues scripts and script modules on the
      # same condition it dequeues styles.
      modules_before = ctx.script_modules.mark
      styles_before = ctx.styles.mark
      html = renderer.new(block, ctx).render.to_s

      # ⚠️ POST-ORDER, and this is not a detail: it decides the order of the
      # `<style id="wp-block-*-inline-css">` elements, which is 39% of a rendered page.
      #
      # `render_block()` builds a container's inner content by rendering its children
      # BEFORE invoking the container's own callback, and the stylesheet is enqueued as
      # part of that callback. So a child's stylesheet is always queued ahead of its
      # parent's. Verified directly against the oracle:
      #
      #   group > [ site-title, navigation > [ page-list ] ]
      #     -> wp-block-site-title, wp-block-page-list, wp-block-navigation, wp-block-group
      #
      # Collecting on the way DOWN instead produces group, site-title, navigation,
      # page-list — which is what this method did until the first byte-level page diff
      # showed the head diverging at exactly the line the block stylesheets begin.
      #
      # ⚠️ AND a block that renders to nothing contributes no stylesheet.
      # class-wp-block.php:757 (new in WordPress 6.9): the enqueue itself is
      # unconditional, and then, if `trim( $block_content ) === ''`, everything the block
      # just enqueued is DEQUEUED again —
      #
      #     // Dequeue the newly enqueued assets with the existing assets
      #     // if the rendered block was empty & wp_enqueue_scripts did not fire.
      #
      # guarded by an `enqueue_empty_block_content_assets` filter that defaults to false.
      # AD-01 removes the filter, so the default is the only behaviour. Observable in the
      # corpus: the footer pattern contains an unconditional `<!-- wp:site-logo /-->`, no
      # site logo is set, the block renders '' — and no `wp-block-site-logo-inline-css`
      # appears in any golden file. `core/spacer` with no attributes behaves the same way.
      #
      # Whitespace-only counts as empty, because the legacy trims before comparing.
      if html.strip.empty?
        ctx.script_modules.rollback(ctx.script_modules.since(modules_before))
        # class-wp-block.php:766 dequeues the STYLES of an empty render too — the
        # subtree's included. `core/query-no-results` is the observable case: its inner
        # paragraph renders (enqueuing wp-block-paragraph) before the callback sees the
        # loop had results and returns '', and the golden archive screens show the
        # paragraph stylesheet first appearing at the FOOTER's paragraph, not the loop.
        ctx.styles.rollback(ctx.styles.since(styles_before))
      elsif type
        ctx.styles.use(block.block_name)
      end

      # `wp_render_block_style_variation_class_name` (block-style-variations.php:217):
      # the instance class allocated before the render must reach the rendered markup's
      # first tag. A no-op unless `attrs.className` carries an `is-style-<slug>--<n>`
      # instance class.
      Renderers::CommentBlocks::StyleVariations.apply_class_name(html, block)
    end
  end
end
