# frozen_string_literal: true

module Composition
  # What a block needs to know about where it is being rendered.
  #
  # ⚠️ paradigm_decision.md implication 1: no global mutable state. The legacy tracks the
  # block being rendered in `WP_Block_Supports::$block_to_render`, a PUBLIC STATIC
  # (BR-MIGRATE-205), and the current post in the `$post` global. Neither has a Rails
  # analogue, so both travel explicitly through this object instead. Every renderer
  # receives it; nothing reaches for ambient state.
  #
  # `usesContext` / `providesContext` in the block schemas are the legacy's own mechanism
  # for exactly this, so `context` mirrors it: a parent block adds keys, children read
  # them, and the addition is scoped to the subtree via `with`.
  class RenderContext
    attr_reader :post, :query, :styles, :script_modules, :scripts, :context, :depth

    def initialize(post: nil, query: nil, styles: nil, script_modules: nil, scripts: nil,
                   context: {}, depth: 0)
      @post = post
      @query = query
      @styles = styles || StyleCollector.new
      # `wp_enqueue_script_module()`. Some blocks enqueue a view module from inside their
      # render callback rather than declaring it in block.json — `core/navigation` is the
      # one the corpus exercises (navigation.php:955) — so the collector travels with the
      # render, exactly as the stylesheet collector does, instead of living in a global.
      @script_modules = script_modules || ScriptModuleCollector.new
      # `wp_enqueue_script()` — CLASSIC scripts, the `$wp_scripts` queue. One block in
      # the corpus reaches for it from inside its render callback:
      # `core/post-comments-form` enqueues 'comment-reply'
      # (wp-includes/blocks/post-comments-form.php:52), which `wp_footer()` then prints.
      # The collector shape is identical to the module one — an insertion-ordered,
      # deduplicated list of handles — so the same class serves.
      @scripts = scripts || ScriptModuleCollector.new
      @context = context
      @depth = depth
    end

    def with(post: @post, query: @query, context: {}, depth: @depth)
      self.class.new(post: post, query: query, styles: @styles,
                     script_modules: @script_modules, scripts: @scripts,
                     context: @context.merge(context), depth: depth)
    end

    def site_name = Configuration::Setting.display("blogname").to_s
    def site_description = Configuration::Setting.display("blogdescription").to_s

    def permalink_for(record)
      return "#" if record.nil?
      return "/#{record.slug}" if record.is_a?(Publishing::Page)
      return "#" if record.published_at.nil?

      "/#{record.published_at.strftime("%Y/%m")}/#{record.slug}"
    end
  end
end
