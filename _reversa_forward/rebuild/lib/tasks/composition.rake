# frozen_string_literal: true

namespace :composition do
  desc "Generate the block type registry and style assets from the legacy block.json files"
  task :generate_blocks do
    require "json"
    require "fileutils"

    # handoff.md, closing note 3: the editor's "readable half (115 block schemas, 23
    # supports, the theme.json cascade) should be generated MECHANICALLY". This is that
    # generator. Nothing here is hand-authored, so a WordPress point release is re-run
    # rather than re-read.
    legacy = ENV.fetch("LEGACY_ROOT", "/workspace/WordPress")
    blocks_dir = File.join(legacy, "wp-includes", "blocks")
    out_dir = Rails.root.join("db", "blocks")
    FileUtils.mkdir_p(out_dir)

    types = {}
    styles = {}
    Dir[File.join(blocks_dir, "*", "block.json")].sort.each do |path|
      schema = JSON.parse(File.read(path))
      name = schema["name"]
      next if name.nil?

      dir = File.dirname(path)
      types[name] = {
        "name" => name,
        "title" => schema["title"],
        "category" => schema["category"],
        "apiVersion" => schema["apiVersion"],
        "attributes" => schema["attributes"] || {},
        "supports" => schema["supports"] || {},
        "usesContext" => schema["usesContext"] || [],
        "providesContext" => schema["providesContext"] || {},
        "parent" => schema["parent"],
        "ancestor" => schema["ancestor"],
        "allowedBlocks" => schema["allowedBlocks"],
        "selectors" => schema["selectors"],
        "styles" => schema["styles"],
        # A block is DYNAMIC when the legacy ships a render callback beside it. That file
        # is the definition of its server-side behaviour, so the flag is derived from the
        # filesystem rather than asserted.
        "dynamic" => File.exist?("#{dir}.php"),
        "styleHandle" => ("wp-block-#{File.basename(dir)}" if File.exist?(File.join(dir, "style.min.css"))),
      }.compact

      css = File.join(dir, "style.min.css")
      styles[name] = File.read(css) if File.exist?(css)
    end

    File.write(out_dir.join("types.json"), JSON.pretty_generate(types))
    File.write(out_dir.join("styles.json"), JSON.pretty_generate(styles))

    dynamic = types.values.count { |t| t["dynamic"] }
    puts "  block types      #{types.size}  (#{dynamic} dynamic, #{types.size - dynamic} static)"
    puts "  style assets     #{styles.size}  (#{styles.values.sum(&:bytesize) / 1024} KB)"
    puts "  wrote            db/blocks/types.json, db/blocks/styles.json"

    # The 23 supports the handoff counts, taken from what the schemas actually declare.
    supports = types.values.flat_map { |t| (t["supports"] || {}).keys }.tally.sort_by { |_, c| -c }
    puts "  distinct supports #{supports.size}: #{supports.first(8).map { |k, c| "#{k}(#{c})" }.join(" ")}"
  end
end
