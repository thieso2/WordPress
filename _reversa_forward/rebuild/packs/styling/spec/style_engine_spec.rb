# frozen_string_literal: true

require_relative 'styling_helper'

# Every expectation in this file was produced by running the PHP oracle
# (_reversa_forward/oracle/wordpress) and copying its output verbatim.
RSpec.describe Styling::StyleEngine do
  describe 'BR-MIGRATE-219: class names and inline styles for the same style object' do
    it 'returns css, declarations and classnames together' do
      expect(described_class.get_styles({ 'color' => { 'text' => 'red' } })).to eq(
        'css' => 'color:red;',
        'declarations' => { 'color' => 'red' },
        'classnames' => 'has-text-color'
      )
    end

    it 'derives both a class name and a custom property from one preset value' do
      expect(described_class.get_styles({ 'color' => { 'text' => 'var:preset|color|heavenlyBlue' } })).to eq(
        'css' => 'color:var(--wp--preset--color--heavenly-blue);',
        'declarations' => { 'color' => 'var(--wp--preset--color--heavenly-blue)' },
        'classnames' => 'has-text-color has-heavenly-blue-color'
      )
    end

    it 'emits only class names when convert_vars_to_classnames is set' do
      expect(
        described_class.get_styles(
          { 'color' => { 'text' => 'var:preset|color|heavenlyBlue' } },
          convert_vars_to_classnames: true
        )
      ).to eq('classnames' => 'has-text-color has-heavenly-blue-color')
    end

    it 'wraps the declarations in a rule when given a selector' do
      result = described_class.get_styles(
        { 'color' => { 'text' => '#cccccc', 'background' => '#000', 'gradient' => 'var:preset|gradient|nice' } },
        selector: '.foo'
      )
      expect(result['css']).to eq(
        '.foo{color:#cccccc;background-color:#000;background:var(--wp--preset--gradient--nice);}'
      )
      expect(result['classnames']).to eq('has-text-color has-background has-nice-gradient-background')
    end

    it 'expands box-model hashes into longhand properties' do
      expect(
        described_class.get_styles(
          { 'spacing' => { 'padding' => { 'top' => '1px', 'left' => 'var:preset|spacing|50' } } }
        )['declarations']
      ).to eq('padding-top' => '1px', 'padding-left' => 'var(--wp--preset--spacing--50)')
    end

    it 'expands individual border sides through the value parser' do
      expect(
        described_class.get_styles(
          { 'border' => { 'top' => { 'color' => 'var:preset|color|red', 'width' => '1px', 'style' => 'solid' } } }
        )['declarations']
      ).to eq(
        'border-top-color' => 'var(--wp--preset--color--red)',
        'border-top-width' => '1px',
        'border-top-style' => 'solid'
      )
    end

    it 'wraps a background image url object in url()' do
      expect(
        described_class.get_styles(
          { 'background' => { 'backgroundImage' => { 'url' => 'https://example.com/a.png' } } }
        )['declarations']
      ).to eq('background-image' => "url('https://example.com/a.png')")
    end

    it 'combines gradient and image into one comma-separated background-image' do
      expect(
        described_class.get_styles(
          { 'background' => { 'backgroundImage' => "url('https://example.com/a.png')",
                              'gradient' => 'var:preset|gradient|g1' } }
        )['declarations']
      ).to eq(
        'background-image' => "var(--wp--preset--gradient--g-1), url('https://example.com/a.png')"
      )
    end

    it "treats '0' as a valid value but empty string as absent" do
      expect(described_class.get_styles({ 'color' => { 'text' => '0' } })['declarations']).to eq('color' => '0')
      expect(described_class.get_styles({ 'color' => { 'text' => '' } })).to eq({})
    end

    it 'returns an empty hash for an empty style object' do
      expect(described_class.get_styles({})).to eq({})
    end

    it 'passes invalid UTF-8 through byte for byte, as PHP does' do
      # PHP strings are byte arrays and safecss_filter_attr() carries no /u
      # modifier. Oracle: wp_style_engine_get_styles() returns
      # ".x{color:ab\xC3\xC3cd;}" for exactly this input.
      bad = "ab\xC3\xC3cd".dup.force_encoding(Encoding::UTF_8)
      css = described_class.get_styles({ 'color' => { 'text' => bad } }, selector: '.x')['css']
      expect(css.b).to eq("\x2Ex{color:ab\xC3\xC3cd;}".b)
    end

    it 'yields an empty slug for a preset value that is not valid UTF-8' do
      # PCRE's /u makes _wp_to_kebab_case() bail, so no custom property and no
      # slug-derived class survive; the unconditional class still does. Oracle
      # returns exactly array('classnames' => 'has-text-color').
      bad = "var:preset|color|ab\xC3\xC3cd".dup.force_encoding(Encoding::UTF_8)
      expect(described_class.get_styles({ 'color' => { 'text' => bad } }))
        .to eq('classnames' => 'has-text-color')
    end
  end

  describe 'BR-MIGRATE-216: declarations are sanitized when added' do
    it 'sanitizes the property name at add time' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('COLOR!!', 'red')
      expect(declarations.declarations).to eq('color' => 'red')
    end

    it 'rejects non-string values at add time rather than at render time' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('color', ['red'])
      declarations.add_declaration('width', 3)
      declarations.add_declaration('height', nil)
      expect(declarations.declarations).to eq({})
    end

    it 'trims the value and drops it when it becomes empty' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('color', "  red\t")
      declarations.add_declaration('width', "  \n ")
      expect(declarations.declarations).to eq('color' => 'red')
    end

    it 'drops a property whose sanitized name is empty' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('!!!', 'red')
      expect(declarations.declarations).to eq({})
    end

    it 'applies the CSS safety filter when rendering, as the legacy does' do
      declarations = Styling::CssDeclarations.new('color' => 'red', 'evil' => 'x', 'height' => 'expression(1)')
      # All three survive `add`; only the safe one survives rendering.
      expect(declarations.declarations.keys).to eq(%w[color evil height])
      expect(declarations.declarations_string).to eq('color:red;')
    end

    it 'appends !important only when the filter returns a single declaration' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('color', 'red', 'important' => true)
      expect(declarations.declarations_string).to eq('color:red !important;')
    end

    it 'drops the important option when it is false' do
      declarations = Styling::CssDeclarations.new
      declarations.add_declaration('color', 'red', 'important' => false)
      expect(declarations.declaration_options).to eq({})
    end

    it 'strips tags from the value at render time' do
      declarations = Styling::CssDeclarations.new('color' => '<b>red</b>')
      expect(declarations.declarations_string).to eq('color:red;')
    end
  end

  describe 'BR-MIGRATE-216: CSS safety filter parity' do
    {
      'color:red' => 'color:red',
      'evil-property:red' => '',
      'color:red;evil:1;font-size:2px' => 'color:red;font-size:2px',
      'color:red}body{color:blue' => '',
      'color:red;/*comment*/' => 'color:red',
      'background-image:url(javascript:alert(1))' => '',
      "background-image:url('https://example.com/a.png')" => "background-image:url('https://example.com/a.png')",
      'color:var(--wp--preset--color--foo)' => 'color:var(--wp--preset--color--foo)',
      'width:calc(100% - 2px)' => 'width:calc(100% - 2px)',
      '--wp--custom--foo: 12px' => '--wp--custom--foo: 12px',
      '--wp--custom--foo: alert(1)' => '',
      'background:linear-gradient(90deg, rgb(1,2,3), blue)' => 'background:linear-gradient(90deg, rgb(1,2,3), blue)'
    }.each do |input, expected|
      it "filters #{input.inspect} to #{expected.inspect}" do
        expect(Styling::CssSafety.safecss_filter_attr(input)).to eq(expected)
      end
    end
  end
end
