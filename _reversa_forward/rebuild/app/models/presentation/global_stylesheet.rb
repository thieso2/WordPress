# frozen_string_literal: true

module Presentation
  # `wp_enqueue_global_styles()`, wp-includes/script-loader.php:2559 — the part of
  # it that produces bytes.
  #
  # The generator itself is `Styling::GlobalStylesheet` in the `styling` pack. This
  # class is the seam the pack cannot cross on its own (topology_decision.md option
  # 3: the pack has zero dependencies and may not read the database or Rails root):
  # it collects the four origins' DATA and the block registry's DATA, hands them to
  # the pack, and returns the CSS.
  #
  # ⚠️ The four origins, and where each one lives here:
  #
  # | origin   | legacy source                          | here |
  # |----------|----------------------------------------|------|
  # | default  | `wp-includes/theme.json`               | `Styling::CoreThemeData::DATA` (transcribed into the pack) |
  # | blocks   | each block's `supports.__experimentalStyle` | derived by `Styling::ThemeJsonResolver.block_data_from_definitions` |
  # | theme    | the theme's `theme.json`               | the `themes.theme_json` column, loaded by `rake theme:sync` |
  # | custom   | the `wp_global_styles` post            | `Presentation::GlobalStyles` (BR-MIGRATE-208) |
  class GlobalStylesheet
    # ⚠️ `Composition::Registry` is shared contract and exposes `BlockType`
    # objects, which drop `selectors` and `styles` — the two keys
    # `WP_Theme_JSON::get_blocks_metadata()` needs most. Rather than change a file
    # this family does not own, the generated data is read again here, from the
    # same file `rake composition:generate_blocks` writes.
    DEFINITIONS_PATH = Rails.root.join("db", "blocks", "types.json")

    class << self
      # Memoized for the process, not the request: the inputs are generated data
      # files and a `themes` row, none of which change inside a request.
      def block_definitions
        @block_definitions ||= JSON.parse(File.read(DEFINITIONS_PATH)).freeze
      end

      def blocks_metadata
        @blocks_metadata ||= Styling::BlocksMetadata.build(block_definitions).freeze
      end

      def block_data
        @block_data ||= Styling::ThemeJsonResolver.block_data_from_definitions(block_definitions).freeze
      end

      def reset! = (@block_definitions = @blocks_metadata = @block_data = nil)
    end

    def initialize(theme_slug:)
      @theme_slug = theme_slug
    end

    # What `<style id="global-styles-inline-css">` contains for this screen.
    #
    # @param used_blocks [Enumerable<String>] block names the render enqueued
    #   styles for, e.g. `core/search` — `Composition::StyleCollector#used`
    # @return [String, nil] nil when the theme has no theme.json at all
    def css(used_blocks: [])
      return nil if theme.nil?

      handles = used_blocks.map { |name| "wp-block-#{name.to_s.sub(%r{\Acore/}, "")}" }
      generator.for_page(handles)
    end

    private

    def theme = @theme ||= Theme.find_by(slug: @theme_slug)

    def generator
      Styling::GlobalStylesheet.new(
        theme_json: merged_data,
        blocks_metadata: self.class.blocks_metadata,
        block_definitions: self.class.block_definitions,
        custom_css: custom_css
      )
    end

    # `wp_get_custom_css( get_stylesheet() )`, wp-includes/theme.php:2033 — the
    # Customizer's Additional CSS, which the legacy keeps in a `custom_css` post NAMED
    # after the stylesheet it styles. The pipeline pivots that post into the
    # `custom_css_<stylesheet>` setting (lib/seeding/pipeline.rb, load_composition), and
    # wp_enqueue_global_styles() (script-loader.php:2626) is where a block theme prints
    # it — inside `global-styles-inline-css`, which is this class's output.
    def custom_css
      value = Configuration::Setting["custom_css_#{@theme_slug}"]
      value.is_a?(String) ? value : nil
    end

    # BR-MIGRATE-206: default → blocks → theme → custom, in that order.
    def merged_data
      theme.resolver(store: GlobalStyles.new,
                     core_data: Styling::CoreThemeData::DATA,
                     block_data: self.class.block_data).merged_data("custom")
    end
  end
end
