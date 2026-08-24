# `styling` — style engine, global styles and block supports

Wave 0 pack. Rebuilds, in pure Ruby, the part of WordPress 7.2-alpha-63330 that **turns design
data into CSS**.

`topology_decision.md` merges three legacy modules into this one pack because they are a single
responsibility currently split three ways around a 216 KB god-object (F-GS-01, F-CUST-03):

| Legacy source | What came across |
|---|---|
| `wp-includes/style-engine/` (1,623 lines) | Ported close to whole. F-SIM-03 names it the model for the rest, and it is. |
| `wp-includes/class-wp-theme-json*.php` (7,224 lines) | The rules, the four-origin cascade **and** (Wave 2) the stylesheet generator. See §1 and "Deliberately not ported". |
| `wp-includes/global-styles-and-settings.php`, `script-loader.php`'s `wp_enqueue_global_styles()` | `wp_get_global_stylesheet()` and `wp_add_global_styles_for_blocks()`, as `Styling::GlobalStylesheet`. |
| `wp-includes/block-supports/`, `class-wp-block-supports.php` | The dispatch mechanism (`class-wp-block-supports.php`). The 23 individual support files were not in scope. |

`package.yml` declares **zero dependencies**. The pack requires nothing but the Ruby stdlib —
no Rails, no framework runtime, no sibling pack, nothing from `app/`. `spec/pack_isolation_spec.rb`
proves it by loading the whole pack in a bare `ruby --disable-gems` process.

---

## 1. Rules implemented

All 20 assigned rules are implemented. Every public method carries a `BR-MIGRATE-nnn` citation and
the legacy `file:line` it came from.

### style engine

| Rule | Where | Note |
|---|---|---|
| **BR-MIGRATE-216** — declarations sanitized when added, not when rendered | `app/styling/css_declarations.rb` | See the caveat in §4.1: the legacy splits this, and the split is observable. |
| **BR-MIGRATE-217** — multiple named rule stores coexist, render independently | `app/styling/css_rules_store.rb`, `css_rules_store_registry.rb` | |
| **BR-MIGRATE-218** — the processor deduplicates and combines before output | `app/styling/processor.rb` | Dedup by selector (and by `"group selector"`); combine under `optimize: true`. |
| **BR-MIGRATE-219** — both class names and inline styles from one style object | `app/styling/style_engine.rb`, `block_style_definitions.rb` | `BLOCK_STYLE_DEFINITIONS_METADATA` transcribed verbatim. |

### global styles / theme.json

⚠️ **Wave 2 added the stylesheet GENERATOR.** Wave 0 ported WP_Theme_JSON's four-origin cascade
and stopped there, which left `<style id="global-styles-inline-css">` — 18.7 KB on `web.index`,
21.3 KB on `web.single`, present on all 18 screens — entirely absent from the rebuild. The
generator is `Styling::Stylesheet` (`get_stylesheet` and everything under it),
`Styling::Selectors` (the selector algebra), `Styling::BlocksMetadata` (`get_blocks_metadata` +
`wp_get_block_css_selector`), `Styling::FluidTypography`
(`wp_get_typography_font_size_value`), `Styling::LayoutDefinitions`
(`wp_get_layout_definitions`), `Styling::CoreThemeData` (`wp-includes/theme.json`) and
`Styling::GlobalStylesheet` (`wp_get_global_stylesheet` + `wp_add_global_styles_for_blocks`).

