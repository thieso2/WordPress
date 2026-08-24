# frozen_string_literal: true

require "json"
require "base64"
require_relative "markup_helper"
require_relative "support/traces"

# Differential tests against the seeded WordPress 7.2-alpha-63330 PHP oracle.
#
# For every input in spec/fixtures/corpus.json the legacy WP_HTML_Tag_Processor and
# WP_HTML_Processor are run under PHP and their behaviour is captured as a canonical
# trace (spec/support/dump_tokens.php); the port produces the same structure
# (spec/support/traces.rb) and the two are compared field for field.
#
# What each compared field covers:
#   tags     — BR-MIGRATE-220/222: the whole token stream, every token's type, name,
#              closer/self-closing flags, comment type, modifiable text and every
#              attribute name with its decoded value.
#   paused   — the incomplete-input signal at the end of a truncated document.
#   mutated  — BR-MIGRATE-220/221: the document after a deterministic program of
#              set_attribute / add_class / remove_class / remove_attribute plus a
#              set_bookmark and a backward seek, serialized by get_updated_html.
#   prefixes — BR-MIGRATE-222: get_attribute_names_with_prefix at every tag, including
#              attributes enqueued but not yet written to the document.
#   tree     — BR-MIGRATE-223/224/226: the fragment parser's token stream with the full
#              breadcrumb path and depth at each token.
#   full     — BR-MIGRATE-223: the whole-document parser, which reaches the insertion
#              modes a BODY fragment never visits.
#   error /
#   message  — BR-MIGRATE-225: which inputs abort, and the verbatim reason.
RSpec.describe "html-api differential parity with the PHP oracle" do
  corpus_path = File.expand_path("fixtures/corpus.json", __dir__)
  corpus = JSON.parse(File.read(corpus_path))

  before(:all) do
    skip "PHP oracle unavailable" unless MarkupOracle.available?
  end

  # One PHP process for the whole corpus: per-example spawning would dominate runtime.
  def self.oracle_traces(corpus)
    @oracle_traces ||= begin
      require "open3"
      script = File.expand_path("support/dump_tokens.php", __dir__)
      inputs = corpus.map { |entry| entry["html"] }
      out, err, status = Open3.capture3("php", script, stdin_data: JSON.generate(inputs))
      raise "PHP oracle failed: #{err}" unless status.success?
      # A fatal inside the WordPress bootstrap is answered with a wp_die() HTML page on
      # stdout, not a non-zero exit, so JSON.parse would report an unrelated syntax error.
      raise "PHP oracle did not return JSON: #{out[0, 200]}" unless out.start_with?("[")

      JSON.parse(out)
    end
  end

  if MarkupOracle.available?
    expected = oracle_traces(corpus)

    corpus.each_with_index do |entry, index|
      it "matches the oracle for #{entry['name']}" do
        html = Base64.decode64(entry["html"])
        actual = MarkupTraces.trace(html)

        %w[tags paused tree error message mutated prefixes full full_error
           full_message seek].each do |field|
          expect(actual[field]).to eq(expected[index][field]),
                                   "field #{field.inspect} diverged for #{entry['name'].inspect}"
        end
      end
    end
  end

  it "covers every kind of input the corpus is meant to include" do
    names = corpus.map { |entry| entry["name"] }
    expect(names).to include("kses", "astral", "quotes", "backslash")
    expect(names).to include("unclosed", "nested-formatting", "misnested-table")
    expect(corpus.length).to be >= 100
  end

  it "reaches several distinct BR-MIGRATE-225 abort paths across the corpus" do
    messages = corpus.filter_map do |entry|
      MarkupTraces.tree_trace(Base64.decode64(entry["html"]))[:message]
    end

    expect(messages.uniq).to include(
      "Cannot reconstruct active formatting elements when advancing and rewinding is required.",
      "Cannot extract common ancestor in adoption agency algorithm.",
      "Foster parenting is not supported.",
      "Cannot process PLAINTEXT elements."
    )
  end
end
