# frozen_string_literal: true

require_relative '../pack_helper'
require_relative 'corpus'
require_relative 'oracle'
require_relative 'known_divergences'

# ############################################################################
# RISK-005's actual mitigation, and the reason this pack has zero declared
# dependencies: it must be runnable against both engines.
#
# parity_tests/05-kses-sanitization.feature:
#   "Every ported pattern is byte-identical to the PHP original"
#   Given the XSS bypass corpus
#   And the legacy PHP implementation available as an oracle
#   When each corpus entry is sanitized by both implementations
#   Then the outputs are byte-identical for every entry
#
# Any divergence discovered here is either fixed or recorded in README.md with
# its reason. An undocumented divergence is not acceptable output from this
# task; a documented one is.
# ############################################################################
RSpec.describe 'Differential: Ruby port vs the PHP oracle' do
  # Each entry: [oracle function name, ->(input) { ruby result }].
  SUBJECTS = {
    'wp_kses_post' => ->(s) { Sanitizing::Kses.wp_kses_post(s) },
    'wp_kses_data' => ->(s) { Sanitizing::Kses.wp_kses_data(s) },
    'wp_kses_strip' => ->(s) { Sanitizing::Kses.wp_kses(s, 'strip') },
    'wp_kses_user_description' => ->(s) { Sanitizing::Kses.wp_kses(s, 'user_description') },
    'wp_kses_bad_protocol' => lambda { |s|
      Sanitizing::Bytes.utf8(
        Sanitizing::Kses.wp_kses_bad_protocol(s, Sanitizing::Tables::ALLOWED_PROTOCOLS)
      )
    },
    'wp_kses_normalize_entities' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Kses.wp_kses_normalize_entities(s)) },
    'wp_kses_decode_entities' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Kses.wp_kses_decode_entities(s)) },
    'wp_kses_no_null' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Kses.wp_kses_no_null(s)) },
    'wp_kses_stripslashes' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Kses.wp_kses_stripslashes(s)) },
    'safecss_filter_attr' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Css.safecss_filter_attr(s)) },
    'wp_pre_kses_less_than' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting.wp_pre_kses_less_than(s)) },
    'esc_html' => ->(s) { Sanitizing::Formatting.esc_html(s) },
    'esc_attr' => ->(s) { Sanitizing::Formatting.esc_attr(s) },
    'esc_textarea' => ->(s) { Sanitizing::Formatting.esc_textarea(s) },
    'esc_js' => ->(s) { Sanitizing::Formatting.esc_js(s) },
    'esc_url' => ->(s) { Sanitizing::Formatting.esc_url(s) },
    'esc_url_raw' => ->(s) { Sanitizing::Formatting.esc_url_raw(s) },
    'sanitize_key' => ->(s) { Sanitizing::Formatting.sanitize_key(s) },
    'sanitize_title' => ->(s) { Sanitizing::Formatting.sanitize_title(s) },
    'sanitize_title_with_dashes_display' => ->(s) { Sanitizing::Formatting.sanitize_title_with_dashes(s, '', 'display') },
    'remove_accents' => ->(s) { Sanitizing::Formatting.remove_accents(s) },
    'utf8_uri_encode_200' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting.utf8_uri_encode(s, 200)) },
    '_wp_specialchars_xml' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting._wp_specialchars(s, :ent_xml1)) },
    '_wp_specialchars_noquotes' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting._wp_specialchars(s)) },
    'wp_kses_normalize_entities_xml' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Kses.wp_kses_normalize_entities(s, 'xml')) },
    'strip_tags' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting.strip_tags(s)) },
    '_deep_replace' => ->(s) { Sanitizing::Bytes.utf8(Sanitizing::Formatting._deep_replace(%w[%0d %0a %0D %0A], s)) },
    'wptexturize' => ->(s) { Sanitizing::Texturize.wptexturize(s) },
    'wpautop' => ->(s) { Sanitizing::Formatting.wpautop(s) },
    'wpautop_nobr' => ->(s) { Sanitizing::Formatting.wpautop(s, false) }
  }.freeze

  # Divergences that are known, understood and written up in README.md. Each key
  # is a subject name; the value explains why the case is excluded. Nothing is
  # excluded silently — see README "Known divergences".
  KNOWN_DIVERGENCES = Sanitizing::KnownDivergences::RULES

  corpus = Sanitizing::Corpus.all

  before(:all) do
    skip 'PHP oracle not available' unless Sanitizing::Oracle.available?
  end

  SUBJECTS.each do |name, ruby|
    it "#{name} matches the oracle byte-for-byte over the corpus" do
      cases = corpus.map { |input| [name, input] }
      expected = Sanitizing::Oracle.run(cases)

      mismatches = []
      corpus.each_with_index do |input, i|
        actual = begin
          Sanitizing::Bytes.binary(ruby.call(input))
        rescue StandardError => e
          "<<RUBY RAISED #{e.class}: #{e.message}>>".b
        end
        want = expected[i]
        next if actual == want
        next if Sanitizing::KnownDivergences.known?(name, input, want, actual)

        mismatches << <<~REPORT
          input   : #{input.inspect}
          php     : #{want.inspect}
          ruby    : #{actual.inspect}
        REPORT
      end

      expect(mismatches).to be_empty, lambda {
        "#{mismatches.size}/#{corpus.size} corpus entries diverge for #{name}:\n\n" +
          mismatches.first(10).join("\n") +
          (mismatches.size > 10 ? "\n… and #{mismatches.size - 10} more\n" : '')
      }
    end
  end

  it 'covers the four corpus.php constants the migration brief names' do
    expect(corpus).to include(Sanitizing::Corpus::ASTRAL)
    expect(corpus).to include(Sanitizing::Corpus::BACKSLASH)
    expect(corpus).to include(Sanitizing::Corpus::QUOTES)
    expect(corpus).to include(Sanitizing::Corpus::KSES)
  end

  it 'fuzzes a corpus large enough to be worth trusting' do
    expect(corpus.size).to be > 5_000
  end

  it 'keeps the accepted-divergence catalogue small and written up' do
    # handoff.md: a known, documented divergence is acceptable output; an
    # undocumented one is not. Each entry here has a section in README.md
    # under "Known divergences".
    expect(KNOWN_DIVERGENCES.keys).to eq(['D-1 block-attribute pre-filter'])

    readme = File.read(File.expand_path('../../README.md', __dir__))
    expect(readme).to include('D‑1 — the block-attribute pre-filter rewrites comment tokens')
    expect(readme).to include('D‑2 — PCRE')
  end

  it 'still catches a divergence that is not on the catalogue' do
    # The accepting predicate is narrow by construction: prove it does not
    # swallow an ordinary difference on the same subject.
    expect(
      Sanitizing::KnownDivergences.known?('wp_kses_post', '<!--x-->', '<b>a</b>'.b, '<b>b</b>'.b)
    ).to be(false)
    expect(
      Sanitizing::KnownDivergences.known?('esc_html', '<!--x-->', 'a'.b, 'b'.b)
    ).to be(false)
    expect(
      Sanitizing::KnownDivergences.known?('wp_kses_post', '<!------>', ''.b, '<!---->'.b)
    ).to be(true)
  end
end