| Rule | Where |
|---|---|
| **BR-MIGRATE-206** — four origins merge in order `default, blocks, theme, custom` | `ThemeJson#merge`, `ThemeJsonResolver#merged_data` |
| **BR-MIGRATE-207** — `merged_data(origin)` stops the cascade at that origin | `ThemeJsonResolver#merged_data` |
| **BR-MIGRATE-208** — one `wp_global_styles` record per theme, created on first access | `GlobalStylesStore` (interface), `InMemoryGlobalStylesStore`, `ThemeJsonResolver#user_global_styles_id` |
| **BR-MIGRATE-209** — the user global-styles id is memoized for the request | `ThemeJsonResolver#user_global_styles_id` |
| **BR-MIGRATE-210** — `PROTECTED_PROPERTIES` cannot be overridden by the user origin | `ThemeJson.remove_protected_properties`, wired into `ThemeJsonResolver#user_data` |
| **BR-MIGRATE-211** — `:root` for custom properties, `body` for block styles | `ThemeJson::ROOT_CSS_PROPERTIES_SELECTOR` / `ROOT_BLOCK_SELECTOR`; `Stylesheet#css_variables`, `#styles_for_block` (the root ruleset is emitted UNWRAPPED, so its specificity stays 0-0-1) |
| **BR-MIGRATE-212** — presets generate custom properties **and** utility classes | `ThemeJson.compute_preset_vars`, `.compute_preset_classes`, `PRESETS_METADATA`; `Stylesheet#css_variables` / `#preset_classes` are the two halves as `get_stylesheet` calls them |
| **BR-MIGRATE-213** — viewport breakpoints validated and normalized to pixels | `ThemeJson.viewport_media_queries` and friends; `Stylesheet.block_nodes` turns them into the responsive nodes and `#styles_for_block` wraps each node's output in its query |
| **BR-MIGRATE-214** — styleable elements | `ThemeJson::ELEMENTS` (see §4.4); `Stylesheet.style_nodes` emits one node per element and `BlocksMetadata.block_element_selectors` scopes them per block |
| **BR-MIGRATE-215** — older theme.json versions migrated forward at load time | `ThemeJsonSchema.migrate`, called from `ThemeJson#initialize` |

### block supports

| Rule | Where |
|---|---|
| **BR-MIGRATE-200** — only registered block types receive supports | `BlockSupports#apply_block_supports` |
| **BR-MIGRATE-201** — attributes space-concatenated, first writer takes the slot | `BlockSupports#apply_block_supports` |
| **BR-MIGRATE-202** — non-scalars **and booleans** skipped entirely | `BlockSupports#apply_block_supports` |
| **BR-MIGRATE-203** — a support without an apply callback contributes nothing at render | `BlockSupports#apply_block_supports`, `#register_attributes` |
| **BR-MIGRATE-204** — attributes pass through `prepare_attributes_for_render()` first | `BlockType#prepare_attributes_for_render` |
| **BR-MIGRATE-205** — the block being rendered is explicit state, not a public static | `BlockSupports#apply_block_supports(block_to_render, registry)` |

---

## 2. Deviations forced by the accepted decisions

### paradigm_decision.md option 1 — no hook system

Every legacy filter is gone. Where the PHP applies one, the pack implements the value **before** the
filter and offers no way to change it. Filters removed, all of them permanently:

- `sanitize_key`, `safe_style_css`, `safecss_filter_attr_allow_css`, `kses_allowed_protocols`
- `wp_theme_json_data_default`, `..._blocks`, `..._theme`, `..._user`

### paradigm_decision.md option 1 — no global mutable state

Four legacy statics became explicit, caller-owned state. Each is a real behavioural change in
*lifetime*, not in *result*:

| Legacy | Here | Rule |
|---|---|---|
| `WP_Style_Engine_CSS_Rules_Store::$stores` (static) | `CssRulesStoreRegistry` instance | 217 |
| `WP_Block_Supports::$block_to_render` (public static) | parameter of `apply_block_supports` | **205** |
| `WP_Block_Type_Registry::get_instance()` (singleton) | `BlockTypeRegistry` instance | 200 |
| `WP_Theme_JSON_Resolver::$user_custom_post_type_id` (static memo) | ivar on the resolver instance | **209** |

For **BR-MIGRATE-205** specifically: the rule as written describes a mechanism (`public static
$block_to_render`) that option 1 forbids. What is preserved is the *observable*: exactly one block
is in scope for a given `apply_block_supports` call, and supports see its prepared attributes. What
is lost is the ability of unrelated code to read or write the current block out of band — which is
the point of removing it.

For **BR-MIGRATE-209**, "for the request" is now "for the lifetime of the resolver instance". The
application is expected to build one resolver per request; the pack cannot enforce that without a
global, which is precisely what option 1 removes.

### topology_decision.md option 3 — zero dependencies

