# frozen_string_literal: true

require_relative '../pack_helper'

# topology_decision.md option 3: three packs, each declaring ZERO dependencies.
# `sanitizing` is a leaf — nothing depends inward on it, which is what lets the
# mutual recursion between kses.php and formatting.php stop being a cycle.
RSpec.describe 'the sanitizing pack is a pure-Ruby leaf' do
  PACK_ROOT = File.expand_path('../../app/sanitizing', __dir__)
  SOURCES = Dir[File.join(PACK_ROOT, '*.rb')].sort.freeze

  it 'declares zero dependencies' do
    manifest = File.read(File.expand_path('../../package.yml', __dir__))
    expect(manifest).to match(/^dependencies: \[\]$/)
    expect(manifest).to match(/^enforce_dependencies: true$/)
  end

  it 'ships every file the pack needs' do
    expect(SOURCES.map { |f| File.basename(f, '.rb') }).to contain_exactly(
      'accents', 'attribute_parser', 'bytes', 'css', 'formatting',
      'html_decoder', 'kses', 'options', 'safe_html', 'tables', 'texturize'
    )
  end

  it 'requires nothing at all — not even from the stdlib' do
    SOURCES.each do |file|
      offenders = File.readlines(file).grep(/^\s*require(_relative)?\s/)
      expect(offenders).to be_empty, "#{File.basename(file)} requires: #{offenders.inspect}"
    end
  end

  it 'never names Rails, ActiveRecord, ActiveSupport or another pack' do
    forbidden = /\b(Rails|ActiveRecord|ActiveSupport|ApplicationRecord|Markup::|Styling::)\b/
    SOURCES.each do |file|
      body = File.read(file).gsub(/^\s*#.*$/, '') # comments may discuss them
      expect(body).not_to match(forbidden), "#{File.basename(file)} references a forbidden constant"
    end
  end

  it 'defines everything inside the Sanitizing module' do
    top_level = SOURCES.flat_map { |f| File.read(f).scan(/^(?:module|class) (\w+)/) }.flatten.uniq
    expect(top_level).to eq(['Sanitizing'])
  end

  it 'cites a rule id and a legacy file:line on the public surface' do
    # Traceability is a hard requirement of this pipeline.
    %w[kses.rb formatting.rb texturize.rb css.rb options.rb].each do |name|
      body = File.read(File.join(PACK_ROOT, name))
      expect(body).to match(/BR-MIGRATE-\d{3}/), "#{name} cites no rule id"
      expect(body).to match(%r{wp-includes/\w[\w-]*\.php:\d+}), "#{name} cites no legacy file:line"
    end
  end

  it 'loads and runs in a bare ruby process with no Rails anywhere' do
    # Asserting `defined?(Rails).nil?` in-process would be a lie: a sibling
    # pack's spec may already have booted Rails into this one. The only honest
    # proof is a fresh interpreter that loads nothing but this pack.
    helper = File.expand_path('../pack_helper.rb', __dir__)
    script = <<~RUBY
      require #{helper.dump}
      abort('RAILS PRESENT') if defined?(Rails)
      print Sanitizing::Kses.wp_kses_post('<b>x</b><script>y</script>')
    RUBY

    output = IO.popen([RbConfig.ruby, '-e', script], &:read)
    expect($?).to be_success
    expect(output).to eq('<b>x</b>y')
  end
end
