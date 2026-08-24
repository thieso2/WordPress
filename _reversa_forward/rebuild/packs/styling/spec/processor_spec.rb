# frozen_string_literal: true

require_relative 'styling_helper'

# Expectations below are the PHP oracle's output for the same input, compared
# byte for byte — the dedup/combine behaviour is observable only in the string.
RSpec.describe Styling::Processor do
  def stylesheet(rules, **options)
    Styling::StyleEngine.get_stylesheet_from_css_rules(rules, **options)
  end

  describe 'BR-MIGRATE-218: deduplicate' do
    it 'merges declarations of repeated selectors into the first rule' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                     { 'selector' => '.a', 'declarations' => { 'width' => '3em' } }
                   ])
      ).to eq('.a{color:red;width:3em;}')
    end

    it 'merges declarations of repeated grouped selectors' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red' },
                       'rules_group' => '@media (min-width: 80rem)' },
                     { 'selector' => '.a', 'declarations' => { 'width' => '2px' },
                       'rules_group' => '@media (min-width: 80rem)' }
                   ])
      ).to eq('@media (min-width: 80rem){.a{color:red;width:2px;}}')
    end
  end

  describe 'BR-MIGRATE-218: combine' do
    it 'leaves identical rules alone when optimize is off' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                     { 'selector' => '.b', 'declarations' => { 'color' => 'red' } }
                   ])
      ).to eq('.a{color:red;}.b{color:red;}')
    end

    it 'combines selectors with identical declarations when optimize is on' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                     { 'selector' => '.b', 'declarations' => { 'color' => 'red' } }
                   ], optimize: true)
      ).to eq('.a,.b{color:red;}')
    end

    it 'combines declarations that differ only in key order' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red', 'background-color' => 'blue' } },
                     { 'selector' => '.b', 'declarations' => { 'background-color' => 'blue', 'color' => 'red' } }
                   ], optimize: true)
      ).to eq('.a,.b{color:red;background-color:blue;}')
    end

    it 'appends each combined rule at the end, in the legacy order' do
      expect(
        stylesheet([
                     { 'selector' => '.a', 'declarations' => { 'color' => 'red' } },
                     { 'selector' => '.b', 'declarations' => { 'color' => 'blue' } },
                     { 'selector' => '.c', 'declarations' => { 'color' => 'red' } },
                     { 'selector' => '.d', 'declarations' => { 'color' => 'blue' } }
                   ], optimize: true)
      ).to eq('.a,.c{color:red;}.b,.d{color:blue;}')
    end
  end

  describe 'BR-MIGRATE-218: rendering' do
    it 'prettifies with tabs and newlines' do
      expect(
        stylesheet([{ 'selector' => '.a, .b', 'declarations' => { 'color' => 'red', 'width' => '3em' } }],
                   prettify: true)
      ).to eq(".a,\n.b {\n\tcolor: red;\n\twidth: 3em;\n}\n")
    end

    it 'prettifies a grouped rule with nested indentation' do
      expect(
        stylesheet([{ 'selector' => '.a', 'declarations' => { 'color' => 'red' },
                      'rules_group' => '@media (min-width: 80rem)' }], prettify: true)
      ).to eq("@media (min-width: 80rem) {\n\t.a {\n\t\tcolor: red;\n\t}\n}\n")
    end

    it 'skips rules with no selector or no declarations' do
      expect(stylesheet([{ 'selector' => '', 'declarations' => { 'color' => 'red' } }])).to eq('')
      expect(stylesheet([{ 'selector' => '.a', 'declarations' => {} }])).to eq('')
    end

    it 'drops declarations the safety filter rejects' do
      # `evil` is not an allowed property; `notacolor;` survives because the
      # trailing semicolon is swallowed by the declaration split. Both match
      # the PHP oracle exactly.
      expect(
        stylesheet([{ 'selector' => '.a', 'declarations' => { 'color' => 'notacolor;', 'evil' => 'x' } }])
      ).to eq('.a{color:notacolor;}')
    end
  end

  describe 'BR-MIGRATE-217/218: stores feed the processor' do
    it 'pulls rules from every added store' do
      registry = Styling::CssRulesStoreRegistry.new
      registry.store('one').add_rule('.a').add_declarations('color' => 'red')
      registry.store('two').add_rule('.b').add_declarations('color' => 'red')

      processor = described_class.new
      processor.add_store(registry.store('one'))
      processor.add_store(registry.store('two'))

      expect(processor.css(optimize: true)).to eq('.a,.b{color:red;}')
    end

    it 'refuses anything that is not a store' do
      expect { described_class.new.add_store(Object.new) }.to raise_error(ArgumentError)
    end
  end
end
