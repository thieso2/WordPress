# frozen_string_literal: true

module Composition
  # Collects the per-block stylesheets that a render actually used.
  #
  # BR-MIGRATE-218 (BR-SE-03) is the styling pack's rule about deduplicating and combining
  # rules; this is its counterpart for whole block stylesheets. Two properties matter and
  # both are observable in the golden files:
  #
  #  * FIRST-USE ORDER. The legacy emits a block's stylesheet the first time that block
  #    renders, so the order of `<style id="wp-block-*-inline-css">` elements in the
  #    document is the order blocks were first encountered — not alphabetical, and not
  #    registration order. Getting this wrong moves 39% of the page's bytes around and
  #    every screen diff fails on it.
  #  * ONCE ONLY. A block used twenty times contributes its stylesheet once.
  class StyleCollector
    def initialize
      @used = [] # insertion-ordered, deduplicated
    end

    def use(block_name)
      name = block_name.to_s
      return if @used.include?(name)
      return if Registry.style_for(name).nil?

      @used << name
    end

    def used = @used.dup

    # The other half of the empty-content rule (class-wp-block.php:757): a block whose
    # rendered content is empty has every style enqueued DURING its render — its own and
    # its whole subtree's — dequeued again. `core/query-no-results` is the corpus case:
    # its inner paragraph renders (and enqueues) before the callback decides the loop had
    # results and returns '', and the golden archives show no early paragraph stylesheet.
    # Same protocol as ScriptModuleCollector: mark / since / rollback.
    def mark = @used.length
    def since(mark) = @used[mark..] || []
    def rollback(names) = @used -= Array(names)

    # Rendered exactly as the legacy prints it, including the sourceURL comment, because
    # these screens are compared byte-for-byte.
    def to_html
      @used.map do |name|
        short = name.sub(%r{\Acore/}, "")
        css = Registry.style_for(name)
        +"<style id=\"wp-block-#{short}-inline-css\">\n#{css}\n</style>"
      end.join("\n")
    end
  end
end
