# frozen_string_literal: true

require_relative '../pack_helper'

# The ten kses rules, BR-MIGRATE-298…307. Five of them are owner-override rules
# (Q5 was overruled: the regex implementation is reproduced, not replaced), and
# those are marked. parity_tests/05-kses-sanitization.feature is the source of
# the scenario names.
RSpec.describe Sanitizing::Kses do
  describe 'BR-MIGRATE-298 / BR-KSES-01 — KSES is an allowlist (⚠️ override)' do
    it 'strips a disallowed element' do
      expect(described_class.wp_kses_post("a<script>alert('xss')</script>b"))
        .to eq("aalert('xss')b")
    end

    it 'keeps an allowed element but drops a disallowed attribute' do
      expect(described_class.wp_kses_post('<a href="https://example.com/" onclick="x()">t</a>'))
        .to eq('<a href="https://example.com/">t</a>')
    end

    it 'keeps the element when an event-handler attribute is removed' do
      out = described_class.wp_kses_post('<a href="https://example.com/" onmouseover="evil()">t</a>')
      expect(out).to include('<a')
      expect(out).not_to include('onmouseover')
    end

    it 'rejects a seriously malformed tag outright' do
      expect(described_class.wp_kses_post('<:::>')).to eq('')
    end

    it 'is implemented with regular expressions, per owner override 2' do
      # F-KSES-05 is knowingly carried forward and, with no hook system (AD-01),
      # permanently. This assertion exists so that replacing the implementation
      # with a real parser is a deliberate, visible act.
      expect(described_class::SPLIT_PATTERN).to be_a(Regexp)
      expect(described_class::ELEMENT_PATTERN).to be_a(Regexp)
    end
  end

  describe 'BR-MIGRATE-299 / BR-KSES-02 — 22 protocols are allowed by default' do
    it 'has exactly 22 protocols' do
      expect(Sanitizing::Tables::ALLOWED_PROTOCOLS.length).to eq(22)
    end

    it 'lists them in the legacy order' do
      expect(Sanitizing::Tables::ALLOWED_PROTOCOLS.first(6))
        .to eq(%w[http https ftp ftps mailto news])
    end
  end

  describe 'BR-MIGRATE-300 / BR-KSES-03 — the protocol list is frozen' do
    it 'is frozen rather than memoized-then-filterable' do
      # The legacy memoizes in a static and lets a filter change it until
      # wp_loaded. AD-01 removes the filter, so the list is simply immutable.
      expect(Sanitizing::Tables::ALLOWED_PROTOCOLS).to be_frozen
      expect { Sanitizing::Tables::ALLOWED_PROTOCOLS << 'javascript' }.to raise_error(FrozenError)
    end
  end

  describe 'BR-MIGRATE-301 / BR-KSES-04 — four-step scheme normalisation (⚠️ override)' do
    let(:protocols) { Sanitizing::Tables::ALLOWED_PROTOCOLS }

    it 'decodes entities, strips whitespace, removes nulls and lowercases, in that order' do
      # &#104;&#116;&#116;&#112;&#115; = "https", with whitespace and a NUL mixed in.
      obfuscated = "&#104;&#116; &#116;\u0000&#112;&#115;"
      expect(described_class.wp_kses_bad_protocol_once2(obfuscated, protocols)).to eq('https:')
    end

    it 'lowercases a mixed-case scheme' do
      expect(described_class.wp_kses_bad_protocol_once2('HtTpS', protocols)).to eq('https:')
    end

    it 'strips leading whitespace before matching' do
      expect(described_class.wp_kses_bad_protocol('  https://example.com/', protocols))
        .to eq('https://example.com/')
    end

    it 'removes a null byte inside the scheme' do
      expect(described_class.wp_kses_bad_protocol("java\u0000script:alert(1)", protocols))
        .to eq('alert(1)')
    end
  end

  describe 'BR-MIGRATE-302 / BR-KSES-05 — the colon, four ways (⚠️ override)' do
    let(:protocols) { Sanitizing::Tables::ALLOWED_PROTOCOLS }

    {
      ':' => 'plain colon',
      '&#58;' => 'decimal entity colon',
      '&#x3a;' => 'hex entity colon',
      '&colon;' => 'named entity colon'
    }.each do |encoding, description|
      it "recognises #{description} (#{encoding}) as a scheme separator" do
        expect(described_class.wp_kses_bad_protocol("javascript#{encoding}alert(1)", protocols))
          .to eq('alert(1)')
      end

      it "evaluates an allowed scheme against the allowlist through #{description}" do
        expect(described_class.wp_kses_bad_protocol("mailto#{encoding}a@example.com", protocols))
          .to eq('mailto:a@example.com')
      end
    end

    it 'recognises the entity forms case-insensitively' do
      expect(described_class.wp_kses_bad_protocol('javascript&#X3A;alert(1)', protocols))
        .to eq('alert(1)')
      expect(described_class.wp_kses_bad_protocol('javascript&#0000058;alert(1)', protocols))
        .to eq('alert(1)')
    end
  end

  describe 'BR-MIGRATE-303 / BR-KSES-06 — truncated colon entities are repaired (⚠️ override)' do
    let(:protocols) { Sanitizing::Tables::ALLOWED_PROTOCOLS }

    it 'repairs `&#58` before splitting so it cannot evade detection' do
      expect(described_class.wp_kses_bad_protocol('javascript&#58alert(1)', protocols))
        .to eq('alert(1)')
    end

    it 'repairs `&#x3a` before splitting when a non-hex byte follows' do
      expect(described_class.wp_kses_bad_protocol('javascript&#x3axlert(1)', protocols))
        .to eq('xlert(1)')
    end

    it 'does not repair `&#x3a` when a hex digit follows, because it is a different code point' do
      # `(?![;a-f0-9])`. Confirmed against the oracle: PHP returns the input
      # unchanged for `javascript&#x3aalert(1)` — the `a` of `alert` extends the
      # reference. Reproduced deliberately, bug-for-bug.
      expect(described_class.wp_kses_bad_protocol('javascript&#x3aalert(1)', protocols))
        .to eq('javascript&#x3aalert(1)')
    end

    it 'leaves a complete entity alone (the negative lookahead)' do
      expect(described_class.wp_kses_bad_protocol_once('javascript&#58;alert(1)', protocols))
        .to eq('alert(1)')
    end

    it 'does not repair `&#585`, which is a different code point' do
      # The `(?![;0-9])` lookahead is why. Repairing it would change the meaning
      # of legitimate text.
      expect(described_class.wp_kses_bad_protocol_once('x&#585;y', protocols)).to eq('x&#585;y')
    end
  end

  describe 'BR-MIGRATE-304 / BR-KSES-07 — feed: recursion capped at two (⚠️ override)' do
    let(:protocols) { Sanitizing::Tables::ALLOWED_PROTOCOLS }

    it 'evaluates the inner scheme of a feed: URL' do
      expect(described_class.wp_kses_bad_protocol('feed:javascript:alert(1)', protocols))
        .to eq('feed:alert(1)')
    end

    it 'evaluates the inner scheme two levels deep' do
      expect(described_class.wp_kses_bad_protocol('feed:feed:javascript:alert(1)', protocols))
        .to eq('feed:feed:alert(1)')
    end

    it 'stops at two levels and empties the URL at the third' do
      expect(described_class.wp_kses_bad_protocol('feed:feed:feed:javascript:alert(1)', protocols))
        .to eq('')
    end

    it 'keeps a legitimate feed-wrapped URL' do
      expect(described_class.wp_kses_bad_protocol('feed:https://example.com/rss', protocols))
        .to eq('feed:https://example.com/rss')
    end
  end

  describe 'BR-MIGRATE-305 / BR-KSES-08 — a disallowed scheme yields an empty protocol' do
    let(:protocols) { Sanitizing::Tables::ALLOWED_PROTOCOLS }

    it 'leaves the URL schemeless rather than passing it through' do
      expect(described_class.wp_kses_bad_protocol_once2('vbscript', protocols)).to eq('')
      expect(described_class.wp_kses_bad_protocol('data:text/html,x', protocols))
        .to eq('text/html,x')
    end

    it 'returns the scheme with its colon when it is allowed' do
      expect(described_class.wp_kses_bad_protocol_once2('https', protocols)).to eq('https:')
    end
  end

  describe 'BR-MIGRATE-306 / BR-KSES-09 — allowlists are context-specific' do
    it 'has a post context that allows block-level markup' do
      expect(described_class.wp_kses_allowed_html('post')).to include('div', 'table', 'img')
    end

    it 'has a data context restricted to the comment tags' do
      data = described_class.wp_kses_allowed_html('data')
      expect(data.keys).to eq(%w[a abbr acronym b blockquote cite code del em i q s strike strong])
    end

    it 'has a strip context that allows nothing' do
      expect(described_class.wp_kses_allowed_html('strip')).to eq({})
      expect(described_class.wp_kses(described_class.wp_kses_post('<b>x</b>'), 'strip')).to eq('x')
    end

    it 'has an entities context that is the named entity list' do
      expect(described_class.wp_kses_allowed_html('entities'))
        .to eq(Sanitizing::Tables::ALLOWED_ENTITY_NAMES)
    end

    it 'adds rel and target to <a> for the user_description contexts' do
      %w[user_description pre_user_description pre_term_description].each do |context|
        tags = described_class.wp_kses_allowed_html(context)
        expect(tags['a']).to include('rel' => true, 'target' => true)
      end
    end

    it 'does not leak the user_description mutation back into the data table' do
      described_class.wp_kses_allowed_html('user_description')
      expect(Sanitizing::Tables::ALLOWED_TAGS['a']).not_to include('rel')
    end

    it 'falls back to the data context for an unknown name' do
      expect(described_class.wp_kses_allowed_html('nonsense'))
        .to eq(described_class.wp_kses_allowed_html('data'))
    end
  end

  describe 'BR-MIGRATE-307 / BR-KSES-10 — entity normalization' do
    it 'converts every & to &amp; first' do
      expect(described_class.wp_kses_normalize_entities('AT&T')).to eq('AT&amp;T')
    end

    it 'restores a valid named entity' do
      expect(described_class.wp_kses_normalize_entities('&nbsp;')).to eq('&nbsp;')
    end

    it 'refuses an unknown named entity' do
      expect(described_class.wp_kses_normalize_entities('&garbage;')).to eq('&amp;garbage;')
    end

    it 'normalizes a padded decimal reference' do
      expect(described_class.wp_kses_normalize_entities('&#00058;')).to eq('&#058;')
    end

    it 'refuses a reference outside the valid Unicode range' do
      expect(described_class.wp_kses_normalize_entities('&#xD800;')).to eq('&amp;#xD800;')
      expect(described_class.wp_kses_normalize_entities('&#1114112;')).to eq('&amp;#1114112;')
    end

    it 'keeps a double-encoded reference distinguishable from a single-encoded one' do
      # The ordering comment at wp-includes/kses.php:2180 is about exactly this.
      expect(described_class.wp_kses_normalize_entities('&#x2E;')).to eq('&#x2E;')
      expect(described_class.wp_kses_normalize_entities('&amp;#x2E;')).to eq('&amp;#x2E;')
    end
  end

  describe 'RISK-008 — Rails params are never slashed' do
    it 'does not unslash its input' do
      # implication 6: wp_magic_quotes() slashed every superglobal in the legacy,
      # so `\"` in the input meant a literal quote. There is no unslash pass here;
      # a backslash the caller sent is a backslash.
      expect(described_class.wp_kses_post('C:\\Users\\thies')).to eq('C:\\Users\\thies')
    end

    it 'still applies wp_kses_stripslashes inside the tokenizer, as the legacy does' do
      # wp-includes/kses.php:2043 — this one is not an unslash pass, it is a
      # leftover of preg_replace(//e) and it runs on every token either way.
      expect(described_class.wp_kses_stripslashes('a\\"b')).to eq('a"b')
      expect(described_class.wp_kses_stripslashes('a\\nb')).to eq('a\\nb')
    end
  end

  describe 'the byte discipline (RISK-005 / RISK-006)' do
    it 'does not raise on invalid UTF-8' do
      expect { described_class.wp_kses_post("bad \xC3 byte".b) }.not_to raise_error
    end

    it 'passes 4-byte UTF-8 through unharmed' do
      expect(described_class.wp_kses_post('<b>😀🧬🚀</b>')).to eq('<b>😀🧬🚀</b>')
    end
  end
end
