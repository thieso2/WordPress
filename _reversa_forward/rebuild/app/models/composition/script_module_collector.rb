# frozen_string_literal: true

module Composition
  # `wp_enqueue_script_module()` — the modules a render actually asked for.
  #
  # Separate from StyleCollector because the two are enqueued differently: a block's
  # STYLESHEET comes from its `style` handle in block.json and is enqueued for every
  # registered block that renders non-empty, whereas a view SCRIPT MODULE is usually
  # enqueued by the block's own render callback under a condition. `core/navigation` only
  # asks for its module when the menu is actually interactive
  # (navigation.php:953 `handle_view_script_module_loading`).
  #
  # ⚠️ The same empty-content rule applies (class-wp-block.php:757): a block that renders
  # to nothing has its newly enqueued script modules dequeued along with its styles.
  # Composition::Renderer enforces that for both collectors at once.
  class ScriptModuleCollector
    def initialize
      @used = []
    end

    def use(module_id)
      id = module_id.to_s
      @used << id unless @used.include?(id)
    end

    # Modules enqueued while a block was rendering that then turned out to be empty.
    def rollback(ids) = @used -= Array(ids)

    def used = @used.dup
    def mark = @used.length
    def since(mark) = @used[mark..] || []
  end
end
