# frozen_string_literal: true

require_relative 'styling_helper'

RSpec.describe Styling::BlockSupports do
  let(:registry) { Styling::BlockTypeRegistry.new }
  let(:supports) { described_class.new }

  let(:block_type) do
    Styling::BlockType.new(
      'test/plain',
      attributes: {
        'align' => { 'type' => 'string', 'default' => 'left' },
        'count' => { 'type' => 'number', 'default' => 3 },
        'flag' => { 'type' => 'boolean' },
        'noDefault' => { 'type' => 'string' }
      }
    )
  end

  before { registry.register(block_type) }

  def apply(block)
    supports.apply_block_supports(block, registry)
  end

  describe 'BR-MIGRATE-200: only registered block types receive supports' do
    it 'returns nothing for an unregistered block name' do
      supports.register('s', apply: ->(_bt, _a) { { 'class' => 'x' } })
      expect(apply('blockName' => 'test/nope', 'attrs' => {})).to eq({})
    end

    it 'returns nothing when there is no block to render' do
      supports.register('s', apply: ->(_bt, _a) { { 'class' => 'x' } })
      expect(apply(nil)).to eq({})
    end

    it 'applies supports for a registered block name' do
      supports.register('s', apply: ->(_bt, _a) { { 'class' => 'a' } })
      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq('class' => 'a')
    end
  end

  describe 'BR-MIGRATE-201: attributes are space-concatenated, first writer takes the slot' do
    it 'appends later contributions to the same attribute' do
      supports.register('s1', apply: ->(_bt, _a) { { 'class' => 'a' } })
      supports.register('s2', apply: ->(_bt, _a) { { 'class' => 'b', 'style' => 'color:red' } })
      supports.register('s3', apply: ->(_bt, _a) { { 'class' => 'c' } })

      expect(apply('blockName' => 'test/plain', 'attrs' => {}))
        .to eq('class' => 'a b c', 'style' => 'color:red')
    end

    it 'replaces rather than appends when the slot holds an empty string' do
      supports.register('s1', apply: ->(_bt, _a) { { 'class' => '' } })
      supports.register('s2', apply: ->(_bt, _a) { { 'class' => 'b' } })

      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq('class' => 'b')
    end
  end

  describe 'BR-MIGRATE-202: non-scalars and booleans are skipped' do
    it 'keeps strings and numbers and drops everything else' do
      supports.register('s1', apply: lambda { |_bt, _a|
        {
          'boolTrue' => true, 'boolFalse' => false, 'arr' => ['x'], 'hash' => { 'a' => 1 },
          'nul' => nil, 'int' => 5, 'floatInt' => 1.0, 'float' => 1.5, 'str' => 'ok'
        }
      })

      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq(
        'int' => '5', 'floatInt' => '1', 'float' => '1.5', 'str' => 'ok'
      )
    end

    it "never lets true become '1'" do
      supports.register('s1', apply: ->(_bt, _a) { { 'class' => true } })
      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq({})
    end
  end

  describe 'BR-MIGRATE-203: a support without an apply callback contributes nothing' do
    it 'skips it at render time but still registers it' do
      supports.register('s1', name: 's1')
      supports.register('s2', apply: ->(_bt, _a) { { 'class' => 'b' } })

      expect(supports.block_supports.keys).to eq(%w[s1 s2])
      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq('class' => 'b')
    end

    it 'still runs its register_attribute callback' do
      supports.register('s1', register_attribute: lambda { |bt|
        bt.attributes = bt.attributes.merge('added' => { 'type' => 'string', 'default' => 'yes' })
      })
      supports.register_attributes(registry)

      expect(block_type.attributes).to have_key('added')
      supports.register('s2', apply: ->(_bt, attrs) { { 'class' => attrs['added'] } })
      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq('class' => 'yes')
    end
  end

  describe 'BR-MIGRATE-204: schema defaults apply before any support sees them' do
    it 'fills in defaults for missing attributes' do
      seen = []
      supports.register('s', apply: ->(_bt, attrs) { seen << attrs; {} })
      apply('blockName' => 'test/plain', 'attrs' => { 'align' => 'right' })

      expect(seen.first).to eq('align' => 'right', 'count' => 3)
    end

    it 'reverts an invalid value to its default' do
      seen = []
      supports.register('s', apply: ->(_bt, attrs) { seen << attrs; {} })
      apply('blockName' => 'test/plain', 'attrs' => { 'align' => ['bad'], 'count' => 'nope' })

      expect(seen.first).to eq('align' => 'left', 'count' => 3)
    end

    it 'passes an empty bag when the block carries no attrs key' do
      seen = []
      supports.register('s', apply: ->(_bt, attrs) { seen << attrs; {} })
      apply('blockName' => 'test/plain')

      expect(seen.first).to eq({})
    end
  end

  describe 'BR-MIGRATE-205: the block being rendered is explicit state' do
    it 'has no class-level block_to_render' do
      expect(described_class).not_to respond_to(:block_to_render)
    end

    it 'renders two blocks independently from one BlockSupports instance' do
      registry.register(Styling::BlockType.new('test/other', attributes: {}))
      supports.register('s', apply: ->(bt, _a) { { 'class' => "is-#{bt.name.sub('/', '-')}" } })

      expect(apply('blockName' => 'test/plain', 'attrs' => {})).to eq('class' => 'is-test-plain')
      expect(apply('blockName' => 'test/other', 'attrs' => {})).to eq('class' => 'is-test-other')
    end
  end
end
