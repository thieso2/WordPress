# frozen_string_literal: true

namespace :composition do
  # Generates db/theme_content/<theme>.json: the block markup of the active theme's
  # PATTERNS and TEMPLATE PARTS, which `core/pattern` and `core/template-part` splice
  # into the document.
  #
  # ── Why a generator, and why it runs PHP ────────────────────────────────────────
  # A theme pattern is not a data file. `wp-includes/block-patterns.php` registers each
  # one by INCLUDING the .php file with output buffering on
  # (`_register_theme_block_patterns` → `WP_Block_Patterns_Registry::register`), so a
  # pattern's `content` is whatever that include printed. In Twenty Twenty-Five the
  # printed part is `esc_html_e()` / `esc_attr_x()` / `esc_url( get_template_directory_uri() )`
  # and, in patterns/footer.php, a `printf()` that builds an anchor. Two honest options
  # existed:
  #
  #   (a) strip the `<?php … ?>` spans and emit nothing for them. Cheap, and WRONG in a
  #       way that shows: the 404 heading would render as `<h1></h1>` instead of
  #       "Page not found", and the footer would lose its WordPress link entirely.
  #   (b) evaluate the includes ONCE, at generation time, against the oracle, and ship
  #       the result as an asset.
  #
  # (b) is chosen. It is the same treatment `rake composition:generate_blocks` already
  # gives the per-block CSS — an asset copied out of the legacy tree, not a behaviour
  # reimplemented — and it keeps PHP strictly out of the running system: nothing in
  # `app/` evaluates anything, it reads JSON. Re-run this task when the theme changes.
  #
  # The one host-dependent value, `get_template_directory_uri()`, is tokenized back to
  # {{SITE_URL}} so the asset does not carry the oracle's hostname into the rebuild;
  # Renderers::NavigationBlocks substitutes the target's own `home` setting at render.
  desc "Generate the active theme's pattern and template-part content from the legacy theme"
  task :generate_theme_content do
    require "json"
    require "fileutils"

    bootstrap = ENV.fetch("ORACLE_BOOTSTRAP",
                          "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php")
    abort "oracle bootstrap not found at #{bootstrap}" unless File.exist?(bootstrap)

    php = <<~PHP
      require #{bootstrap.inspect};
      $theme = get_stylesheet();
      $site  = untrailingslashit( home_url( '/' ) );
      $patterns = array();
      foreach ( WP_Block_Patterns_Registry::get_instance()->get_all_registered() as $p ) {
        $patterns[ $p['slug'] ] = array(
          'title'   => $p['title'] ?? '',
          'content' => str_replace( $site, '{{SITE_URL}}', $p['content'] ),
        );
      }
      $parts = array();
      foreach ( _get_block_templates_files( 'wp_template_part' ) as $f ) {
        $parts[ $f['slug'] ] = array(
          'area'    => $f['area'] ?? 'uncategorized',
          'title'   => $f['title'] ?? $f['slug'],
          'content' => str_replace( $site, '{{SITE_URL}}', file_get_contents( $f['path'] ) ),
        );
      }
      echo wp_json_encode( array( 'theme' => $theme, 'patterns' => $patterns, 'parts' => $parts ) );
    PHP

    json = IO.popen(["php", "-r", php], &:read)
    abort "php exited #{$?.exitstatus}" unless $?.success?
    data = JSON.parse(json)

    out_dir = Rails.root.join("db", "theme_content")
    FileUtils.mkdir_p(out_dir)
    path = out_dir.join("#{data.fetch("theme")}.json")
    File.write(path, JSON.pretty_generate(data))

    puts "  theme            #{data["theme"]}"
    puts "  patterns         #{data["patterns"].size}"
    puts "  template parts   #{data["parts"].size}  (#{data["parts"].keys.sort.join(", ")})"
    puts "  wrote            db/theme_content/#{data["theme"]}.json"
  end
end
