# frozen_string_literal: true

require 'json'
require_relative 'styling_helper'

RSpec.describe Styling::ThemeJsonResolver do
  let(:store) { Styling::InMemoryGlobalStylesStore.new }
  let(:stylesheet) { 'twentytwentyfive' }

  let(:core_data) do
    { 'version' => 3,
      'settings' => { 'color' => { 'palette' => [{ 'slug' => 'black', 'color' => '#000' }],
                                   'defaultPalette' => true } },
      'styles' => { 'color' => { 'text' => 'core' } } }
  end
  let(:block_data) { { 'version' => 3, 'styles' => { 'color' => { 'text' => 'blocks' } } } }
  let(:theme_data) do
    { 'version' => 3,
      'settings' => { 'color' => { 'palette' => [{ 'slug' => 'brand', 'color' => '#f00' }] } },
      'styles' => { 'color' => { 'text' => 'theme' } } }
  end

  def resolver(**overrides)
    described_class.new(
      **{ store: store, stylesheet: stylesheet, core_data: core_data,
          block_data: block_data, theme_data: theme_data }.merge(overrides)
    )
  end

  def write_user(config)
    store.write(stylesheet, JSON.generate(config.merge('isGlobalStylesUserThemeJSON' => true)))
  end

  describe 'BR-MIGRATE-206: the four origins merge in order' do
    it 'lets each later origin override the earlier ones' do
      write_user('version' => 3, 'styles' => { 'color' => { 'text' => 'user' } })
      merged = resolver.merged_data.raw_data
      expect(merged['styles']['color']['text']).to eq('user')
    end

    it 'keeps each origin layer addressable inside the presets' do
      merged = resolver.merged_data('theme').raw_data
      expect(merged['settings']['color']['palette']).to eq(
        'default' => [{ 'slug' => 'black', 'color' => '#000' }],
        'theme' => [{ 'slug' => 'brand', 'color' => '#f00' }]
      )
    end

    it 'drops theme presets that collide with a protected default slug' do
      colliding = { 'version' => 3,
                    'settings' => { 'color' => { 'palette' => [{ 'slug' => 'black', 'color' => '#111' },
                                                               { 'slug' => 'brand', 'color' => '#f00' }] } } }
      merged = resolver(theme_data: colliding).merged_data('theme').raw_data
      expect(merged['settings']['color']['palette']['theme']).to eq([{ 'slug' => 'brand', 'color' => '#f00' }])
    end
  end

  describe 'BR-MIGRATE-207: get_merged_data stops the cascade at the named origin' do
    before { write_user('version' => 3, 'styles' => { 'color' => { 'text' => 'user' } }) }

    it 'stops at default' do
      expect(resolver.merged_data('default').raw_data['styles']['color']['text']).to eq('core')
    end

    it 'stops at blocks' do
      expect(resolver.merged_data('blocks').raw_data['styles']['color']['text']).to eq('blocks')
    end

    it "answers 'what would the theme alone produce?'" do
      merged = resolver.merged_data('theme').raw_data
      expect(merged['styles']['color']['text']).to eq('theme')
      expect(merged['settings']['color']['palette']).not_to have_key('custom')
    end

    it 'includes the user origin by default' do
      expect(resolver.merged_data.raw_data['styles']['color']['text']).to eq('user')
    end
  end

  describe 'BR-MIGRATE-208: one wp_global_styles record per theme, created on first access' do
    it 'creates the record the first time the id is asked for' do
      expect(store.find_for_theme(stylesheet)).to be_nil
      instance = resolver
      expect(instance.user_global_styles_id).to eq(1)
      expect(store.find_for_theme(stylesheet)).not_to be_nil
    end

    it 'seeds the new record with the legacy content, title and slug' do
      resolver.user_global_styles_id
      record = store.find_for_theme(stylesheet)
      expect(record['content']).to eq('{"version": 3, "isGlobalStylesUserThemeJSON": true }')
      expect(record['title']).to eq('Custom Styles')
      expect(record['name']).to eq('wp-global-styles-twentytwentyfive')
    end

    it 'url-encodes the stylesheet into the slug' do
      store.create_for_theme('my theme/v2')
      expect(store.find_for_theme('my theme/v2')['name']).to eq('wp-global-styles-my+theme%2Fv2')
    end

    it 'keeps exactly one record per theme' do
      resolver.user_global_styles_id
      first = store.find_for_theme(stylesheet)
      expect(store.create_for_theme(stylesheet)).to be(first)
    end

    it 'ignores content that is not flagged isGlobalStylesUserThemeJSON' do
      store.write(stylesheet, JSON.generate('version' => 3, 'styles' => { 'color' => { 'text' => 'unsafe' } }))
      expect(resolver.user_data.raw_data).to eq('version' => 3)
    end

    it 'ignores content that is not valid JSON' do
      store.write(stylesheet, '{ not json')
      expect(resolver.user_data.raw_data).to eq('version' => 3)
    end

    it 'reads a flagged document and strips the flag' do
      write_user('version' => 3, 'styles' => { 'color' => { 'text' => 'user' } })
      expect(resolver.user_data.raw_data).to eq(
        'version' => 3, 'styles' => { 'color' => { 'text' => 'user' } }
      )
    end
  end

  describe 'BR-MIGRATE-209: the user global-styles id is memoized for the request' do
    it 'asks the store only once' do
      instance = resolver
      expect(instance.user_global_styles_id).to eq(1)

      allow(store).to receive(:find_for_theme).and_raise('store must not be consulted again')
      allow(store).to receive(:create_for_theme).and_raise('store must not be consulted again')

      expect(instance.user_global_styles_id).to eq(1)
    end

    it 'scopes the memo to the resolver instance, not the process' do
      resolver.user_global_styles_id
      other_store = Styling::InMemoryGlobalStylesStore.new
      other = described_class.new(store: other_store, stylesheet: 'other-theme')
      expect(other_store.find_for_theme('other-theme')).to be_nil
      expect(other.user_global_styles_id).to eq(1)
    end
  end

  describe 'BR-MIGRATE-210: the user origin cannot override PROTECTED_PROPERTIES' do
    it 'strips spacing.blockGap out of the user document' do
      write_user('version' => 3, 'styles' => { 'spacing' => { 'blockGap' => '9em' }, 'color' => { 'text' => 'user' } })
      expect(resolver.user_data.raw_data['styles']).to eq('color' => { 'text' => 'user' }, 'spacing' => {})
    end

    it 'leaves the theme origin free to set it' do
      theme = { 'version' => 3, 'styles' => { 'spacing' => { 'blockGap' => '2em' } } }
      write_user('version' => 3, 'styles' => { 'spacing' => { 'blockGap' => '9em' } })
      merged = resolver(theme_data: theme).merged_data.raw_data
      expect(merged['styles']['spacing']['blockGap']).to eq('2em')
    end

    it 'can be turned off to reproduce 7.2-alpha exactly' do
      write_user('version' => 3, 'styles' => { 'spacing' => { 'blockGap' => '9em' } })
      raw = resolver(enforce_protected_properties: false).user_data.raw_data
      expect(raw['styles']['spacing']['blockGap']).to eq('9em')
    end
  end
end
