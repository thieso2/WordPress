# frozen_string_literal: true

require 'open3'
require 'yaml'
require_relative 'styling_helper'

# topology_decision.md option 3: three packs, each with ZERO declared
# dependencies. These specs are the executable form of that decision.
RSpec.describe 'styling pack isolation' do
  APP_DIR = File.expand_path('../app/styling', __dir__)
  PACKAGE_YML = File.expand_path('../package.yml', __dir__)

  it 'declares no dependencies' do
    package = YAML.safe_load(File.read(PACKAGE_YML))
    expect(package['enforce_dependencies']).to be(true)
    expect(package['dependencies']).to eq([])
  end

  it 'never requires Rails, ActiveSupport or another pack' do
    offenders = Dir[File.join(APP_DIR, '*.rb')].filter_map do |path|
      source = File.read(path)
      bad = source.scan(/^\s*require(?:_relative)?\s+['"]([^'"]+)['"]/).flatten
      forbidden = bad.grep(/\A(rails|active_|action_|app\/|markup|sanitizing)/)
      [File.basename(path), forbidden] unless forbidden.empty?
    end
    expect(offenders).to be_empty
  end

  it 'references no constant from a sibling pack' do
    # Comment lines are stripped first so prose about the boundary cannot be
    # mistaken for a reference across it.
    source = Dir[File.join(APP_DIR, '*.rb')].map { |path| File.read(path) }.join("\n")
    source = source.lines.grep_v(/\A\s*#/).join
    expect(source).not_to match(/\bMarkup::/)
    expect(source).not_to match(/\bSanitizing::/)
    expect(source).not_to match(/\bActiveRecord\b|\bActiveSupport\b|\bApplicationRecord\b/)
  end

  it 'loads and works in a bare Ruby process with no Rails on the load path' do
    script = <<~RUBY
      $LOAD_PATH.unshift #{File.expand_path('../app', __dir__).inspect}
      %w[php_compat css_safety css_declarations css_rule css_rules_store
         css_rules_store_registry processor block_style_definitions style_engine
         block_type block_type_registry block_supports theme_json_schema
         fluid_typography theme_json core_theme_data layout_definitions selectors
         blocks_metadata stylesheet global_stylesheet
         global_styles_store in_memory_global_styles_store theme_json_resolver]
        .each { |f| require "styling/\#{f}" }
      abort('rails leaked into the pack') if defined?(Rails) || defined?(ActiveSupport)
      print Styling::StyleEngine.get_styles({ 'color' => { 'text' => 'red' } })['css']
    RUBY

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '--disable-gems', '-e', script)
    expect(status).to be_success, stderr
    expect(stdout).to eq('color:red;')
  end
end
