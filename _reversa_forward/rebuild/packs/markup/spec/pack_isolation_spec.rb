# frozen_string_literal: true

require "yaml"
require_relative "markup_helper"

# topology_decision.md option 3: the three packs are leaves with zero declared
# dependencies. bin/check_cycles enforces the declaration; these examples enforce that the
# source actually honours it, which the declaration alone cannot.
RSpec.describe "markup pack isolation" do
  MARKUP_APP_DIR = File.expand_path("../app/markup", __dir__)
  MARKUP_SOURCES = Dir[File.join(MARKUP_APP_DIR, "*.rb")].sort.freeze

  it "declares zero dependencies" do
    package = YAML.safe_load_file(File.expand_path("../package.yml", __dir__))

    expect(package["dependencies"]).to eq([])
    expect(package["enforce_dependencies"]).to be true
  end

  it "requires nothing at all — not Rails, not ActiveSupport, not another pack" do
    offenders = MARKUP_SOURCES.select do |file|
      File.readlines(file).any? { |line| line.match?(/^\s*require(_relative)?\s/) }
    end

    expect(offenders).to be_empty
  end

  it "names no constant from Rails, ActiveSupport or a sibling pack" do
    forbidden = /\b(Rails|ActiveRecord|ActiveSupport|ActionView|ApplicationRecord|
                   Sanitizing|Styling)\b/x

    offenders = MARKUP_SOURCES.reject { |file| File.basename(file) == "named_character_references.rb" }
                       .flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?("#")

        "#{File.basename(file)}:#{index + 1}" if line.match?(forbidden)
      end
    end

    expect(offenders).to be_empty
  end

  it "uses no ActiveSupport core extension that plain Ruby does not provide" do
    core_ext = /\.(blank\?|present\?|presence|deep_dup|deep_symbolize_keys|squish|
                  underscore|camelize|constantize|safe_constantize|to_sentence|
                  in_groups_of|days|hours|minutes|ago|from_now)\b/x

    offenders = MARKUP_SOURCES.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?("#")

        "#{File.basename(file)}:#{index + 1}" if line.match?(core_ext)
      end
    end

    expect(offenders).to be_empty
  end

  it "keeps every class inside the Markup module, as Zeitwerk expects" do
    MARKUP_SOURCES.each do |file|
      expected = File.basename(file, ".rb").split("_").map(&:capitalize).join
      # `utf8.rb` -> `Utf8`, `byte_scan.rb` -> `ByteScan`, and so on.
      expect(Markup.const_defined?(expected, false)).to be(true), "#{file} should define Markup::#{expected}"
    end
  end

  it "loads and runs in a bare Ruby process with no gems and no Rails" do
    loader = File.expand_path("../spec/markup_helper.rb", __dir__)
    script = <<~RUBY
      require #{loader.inspect}
      raise "Rails leaked in" if defined?(::Rails)
      raise "ActiveSupport leaked in" if defined?(::ActiveSupport)
      p1 = Markup::TagProcessor.new("<div a=1><p>x</p></div>")
      p1.next_tag
      p1.set_attribute("b", "2")
      print p1.get_updated_html
    RUBY

    require "open3"
    out, err, status = Open3.capture3("ruby", "--disable-gems", "-e", script)

    expect(status).to be_success, err
    # A new attribute is inserted right after the tag name, exactly as the legacy does.
    expect(out).to eq('<div b="2" a=1><p>x</p></div>')
  end
end
