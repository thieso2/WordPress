# frozen_string_literal: true

# The SITE-DATA half of the theme pipeline — the facts `/wp/v2/themes`,
# `/wp/v2/global-styles/themes/*` and `/wp/v2/templates` answer with that
# `rake theme:generate` never extracted, because until the REST site-data surface existed
# nothing read them:
#
#   * the theme's style.css HEADERS (description, author, tags, requires_*, textdomain) and
#     its `theme_supports` block — facts about the theme's FILES, not about the cascade;
#   * `get_default_block_template_types()` / `get_allowed_block_template_part_areas()` —
#     core's own tables, which supply every template's `description` and the site editor's
#     area vocabulary;
#   * the theme's STYLE VARIATIONS (`styles/*.json`, `styles/colors/*.json`,
#     `styles/typography/*.json`) — what `/global-styles/themes/<t>/variations` returns;
#   * the theme's BLOCK style-variation partials (`styles/blocks/*.json`,
#     `styles/sections/*.json`) — which `WP_Theme_JSON_Resolver::get_theme_data()` injects
#     into `styles.blocks.<type>.variations.<slug>` before the cascade runs, and whose
#     absence was the ONLY difference between the rebuild's merged theme data and the
#     oracle's (6 keys: core/column, core/group, core/heading, core/paragraph and the
#     `variations` of core/columns and core/post-terms);
#   * the registered BLOCK PATTERN CATEGORIES.
#
# ⚠️ Same discipline as `theme:generate`'s pattern dump: nothing here is hand-copied.
# 75 of the theme's assets only exist after PHP has run, and `theme_supports` is the
# product of `add_theme_support()` calls spread across core defaults and the theme's
# functions.php. Rather than reimplement either, this ASKS THE ORACLE — which is the
# ground truth for every behavioural question in this migration — and freezes the answer
# into db/theme/site_data.json. The oracle is needed to GENERATE, never to RUN.
#
# A separate file, and a separate namespace, so that `rake theme:sync` keeps working
# untouched: this is additive data, read at request time by Presentation::ThemeSiteData
# exactly the way Presentation::Assets reads db/theme/assets.json.
namespace :theme do
  namespace :site_data do
    SITE_DATA_OUT = File.expand_path("../../db/theme", __dir__)

    desc "Generate db/theme/site_data.json from the oracle (theme headers, supports, template types, style variations, pattern categories)"
    task :generate do
      require "json"
      require "fileutils"

      bootstrap = ENV.fetch(
        "ORACLE_BOOTSTRAP",
        "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
      )
      theme_slug = ENV.fetch("THEME", "twentytwentyfive")

      # Everything below is READ from the oracle's own registries and resolvers. The two
      # REST controllers are invoked through `rest_do_request` rather than re-derived,
      # because `theme_supports` is assembled from `get_registered_theme_features()` and
      # per-feature `prepare_callback`s that exist only inside a booted WordPress.
      script = <<~PHP
        require #{bootstrap.dump};
        wp_set_current_user(1);

        $slug = #{theme_slug.dump};
        $out = array();

        // ── /wp/v2/themes?context=edit&status=active, verbatim ────────────────────
        $req = new WP_REST_Request('GET', '/wp/v2/themes');
        $req->set_query_params(array('context' => 'edit', 'status' => 'active'));
        $themes = rest_do_request($req)->get_data();
        $theme = $themes[0];
        unset($theme['_links']);
        // The URL fields are the ORACLE's host; store them site-relative so the rebuild
        // renders them against its own home_url (PublicApi::Url).
        $home = home_url();
        foreach (array('screenshot', 'stylesheet_uri', 'template_uri') as $field) {
          if (isset($theme[$field]) && is_string($theme[$field])) {
            $theme[$field] = str_replace($home, '', $theme[$field]);
          }
        }
        // ⚠️ `Tags` is the one header whose value depends on WHICH WordPress is running
        // the call. WP_Theme::display('Tags', false, true) translates the slugs to their
        // display names via get_theme_feature_list(), which only exists once
        // wp-admin/includes/theme.php is loaded — true in this bootstrap, FALSE in a real
        // REST request. The oracle's live response therefore carries the raw slugs, and so
        // must the frozen copy. Rebuilt from the header rather than trusted from the call.
        $tags = wp_get_theme($slug)->get('Tags');
        $tags = is_array($tags) ? array_values($tags) : array();
        $theme['tags'] = array('raw' => $tags, 'rendered' => implode(', ', $tags));
        $out['theme'] = $theme;

        // ── core's own tables ─────────────────────────────────────────────────────
        $types = array();
        foreach (get_default_block_template_types() as $tslug => $type) {
          $types[(string) $tslug] = $type;
        }
        $out['default_template_types'] = $types;
        $out['default_template_part_areas'] = get_allowed_block_template_part_areas();

        // ── /wp/v2/block-patterns/categories, verbatim ────────────────────────────
        $cats = array();
        foreach (WP_Block_Pattern_Categories_Registry::get_instance()->get_all_registered() as $c) {
          $cats[] = array(
            'name' => $c['name'],
            'label' => $c['label'],
            'description' => isset($c['description']) ? $c['description'] : '',
          );
        }
        $out['block_pattern_categories'] = $cats;

        // ── the theme's style variations ──────────────────────────────────────────
        // ⚠️ Taken from the ENDPOINT, not from get_style_variations() directly. The
        // controller registers the theme's block style-variation partials FIRST
        // (:644-645, wp_register_block_style_variations_from_theme_json_partials), and
        // that registration is what puts `styles.blocks.core/group` &co. into each
        // variation document. Calling the resolver on its own returns the same list with
        // those keys absent — which is exactly the 50-key diff the first cut produced.
        $req = new WP_REST_Request('GET', '/wp/v2/global-styles/themes/' . $slug . '/variations');
        $req->set_query_params(array('context' => 'view'));
        $out['style_variations'] = rest_do_request($req)->get_data();

        // ── the block style-variation partials ────────────────────────────────────
        // WP_Theme_JSON_Resolver::get_theme_data() injects each partial at
        // styles.blocks.<blockType>.variations.<slug>. Frozen here in exactly that
        // shape, with `var:preset|…` values UNRESOLVED — Styling::ThemeJson's
        // constructor runs resolve_custom_css_format() over `styles`, so the conversion
        // to `var(--wp--…)` happens in the rebuild, not here.
        $partials = array();
        foreach (WP_Theme_JSON_Resolver::get_style_variations('block') as $variation) {
          if (empty($variation['blockTypes']) || empty($variation['slug'])) { continue; }
          foreach ($variation['blockTypes'] as $block_type) {
            if (!isset($partials[$block_type])) { $partials[$block_type] = array(); }
            $partials[$block_type][$variation['slug']] =
              isset($variation['styles']) ? $variation['styles'] : array();
          }
        }
        $out['block_style_variations'] = $partials;

        echo json_encode($out);
      PHP

      json = IO.popen(["php", "-r", script], &:read)
      raise "theme:site_data:generate — the oracle dump failed" unless $?.success?

      data = JSON.parse(json)
      raise "theme:site_data:generate — no theme" if data["theme"].nil?
      raise "theme:site_data:generate — no style variations" if data["style_variations"].to_a.empty?
      raise "theme:site_data:generate — no pattern categories" if data["block_pattern_categories"].to_a.empty?

      FileUtils.mkdir_p(SITE_DATA_OUT)
      path = File.join(SITE_DATA_OUT, "site_data.json")
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      puts format("  %-22s %s", "site_data.json", "#{File.size(path)} bytes")
      puts "  theme                #{data.dig("theme", "stylesheet")} #{data.dig("theme", "version")}"
      puts "  template types       #{data["default_template_types"].length}"
      puts "  part areas           #{data["default_template_part_areas"].length}"
      puts "  pattern categories   #{data["block_pattern_categories"].length}"
      puts "  style variations     #{data["style_variations"].length}"
      puts "  block variations     #{data["block_style_variations"].keys.length} block types"
    end
  end
end
