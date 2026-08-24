# frozen_string_literal: true

module Composition
  module Renderers
    # The contract every block renderer implements.
    #
    # BR-MIGRATE-203 (BR-BSUP-04): "A support WITHOUT an apply callback contributes nothing
    # at render time, though it may still register attributes." The same shape holds one
    # level up: a registered block with no renderer contributes its saved markup and
    # nothing more, which is exactly what a STATIC block is. That is why `Base` is not
    # abstract — it IS the static-block renderer.
    class Base
      class << self
        # Renderers register themselves by block name. Not a hook: the mapping is resolved
        # at boot from the constants that exist, there is no runtime `add_filter`, and
        # nothing can substitute a renderer for another after the fact (AD-01).
        def handles(*block_names)
          block_names.each { |name| Renderers.register(name.to_s, self) }
        end
      end

      attr_reader :block, :type, :attrs, :ctx

      def initialize(block, ctx)
        @block = block
        @ctx = ctx
        @type = Registry[block.block_name]
        # BR-MIGRATE-204: schema defaults are applied before anything reads an attribute.
        @attrs = @type ? @type.prepare_attributes(block.attrs) : (block.attrs || {})
      end

      # Static blocks emit their saved markup with inner blocks spliced back into the
      # positions `inner_content` marks with nil. Reconstructing from `inner_html` instead
      # would drop every nested block.
      def render
        return block.inner_html if block.inner_blocks.empty?

        index = -1
        block.inner_content.map do |chunk|
          next chunk unless chunk.nil?

          index += 1
          Renderer.render_block(block.inner_blocks[index], ctx)
        end.join
      end

      private

      def inner = render
      def esc(text) = ERB::Util.html_escape(text.to_s)
    end
  end
end
