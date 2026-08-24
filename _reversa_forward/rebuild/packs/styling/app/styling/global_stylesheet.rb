# frozen_string_literal: true

module Styling
  # `wp_get_global_stylesheet()` (wp-includes/global-styles-and-settings.php:148)
  # and `wp_add_global_styles_for_blocks()` (:239) — the two halves of what a
  # front-end request prints as `<style id="global-styles-inline-css">`.
  #
  # They are one class here because they are one output: `wp_enqueue_global_styles()`
  # registers the `global-styles` handle, `wp_get_global_stylesheet()` supplies its
  # first inline chunk and `wp_add_global_styles_for_blocks()` appends one chunk per
  # block on the page. `WP_Styles::print_inline_style()` joins the chunks with "\n".
  #
  # ⚠️ AD-01, three filters removed and their pre-filter values fixed here:
  #
  # * `wp_theme_json_get_style_nodes` — `wp_enqueue_global_styles()` registers
  #   `wp_filter_out_block_nodes` on it unconditionally (script-loader.php:2605),
  #   so block style nodes NEVER appear in the base stylesheet on the front end.
  #   That is `skip_block_nodes: true` below, and nothing can turn it off.
  # * `should_load_block_assets_on_demand` — its unfiltered value is
  #   `wp_should_load_separate_core_block_assets()`, which is true for a block
  #   theme. Hence `block_styles` takes the enqueued handles and emits a chunk
  #   only for a block that is actually on the page.
  # * `wp_get_global_stylesheet`'s object cache (`theme_json` group) — a
  #   non-persistent per-request memo, replaced by memoization on this instance.
  class GlobalStylesheet
    # :182 — the default set, in this order.
    DEFAULT_TYPES = %w[variables styles presets].freeze
    # :202, :219 — 'blocks' is deliberately absent: styles for the `blocks`
    # origin are added later, per block, by `block_styles`.
    ORIGINS = %w[default theme custom].freeze

    # @param theme_json [ThemeJson] the merged four-origin document
    # @param blocks_metadata [Hash{String=>Hash}] `BlocksMetadata.build(...)`
    # @param block_definitions [Hash{String=>Hash}] the block.json data
    # @param base_layout_styles [Boolean] :190 — true only for a classic theme
    #   with no theme.json, which has no `.wp-site-blocks` wrapper to align against
    # @param custom_css [String, nil] the Customizer's Additional CSS —
    #   `wp_get_custom_css()` (wp-includes/theme.php:2033). The pack is a leaf, so the
    #   CSS arrives as data; the application supplies it (Presentation::GlobalStylesheet).
    def initialize(theme_json:, blocks_metadata: {}, block_definitions: {}, base_layout_styles: false,
                   custom_css: nil)
      @generator = Stylesheet.new(theme_json, blocks_metadata, block_definitions)
      @base_layout_styles = base_layout_styles
      @custom_css = custom_css.to_s
    end

    # `wp_get_global_stylesheet()`, :148.
    #
    # ⚠️ The two calls are NOT one call with three types. `variables` is
    # generated on its own (:200) and the remaining types after it (:227), and
    # `array_diff` leaves them in the order `styles`, `presets` — which is not
    # the order they were asked for. Read from the source, not inferred.
    #
    # @param types [Array<String>] defaults to DEFAULT_TYPES
    # @return [String]
    def stylesheet(types = nil)
      types = DEFAULT_TYPES.dup if PhpCompat.php_empty?(types)
      options = { 'skip_block_nodes' => true }
      options['base_layout_styles'] = true if @base_layout_styles

      variables = ''
      if types.include?('variables')
        variables = @generator.get_stylesheet(['variables'], ORIGINS, options)
        types -= ['variables']
      end

      rest = PhpCompat.php_empty?(types) ? '' : @generator.get_stylesheet(types, ORIGINS, options)
      variables + rest
    end

    # `wp_add_global_styles_for_blocks()`, :239. One CSS chunk per block style
    # node, in theme.json order, for the blocks the page actually rendered.
    #
    # ⚠️ `wp_add_inline_style()` rejects an empty string (class-wp-styles.php),
    # so a node that generates nothing contributes no chunk — not an empty one.
    #
    # @param enqueued_handles [Enumerable<String>] the `wp-block-*` style handles
    #   in the queue, i.e. the blocks rendered on this page
    # @return [Array<String>]
    def block_styles(enqueued_handles)
      handles = enqueued_handles.to_a
      @generator.styles_block_nodes.filter_map do |metadata|
        css = @generator.styles_for_block(metadata)
        next if PhpCompat.php_empty?(css)

        block_name = metadata['name'] || self.class.block_name_from_theme_json_path(metadata['path'])
        next if PhpCompat.php_empty?(block_name)

        # :311 — the on-demand check applies to core blocks only; a third-party
        # block's styles are always added.
        if block_name.start_with?('core/')
          next unless handles.include?("wp-block-#{block_name.delete_prefix('core/')}")
        end

        css
      end
    end

    # What `<style id="global-styles-inline-css">` contains: the base stylesheet,
    # then — on a block theme — the Customizer's custom CSS
    # (`wp_enqueue_global_styles()`, script-loader.php:2616-2642: dequeued from its
    # classic-theme `wp_head` slot and appended as `"\n" . trim( $custom_css )`),
    # followed by each block's chunk, joined the way `WP_Styles` joins inline
    # styles for one handle.
    #
    # :2645 also appends `wp_get_global_stylesheet( array( 'custom-css' ) )` — the
    # theme.json `styles.css` origin. twentytwentyfive declares none, so that chunk is
    # the empty string for this corpus; the type is not generated here. Reported.
    #
    # @param enqueued_handles [Enumerable<String>]
    # @return [String]
    def for_page(enqueued_handles = [])
      base = stylesheet
      custom = @custom_css.strip
      base += "\n#{custom}" unless custom.empty?
      ([base] + block_styles(enqueued_handles)).join("\n")
    end

    # `wp_get_block_name_from_theme_json_path()`, :355. Block element and pseudo
    # nodes carry no `name`, so the name has to come back out of the path.
    #
    # @param path [Array<String>]
    # @return [String]
    def self.block_name_from_theme_json_path(path)
      path = Array(path)
      if path.length >= 3 && path[0] == 'styles' && path[1] == 'blocks' && path[2].to_s.include?('/')
        return path[2]
      end

      # Backward compatibility: a core block name anywhere in the path.
      path.find { |item| item.to_s.include?('core/') } || ''
    end
  end
end
