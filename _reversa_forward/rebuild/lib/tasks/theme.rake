# frozen_string_literal: true

# The theme pipeline, in the shape `composition:generate_blocks` already established:
#
#   rake theme:generate   reads the LEGACY tree (read-only) and writes db/theme/*.json
#   rake theme:load       loads db/theme/*.json into PostgreSQL
#   rake theme:sync       both, in order
#
# The split matters. `generate` needs the legacy theme directory and, for the 98 pattern
# files (75 of which contain PHP), a PHP interpreter; `load` needs neither. So a deploy
# never reads a theme directory and a request never reads a file — which is the whole
# point of AD-02 moving these documents into tables.
#
# ⚠️ Nothing here is hand-copied. A theme update is a re-run, not a re-read.
namespace :theme do
  LEGACY_ROOT = ENV.fetch("LEGACY_ROOT", "/workspace/WordPress")
  THEME_SLUG  = ENV.fetch("THEME", "twentytwentyfive")
  OUT_DIR     = File.expand_path("../../db/theme", __dir__)

  def theme_dir = File.join(LEGACY_ROOT, "wp-content", "themes", THEME_SLUG)

  # ── generate ───────────────────────────────────────────────────────────────────────

  desc "Generate db/theme/*.json from the legacy theme directory (read-only)"
  task :generate do
    require "json"
    require "fileutils"
    FileUtils.mkdir_p(OUT_DIR)

    write = lambda do |name, data|
      File.write(File.join(OUT_DIR, name), "#{JSON.pretty_generate(data)}\n")
      puts format("  %-22s %s", name, data.is_a?(Array) ? "#{data.length} entries" : "#{JSON.generate(data).bytesize} bytes")
    end

    theme_json = JSON.parse(File.read(File.join(theme_dir, "theme.json")))

    write.call("theme.json", theme_json)
    write.call("theme.meta.json", generate_meta(theme_json))
    write.call("templates.json", generate_templates(theme_json))
    write.call("patterns.json", generate_patterns)
    write.call("assets.json", generate_assets)
    write.call("script_modules.json", generate_script_modules)
  end

  # style.css's file header is the theme's metadata — wp-includes/class-wp-theme.php:53
  # (`$file_headers`). Only the fields the target has a column for are kept.
  def generate_meta(theme_json)
    header = File.read(File.join(theme_dir, "style.css"))[0, 8192]
    field = ->(name) { header[/^[ \t\/*#@]*#{Regexp.escape(name)}:(.*)$/, 1].to_s.strip }
    {
      "slug" => THEME_SLUG,
      "name" => field.call("Theme Name"),
      "version" => field.call("Version"),
      # A child theme declares `Template:`; twentytwentyfive does not, so this is nil and
      # Presentation::Theme#ancestry is a single link (BR-MIGRATE-001…006).
      "parent_slug" => field.call("Template").presence,
      "template_parts" => theme_json["templateParts"] || [],
      "custom_templates" => theme_json["customTemplates"] || [],
    }
  end

  # ⚠️ block-template-utils.php:662 — `_build_block_template_result_from_file()` runs the
  # file's content through `apply_block_hooks_to_content()`. Under AD-01 the hook half of
  # that function does not exist, but its OTHER half is not a hook: the default
  # `$before_block_visitor` is `_inject_theme_attribute_in_template_part_block`
  # (blocks.php:1169), which stamps the active stylesheet onto every `core/template-part`
  # block that does not already carry one (block-template-utils.php:566).
  #
  # That injection is the entire difference between the file on disk and the template
  # WordPress renders: verified against the oracle, all 8 templates differ from their file
  # by exactly 2 × 27 bytes (`,"theme":"twentytwentyfive"`) and all 7 parts are identical,
  # because parts contain no template-part blocks. The differential spec asserts the built
  # content byte-for-byte against `get_block_template()`.
  #
  # It is applied here, at load time, for the same reason the legacy applies it at build
  # time: the renderer must never have to know which theme it is inside.
  def inject_theme_attribute(content)
    content.gsub(/<!--\s+wp:template-part(\s+(\{.*?\}))?\s+\/-->/m) do
      attrs = Regexp.last_match(2) ? JSON.parse(Regexp.last_match(2)) : {}
      next Regexp.last_match(0) if attrs.key?("theme")

      attrs["theme"] = THEME_SLUG
      # serialize_block_attributes(), blocks.php: JSON_UNESCAPED_SLASHES |
      # JSON_UNESCAPED_UNICODE, then four entity escapes. None of the four can occur in a
      # template-part's slug/theme/tagName/area, so plain generate is equivalent here and
      # the spec proves it.
      "<!-- wp:template-part #{JSON.generate(attrs)} /-->"
    end
  end

  # get_block_templates() reads `templates/*.html` and `parts/*.html`
  # (block-template-utils.php:414, `_get_block_templates_files`). Title and area come from
  # theme.json's `templateParts` / `customTemplates`, and for the standard slugs from
  # get_default_block_template_types() — the titles below are that table, verbatim.
  DEFAULT_TEMPLATE_TITLES = {
    "index" => "Index", "home" => "Blog Home", "front-page" => "Front Page",
    "singular" => "Single Entries", "single" => "Single Posts", "page" => "Pages",
    "archive" => "All Archives", "author" => "Author Archives",
    "category" => "Category Archives", "taxonomy" => "Taxonomy",
    "date" => "Date Archives", "tag" => "Tag Archives", "attachment" => "Attachment Pages",
    "search" => "Search Results", "privacy-policy" => "Privacy Policy", "404" => "Page: 404",
  }.freeze

  def generate_templates(theme_json)
    parts_meta = (theme_json["templateParts"] || []).to_h { |p| [p["name"], p] }
    custom = (theme_json["customTemplates"] || []).to_h { |t| [t["name"], t] }
    rows = []

    Dir[File.join(theme_dir, "templates", "*.html")].sort.each do |path|
      slug = File.basename(path, ".html")
      rows << {
        "kind" => "template", "slug" => slug, "area" => nil,
        "title" => DEFAULT_TEMPLATE_TITLES[slug] || custom.dig(slug, "title") || slug,
        "content" => inject_theme_attribute(File.read(path)),
      }
    end

    Dir[File.join(theme_dir, "parts", "*.html")].sort.each do |path|
      slug = File.basename(path, ".html")
      meta = parts_meta[slug] || {}
      rows << {
        "kind" => "part", "slug" => slug,
        # block-template-utils.php:641 — a part with no declaration in theme.json is
        # 'uncategorized', which is also what theme.json says for `sidebar`.
        "area" => meta["area"] || "uncategorized",
        "title" => meta["title"] || slug,
        "content" => inject_theme_attribute(File.read(path)),
      }
    end
    rows
  end

  # The theme's 98 pattern files are PHP: 75 of them interpolate translated strings into
  # the block markup, so their CONTENT does not exist until PHP has run
  # (WP_Block_Patterns_Registry::get_registered → `ob_start(); include $file;`).
  #
  # Rather than reimplement that, this asks the oracle — which is the ground truth for
  # every behavioural question in this migration — and freezes the answer into
  # db/theme/patterns.json. The oracle is needed to GENERATE, never to RUN.
  def generate_patterns
    bootstrap = ENV.fetch(
      "ORACLE_BOOTSTRAP",
      "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
    )
    script = <<~PHP
      require #{bootstrap.dump};
      $out = array();
      foreach (WP_Block_Patterns_Registry::get_instance()->get_all_registered() as $p) {
        if (!str_starts_with($p['name'], #{THEME_SLUG.dump} . '/')) { continue; }
        $out[] = array(
          'slug' => $p['name'],
          'title' => $p['title'],
          'description' => isset($p['description']) ? $p['description'] : '',
          'inserter' => !isset($p['inserter']) || $p['inserter'],
          'categories' => isset($p['categories']) ? array_values($p['categories']) : array(),
          'content' => $p['content'],
        );
      }
      usort($out, function ($a, $b) { return strcmp($a['slug'], $b['slug']); });
      echo json_encode($out);
    PHP
    json = IO.popen(["php", "-r", script], &:read)
    raise "theme:generate — the oracle pattern dump failed" unless $?.success?

    JSON.parse(json)
  end

  # The `<head>` assets that are NOT per-block stylesheets. Every one is either a file
  # copied verbatim out of the legacy tree or a string literal in the legacy source; none
  # is reimplemented, for the same reason Composition::Registry.style_for is an asset.
  #
  # Each entry records where it came from so a WordPress point release re-runs this.
  def generate_assets
    inc = File.join(LEGACY_ROOT, "wp-includes")
    files = {
      # script-loader.php — 'wp-block-library' inlines common.min.css.
      "wp-block-library" => File.join(inc, "css/dist/block-library/common.min.css"),
      # block-template.php:322, `wp_enqueue_block_template_skip_link`.
      "wp-block-template-skip-link" => File.join(inc, "css/wp-block-template-skip-link.min.css"),
      # The active theme's own stylesheet. style.css is only served under SCRIPT_DEBUG.
      "#{THEME_SLUG}-style" => File.join(theme_dir, "style.min.css"),
    }
    # The `/*# sourceURL=… */` trailer wp_maybe_inline_styles() appends is the style's
    # registered `src`. ⚠️ It is site-absolute for theme assets and site-RELATIVE for
    # wp-includes assets — an inconsistency in the legacy, visible in every golden file,
    # and reproduced rather than tidied up.
    assets = files.transform_values do |path|
      raise "theme:generate — missing asset #{path}" unless File.exist?(path)

      relative = path.sub(LEGACY_ROOT, "")
      { "css" => File.read(path), "source" => relative,
        "source_url" => relative.start_with?("/wp-includes/") ? relative : "{site}#{relative}" }
    end

    # Two handles carry a string literal rather than a file. Both are extracted from the
    # legacy source by anchor so that an upstream edit shows up as a diff here.
    media = File.read(File.join(inc, "media.php"))
    assets["wp-img-auto-sizes-contain"] = {
      # media.php:2212 — `wp_add_inline_style( $handle, '…' )` inside
      # wp_enqueue_img_auto_sizes_contain_css_fix().
      "css" => php_single_quoted(media[/\$handle\s*=\s*'wp-img-auto-sizes-contain';.*?wp_add_inline_style\(\s*\$handle,\s*'((?:[^'\\]|\\.)*)'/m, 1]),
      "source" => "/wp-includes/media.php:2212",
      "source_url" => "wp-img-auto-sizes-contain-inline-css",
    }
    formatting = File.read(File.join(inc, "formatting.php"))
    assets["wp-emoji-styles"] = {
      # formatting.php:5979 — `$emoji_styles = '…';` inside wp_enqueue_emoji_styles().
      "css" => php_single_quoted(formatting[/\$emoji_styles\s*=\s*'((?:[^'\\]|\\.)*)'/m, 1]),
      "source" => "/wp-includes/formatting.php:5979",
      "source_url" => "wp-emoji-styles-inline-css",
    }
    assets.each_value { |a| raise "theme:generate — empty asset #{a}" if a["css"].to_s.empty? }

    # wp_footer's two JavaScript assets. Both are files; neither is reimplemented.
    assets["wp-emoji-loader"] = {
      "js" => File.read(File.join(inc, "js/wp-emoji-loader.min.js")),
      "source" => "/wp-includes/js/wp-emoji-loader.min.js",
      "source_url" => "{site}/wp-includes/js/wp-emoji-loader.min.js",
    }
    # `_print_emoji_detection_script()`, formatting.php:6036 — four literals whose only
    # other definition is a filter, and AD-01 removed the filter.
    assets["wp-emoji-settings"] = {
      "settings" => {
        "baseUrl" => formatting[/'baseUrl'\s*=>\s*apply_filters\(\s*'emoji_url',\s*'([^']+)'/, 1],
        "ext" => formatting[/'ext'\s*=>\s*apply_filters\(\s*'emoji_ext',\s*'([^']+)'/, 1],
        "svgUrl" => formatting[/'svgUrl'\s*=>\s*apply_filters\(\s*'emoji_svg_url',\s*'([^']+)'/, 1],
        "svgExt" => formatting[/'svgExt'\s*=>\s*apply_filters\(\s*'emoji_svg_ext',\s*'([^']+)'/, 1],
      },
      "source" => "/wp-includes/formatting.php:6036",
    }

    # ── The embed iframe template's three assets (web.embed) ─────────────────────────
    # `wp_enqueue_embed_styles()`, wp-includes/embed.php:1096 — the stylesheet is
    # registered with `false` src and the FILE inlined via wp_add_inline_style(), so its
    # sourceURL trailer is the handle-relative form, exactly like wp-emoji-styles.
    assets["wp-embed-template"] = {
      "css" => File.read(File.join(inc, "css/wp-embed-template.min.css")),
      "source" => "/wp-includes/css/wp-embed-template.min.css",
      "source_url" => "wp-embed-template-inline-css",
    }
    # `print_embed_scripts()`, wp-includes/embed.php:1107 — `trim(file_get_contents())`
    # printed inline with an absolute sourceURL appended.
    assets["wp-embed-template-js"] = {
      "js" => File.read(File.join(inc, "js/wp-embed-template.min.js")),
      "source" => "/wp-includes/js/wp-embed-template.min.js",
      "source_url" => "{site}/wp-includes/js/wp-embed-template.min.js",
    }
    # `get_post_embed_html()`, wp-includes/embed.php:531 — the copy-paste embed code in
    # the share dialog carries this file inline (escaped through esc_textarea).
    assets["wp-embed-js"] = {
      "js" => File.read(File.join(inc, "js/wp-embed.min.js")),
      "source" => "/wp-includes/js/wp-embed.min.js",
      "source_url" => "{site}/wp-includes/js/wp-embed.min.js",
    }
    assets
  end

  # The `<head>` importmap and its modulepreload carry a build hash, not a version number
  # — `?ver=efaa5193bbad9c60ffd1` — which the parity normalizer does NOT strip (it only
  # matches `ver=<digits>.<digits>`, normalizer.rb:76). So the hash has to be right, and
  # it is read from the same generated manifest `wp_default_script_modules()` reads.
  #
  # ⚠️ ALL of them, not just the ones a screen happened to print. This generator
  # previously kept `@wordpress/interactivity` alone, on the reasoning that "the corpus
  # screens print exactly one" — and that was wrong: `core/navigation` enqueues
  # `@wordpress/block-library/navigation/view` when the menu is interactive
  # (navigation.php:955), which was the single remaining divergence on web.not_found_404.
  # A manifest that records only what was observed is a fixture, not a manifest.
  #
  # `wp_default_script_modules()`, script-modules.php:180. The id is built from the file
  # name by stripping `.min` / `.js` and a trailing `/index`, then prefixing `@wordpress/`.
  # fetchpriority and in_footer are set for the interactivity, block-library and a11y
  # families (:200); every `@wordpress/block-library/*` module is additionally marked as
  # able to load on client navigation (:209), which is what puts `data-wp-router-options`
  # on its printed tag.
  ID_FROM_FILE = %r{(?:/index)?(?:\.min)?\.js\z}
  LOW_PRIORITY_PREFIXES = ["@wordpress/interactivity", "@wordpress/block-library"].freeze

  def generate_script_modules
    manifest = File.read(File.join(LEGACY_ROOT, "wp-includes", "assets", "script-modules-packages.php"))
    modules = {}
    manifest.scan(/'([^']+\.js)'\s*=>\s*array\((.*?)'version'\s*=>\s*'([^']+)'/m) do |file_name, body, version|
      id = "@wordpress/#{file_name.sub(ID_FROM_FILE, "")}"
      # `'dependencies' => array( '@wordpress/interactivity', … )`. Static imports only —
      # the manifest records no dynamic ones, and only static dependencies are preloaded
      # (class-wp-script-modules.php:print_script_module_preloads).
      dependencies = body.scan(/'(@wordpress\/[^']+)'/).flatten
      low = LOW_PRIORITY_PREFIXES.any? { |p| id.start_with?(p) } || id == "@wordpress/a11y"
      modules[id] = {
        "src" => "/wp-includes/js/dist/script-modules/#{file_name.sub(/\.js\z/, "")}.min.js",
        "version" => version,
        # ':200 — set together; the module is printed in the footer, not the head.
        "fetchpriority" => low ? "low" : "auto",
        "in_footer" => low,
        # :209 — "Marks all Core blocks as compatible with client-side navigation."
        "client_navigation" => id.start_with?("@wordpress/block-library"),
        "dependencies" => dependencies,
      }
    end
    raise "theme:generate — parsed no script modules" if modules.empty?

    modules
  end

  # PHP single-quoted strings escape exactly two characters.
  def php_single_quoted(raw) = raw.to_s.gsub("\\'", "'").gsub("\\\\", "\\")

  # ── load ───────────────────────────────────────────────────────────────────────────

  desc "Load db/theme/*.json into PostgreSQL (theme, templates, parts, patterns, theme.json)"
  task load: :environment do
    require "json"
    read = ->(name) { JSON.parse(File.read(File.join(OUT_DIR, name))) }
    meta = read.call("theme.meta.json")
    slug = meta.fetch("slug")

    ActiveRecord::Base.transaction do
      theme = Presentation::Theme.find_or_initialize_by(slug: slug)
      theme.version = meta["version"].presence || "0"
      theme.parent_slug = meta["parent_slug"]
      # Wave 4 (console.themes): the human name and screenshot live in the row's
      # theme.json so Presentation::Theme#name/#screenshot_url can render the list
      # without a `name` column. Merged from theme.meta.json, non-destructively.
      theme_json = read.call("theme.json")
      theme_json["name"] = meta["name"] if meta["name"].present?
      theme.theme_json = theme_json
      theme.active = true
      theme.save!
      # BR-MIGRATE-001…006: exactly one theme is active.
      Presentation::Theme.where.not(id: theme.id).update_all(active: false)

      # Idempotent by construction: the theme's OWN documents are replaced wholesale,
      # while templates belonging to any other theme_slug — the seeded `wp_template` rows
      # (lib/seeding/pipeline.rb:689), which carry no wp_theme term and therefore do not
      # belong to this theme — are left untouched. That asymmetry is the legacy's own:
      # get_block_templates() filters by the wp_theme term.
      Composition::Template.where(theme_slug: slug).delete_all
      templates = read.call("templates.json")
      templates.each do |row|
        Composition::Template.create!(
          theme_slug: slug, kind: row["kind"], slug: row["slug"],
          area: row["area"], title: row["title"], content: row["content"]
        )
      end

      patterns = read.call("patterns.json")
      patterns.each do |row|
        record = Composition::Pattern.find_or_initialize_by(slug: row["slug"])
        record.assign_attributes(
          title: row["title"], content: row["content"],
          description: row["description"].to_s, inserter: row["inserter"] != false,
          categories: row["categories"] || []
        )
        record.save!
      end

      puts "  theme            #{slug} #{theme.version}#{" (child of #{theme.parent_slug})" if theme.parent_slug}"
      puts "  templates        #{templates.count { |r| r["kind"] == "template" }}"
      puts "  parts            #{templates.count { |r| r["kind"] == "part" }}"
      puts "  patterns         #{patterns.length}"
      puts "  theme.json       #{theme.theme_json.keys.sort.join(", ")}"
    end
  end

  desc "theme:generate followed by theme:load"
  task sync: %i[generate load]
end
