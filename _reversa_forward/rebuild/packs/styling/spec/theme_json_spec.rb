# frozen_string_literal: true

require_relative 'styling_helper'

RSpec.describe Styling::ThemeJson do
  describe 'BR-MIGRATE-211: root selectors' do
    it 'uses :root for custom properties and body for block styles' do
      expect(described_class::ROOT_CSS_PROPERTIES_SELECTOR).to eq(':root')
      expect(described_class::ROOT_BLOCK_SELECTOR).to eq('body')
    end

    it 'strips the root selector from preset classes so they gain no specificity' do
      settings = { 'color' => { 'palette' => { 'theme' => [{ 'slug' => 'brand', 'color' => '#f00' }] } } }

      root = described_class.compute_preset_classes(settings, ':root', ['theme'])
      body = described_class.compute_preset_classes(settings, 'body', ['theme'])
      block = described_class.compute_preset_classes(settings, '.wp-block-quote', ['theme'])

      expect(root).to eq(body)
      expect(root).to start_with('.has-brand-color{color: var(--wp--preset--color--brand) !important;}')
      expect(block).to start_with(':where(.wp-block-quote).has-brand-color{')
    end
  end

  describe 'BR-MIGRATE-212: presets generate custom properties and utility classes' do
    let(:settings) do
      {
        'color' => {
          'palette' => {
            'default' => [{ 'slug' => 'black', 'color' => '#000' }, { 'slug' => 'vividGreen', 'color' => '#0f0' }]
          }
        }
      }
    end

    it 'produces one custom property per preset, slug kebab-cased' do
      expect(described_class.compute_preset_vars(settings, %w[default theme custom])).to eq(
        [
          { 'name' => '--wp--preset--color--black', 'value' => '#000' },
          { 'name' => '--wp--preset--color--vivid-green', 'value' => '#0f0' }
        ]
      )
    end

    it 'renders those properties into a :root ruleset' do
      vars = described_class.compute_preset_vars(settings, ['default'])
      expect(described_class.to_ruleset(':root', vars)).to eq(
        ':root{--wp--preset--color--black: #000;--wp--preset--color--vivid-green: #0f0;}'
      )
    end

    it 'produces every utility class declared in PRESETS_METADATA' do
      expect(described_class.compute_preset_classes(settings, ':root', ['default'])).to eq(
        '.has-black-color{color: var(--wp--preset--color--black) !important;}' \
        '.has-vivid-green-color{color: var(--wp--preset--color--vivid-green) !important;}' \
        '.has-black-background-color{background-color: var(--wp--preset--color--black) !important;}' \
        '.has-vivid-green-background-color{background-color: var(--wp--preset--color--vivid-green) !important;}' \
        '.has-black-border-color{border-color: var(--wp--preset--color--black) !important;}' \
        '.has-vivid-green-border-color{border-color: var(--wp--preset--color--vivid-green) !important;}'
      )
    end

    it 'only reads the origins it is asked for' do
      mixed = {
        'color' => {
          'palette' => {
            'default' => [{ 'slug' => 'black', 'color' => '#000' }],
            'theme' => [{ 'slug' => 'brand', 'color' => '#f00' }]
          }
        }
      }
      expect(described_class.compute_preset_vars(mixed, ['default']).map { |d| d['name'] })
        .to eq(['--wp--preset--color--black'])
      expect(described_class.compute_preset_vars(mixed, %w[default theme]).map { |d| d['name'] })
        .to eq(['--wp--preset--color--black', '--wp--preset--color--brand'])
    end

    it 'emits nothing for duotone, whose css_vars are null' do
      duotone = { 'color' => { 'duotone' => { 'theme' => [{ 'slug' => 'd', 'colors' => %w[#000 #fff] }] } } }
      expect(described_class.compute_preset_vars(duotone, ['theme'])).to eq([])
      expect(described_class.compute_preset_classes(duotone, ':root', ['theme'])).to eq('')
    end

    it 'keeps a valueless font size preset but never renders it' do
      settings = {
        'typography' => {
          'fontSizes' => { 'theme' => [{ 'slug' => 'big', 'size' => '3rem' }, { 'slug' => 'nosize', 'name' => 'x' }] }
        }
      }
      vars = described_class.compute_preset_vars(settings, ['theme'])
      # The legacy value_func returns null, and to_ruleset drops non-strings.
      expect(vars).to eq(
        [
          { 'name' => '--wp--preset--font-size--big', 'value' => '3rem' },
          { 'name' => '--wp--preset--font-size--nosize', 'value' => nil }
        ]
      )
      expect(described_class.to_ruleset(':root', vars)).to eq(':root{--wp--preset--font-size--big: 3rem;}')
    end

    it 'flattens settings.custom into --wp--custom--* properties' do
      settings = {
        'custom' => {
          'lineHeight' => { 'body' => 1.7 },
          'some/property' => 'v',
          'nested' => { 'subProperty' => 'x' }
        }
      }
      expect(described_class.compute_theme_vars(settings)).to eq(
        [
          { 'name' => '--wp--custom--line-height--body', 'value' => 1.7 },
          { 'name' => '--wp--custom--some-property', 'value' => 'v' },
          { 'name' => '--wp--custom--nested--sub-property', 'value' => 'x' }
        ]
      )
    end
  end

  describe 'BR-MIGRATE-213: viewport breakpoints are validated and normalized' do
    it 'falls back to the default breakpoints' do
      expect(described_class.viewport_media_queries).to eq(
        '@mobile' => '@media (width <= 480px)',
        '@tablet' => '@media (480px < width <= 782px)'
      )
    end

    it 'adds the desktop query on request' do
      expect(described_class.viewport_media_queries(nil, include_desktop: true)['@desktop'])
        .to eq('@media (width > 782px)')
    end

    it 'honours custom px breakpoints' do
      expect(described_class.viewport_media_queries({ 'mobile' => '600px', 'tablet' => '900px' })).to eq(
        '@mobile' => '@media (width <= 600px)',
        '@tablet' => '@media (600px < width <= 900px)'
      )
    end

    it 'keeps the authored unit while ordering in pixels' do
      expect(
        described_class.viewport_media_queries({ 'mobile' => '30rem', 'tablet' => '50em' }, include_desktop: true)
      ).to eq(
        '@mobile' => '@media (width <= 30rem)',
        '@tablet' => '@media (30rem < width <= 50em)',
        '@desktop' => '@media (width > 50em)'
      )
    end

    it 'drops tablet when it is not larger than mobile' do
      expect(described_class.viewport_media_queries({ 'mobile' => '900px', 'tablet' => '600px' })).to eq(
        '@mobile' => '@media (width <= 900px)'
      )
    end

    it 'keeps a single valid breakpoint under its own key' do
      expect(described_class.viewport_media_queries({ 'tablet' => '900px' })).to eq(
        '@tablet' => '@media (width <= 900px)'
      )
    end

    it 'rejects percentages, CSS functions and unsupported units' do
      expect(described_class.viewport_media_queries({ 'mobile' => '50%', 'tablet' => '900px' })).to eq(
        '@tablet' => '@media (width <= 900px)'
      )
      # No breakpoint survives validation, so the defaults come back.
      expect(described_class.viewport_media_queries({ 'mobile' => 'calc(10px)', 'tablet' => 'bad' }))
        .to eq(described_class.viewport_media_queries)
      expect(described_class.viewport_media_queries({ 'mobile' => '600vw' }))
        .to eq(described_class.viewport_media_queries)
    end

    it 'trims a valid value before interpolating it' do
      expect(described_class.viewport_media_queries({ 'mobile' => ' 600px ', 'tablet' => '900px' })).to eq(
        '@mobile' => '@media (width <= 600px)',
        '@tablet' => '@media (600px < width <= 900px)'
      )
    end

    it 'anchors the size pattern to the whole string, blocking newline injection' do
      expect(described_class.valid_viewport_breakpoint_size?("600px\n) or (width>0")).to be(false)
    end
  end

  describe 'BR-MIGRATE-214: styleable elements' do
    it 'includes every element the rule enumerates' do
      expect(described_class::ELEMENTS.keys).to include(*%w[link heading h1 h2 h3 h4 h5 h6 button caption cite])
    end

    it 'maps each element to the legacy selector' do
      expect(described_class.element_selector('link')).to eq('a:where(:not(.wp-element-button))')
      expect(described_class.element_selector('heading')).to eq('h1, h2, h3, h4, h5, h6')
      expect(described_class.element_selector('button')).to eq('.wp-element-button, .wp-block-button__link')
      expect(described_class.element_selector('cite')).to eq('cite')
      expect(described_class.element_selector('nope')).to be_nil
    end

    it 'exposes the two elements that own a class name' do
      expect(described_class.element_class_name('button')).to eq('wp-element-button')
      expect(described_class.element_class_name('caption')).to eq('wp-element-caption')
      expect(described_class.element_class_name('link')).to eq('')
    end

    it 'also carries the two elements 7.2-alpha added beyond the rule text' do
      # Recorded as a divergence in README.md.
      expect(described_class::ELEMENTS.keys).to include('textInput', 'select')
    end
  end

  describe 'BR-MIGRATE-215: older versions migrate forward at load time' do
    it 'renames the v1 custom-prefixed settings' do
      migrated = Styling::ThemeJsonSchema.migrate(
        { 'version' => 1,
          'settings' => { 'border' => { 'customRadius' => true },
                          'spacing' => { 'customMargin' => true, 'customPadding' => false },
                          'typography' => { 'customLineHeight' => true } } },
        'theme'
      )
      expect(migrated).to eq(
        'version' => 3,
        'settings' => { 'border' => { 'radius' => true },
                        'spacing' => { 'margin' => true, 'padding' => false },
                        'typography' => { 'lineHeight' => true } }
      )
    end

    it 'renames per-block settings too' do
      migrated = Styling::ThemeJsonSchema.migrate(
        { 'version' => 1, 'settings' => { 'blocks' => { 'core/group' => { 'spacing' => { 'customPadding' => true } } } } },
        'theme'
      )
      expect(migrated['settings']['blocks']['core/group']).to eq('spacing' => { 'padding' => true })
    end

    it 'turns off defaultFontSizes when a v2 theme declares fontSizes' do
      migrated = Styling::ThemeJsonSchema.migrate(
        { 'version' => 2, 'settings' => { 'typography' => { 'fontSizes' => [{ 'slug' => 's', 'size' => '1px' }] } } },
        'theme'
      )
      expect(migrated['settings']['typography']['defaultFontSizes']).to be(false)
      expect(migrated['version']).to eq(3)
    end

    it 'drops spacingScale when a v2 theme also declares spacingSizes' do
      migrated = Styling::ThemeJsonSchema.migrate(
        { 'version' => 2,
          'settings' => { 'spacing' => { 'spacingSizes' => [{ 'slug' => '10', 'size' => '1px' }],
                                         'spacingScale' => { 'steps' => 4 } } } },
        'theme'
      )
      expect(migrated['settings']['spacing']).to eq(
        'spacingSizes' => [{ 'slug' => '10', 'size' => '1px' }], 'defaultSpacingSizes' => false
      )
    end

    it 'leaves the custom origin alone beyond the version bump' do
      migrated = Styling::ThemeJsonSchema.migrate(
        { 'version' => 2, 'settings' => { 'typography' => { 'fontSizes' => [{ 'slug' => 's', 'size' => '1px' }] } } },
        'custom'
      )
      expect(migrated['settings']['typography']).to eq('fontSizes' => [{ 'slug' => 's', 'size' => '1px' }])
    end

    it 'discards a document with no version entirely' do
      expect(Styling::ThemeJsonSchema.migrate({ 'settings' => { 'color' => { 'palette' => [] } } }))
        .to eq('version' => 3)
    end

    it 'migrates on construction, before presets are keyed by origin' do
      theme_json = described_class.new(
        { 'version' => 1,
          'settings' => { 'border' => { 'customRadius' => true },
                          'color' => { 'palette' => [{ 'slug' => 'a', 'color' => '#000' }] } } },
        'theme'
      )
      expect(theme_json.raw_data).to eq(
        'version' => 3,
        'settings' => { 'border' => { 'radius' => true },
                        'color' => { 'palette' => { 'theme' => [{ 'slug' => 'a', 'color' => '#000' }] } } }
      )
    end
  end

  describe 'construction' do
    it 'keys presets by the origin it was given' do
      expect(
        described_class.new({ 'version' => 3, 'settings' => { 'color' => { 'palette' => [{ 'slug' => 'a', 'color' => '#000' }] } } }, 'theme')
          .raw_data['settings']['color']['palette']
      ).to eq('theme' => [{ 'slug' => 'a', 'color' => '#000' }])
    end

    it 'leaves presets that are already keyed by origin alone' do
      already = { 'version' => 3, 'settings' => { 'color' => { 'palette' => { 'theme' => [{ 'slug' => 'a', 'color' => '#000' }] } } } }
      expect(described_class.new(already, 'custom').raw_data).to eq(already)
    end

    it 'falls back to the theme origin for an unknown origin' do
      expect(
        described_class.new({ 'version' => 3, 'settings' => { 'color' => { 'palette' => [{ 'slug' => 'a', 'color' => '#000' }] } } }, 'nonsense')
          .raw_data['settings']['color']['palette'].keys
      ).to eq(['theme'])
    end

    it 'pre-generates spacingSizes from spacingScale' do
      generated = described_class.new(
        { 'version' => 3,
          'settings' => { 'spacing' => { 'spacingScale' => { 'steps' => 4, 'mediumStep' => 16, 'unit' => 'px',
                                                             'operator' => '+', 'increment' => 2 } } } },
        'theme'
      ).raw_data['settings']['spacing']['spacingSizes']['theme']

      expect(generated).to eq(
        [
          { 'name' => 'Small', 'slug' => '40', 'size' => '14px' },
          { 'name' => 'Medium', 'slug' => '50', 'size' => '16px' },
          { 'name' => 'Large', 'slug' => '60', 'size' => '18px' },
          { 'name' => 'X-Large', 'slug' => '70', 'size' => '20px' }
        ]
      )
    end
  end

  describe 'BR-MIGRATE-210: PROTECTED_PROPERTIES cannot be overridden by the user origin' do
    it 'names spacing.blockGap' do
      expect(described_class::PROTECTED_PROPERTIES).to eq('spacing.blockGap' => %w[spacing blockGap])
    end

    it 'removes the protected path from every style node of a user document' do
      user = {
        'version' => 3,
        'styles' => {
          'spacing' => { 'blockGap' => '3em', 'padding' => { 'top' => '1px' } },
          'blocks' => { 'core/group' => { 'spacing' => { 'blockGap' => '9em' } } },
          'elements' => { 'link' => { 'spacing' => { 'blockGap' => '1em' } } }
        }
      }

      expect(described_class.remove_protected_properties(user)).to eq(
        'version' => 3,
        'styles' => {
          'spacing' => { 'padding' => { 'top' => '1px' } },
          'blocks' => { 'core/group' => { 'spacing' => {} } },
          'elements' => { 'link' => { 'spacing' => {} } }
        }
      )
    end

    it 'does not mutate the document it is given' do
      user = { 'version' => 3, 'styles' => { 'spacing' => { 'blockGap' => '3em' } } }
      described_class.remove_protected_properties(user)
      expect(user['styles']['spacing']).to eq('blockGap' => '3em')
    end
  end
end
