# frozen_string_literal: true

module Presentation
  # The `<head>` stylesheets that are NOT per-block.
  #
  # Every one is an ASSET — a file copied out of the legacy tree, or a string literal in
  # the legacy source — for exactly the reason Composition::Registry.style_for is an
  # asset: reimplementing CSS byte-for-byte is not migration, it is transcription with
  # extra steps. `rake theme:generate` produces db/theme/assets.json; nothing here is
  # hand-written.
  module Assets
    DATA = Rails.root.join("db", "theme")

    module_function

    def all
      @all ||= JSON.parse(File.read(DATA.join("assets.json")))
    end

    def theme_json
      @theme_json ||= JSON.parse(File.read(DATA.join("theme.json")))
    end

    def meta
      @meta ||= JSON.parse(File.read(DATA.join("theme.meta.json")))
    end

    # `wp_default_script_modules()` — id => { src, version }.
    def script_modules
      @script_modules ||= JSON.parse(File.read(DATA.join("script_modules.json")))
    end

    def reset! = (@all = nil; @theme_json = nil; @meta = nil; @script_modules = nil)

    # `get_sorted_dependencies( $queue, array( 'static' ) )`. Depth-first over static
    # imports, deduplicated, dependencies before their dependents.
    def script_module_dependencies(queue)
      catalogue = script_modules
      seen = []
      visit = lambda do |id|
        return if seen.include?(id)

        entry = catalogue[id]
        return if entry.nil?

        Array(entry["dependencies"]).each { |dep| visit.call(dep) }
        seen << id
      end
      Array(queue).each { |id| visit.call(id) }
      seen
    end

    def [](handle) = all[handle.to_s]

    # `wp_maybe_inline_styles()`, wp-includes/script-loader.php:3095, printing one
    # `<style id="{handle}-inline-css">` per style with the file's contents inlined and a
    # sourceURL comment appended so devtools can still find the original.
    def style_tag(handle, site_url:)
      asset = all.fetch(handle.to_s)
      inline(handle, asset["css"], asset["source_url"].to_s.sub("{site}", site_url))
    end

    def inline(handle, css, source_url)
      +"<style id=\"#{handle}-inline-css\">\n#{css}\n/*# sourceURL=#{source_url} */\n</style>"
    end
  end
end
