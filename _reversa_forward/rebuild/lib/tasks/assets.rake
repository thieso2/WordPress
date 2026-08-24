# frozen_string_literal: true

namespace :assets do
  desc "Copy the static assets the rendered pages reference into public/ (read-only, from the legacy tree)"
  task :sync do
    require "fileutils"

    # ⚠️ Byte-identical HTML is not a working page.
    #
    # `web.not_found_404` reached byte parity with the oracle while rendering visibly
    # broken in a browser, because every asset its own markup references — the externally
    # linked block stylesheet, the theme's two variable fonts, the navigation view script
    # module — 404'd. The parity harness compares HTML and cannot see that.
    #
    # These files are ASSETS, not behaviour: the same CSS, fonts and compiled JS the
    # product ships. `styling` already treats per-block CSS that way (db/blocks/styles.json
    # is copied, not reimplemented). This copies the rest, so the rebuild serves itself
    # rather than depending on the legacy tree at runtime — which would make the legacy a
    # deployment dependency and defeat the point of the migration.
    #
    # Derived from what the GOLDENS actually reference, so the list cannot drift away from
    # what the pages ask for. Re-run after a corpus or theme change.
    legacy = ENV.fetch("LEGACY_ROOT", "/workspace/WordPress")
    public_dir = Rails.root.join("public")
    goldens = Dir[Rails.root.join("spec", "parity", "golden", "*").to_s]

    referenced = goldens.flat_map do |file|
      body = File.read(file, encoding: "UTF-8")
      next [] unless body.valid_encoding?

      body.scan(%r{<SITE>(/wp-(?:includes|content)/[^"'?\s)]+)}).flatten
    end.uniq.reject { |path| path.include?("<") }

    copied = 0
    missing = []
    referenced.sort.each do |path|
      source = File.join(legacy, path)
      # The corpus's uploads live in the ORACLE's tree, not the pristine legacy checkout.
      source = File.join(legacy, "_reversa_forward", "oracle", "wordpress", path) unless File.exist?(source)
      unless File.exist?(source)
        missing << path
        next
      end

      destination = File.join(public_dir, path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
      copied += 1
    end

    puts "  referenced by the goldens  #{referenced.length}"
    puts "  copied into public/        #{copied}"
    unless missing.empty?
      puts "  ⚠️  not found in the legacy tree (#{missing.length}):"
      missing.each { |path| puts "        #{path}" }
    end
  end
end
