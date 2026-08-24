# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'styling_helper'

# `WP_Theme_JSON::get_stylesheet()` and everything under it, compared to the live
# PHP oracle rather than to hand-written expectations.
#
# handoff.md's rule for this pack: prefer a DIFFERENTIAL spec. A hand-written
# expectation for a 16 KB stylesheet would be a transcription of the output, and
# a transcription cannot catch a transcription error. Every assertion below is
# "PHP said X" — including the block metadata the generator runs on.
RSpec.describe 'Styling::Stylesheet vs the PHP oracle' do
  # Methods, not constants: `differential_spec.rb` already names ORACLE_BOOTSTRAP
  # and ORACLE_BRIDGE at the top level, and a second definition would warn.
  def bootstrap_path = '/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php'
  def bridge_path = File.expand_path('support/oracle.php', __dir__)
  def rebuild_root = File.expand_path('../../..', __dir__)

  def oracle_available?
    File.exist?(bootstrap_path) && system('sh', '-c', 'command -v php > /dev/null 2>&1')
  end

  def oracle(calls)
    stdout, stderr, status = Open3.capture3(
      { 'WP_ORACLE_BOOTSTRAP' => bootstrap_path }, 'php', bridge_path,
      stdin_data: JSON.generate(calls)
    )
    raise "oracle failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  # The generated block.json data the application feeds the pack. Read here so the
  # spec exercises the same input the request does.
  def block_definitions
    @block_definitions ||= JSON.parse(File.read(File.join(rebuild_root, 'db/blocks/types.json')))
  end

  def theme_document
    @theme_document ||= JSON.parse(File.read(File.join(rebuild_root, 'db/theme/theme.json')))
  end

  def merged_tree
    Styling::ThemeJsonResolver.new(
      store: Styling::InMemoryGlobalStylesStore.new, stylesheet: 'twentytwentyfive',
      core_data: Styling::CoreThemeData::DATA,
      block_data: Styling::ThemeJsonResolver.block_data_from_definitions(block_definitions),
      theme_data: theme_document
    ).merged_data('custom')
  end

  def generator
    Styling::Stylesheet.new(merged_tree, Styling::BlocksMetadata.build(block_definitions), block_definitions)
  end

  before { skip 'PHP oracle not available' unless oracle_available? }

  # ── the selector algebra ────────────────────────────────────────────────────

  # rubocop:disable RSpec/LeakyConstantDeclaration
  SELECTOR_CORPUS = [
    '.wp-block', '.one, .two', ':is(.a, .b), .c', '[data-label="Save, continue"],.fallback',
    'lang(zh, "*-hant"), .foo', '.foo\\,bar,.baz', '.a /* a, the first */,.b',
    'h1, h2, h3, h4, h5, h6', "  .padded ,\t.other  ", '.a<!--, b-->,.c',
    'a:where(:not(.wp-element-button))', '.x:nth-child(1), .y',
    '.wp-element-caption, .wp-block-audio figcaption, .wp-block-video figcaption',
    'textarea, input:where([type=email],[type=number])', ''
  ].freeze
  # rubocop:enable RSpec/LeakyConstantDeclaration

  it 'splits a selector list exactly as split_selector_list() does' do
    expected = oracle(SELECTOR_CORPUS.map { |s| { 'fn' => 'split_selector_list', 'selector' => s } })
    SELECTOR_CORPUS.each_with_index do |selector, i|
      expect(Styling::Selectors.split_selector_list(selector)).to eq(expected[i]), "case #{selector.inspect}"
    end
  end

  it 'appends and prepends to every branch exactly as the legacy does' do
    appends = [':hover', ':focus-visible', '.is-style-x', ' > *']
    calls = SELECTOR_CORPUS.flat_map do |s|
      appends.flat_map do |a|
        [{ 'fn' => 'append_to_selector', 'selector' => s, 'append' => a },
         { 'fn' => 'prepend_to_selector', 'selector' => s, 'prepend' => a }]
      end
    end
    expected = oracle(calls)
    i = 0
    SELECTOR_CORPUS.each do |s|
      appends.each do |a|
        expect(Styling::Selectors.append_to_selector(s, a)).to eq(expected[i]), "append #{s.inspect} + #{a.inspect}"
        expect(Styling::Selectors.prepend_to_selector(s, a)).to eq(expected[i + 1]), "prepend #{a.inspect} + #{s.inspect}"
        i += 2
      end
    end
  end

  it 'scopes and variation-classes selectors exactly as the legacy does' do
    scopes = ['.editor-styles-wrapper', '.a, .b', '']
    calls = scopes.flat_map { |scope| SELECTOR_CORPUS.map { |s| { 'fn' => 'scope_selector', 'scope' => scope, 'selector' => s } } }
    calls += SELECTOR_CORPUS.map { |s| { 'fn' => 'block_style_variation_selector', 'variation' => 'custom', 'selector' => s } }
    expected = oracle(calls)
    i = 0
    scopes.each do |scope|
      SELECTOR_CORPUS.each do |s|
        expect(Styling::Selectors.scope_selector(scope, s)).to eq(expected[i]), "scope #{scope.inspect} #{s.inspect}"
        i += 1
      end
    end
    SELECTOR_CORPUS.each do |s|
      expect(Styling::Selectors.block_style_variation_selector('custom', s)).to eq(expected[i]), "variation #{s.inspect}"
      i += 1
    end
  end

  # ── fluid typography ────────────────────────────────────────────────────────

  it 'matches wp_get_typography_font_size_value() exactly' do
    settings = { 'typography' => { 'fluid' => true }, 'layout' => { 'wideSize' => '1340px' } }
    presets = [
      { 'size' => '1rem' }, { 'size' => '0.875rem' }, { 'size' => '2.15rem' },
      { 'size' => '1rem', 'fluid' => { 'min' => '1rem', 'max' => '1.125rem' } },
      { 'size' => '1.38rem', 'fluid' => { 'min' => '1.125rem', 'max' => '1.375rem' } },
      { 'size' => '1.75rem', 'fluid' => { 'min' => '1.75rem', 'max' => '2rem' } },
      { 'size' => '2.15rem', 'fluid' => { 'min' => '2.15rem', 'max' => '3rem' } },
      { 'size' => '20px' }, { 'size' => '14px' }, { 'size' => '13px' },
      { 'size' => '1.5em' }, { 'size' => 24 }, { 'size' => '3vw' },
      { 'size' => '1rem', 'fluid' => false }, { 'size' => 0 },
      { 'size' => 'clamp(1rem, 2vw, 3rem)' }
    ]
    # ⚠️ Every variant states `layout` explicitly. The legacy fills the gaps from
    # `wp_get_global_settings()` (typography.php:591); the port has no global to
    # fall back to and uses what it is given. On the real call path they are the
    # same value — `compute_style_properties` and `settings_values_by_slug` both
    # pass the document's merged root settings — so the difference is only
    # reachable by handing this function a PARTIAL settings array, as here.
    variants = [
      settings,
      { 'typography' => { 'fluid' => false }, 'layout' => { 'wideSize' => '1340px' } },
      { 'typography' => { 'fluid' => { 'minFontSize' => '16px', 'maxViewportWidth' => '1000px' } },
        'layout' => { 'wideSize' => '1340px' } }
    ]
    calls = variants.flat_map { |s| presets.map { |p| { 'fn' => 'typography_font_size_value', 'preset' => p, 'settings' => s } } }
    expected = oracle(calls)
    i = 0
    variants.each do |s|
      presets.each do |preset|
        expect(Styling::FluidTypography.font_size_value(preset, s)).to eq(expected[i]),
                                                                      "preset #{preset.inspect} settings #{s.inspect}"
        i += 1
      end
    end
  end

  # ── block metadata ──────────────────────────────────────────────────────────

  it 'derives the same block metadata as WP_Theme_JSON::get_blocks_metadata()' do
    expected = oracle([{ 'fn' => 'blocks_metadata' }]).first
    mine = Styling::BlocksMetadata.build(block_definitions)

    # ⚠️ Two known, reported absences, asserted so they cannot grow silently:
    #  * core/post-comments is registered at runtime as a deprecated alias and is
    #    in no block.json, so the generated registry has no row for it.
    #  * core/list's `checkmark-list` variation is registered through
    #    WP_Block_Styles_Registry, not block.json. AD-01 removed runtime
    #    registration, so block.json's `styles` array is the whole set here.
    expect(expected.keys - mine.keys).to eq(['core/post-comments'])
    expect(mine.keys - expected.keys).to be_empty

    differing = (expected.keys & mine.keys).reject { |name| expected[name] == mine[name] }
    expect(differing).to eq(['core/list'])
    expect(mine['core/list']).to eq(expected['core/list'].reject { |k, _| k == 'styleVariations' })
  end

  it 'merges the four origins into the same document the oracle merges them into' do
    # The 'blocks' origin is not directly reachable through the bridge, so it is
    # compared through the document it feeds: the merged tree.
    expected = oracle([{ 'fn' => 'merged_theme_json' }]).first
    mine = merged_tree.raw_data

    expect(mine['settings']).to eq(expected['settings'])

    # ⚠️ `variations` is excluded: `sanitize()`'s schema pruning is not ported
    # (README §3), so a `styles.blocks.*.variations` entry the legacy drops
    # survives here. It reaches no CSS — `include_block_style_variations` is false
    # on every front-end path — and `get_block_nodes` ignores the key.
    strip = ->(node) { node.is_a?(Hash) ? node.reject { |k, _| k == 'variations' } : node }
    (expected['styles']['blocks'].keys & mine['styles']['blocks'].keys).each do |name|
      expect(strip.call(mine['styles']['blocks'][name]))
        .to eq(strip.call(expected['styles']['blocks'][name])), "styles.blocks.#{name}"
    end
  end

  # ── the stylesheet itself ───────────────────────────────────────────────────

  it 'generates wp_get_global_stylesheet() byte for byte' do
    expected = oracle([{ 'fn' => 'global_stylesheet', 'filter_block_nodes' => true }]).first
    got = Styling::GlobalStylesheet.new(
      theme_json: merged_tree,
      blocks_metadata: Styling::BlocksMetadata.build(block_definitions),
      block_definitions: block_definitions
    ).stylesheet
    expect(got).to eq(expected)
  end

  it 'generates every per-block ruleset byte for byte, in the same order' do
    expected = oracle([{ 'fn' => 'global_style_block_nodes' }]).first
    gen = generator
    mine = gen.styles_block_nodes.map do |metadata|
      { 'path' => metadata['path'], 'selector' => metadata['selector'], 'css' => gen.styles_for_block(metadata) }
    end

    # ⚠️ Two structural differences, both asserted so neither can grow silently.
    #
    # 1. `unwrap_shared_block_style_variations()` is not ported, so the four nodes
    #    it invents are absent. All four produce the EMPTY string in the oracle.
    #    (An element node and its `:hover` node share a path, so membership is
    #    tested on the whole path list, not on a path-keyed map.)
    paths = mine.map { |n| n['path'] }
    missing = expected.reject { |node| paths.include?(node['path']) }
    expect(missing.map { |n| n['path'] }).to eq(
      [%w[styles blocks core/heading], %w[styles blocks core/paragraph],
       %w[styles blocks core/group], %w[styles blocks core/column]]
    )
    expect(missing.map { |n| n['css'] }).to all(eq(''))
    expect(mine.map { |n| n['path'] } - expected.map { |n| n['path'] }).to be_empty

    # 2. The 'blocks' origin's key ORDER follows `db/blocks/types.json`
    #    (alphabetical) rather than the legacy's registration order, so four nodes
    #    sit at a different index. All four generate the empty string, so what
    #    reaches the page — the ordered sequence of NON-EMPTY rulesets — is
    #    identical, and that is what this asserts.
    expect(mine.reject { |n| n['css'].empty? }).to eq(expected.reject { |n| n['css'].empty? })
  end

  it 'BR-MIGRATE-211: the root custom-property selector is :root and the root block selector is body' do
    variables = generator.get_stylesheet(['variables'], %w[default theme custom], { 'skip_block_nodes' => true })
    expect(variables).to start_with(':root{--wp--preset--')

    styles = generator.get_stylesheet(['styles'], %w[default theme custom], { 'skip_block_nodes' => true })
    # `body{…}` unwrapped — NOT `:root :where(body)`, which would be 0-1-0.
    expect(styles).to include('body{background-color: var(--wp--preset--color--base);')
    expect(styles).not_to include(':root :where(body)')
  end

  it 'BR-MIGRATE-212: every preset becomes both a custom property and a utility class' do
    origins = %w[default theme custom]
    variables = generator.get_stylesheet(['variables'], origins, { 'skip_block_nodes' => true })
    presets = generator.get_stylesheet(['presets'], origins, { 'skip_block_nodes' => true })

    expect(variables).to include('--wp--preset--color--accent-1: #FFEE58;')
    expect(presets).to include('.has-accent-1-color{color: var(--wp--preset--color--accent-1) !important;}')
    expect(presets).to include('.has-accent-1-background-color{background-color: var(--wp--preset--color--accent-1) !important;}')
    # Duotone declares `css_vars => nil`, so it must produce neither.
    expect(variables).not_to include('--wp--preset--duotone--')
  end

  it 'BR-MIGRATE-213: viewport breakpoints become media queries around the block rulesets' do
    doc = {
      'version' => 3,
      'settings' => { 'viewport' => { 'mobile' => '480px', 'tablet' => '782px' } },
      'styles' => { 'blocks' => { 'core/group' => {
        '@mobile' => { 'spacing' => { 'padding' => { 'top' => '4px' } } },
        '@tablet' => { 'spacing' => { 'padding' => { 'top' => '8px' } } }
      } } }
    }
    tree = Styling::ThemeJson.new(doc, 'theme')
    metadata = Styling::BlocksMetadata.build('core/group' => { 'name' => 'core/group' })
    css = Styling::Stylesheet.new(tree, metadata).get_stylesheet(['styles'], %w[theme])
    # The breakpoint VALUES were validated and normalized before they became
    # queries, and the tablet range is bounded below by the mobile breakpoint.
    expect(css).to include('@media (width <= 480px){:root :where(.wp-block-group){padding-top: 4px;}}')
    expect(css).to include('@media (480px < width <= 782px){:root :where(.wp-block-group){padding-top: 8px;}}')

    # An unsafe breakpoint is rejected outright and the defaults are used, so
    # nothing an attacker writes reaches a media query.
    hostile = Styling::ThemeJson.new(
      doc.merge('settings' => { 'viewport' => { 'mobile' => "480px)\n or (width > 0" } }), 'theme'
    )
    hostile_css = Styling::Stylesheet.new(hostile, metadata).get_stylesheet(['styles'], %w[theme])
    expect(hostile_css).to include('@media (width <= 480px)')
    expect(hostile_css).not_to include('width > 0')
  end

  it 'BR-MIGRATE-214: exactly the styleable elements get element nodes' do
    styled = Styling::ThemeJson::ELEMENTS.keys.to_h { |el| [el, { 'color' => { 'text' => 'red' } }] }
    tree = Styling::ThemeJson.new({ 'version' => 3, 'styles' => { 'elements' => styled.merge('nope' => { 'color' => { 'text' => 'red' } }) } }, 'theme')
    nodes = Styling::Stylesheet.style_nodes(tree.raw_data)
    element_paths = nodes.map { |n| n['path'] }.select { |p| p[1] == 'elements' }.map(&:last)
    expect(element_paths).to eq(Styling::ThemeJson::ELEMENTS.keys)
    expect(element_paths).to include('link', 'heading', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'button', 'caption', 'cite')
  end
end
