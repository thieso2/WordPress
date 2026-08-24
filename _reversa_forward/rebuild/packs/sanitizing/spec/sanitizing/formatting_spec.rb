# frozen_string_literal: true

require_relative '../pack_helper'

# The six formatting rules, BR-MIGRATE-292…297. BR-FMT-04 is an owner-override
# rule (Q5 was overruled).
RSpec.describe Sanitizing::Formatting do
  describe 'BR-MIGRATE-292 / BR-FMT-01 — escaping is chosen by context' do
    it 'escapes HTML blocks with esc_html' do
      expect(described_class.esc_html(%(<b>"x" & 'y'</b>)))
        .to eq('&lt;b&gt;&quot;x&quot; &amp; &#039;y&#039;&lt;/b&gt;')
    end

    it 'escapes attribute values with esc_attr' do
      expect(described_class.esc_attr(%(a "quoted" & <tag>)))
        .to eq('a &quot;quoted&quot; &amp; &lt;tag&gt;')
    end

    it 'escapes textarea bodies without normalizing entities first' do
      # The one escaper that double-encodes: it is a bare htmlspecialchars().
      expect(described_class.esc_textarea('&amp; <b>')).to eq('&amp;amp; &lt;b&gt;')
      expect(described_class.esc_html('&amp; <b>')).to eq('&amp; &lt;b&gt;')
    end

    it 'escapes JavaScript string literals with esc_js' do
      expect(described_class.esc_js(%(it's "quoted"\nnext))).to eq(%(it\\'s &quot;quoted&quot;\\nnext))
    end

    it 'has no single universal escaper' do
      # F-FMT-02 / architecture.md §4. The four escapers agree on `& " < >` and
      # disagree the moment anything else is involved — an already-encoded
      # entity, a newline, an apostrophe. That is precisely why picking the wrong
      # one is a bug the legacy's type system could not catch.
      cases = ['&amp;', "a\nb", "it's", '&#039;']
      disagreements = cases.count do |input|
        [
          described_class.esc_html(input),
          described_class.esc_attr(input),
          described_class.esc_textarea(input),
          described_class.esc_js(input)
        ].uniq.length > 1
      end
      expect(disagreements).to eq(cases.length)
    end

    it 'empties invalid UTF-8 rather than passing it through' do
      expect(described_class.esc_html("bad \xC3 byte".b)).to eq('')
    end
  end

  describe 'BR-MIGRATE-293 / BR-FMT-02 — esc_url vs esc_url_raw' do
    it 'encodes & as &#038; in the display context' do
      expect(described_class.esc_url('https://example.com/?a=1&b=2'))
        .to eq('https://example.com/?a=1&#038;b=2')
    end

    it 'leaves & alone in the db context, for storage and Location headers' do
      expect(described_class.esc_url_raw('https://example.com/?a=1&b=2'))
        .to eq('https://example.com/?a=1&b=2')
    end

    it 'encodes single quotes only when displaying' do
      expect(described_class.esc_url("https://example.com/?q='x'")).to include('&#039;')
      expect(described_class.esc_url_raw("https://example.com/?q='x'")).to include("'")
    end

    it 'empties a URL whose scheme is not allowed' do
      expect(described_class.esc_url('javascript:alert(1)')).to eq('')
    end

    it 'presumes http:// when there is no scheme' do
      expect(described_class.esc_url('example.com/x')).to eq('http://example.com/x')
    end

    it 'presumes https:// when the caller leads its protocol list with https' do
      expect(described_class.esc_url('example.com/x', %w[https http]))
        .to eq('https://example.com/x')
    end

    it 'leaves relative URLs relative' do
      expect(described_class.esc_url('/a/b')).to eq('/a/b')
      expect(described_class.esc_url('#frag')).to eq('#frag')
    end

    it 'strips encoded CR and LF outside mailto:, defeating header injection' do
      expect(described_class.esc_url('https://example.com/%0d%0aSet-Cookie:x'))
        .not_to include('%0d')
    end
  end

  describe 'BR-MIGRATE-294 / BR-FMT-03 — the transforms run on output, not on storage' do
    it 'leaves stored newlines untouched: wpautop is a rendering step' do
      stored = "one\n\ntwo"
      expect(Sanitizing::Kses.wp_kses_post(stored)).to eq(stored)
      expect(described_class.wpautop(stored)).to eq("<p>one</p>\n<p>two</p>\n")
    end

    it 'is idempotent enough to be applied at render time only' do
      expect(described_class.wpautop('<p>already</p>')).to eq("<p>already</p>\n")
    end
  end

  describe 'BR-MIGRATE-295 / BR-FMT-04 — regex transforms that skip a tag list (⚠️ override)' do
    it 'wraps paragraphs and inserts line breaks' do
      expect(described_class.wpautop("a\n\nb\nc")).to eq("<p>a</p>\n<p>b<br />\nc</p>\n")
    end

    it 'does not insert breaks when asked not to' do
      expect(described_class.wpautop("a\n\nb\nc", false)).to eq("<p>a</p>\n<p>b\nc</p>\n")
    end

    it 'leaves <pre> content alone' do
      expect(described_class.wpautop("<pre>a\n\nb</pre>")).to eq("<pre>a\n\nb</pre>\n")
    end

    it 'does not wrap block-level elements in <p>' do
      expect(described_class.wpautop('<div>x</div>')).to eq("<div>x</div>\n")
    end

    it 'maintains the block-level tag list as a literal alternation' do
      expect(described_class::ALL_BLOCKS).to include('blockquote', 'figcaption', 'summary')
    end

    it 'texturizes quotes, dashes and ellipses' do
      expect(Sanitizing::Texturize.wptexturize(%(He said "hi" -- ...)))
        .to eq('He said &#8220;hi&#8221; &#8212; &#8230;')
    end

    it 'skips the no-texturize tags' do
      expect(Sanitizing::Texturize.wptexturize(%(<code>"x"</code>)))
        .to eq(%(<code>"x"</code>))
      expect(Sanitizing::Texturize::NO_TEXTURIZE_TAGS)
        .to eq(%w[pre code kbd style script tt])
    end

    it 'is a regex transformation over rendered HTML, per owner override 2' do
      expect(Sanitizing::Texturize::APOS_PATTERNS.map(&:first)).to all(be_a(Regexp))
      expect(Sanitizing::Texturize::DASH_PATTERNS.map(&:first)).to all(be_a(Regexp))
    end
  end

  describe 'BR-MIGRATE-296 / BR-FMT-06 — slugs and keys' do
    it 'produces a URL-safe slug from a title' do
      expect(described_class.sanitize_title('Héllo Wörld — Test!')).to eq('hello-world-test')
    end

    it 'collapses runs of separators and trims them' do
      expect(described_class.sanitize_title('  a   b  ')).to eq('a-b')
      expect(described_class.sanitize_title('--a--b--')).to eq('a-b')
    end

    it 'strips tags before slugging' do
      expect(described_class.sanitize_title('<b>bold</b> title')).to eq('bold-title')
    end

    it 'removes accents only in the save context' do
      expect(described_class.sanitize_title('Café', '', 'save')).to eq('cafe')
      expect(described_class.sanitize_title('Café', '', 'query')).to eq('caf%c3%a9')
    end

    it 'falls back when the result is empty' do
      expect(described_class.sanitize_title('!!!', 'fallback')).to eq('fallback')
    end

    it 'lowercases a key and restricts it to [a-z0-9_-]' do
      expect(described_class.sanitize_key('My.Key Name-1_2!')).to eq('mykeyname-1_2')
    end

    it 'returns an empty key for a non-scalar' do
      expect(described_class.sanitize_key(['a'])).to eq('')
    end
  end

  describe 'PHP string-function fidelity (found by adversarial review)' do
    # Verified against the oracle:
    #   php -r 'require ".../tools/_bootstrap.php"; var_dump(esc_js("a".chr(92)));'
    #   => string(1) "a"
    # php_stripslashes() consumes the slash first and only then looks for a
    # character to preserve, so a lone trailing backslash disappears.
    it 'drops a lone trailing backslash in esc_js, as PHP stripslashes() does' do
      expect(described_class.esc_js('a\\')).to eq('a')
      expect(described_class.esc_js('a\\\\')).to eq('a\\\\')
      expect(described_class.esc_js('a\\nb')).to eq('anb')
    end

    # Verified against the oracle:
    #   _wp_specialchars( "&apos;", ENT_XML1 ) => "&apos;"
    #   _wp_specialchars( "&apos;", ENT_QUOTES ) => "&amp;apos;"
    # htmlspecialchars() takes its "already a valid reference" set from the
    # doctype flag, and XML 1.0 knows `apos` while HTML 4.01 does not.
    it 'honours the ENT_XML1 doctype entity set in _wp_specialchars' do
      # _wp_specialchars() stays in the byte domain (Bytes), so compare bytes.
      expect(described_class._wp_specialchars('&apos;', :ent_xml1)).to eq('&apos;'.b)
      expect(described_class._wp_specialchars('&apos;', :ent_quotes)).to eq('&amp;apos;'.b)
      expect(described_class._wp_specialchars("'", :ent_xml1)).to eq('&apos;'.b)
      # `nbsp` is the converse: HTML 4.01 knows it, XML 1.0 does not — and
      # wp_kses_normalize_entities(…, 'xml') has already decoded it by then.
      expect(described_class._wp_specialchars('&nbsp;', :ent_xml1)).to eq("\xC2\xA0".b)
      expect(described_class._wp_specialchars('&nbsp;', :ent_quotes)).to eq('&nbsp;'.b)
    end
  end

  describe 'RISK-008 — no unslash pass' do
    it 'keeps a backslash the caller sent' do
      expect(described_class.esc_html('C:\\Users\\thies')).to eq('C:\\Users\\thies')
      expect(described_class.sanitize_title('a\\b')).to eq('ab')
    end
  end
end
