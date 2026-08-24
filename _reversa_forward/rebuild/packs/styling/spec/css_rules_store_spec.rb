# frozen_string_literal: true

require_relative 'styling_helper'

RSpec.describe 'BR-MIGRATE-217: named rule stores' do
  let(:registry) { Styling::CssRulesStoreRegistry.new }

  it 'returns the same store object for the same name' do
    expect(registry.store('block-supports')).to be(registry.store('block-supports'))
  end

  it 'keeps distinct stores for distinct names' do
    expect(registry.store('block-supports')).not_to be(registry.store('global-styles'))
    expect(registry.stores.keys).to eq(%w[block-supports global-styles])
  end

  it 'rejects a blank or non-string store name' do
    expect(registry.store('')).to be_nil
    expect(registry.store(nil)).to be_nil
    expect(registry.store(12)).to be_nil
  end

  it 'renders each store independently' do
    Styling::StyleEngine.get_styles(
      { 'color' => { 'text' => 'red' } }, selector: '.a', store: registry.store('block-supports')
    )
    Styling::StyleEngine.get_styles(
      { 'color' => { 'text' => 'blue' } }, selector: '.b', store: registry.store('global-styles')
    )

    expect(Styling::StyleEngine.get_stylesheet_from_store(registry.store('block-supports')))
      .to eq('.a{color:red;}')
    expect(Styling::StyleEngine.get_stylesheet_from_store(registry.store('global-styles')))
      .to eq('.b{color:blue;}')
  end

  it 'creates the rule for a selector once and reuses it' do
    store = registry.store('default')
    rule = store.add_rule('.a')
    expect(store.add_rule('.a')).to be(rule)
    expect(store.all_rules.keys).to eq(['.a'])
  end

  it 'keys a grouped rule by "group selector"' do
    store = registry.store('default')
    store.add_rule('.a', '@media (min-width: 80rem)').add_declarations('color' => 'red')
    expect(store.all_rules.keys).to eq(['@media (min-width: 80rem) .a'])
    expect(Styling::StyleEngine.get_stylesheet_from_store(store))
      .to eq('@media (min-width: 80rem){.a{color:red;}}')
  end

  it 'returns nil for an empty selector' do
    expect(registry.store('default').add_rule('')).to be_nil
    expect(registry.store('default').add_rule(nil)).to be_nil
  end

  it 'clears every store on remove_all_stores' do
    registry.store('a')
    registry.remove_all_stores
    expect(registry.stores).to eq({})
  end
end
