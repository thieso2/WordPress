# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'styling_helper'

# Differential tests against the live PHP oracle
# (_reversa_forward/oracle/wordpress, WordPress 7.2-alpha-63330). Skipped when
# PHP or the oracle tree is unavailable, so the pack stays runnable anywhere.
RSpec.describe 'styling pack vs the PHP oracle' do
  ORACLE_BOOTSTRAP = '/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php'
  ORACLE_BRIDGE = File.expand_path('support/oracle.php', __dir__)

  def oracle_available?
    File.exist?(ORACLE_BOOTSTRAP) &&
      system('sh', '-c', 'command -v php > /dev/null 2>&1')
  end

  def oracle(calls)
    stdout, stderr, status = Open3.capture3(
      { 'WP_ORACLE_BOOTSTRAP' => ORACLE_BOOTSTRAP },
      'php', ORACLE_BRIDGE,
      stdin_data: JSON.generate(calls)
    )
    raise "oracle failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  before { skip 'PHP oracle not available' unless oracle_available? }

  it 'matches wp_style_engine_get_styles() exactly' do
    cases = [
      { 'color' => { 'text' => 'red' } },
      { 'color' => { 'text' => 'var:preset|color|heavenlyBlue' } },
      { 'color' => { 'text' => '#cccccc', 'background' => '#000', 'gradient' => 'var:preset|gradient|nice' } },
      { 'spacing' => { 'padding' => { 'top' => '1px', 'left' => 'var:preset|spacing|50' } } },
      { 'border' => { 'top' => { 'color' => 'var:preset|color|red', 'width' => '1px' } } },
      { 'background' => { 'backgroundImage' => { 'url' => 'https://example.com/a.png' },
                          'gradient' => 'var:preset|gradient|g1' } },
      { 'typography' => { 'fontSize' => 'var:preset|font-size|large', 'lineHeight' => '1.5' } },
      { 'dimensions' => { 'aspectRatio' => '16/9', 'minHeight' => '10px' } },
      { 'shadow' => 'var:preset|shadow|sh1' },
      { 'color' => { 'text' => 'expression(alert(1))' } },
      { 'background' => { 'backgroundImage' => { 'url' => 'javascript:alert(1)' } } },
      {}
    ]
    calls = cases.map { |styles| { 'fn' => 'style_engine_get_styles', 'styles' => styles, 'selector' => nil } }
    expected = oracle(calls)

    cases.each_with_index do |styles, i| # rubocop:disable Style/HashEachMethods
      want = expected[i] == [] ? {} : expected[i]
      expect(Styling::StyleEngine.get_styles(styles)).to eq(want), "case #{i}: #{styles.inspect}"
    end
  end

  it 'matches wp_style_engine_get_stylesheet_from_css_rules() exactly, dedup and combine included' do
    cases = [
      { 'rules' => [{ 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                    { 'selector' => '.a', 'declarations' => { 'width' => '3em' } }],
        'optimize' => false, 'prettify' => false },
      { 'rules' => [{ 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                    { 'selector' => '.b', 'declarations' => { 'color' => 'red' } }],
        'optimize' => true, 'prettify' => false },
      { 'rules' => [{ 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                    { 'selector' => '.b', 'declarations' => { 'color' => 'blue' } },
                    { 'selector' => '.c', 'declarations' => { 'color' => 'red' } },
                    { 'selector' => '.d', 'declarations' => { 'color' => 'blue' } }],
        'optimize' => true, 'prettify' => false },
      { 'rules' => [{ 'selector' => '.a, .b', 'declarations' => { 'color' => 'red', 'width' => '3em' } }],
        'optimize' => false, 'prettify' => true },
      { 'rules' => [{ 'selector' => '.a', 'declarations' => { 'color' => 'red' },
                      'rules_group' => '@media (min-width: 80rem)' }],
        'optimize' => false, 'prettify' => true }
    ]
    expected = oracle(cases.map { |c| c.merge('fn' => 'stylesheet_from_css_rules') })

    cases.each_with_index do |c, i|
      got = Styling::StyleEngine.get_stylesheet_from_css_rules(
        c['rules'], optimize: c['optimize'], prettify: c['prettify']
      )
      expect(got).to eq(expected[i]), "case #{i}"
    end
  end

  it 'matches safecss_filter_attr() exactly on adversarial CSS' do
    cases = [
      'color:red', 'evil-property:red', 'color:red}body{color:blue', 'color:red;/*comment*/',
      'background-image:url(javascript:alert(1))', "background-image:url('feed:javascript:alert(1)')",
      "background-image:url('https://example.com/a.png')", 'background:linear-gradient(90deg, rgb(1,2,3), blue)',
      'color:var(--wp--preset--color--foo)', 'width:calc(100% - 2px)', '--wp--custom--foo: url(https://x.test/a.png)',
      '--wp--custom--foo: alert(1)', 'transform:translateX(10px) rotate(3deg)',
      'clip-path:polygon(0 0, 100% 0, 100% 100%)', "color:red\\", 'color:re&d', 'color:red=blue',
      'background-image:url()', "background-image:url('http&#58;//example.com/a.png')", 'noColon', ';;;'
    ]
    expected = oracle(cases.map { |css| { 'fn' => 'safecss_filter_attr', 'css' => css } })

    cases.each_with_index do |css, i|
      expect(Styling::CssSafety.safecss_filter_attr(css)).to eq(expected[i]), "case #{i}: #{css.inspect}"
    end
  end

  it 'matches _wp_to_kebab_case() exactly' do
    cases = ['heavenlyBlue', 'someProperty', '2XLarge', 'foo/bar', 'XMLHttpRequest', 'a1b2c3',
             'ÄÖÜ', 'naïveCafé', '1st2ND3rd', 'snake_case_name', 'mixedUPPERCase', "it's a test"]
    expected = oracle(cases.map { |v| { 'fn' => 'to_kebab_case', 'value' => v } })

    cases.each_with_index do |value, i|
      expect(Styling::PhpCompat.to_kebab_case(value)).to eq(expected[i]), "case #{i}: #{value.inspect}"
    end
  end

  it 'matches WP_Theme_JSON::get_viewport_media_queries() exactly' do
    cases = [
      { 'settings' => nil, 'desktop' => false },
      { 'settings' => nil, 'desktop' => true },
      { 'settings' => { 'mobile' => '30rem', 'tablet' => '50em' }, 'desktop' => true },
      { 'settings' => { 'mobile' => '900px', 'tablet' => '600px' }, 'desktop' => true },
      { 'settings' => { 'mobile' => '50%', 'tablet' => '900px' }, 'desktop' => false },
      { 'settings' => { 'mobile' => 'calc(10px)', 'tablet' => 'bad' }, 'desktop' => false }
    ]
    expected = oracle(cases.map { |c| c.merge('fn' => 'viewport_media_queries') })

    cases.each_with_index do |c, i|
      got = Styling::ThemeJson.viewport_media_queries(c['settings'], include_desktop: c['desktop'])
      expect(got).to eq(expected[i]), "case #{i}"
    end
  end

  it 'matches WP_Theme_JSON_Schema::migrate() exactly' do
    cases = [
      { 'doc' => { 'version' => 1, 'settings' => { 'border' => { 'customRadius' => true } } }, 'origin' => 'theme' },
      { 'doc' => { 'version' => 2, 'settings' => { 'typography' => { 'fontSizes' => [{ 'slug' => 's', 'size' => '1px' }] } } },
        'origin' => 'theme' },
      { 'doc' => { 'version' => 2, 'settings' => { 'spacing' => { 'spacingSizes' => [{ 'slug' => '10', 'size' => '1px' }],
                                                                  'spacingScale' => { 'steps' => 4 } } } },
        'origin' => 'theme' },
      { 'doc' => { 'settings' => { 'color' => { 'palette' => [] } } }, 'origin' => 'theme' }
    ]
    expected = oracle(cases.map { |c| c.merge('fn' => 'theme_json_migrate') })

    cases.each_with_index do |c, i|
      expect(Styling::ThemeJsonSchema.migrate(c['doc'], c['origin'])).to eq(expected[i]), "case #{i}"
    end
  end

  it 'matches WP_Theme_JSON::merge() exactly, spacing scales included' do
    cases = [
      { 'a' => { 'version' => 3, 'settings' => { 'color' => { 'palette' => [{ 'slug' => 'black', 'color' => '#000' }],
                                                              'defaultPalette' => true } } },
        'a_origin' => 'default',
        'b' => { 'version' => 3, 'settings' => { 'color' => { 'palette' => [{ 'slug' => 'black', 'color' => '#111' },
                                                                            { 'slug' => 'brand', 'color' => '#f00' }] } } },
        'b_origin' => 'theme' },
      { 'a' => { 'version' => 3, 'styles' => { 'background' => { 'backgroundImage' => { 'url' => 'a.png', 'id' => 1 } } } },
        'a_origin' => 'theme',
        'b' => { 'version' => 3, 'styles' => { 'background' => { 'backgroundImage' => { 'url' => 'b.png' } } } },
        'b_origin' => 'custom' },
      { 'a' => { 'version' => 3, 'settings' => { 'spacing' => { 'spacingScale' => { 'steps' => 4, 'mediumStep' => 16,
                                                                                    'unit' => 'px', 'operator' => '+',
                                                                                    'increment' => 2 } } } },
        'a_origin' => 'default',
        'b' => { 'version' => 3, 'settings' => { 'spacing' => { 'spacingScale' => { 'increment' => 4 } } } },
        'b_origin' => 'theme' }
    ]
    expected = oracle(cases.map { |c| c.merge('fn' => 'theme_json_merge') })

    cases.each_with_index do |c, i|
      a = Styling::ThemeJson.new(c['a'], c['a_origin'])
      a.merge(Styling::ThemeJson.new(c['b'], c['b_origin']))
      expect(a.raw_data).to eq(expected[i]), "case #{i}"
    end
  end
end