- **BR-MIGRATE-208** names a `wp_global_styles` record. The pack cannot reach the database, so
  storage is an interface the pack **defines** (`GlobalStylesStore`: `find_for_theme`,
  `create_for_theme`) and the application **implements**. `InMemoryGlobalStylesStore` is a working
  reference implementation and is what the specs run against. The legacy's record shape is carried
  through it verbatim: content `{"version": 3, "isGlobalStylesUserThemeJSON": true }`, title
  `Custom Styles` (untranslated in the legacy too, per Trac #54518), slug
  `wp-global-styles-<urlencode(stylesheet)>`.
- `safecss_filter_attr()` and the KSES protocol checks live in `app/styling/css_safety.rb` rather
  than being borrowed from the `sanitizing` pack. Duplication is the cost of the boundary; the
  decision is already made.
- `_wp_to_kebab_case`, `sanitize_key`, `wp_strip_all_tags`, `_wp_array_get/_set`,
  `array_replace_recursive` are ported into `app/styling/php_compat.rb` for the same reason.

---

## 3. Deliberately not ported

Nothing on the list of 20 rules was skipped. These are things *inside* the same legacy files that
were out of scope, with the reason:

| Not ported | Reason |
|---|---|
| ~~`WP_Theme_JSON::get_stylesheet()` and everything under it~~ | **Ported in Wave 2** — `Styling::Stylesheet`. `get_block_classes`, `get_layout_styles`, `get_styles_for_block`, `get_root_layout_rules`, `compute_style_properties`, `get_property_value`, `get_setting_nodes`, `get_style_nodes`, `get_block_nodes`, `get_feature_declarations_for_node`, feature-level selectors, element and block pseudo-selectors, custom states and responsive breakpoint nodes are all in. What is still out is listed below. |
| Block style **variations** (`include_block_style_variations`, `get_block_style_variation_selector`'s consumers inside `get_styles_for_block`) | The option is false on every front-end path — `wp_get_global_stylesheet()` and `wp_add_global_styles_for_blocks()` both leave it unset — so the 180-line branch at `class-wp-theme-json.php:3838` is unreachable in the front end and generates nothing. `Selectors.block_style_variation_selector` and `.block_style_variation_feature_selector` **are** ported, because `get_blocks_metadata` needs them. The editor and `wp_get_block_css_selector`'s variation paths would need the branch. |
| `unwrap_shared_block_style_variations()` | Needs the valid-variation set, which needs the block-styles registry. Consequence, measured against the oracle: four block nodes (`core/heading`, `core/paragraph`, `core/group`, `core/column`) are absent from `get_styles_block_nodes()`. All four generate the **empty string** in the oracle, so no CSS is lost. Pinned by `spec/stylesheet_spec.rb`. |
| `WP_Duotone` / `get_svg_filters()` | Unchanged from Wave 0. The `duotone` selector IS carried in the block metadata and the `filter` declaration IS split onto it (`get_styles_for_block` step 3), so a theme.json duotone reaches CSS; the SVG filter elements do not. |
| `WP_Theme_JSON::sanitize()`'s schema PRUNING — `remove_keys_not_in_schema`, `VALID_SETTINGS`, `VALID_STYLES` | Needs the block registry and is not a listed rule. Consequence: the pack does not strip unknown keys from a theme.json. Wave 2 ported four things that live in the same method but are **rewrites, not pruning**, because leaving them out made `get_stylesheet` diverge: the `VALID_TOP_LEVEL_KEYS` intersection (:1284), `resolve_custom_css_format` (:1466 — `var:preset\|color\|x` → `var(--wp--preset--color--x)`, which every theme.json value uses), `sanitize_viewport_settings` (:1460) and `maybe_opt_in_into_settings` (:1103 — `appearanceTools: true` expanded into 22 individual settings and then removed). Measured: with those four in, the merged document equals the oracle's everywhere except `styles.blocks.*.variations`. |
| `remove_insecure_properties()`, `remove_insecure_settings/styles`, `is_safe_css_declaration` | The user-content security pass for global styles. A real gap — see §5. |
| `get_blocks_metadata()`, `unwrap_shared_block_style_variations()`, `get_valid_block_style_variations()` | Require the global block-type registry and `WP_Block_Styles_Registry`. |
| ~~`wp_get_typography_font_size_value()` fluid path~~ | **Ported in Wave 2** — `Styling::FluidTypography`, with `wp_get_typography_value_and_unit()` and `wp_get_computed_fluid_typography_value()`. Wave 0's reasoning ("core declares no `settings.typography.fluid`") was true of CORE's theme.json and false of the active theme: twentytwentyfive sets `typography.fluid: true`, so every `--wp--preset--font-size--*` on every screen is a `clamp()`. See §4.10 for the one thing that is still different. |
| `get_block_wrapper_attributes()` | Needs `esc_attr()` (→ `wp_check_invalid_utf8` + `_wp_specialchars`), which belongs to another pack. BR-MIGRATE-201 and 202 are fully exercised by `apply_block_supports` without it. |
| The 23 files in `wp-includes/block-supports/` (`layout.php` alone is 62 KB) | The rules assigned are about the **dispatch mechanism**, not the individual supports. Supports are registered by the caller as plain callables. |
| `WP_Duotone`, SVG filters (`get_svg_filters`) | Out of scope; `PRESETS_METADATA` keeps duotone's `css_vars => nil` so it correctly emits nothing. |
| `WP_Theme_JSON_Resolver` theme-file discovery, `get_style_variations`, `get_custom_templates`, `get_template_parts`, `resolve_theme_file_uris` | Filesystem and theme-registry concerns, not rules. The resolver takes the four origins' data as constructor arguments instead. `get_block_data()` **is** ported, as `ThemeJsonResolver.block_data_from_definitions` — it takes the block definitions rather than reading the registry singleton. `resolve_theme_file_uris` is still absent: it rewrites `file:./…` background-image and font URLs to absolute theme URLs, and twentytwentyfive's theme.json declares none in `styles`, so the merged tree is unchanged by it (verified against the oracle). |

Two things were ported **even though no rule required them**, because leaving them out made a rule
that *is* required diverge from the oracle:

- `compute_spacing_sizes()` / `merge_spacing_sizes()` — run by `ThemeJson#initialize` and by
  `merge()`. Without them BR-MIGRATE-206 diverges for any theme declaring
  `settings.spacing.spacingScale`.
- The origin re-keying loop in the constructor — BR-MIGRATE-206's merge is defined over
  origin-keyed presets.

---

## 4. Known divergences from the PHP oracle

### 4.1 BR-MIGRATE-216 overstates the legacy (behaviour preserved, rule text softened)

The rule says "declarations are sanitized when added, not when rendered". In 7.2-alpha the split is:

- **at `add_declaration()`** — the property is run through `sanitize_key()`; non-string values are
  rejected outright; the value is trimmed and dropped if it becomes empty.
- **at `get_declarations_string()`** — `wp_strip_all_tags()` and `safecss_filter_attr()` run
  (`class-wp-style-engine-css-declarations.php:184`, called from `:207`).

The port keeps the legacy timing, because moving the CSS-safety filter to add-time changes
observable output: `BR-MIGRATE-218`'s combine step compares *raw* declarations, and the prettify
spacer is applied inside `filter_declaration`. So the pack is byte-identical to the oracle and the
rule statement is true of the *value-level* sanitization only. `spec/style_engine_spec.rb` asserts
both halves explicitly.

### 4.2 BR-MIGRATE-210 is enforcement the target *adds back*

`grep -rn PROTECTED_PROPERTIES wp-includes/` returns **exactly one hit**: the declaration at
`class-wp-theme-json.php:371`. WordPress 7.2-alpha-63330 no longer references the constant anywhere.
The rule says the user origin cannot override it, so the pack enforces it: `user_data` runs
`ThemeJson.remove_protected_properties` and strips `styles[.blocks.*|.elements.*].spacing.blockGap`.

This is a **deliberate divergence from the oracle**. Pass
`ThemeJsonResolver.new(..., enforce_protected_properties: false)` to reproduce 7.2-alpha exactly;
`spec/theme_json_resolver_spec.rb` covers both directions. Flag for the Inspector: decide whether the
rule or the source is authoritative here.

### 4.3 `prepare_attributes_for_render` validates types and enums only

The legacy calls `rest_validate_value_from_schema()`, which also honours `format`, `pattern`,
`minimum`/`maximum`, `minItems`, `uniqueItems`, `properties`, `additionalProperties`, `oneOf`/`anyOf`
and multi-type coercion. The port (`BlockType.value_valid_for_schema?`) handles `type` (including
unions) and `enum`. **Consequence:** an attribute that violates only a non-type constraint keeps its
value here where the legacy would reset it to the schema default. Verified identical for the type
and enum cases against the oracle.

### 4.4 `ELEMENTS` carries two elements the rule text omits

BR-MIGRATE-214 enumerates `link, heading, h1..h6, button, caption, cite`. 7.2-alpha's
`WP_Theme_JSON::ELEMENTS` also ships `textInput` and `select` (added after the rule was written).
The constant follows the **legacy source**, which is the oracle. The rule's list is a strict subset
and every element it names is present with the legacy selector.

### 4.5 The combine step's legacy null-dereference

`combine_rules_selectors()` builds `$selectors_json` keyed by the **bare selector** but deletes from
`$this->css_rules`, which is keyed `"$rules_group $selector"` for grouped rules
(`class-wp-style-engine-processor.php:147` vs `:88`). When two grouped rules share declarations, PHP 8
dereferences null and fatals. The port skips such a rule instead of raising. Non-grouped rules — the
only case the legacy actually reaches in core — are byte-identical.

### 4.6 PCRE backtrack limits have no Onigmo equivalent

`safecss_filter_attr()` checks `if (null === $css_test_string) continue;` after the recursive
function-stripping `preg_replace`, i.e. it *drops* a declaration whose nesting blew PCRE's
backtrack limit. Onigmo has no such limit, so a pathological input PHP would drop, the port will
process. The port keeps the `null` branch's *intent* but can never take it. Low risk: the branch is
a resource guard, not a security rule, and the `[\\(&=}]|/\*` check still runs on whatever remains.

### 4.7 Float formatting

`PhpCompat.to_php_string` reproduces PHP's `(string)` cast for the case that matters —
`(string)1.0 === "1"` where Ruby's `1.0.to_s == "1.0"` (BR-MIGRATE-202). It does **not** reproduce
PHP's `precision=14` significant-digit rendering for large or repeating floats; Ruby uses the
shortest round-trip representation. `0.1 + 0.2` renders as `0.30000000000000004` here and `0.3` in
PHP. Reachable only through `spacingScale` arithmetic with pathological increments.

### 4.8 `sanitize_title()` for spacing units is restricted

`compute_spacing_sizes()` calls `sanitize_title($spacing_scale['unit'])`. The port
(`ThemeJson.sanitize_unit`) lowercases, keeps `[a-z0-9_-]`, collapses whitespace to dashes and trims.
It does **not** do accent folding (`remove_accents`), percent-decoding, or the HTML-entity pass.
Identical for every real CSS unit; divergent for a deliberately hostile `unit` string.

### 4.9 Reduced node walkers

`ThemeJson.setting_nodes` and `.style_node_paths` derive nodes from the **data** rather than from the
block-type registry (`get_setting_nodes` / `get_block_nodes`). For `settings` this is exactly
equivalent — the legacy walks registered blocks but only ever writes where data exists. For `styles`
the port covers `styles`, `styles.elements.*`, `styles.blocks.*` and `styles.blocks.*.elements.*`;
it does **not** cover `styles.blocks.*.variations.*`. Consequence: a `background.backgroundImage`
inside a block style *variation* merges leaf-wise instead of being replaced wholesale.

---

### 4.10 `wp_get_typography_font_size_value()` has no global settings to fall back on

The legacy fills gaps in the `$settings` argument from `wp_get_global_settings()`
(`block-supports/typography.php:591`, `wp_parse_args`). `Styling::FluidTypography` uses what it
is given. On every path this pack takes they are the same value — `compute_style_properties` and
`settings_values_by_slug` both pass the merged document's root settings, and for a block-level
settings node `settings_values_by_slug` merges the root settings underneath it explicitly. The
difference is reachable only by calling `FluidTypography.font_size_value` directly with a
PARTIAL settings hash: PHP would then read `layout.wideSize` from the site, the port would use
the `1600px` default. `spec/stylesheet_spec.rb` states this where it passes complete settings.

### 4.11 The 'blocks' origin's key ORDER follows the generated registry, not registration order

`WP_Theme_JSON_Resolver::get_block_data()` walks `WP_Block_Type_Registry`, whose order is the
`$block_folders` list in `wp-includes/blocks.php`. `ThemeJsonResolver.block_data_from_definitions`
walks whatever hash it is handed, and the application hands it `db/blocks/types.json`, which
`rake composition:generate_blocks` writes in **alphabetical** order. `array_replace_recursive`
appends new keys in the incoming document's order, so four block nodes — `core/gallery`,
`core/latest-posts`, `core/post-template`, `core/term-template` — sit at a different index in
`get_styles_block_nodes()`.

Measured, not assumed: all four generate the **empty string**, so `wp_add_inline_style()` would
reject them anyway. Rendering every block on one page and comparing produced byte-identical
output. The ordered sequence of non-empty rulesets is asserted in `spec/stylesheet_spec.rb`. The
fix, if the four ever gain styles, belongs in the generator task, not here.

### 4.12 `is_safe_css_declaration()` drops the `esc_html()` wrapper

`class-wp-theme-json.php:5066` is `! empty( trim( esc_html( safecss_filter_attr( $s ) ) ) )`.
`esc_html` lives in another pack, and it can only ever make a non-empty string longer or leave an
empty one empty, so the emptiness test is unchanged. `Stylesheet.safe_css_declaration?` calls
`CssSafety.safecss_filter_attr` and trims.

---

## 5. Security notes for whoever wires this up

- **`remove_insecure_properties()` is not ported.** The legacy runs it over theme and user
  theme.json before the data is trusted. This pack's `ThemeJsonResolver` does **not**. The user
  document is still gated on the `isGlobalStylesUserThemeJSON` flag (the legacy's own "if it's not
  true then the content was not escaped and is not safe" check, ported verbatim), and every value
  that reaches CSS passes `safecss_filter_attr()`, but preset *values* rendered through
  `to_ruleset` do not. Do not accept untrusted theme.json until this is closed.
- **The generator interpolates four things into CSS without passing them through
  `safecss_filter_attr()`, exactly as the legacy does**: preset VALUES (`to_ruleset`), the
  `blockGap` value in `get_root_layout_rules`, `styles.css` custom CSS
  (`process_blocks_custom_css`) and a block's own selectors from `block.json`. Layout rules and
  the root content/wide sizes DO go through it (`Stylesheet.safe_css_declaration?`). With
  `remove_insecure_properties()` still unported, a hostile theme.json or user global-styles
  document reaches CSS unfiltered through those four. The gate remains: do not accept untrusted
  theme.json.
- **`ThemeJson.valid_viewport_breakpoint_size?` is anchored with `\A…\z`, not `^…$`.** This is not
  cosmetic: the value is interpolated straight into a media query, and Ruby's `^`/`$` are *line*
  anchors. A literal translation of the PCRE would have accepted `"600px\n) or (width > 0"`. See §6.

---

## 6. PCRE vs Onigmo — every regex ported

Ruby's Onigmo and PHP's PCRE differ in ways that are silent until they are not. Each regex crossing
over, and what had to change:

| Legacy regex | Ported as | Difference that mattered |
|---|---|---|
| `_wp_to_kebab_case`'s assembled `/…/u` (functions.php:5338) | `PhpCompat::KEBAB_REGEXP` | Three changes. (a) `\x{2000}`, `\xdf` etc. → `\u{2000}`, `\u{df}`: Ruby rejects raw high bytes in a UTF-8 regexp literal. (b) `$` → `\Z`: PHP's `$` (no `/D`) means "end, or before a final newline", which is Ruby's `\Z`, **not** Ruby's `$`. (c) `/u` on invalid UTF-8 makes `preg_match_all` bail and return nothing — Onigmo *raises* instead, so `to_kebab_case` guards with `valid_encoding?` and returns `''`, matching PHP. Verified: PHP `_wp_to_kebab_case("ab\xC3\xC3cd") === ""`. |
| `strtolower()` throughout | `.downcase(:ascii)` | PHP 8's `strtolower` is ASCII-only and locale-independent. Ruby's `downcase` is Unicode-aware and would fold `Ä`→`ä`. |
| `/[^a-z0-9_\-]/` (`sanitize_key`) | identical | — |
| `@<(script\|style)[^>]*?>.*?</\1>@si` (`wp_strip_all_tags`) | `%r{…}mi` | PHP `s` (dotall) is Ruby `m`. PHP `m` (multiline anchors) is Ruby's **default** and must not be added. |
| `/^--[a-zA-Z0-9-_]+$/` (`safecss_filter_attr`) | `/\A--[a-zA-Z0-9\-_]+\z/` | `^`/`$` are line anchors in Ruby. Equivalent here only because `\n\r\t` are stripped upstream; anchored anyway. |
| `/^url\(\s*(['\"]?)(.*)(\g1)\s*\)$/` | `/\Aurl\(\s*(['"]?)(.*)(\1)\s*\)\z/` | PCRE's `\g1` **backreference** syntax is not Ruby's; Ruby writes `\1`. (Ruby's `\g<1>` is a subexpression *call*, which would be wrong here.) Plus the `\A…\z` anchoring. |
| `/url\([^)]+\)/`, `/(?:repeating-)?(?:linear\|radial\|conic)-gradient\((?:[^()]\|\([^()]*\))*\)/` | identical | Neither uses a PCRE-only feature. |
| The CSS-function stripper with PCRE recursion `(?1)` | `\g<1>` (Onigmo subexpression call) | This is the one place where `\g<n>` **is** correct: PCRE `(?1)` and Onigmo `\g<1>` both re-enter group 1, giving balanced-paren matching. Ruby has no `preg_replace` backtrack-limit failure mode — see §4.6. |
| `%[\\\(&=}]\|/\*%` | `/[\\(&=}]\|\/\*/` | PHP's single-quoted string collapses `\\\(` to `\\(`; the class is {`\`, `(`, `&`, `=`, `}`}. Transcribed by value, not by source text. |
| `/[\x00-\x08\x0B\x0C\x0E-\x1F]/`, `/\\+0+/` (`wp_kses_no_null`) | identical | — |
| `/(&#0*58(?![;0-9])\|&#x0*3a(?![;a-f0-9]))/i` + `'$1;'` | same regex, replacement `'\1;'` | PCRE replacement `$1` → Ruby `\1`. |
| `preg_split('/:\|&#0*58;\|&#x0*3a;\|&colon;/i', $c, 2)` | `split(regex, 2)` | Ruby's `split` limit semantics match PHP's here, including a leading empty field. |
| `/\s/` (`wp_kses_bad_protocol_once2`) | `/[ \t\r\n\f\v]/` | PCRE `\s` and Ruby `\s` agree in modern versions, but not historically. Written out as a class so it cannot drift. |
| `/^(?:\d+\|\d*\.\d+)(?:px\|em\|rem)$/` (viewport breakpoints) | `/\A(?:\d+\|\d*\.\d+)(?:px\|em\|rem)\z/` | **Security-relevant.** See §5. |

Also: no regex in `safecss_filter_attr()` or its KSES helpers carries `/u`, so PHP treats the input
as bytes and passes invalid UTF-8 straight through. Ruby raises on such input. `PhpCompat.as_bytes` /
`.as_text` re-tag the string BINARY for the operation and UTF-8 on the way out, so the port produces
the identical byte sequence. Verified: PHP `safecss_filter_attr("color:ab\xC3\xC3cd")` returns
`"color:ab\xC3\xC3cd"`, and so does this pack.

---

## 7. Differential testing

`php` 8.4 and a fully seeded WordPress 7.2-alpha-63330 oracle are available at
`_reversa_forward/oracle/wordpress`. Everything below was compared **string-exactly** against it,
including ordering and whitespace.

`spec/stylesheet_spec.rb` is the Wave 2 half and is entirely differential — a hand-written
expectation for a 16 KB stylesheet is a transcription of the output, and a transcription cannot
catch a transcription error. It compares, against the live oracle:

| Surface | Result |
|---|---|
| `split_selector_list`, `append_to_selector`, `prepend_to_selector`, `scope_selector`, `get_block_style_variation_selector` over a 16-case corpus (comments, strings, escapes, CDO/CDC, nested lists, `:nth-child`) | identical |
| `wp_get_typography_font_size_value()` × 16 presets × 3 settings shapes | identical |
| `WP_Theme_JSON::get_blocks_metadata()` over all 115 generated block definitions | identical but for the two absences in §7.1 |
| `WP_Theme_JSON_Resolver::get_merged_data()` — the whole merged document | `settings` identical; `styles` identical outside `variations` |
| **`wp_get_global_stylesheet()`** with `wp_filter_out_block_nodes` applied | **byte-identical, 16,633 bytes** |
| `get_styles_for_block()` for every block node, in order | byte-identical; see §4.11 |

### 7.1 Two block-metadata absences

* `core/post-comments` is registered at runtime as a deprecated alias of `core/comments` and has
  no `block.json`, so the generated registry has no row for it. theme.json does not style it.
* `core/list`'s `checkmark-list` style variation is registered through `WP_Block_Styles_Registry`
  rather than `block.json`. AD-01 removed runtime registration, so `block.json`'s `styles` array
  is the whole set here. It affects only variation selectors, which the front end does not emit.

`spec/differential_spec.rb` runs a representative subset on every `rspec` run (it skips itself when
PHP or the oracle is absent) via the bridge at `spec/support/oracle.php`. It covers
`wp_style_engine_get_styles()`, `wp_style_engine_get_stylesheet_from_css_rules()` (dedup, combine,
prettify, rules groups), `safecss_filter_attr()`, `_wp_to_kebab_case()`,
`WP_Theme_JSON::get_viewport_media_queries()`, `WP_Theme_JSON_Schema::migrate()` and
`WP_Theme_JSON::merge()`.

A wider one-off harness was run during development. Results, all **identical**:

| Surface | Cases | Result |
|---|---|---|
| `safecss_filter_attr()` — adversarial CSS | 55 | 55/55 |
| `wp_style_engine_get_styles()` | 24 | 24/24 |
| `wp_style_engine_get_stylesheet_from_css_rules()` — incl. `optimize`, `prettify`, rules groups | 15 | 15/15 |
| `WP_Theme_JSON` — migrate, viewport, preset vars/classes/rulesets, merge, construction, 4-origin cascade | 97 | 97/97 |
| `WP_Block_Supports::apply_block_supports()` — via reflection on the singleton | 10 | 10/10 |
| Corpus fuzz (`CORPUS_ASTRAL`, `CORPUS_BACKSLASH`, `CORPUS_QUOTES`, `CORPUS_KSES`, NUL bytes, truncated UTF-8) through `safecss_filter_attr` × 8 properties and through the style engine × 4 shapes, base64-transported so bytes survive | 192 | 192/192 |
| **Total** | **393** | **393/393** |

The `_wp_to_kebab_case` port was checked separately over accented, astral, ordinal, snake_case and
apostrophe inputs: identical.

---

## 8. Running it

```sh
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
bundle exec rspec --pattern "packs/styling/spec/**/*_spec.rb"
```

**144 examples, 0 failures.**

The `--pattern` flag is needed because the project's `.rspec` sets a repo-wide pattern, so
`bundle exec rspec packs/styling/spec` also loads the other packs' specs. Nothing in this pack
depends on them.

`bin/rails zeitwerk:check` passes — every file maps to the constant Zeitwerk expects
(`packs/styling/app/styling/css_rules_store_registry.rb` → `Styling::CssRulesStoreRegistry`, and so
on; one top-level constant per file).

Pack isolation is enforced twice: by `bin/check_cycles` (zero declared dependencies, no reference to
`Markup::`, `Sanitizing::`, any `app/models/<context>` namespace, or any Rails constant) and by
`spec/pack_isolation_spec.rb`.

---

## 9. File map

```
packs/styling/
  package.yml
  README.md
  app/styling/
    php_compat.rb                     # _wp_to_kebab_case, sanitize_key, wp_strip_all_tags,
                                      #   _wp_array_get/_set, array_replace_recursive, byte helpers
    css_safety.rb                     # safecss_filter_attr + the KSES protocol checks
    css_declarations.rb               # BR-216
    css_rule.rb                       # selector + declarations + rules group
    css_rules_store.rb                # BR-217
    css_rules_store_registry.rb       # BR-217 (replaces the static $stores)
    processor.rb                      # BR-218
    block_style_definitions.rb        # BLOCK_STYLE_DEFINITIONS_METADATA, verbatim
    style_engine.rb                   # BR-219 + the public style-engine functions
    block_type.rb                     # BR-204
    block_type_registry.rb            # BR-200
    block_supports.rb                 # BR-200…205
    theme_json_schema.rb              # BR-215
    theme_json.rb                     # BR-206, 210…214 + spacing scales + appearanceTools
    fluid_typography.rb               # wp_get_typography_font_size_value + value_and_unit
    selectors.rb                      # split/append/prepend/scope + variation selectors
    core_theme_data.rb                # wp-includes/theme.json, the 'default' origin
    layout_definitions.rb             # wp_get_layout_definitions(), transcribed
    blocks_metadata.rb                # get_blocks_metadata + wp_get_block_css_selector
    stylesheet.rb                     # BR-211…214: get_stylesheet and everything under it
    global_stylesheet.rb              # wp_get_global_stylesheet + wp_add_global_styles_for_blocks
    global_styles_store.rb            # BR-208 (interface)
    in_memory_global_styles_store.rb  # BR-208 (reference implementation)
    theme_json_resolver.rb            # BR-206…210
  spec/
    styling_helper.rb
    style_engine_spec.rb              # BR-216, 219
    css_rules_store_spec.rb           # BR-217
    processor_spec.rb                 # BR-217, 218
    block_supports_spec.rb            # BR-200…205
    theme_json_spec.rb                # BR-210…215
    theme_json_resolver_spec.rb       # BR-206…210
    stylesheet_spec.rb                # BR-211…214, differential against the oracle
    differential_spec.rb              # live comparison against the PHP oracle
    pack_isolation_spec.rb            # topology_decision.md option 3
    support/oracle.php                # the oracle bridge
```
