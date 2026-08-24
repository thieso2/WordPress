# frozen_string_literal: true

module Sanitizing
  # The adversarial input corpus for the differential harness.
  #
  # handoff.md item 3 and parity_tests/05-kses-sanitization.feature, scenario
  # "Every ported pattern is byte-identical to the PHP original".
  #
  # The four CORPUS_* constants are copied byte-for-byte from the oracle's own
  # corpus definition at
  # _reversa_forward/oracle/wordpress/tools/corpus.php, so both sides fuzz the
  # same adversarial text the migration brief specified.
  module Corpus
    # corpus.php:20 — 4-byte UTF-8: emoji, astral maths, CJK ext B, ZWJ, flag.
    ASTRAL = "Emoji 😀🧬🚀 · Math 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𝕬𝖑𝖌𝖊𝖇𝖗𝖆 · CJK-Ext-B 𠜎𠜱𠝹 · ZWJ 👨‍👩‍👧‍👦 · Flag 🇯🇵"

    # corpus.php:23 — backslashes that must survive verbatim (T-08, RISK-008).
    BACKSLASH = 'Windows path C:\\Users\\thies\\file.txt — regex \\d+\\s*\\\\ — literal \\n not a newline — LaTeX \\frac{1}{2} — escaped quote \\" and \\\''

    # corpus.php:26 — quote-heavy text for wptexturize and attribute parsing.
    QUOTES = 'He said "it\'s a test" -- she replied \'"nested"\' ... 5\'9" tall, 3" wide « French » 「日本語」 ‘curly’ “already curly”'

    # corpus.php:29 — the KSES payloads. BR-KSES-04/05/06/07.
    KSES = <<~HTML.chomp
      <p>Safe paragraph with <strong>bold</strong> and <em>emphasis</em>.</p>
      <script>alert('xss')</script>
      <a href="javascript:alert(1)">plain colon</a>
      <a href="javascript&#58;alert(2)">numeric entity colon</a>
      <a href="javascript&#x3a;alert(3)">hex entity colon</a>
      <a href="javascript&colon;alert(4)">named entity colon</a>
      <a href="javascript&#58alert(5)">truncated colon entity</a>
      <a href="feed:javascript:alert(6)">feed prefix, one level</a>
      <a href="feed:feed:javascript:alert(7)">feed prefix, two levels</a>
      <a href="JaVaScRiPt:alert(8)">mixed case scheme</a>
      <a href="  javascript:alert(9)">leading whitespace scheme</a>
      <a href="java\\0script:alert(10)">null byte in scheme</a>
      <img src="x" onerror="alert(11)" />
      <div style="background:url(javascript:alert(12))">style payload</div>
      <a href="https://example.com/ok" title="a &quot;quoted&quot; title">legitimate link</a>
      <iframe src="https://evil.example"></iframe>
      <p>Unclosed tag <b>bold forever
      <table><tr><td>cell</td></tr></table>
    HTML

    # Scheme obfuscations. BR-KSES-04/05/06/07 are exactly the rules that two
    # decades of these attempts produced, so they get the densest coverage.
    SCHEMES = [
      'javascript:alert(1)',
      'JAVASCRIPT:alert(1)',
      'JaVaScRiPt:alert(1)',
      '  javascript:alert(1)',
      "\tjava\nscript:alert(1)",
      "java\0script:alert(1)",
      "java\\0script:alert(1)",
      'javascript&#58;alert(1)',
      'javascript&#058;alert(1)',
      'javascript&#0000058;alert(1)',
      'javascript&#x3a;alert(1)',
      'javascript&#X3A;alert(1)',
      'javascript&#x03a;alert(1)',
      'javascript&colon;alert(1)',
      'javascript&COLON;alert(1)',
      # BR-KSES-06: truncated colon entities, repaired before splitting.
      'javascript&#58alert(1)',
      'javascript&#x3aalert(1)',
      'javascript&#058alert(1)',
      'javascript&#58',
      'javascript&#x3a',
      'javascript&#58;;alert(1)',
      'javascript&#585;alert(1)',
      'javascript&#x3af;alert(1)',
      # BR-KSES-07: feed: recursion, capped at two levels.
      'feed:javascript:alert(1)',
      'feed:feed:javascript:alert(1)',
      'feed:feed:feed:javascript:alert(1)',
      'feed:feed:feed:feed:javascript:alert(1)',
      'feed:https://example.com/',
      'FEED:JAVASCRIPT:alert(1)',
      'feed&#58;javascript&#58;alert(1)',
      # Repetition, to exercise the six-iteration cap in wp_kses_bad_protocol().
      'javascript:javascript:alert(1)',
      'javascript:javascript:javascript:javascript:javascript:javascript:alert(1)',
      # BR-KSES-08: a disallowed scheme leaves the URL schemeless.
      'data:text/html;base64,PHNjcmlwdD4=',
      'vbscript:msgbox(1)',
      'file:///etc/passwd',
      # The `/?` guard in wp_kses_bad_protocol_once().
      'https://example.com/?x=y:z',
      '/relative/path:with:colons',
      '#fragment:only',
      '?query=1:2',
      'mailto:someone@example.com',
      'MAILTO:someone@example.com',
      'tel:+1-555-0100',
      'urn:isbn:0451450523',
      'https://example.com/ok',
      'http://example.com/ok',
      '//protocol-relative.example/x',
      ''
    ].freeze

    # Tag and attribute shapes, aimed at wp_kses_split()'s tokenizer and at the
    # attribute parser's incomplete-input rule.
    MARKUP = [
      '<b>bold</b>',
      '<B>BOLD</B>',
      '<b class="x" class="y">dup attrs</b>',
      '<b class=unquoted>x</b>',
      '<b class=>empty value</b>',
      '<b class>boolean</b>',
      '<b class="unterminated>x</b>',
      "<b class='single'>x</b>",
      '<b =weird>x</b>',
      '<b 🐮=/>x</b>',
      '<img src="x" onerror="alert(1)" />',
      '<img src=x onerror=alert(1)>',
      '<a href="x" download>d</a>',
      '<a href="x" download="y">d</a>',
      '<script>alert(1)</script>',
      '<SCRIPT SRC=//evil.example></SCRIPT>',
      '<iframe src="https://evil.example"></iframe>',
      '<object data="doc.pdf" type="application/pdf"></object>',
      '<object data="x.exe" type="application/pdf"></object>',
      '<object type="application/pdf"></object>',
      '<div data-foo="1" data-BAR="2" data-="3">x</div>',
      '<div style="color:red">x</div>',
      '<div style="background:url(javascript:alert(1))">x</div>',
      '<div style="background:url(https://example.com/a.png)">x</div>',
      '<div style="width:calc(100% - 10px)">x</div>',
      '<div style="background:linear-gradient(red,blue)">x</div>',
      '<div style="--custom:url(javascript:alert(1))">x</div>',
      '<div style="color:red;expression(alert(1));font-size:2em">x</div>',
      '<div style="behavior:url(x.htc)">x</div>',
      '<!-- a normal comment -->',
      '<!-- a comment with <b>tags</b> inside -->',
      '<!-- unterminated comment',
      '<!-- dashes --- inside -->',
      '<!--->',
      '<!---->',
      '<!doctype html>',
      '<!DOCTYPE html>',
      '<![CDATA[raw]]>',
      '</ bogus>',
      '</3>',
      '</:foo attr="1">',
      '<:::>',
      '<3 hearts',
      'a > b',
      'a < b',
      '5 < 6 and 7 > 6',
      '<p>Unclosed <b>bold forever',
      '<table><tr><td>cell</td></tr></table>',
      '<p>&amp; &lt; &gt; &quot; &#039; &nbsp; &garbage; &#x41; &#65; &#0065; &#x0041;</p>',
      '&amp;amp; &amp;#x2E; &#x2E;',
      '<a href="https://example.com/?a=1&b=2">amp in url</a>',
      '<b>' + ('x' * 500) + '</b>',
      "<b\nclass=\"x\"\n>newlines in tag</b>",
      "<b\tclass=\"x\">tab in tag</b>",
      '<b class="x"/>',
      '<b/>',
      '<b //>',
      '<hr />',
      '<p>x</p',
      '<p',
      '<',
      '>',
      '<>',
      ''
    ].freeze

    # Text shapes for wptexturize / wpautop / esc_* / sanitize_title.
    TEXT = [
      'one line',
      "two\n\nparagraphs",
      "line\nbreak",
      "<p>already</p>\n\n<p>wrapped</p>",
      "<pre>pre\n\nblock</pre>",
      "<script>a\n\nb</script>",
      "<div>\n\nblock\n\n</div>",
      "<ul>\n<li>a</li>\n<li>b</li>\n</ul>",
      "<blockquote>\n\nquote\n\n</blockquote>",
      "text<br><br>more",
      "<audio><source src=x>\n</audio>",
      "<figure>\n<figcaption>cap</figcaption>\n</figure>",
      "a\r\nb\rc\nd",
      "\n\n\n\nmany\n\n\n\nbreaks\n\n\n\n",
      '   ',
      '',
      "He said \"it's a test\" -- she replied '\"nested\"' ... 5'9\" tall",
      "'tain't 'twere 'twas 'tis 'twill 'til 'bout 'nuff 'round 'cause 'em",
      "The '90s were 'quoted' and \"double quoted\"",
      "9x9 but never 0x9999 and 3x4",
      'a--b a---b a - b a -- b xn--foo',
      '``double backticks'' and (tm)',
      "5'9\" and 3\" wide",
      "<code>don't texturize 'this'</code>",
      "<pre>nor 'this'</pre>",
      'AT&T and R&D and &copy; and &notanentity;',
      'Héllo Wörld — Test! Ünïcödé',
      'Ω≈ç√∫˜µ≤≥÷',
      'a/b/c and a.b.c and a_b_c and a-b-c',
      '%41%42 and %zz and 100%',
      'MiXeD CaSe TiTlE',
      '   leading and trailing   ',
      'multiple    spaces',
      "tab\tseparated",
      '<b>tags in title</b>',
      '&nbsp;&#8209;&ndash;&mdash;',
      # `&apos;` is the one named entity ENT_XML1 knows and ENT_HTML401 does
      # not, so it is the only input that separates the two doctype tables in
      # _wp_specialchars(). Added after review found the port using the HTML401
      # table for both.
      '&apos;',
      "x&apos;y &quot; &amp; &nbsp; &#039; &AMP; &apos",
      # A lone *trailing* backslash: PHP's stripslashes() drops it, which
      # esc_js() then cannot re-double. Added after review found the port
      # keeping it. The interior cases were already covered by CORPUS_BACKSLASH.
      'trailing backslash \\',
      'a\\',
      'a\\\\',
      "quote ' and \" and a slash at the very end \\",
      ('long-slug-segment-' * 20)
    ].freeze

    # Fragments the generator recombines. Each one is a token the legacy's
    # regexes treat specially.
    FRAGMENTS = [
      '<', '>', '</', '/>', '<!--', '-->', '<!', '<!DOCTYPE', '<![CDATA[', ']]>',
      'b', 'div', 'script', 'iframe', 'a', 'img', 'object', 'span', ':::', '3',
      ' ', "\t", "\n", "\r\n", "\0", "\x0B", "\x0C", '  ',
      'href', 'src', 'style', 'onerror', 'data-x', 'class', 'title', '=', '"', "'",
      'javascript', 'feed', 'https', 'data', ':', '&#58;', '&#x3a;', '&colon;', '&#58',
      'alert(1)', '//example.com', '/path', '?q=1', '#frag', '%20', '\\\\',
      '&', '&amp;', '&lt;', '&quot;', '&nbsp;', '&#039;', '&apos;', '&#x41;', '&garbage;',
      '\\',
      '--', '---', '...', "''", '``', ' (tm)', "'em", '9x9', '0x99',
      'url(', ')', 'color:red', 'background', ';', 'calc(1 + 1)', 'var(--x)',
      'é', '😀', "\xC2\xA0", "\xC3", "\xF0\x9F"
    ].freeze

    module_function

    # Everything, deduplicated: the four corpus.php constants, the hand-written
    # adversarial sets, the mutations handoff.md asks for, and a seeded
    # recombination fuzzer so the corpus is wider than anything hand-listed.
    def all
      @all ||= (
        [ASTRAL, BACKSLASH, QUOTES, KSES] +
        SCHEMES + MARKUP + TEXT +
        SCHEMES.map { |s| %(<a href="#{s}">link</a>) } +
        SCHEMES.map { |s| %(<img src='#{s}'>) } +
        SCHEMES.map { |s| %(<div style="background:url(#{s})">x</div>) } +
        SCHEMES.map { |s| %(<a href=#{s}>unquoted</a>) } +
        MARKUP.map { |m| "before #{m} after" } +
        mutations +
        generated +
        byte_mutations
      ).uniq
    end

    # Seeded so a failure is reproducible: the same corpus every run, on every
    # machine, in both engines.
    SEED = 20_260_822

    def generated(count = 4000)
      rng = Random.new(SEED)
      Array.new(count) do
        Array.new(rng.rand(2..12)) { FRAGMENTS[rng.rand(FRAGMENTS.length)] }.join
      end
    end

    # Byte-level mutation of the real payloads: flip, delete, duplicate and
    # truncate. This is what finds the anchor bugs — a `$` that became a line
    # anchor only misbehaves when a newline lands in the middle of a token.
    def byte_mutations(count = 1200)
      rng = Random.new(SEED + 1)
      seeds = [KSES, QUOTES, BACKSLASH] + MARKUP + SCHEMES.map { |x| %(<a href="#{x}">l</a>) }

      Array.new(count) do
        base = seeds[rng.rand(seeds.length)].dup.force_encoding(Encoding::BINARY)
        next '' if base.empty?

        case rng.rand(5)
        when 0
          at = rng.rand(base.bytesize)
          base[at] = [rng.rand(256)].pack('C')
          base
        when 1
          at = rng.rand(base.bytesize)
          base[0, at] + base[(at + 1)..].to_s
        when 2
          at = rng.rand(base.bytesize)
          base[0, at] + "\n" + base[at..].to_s
        when 3
          base[0, 1 + rng.rand(base.bytesize)]
        else
          at = rng.rand(base.bytesize)
          base[0, at] + base[at, 1].to_s * 3 + base[(at + 1)..].to_s
        end
      end
    end

    # Mutations: null bytes, control characters, invalid UTF-8, truncation.
    def mutations
      seeds = [ASTRAL, BACKSLASH, QUOTES, KSES]
      out = []

      seeds.each do |seed|
        out << seed.dup.force_encoding(Encoding::BINARY)
        out << "\x00#{seed}\x00"
        out << seed.gsub(' ', "\x01")
        out << seed[0, seed.bytesize / 2].to_s
        out << "#{seed}\n"
      end

      # Deliberately invalid UTF-8: a lone continuation byte, a truncated
      # 4-byte sequence, and an overlong encoding. RISK-006.
      out << "invalid \xC3 sequence".b
      out << "truncated \xF0\x9F\x98 emoji".b
      out << "overlong \xC0\xAF slash".b
      out << "<a href=\"javascript\xC0\xBAalert(1)\">x</a>".b
      out << "\xED\xA0\x80 lone surrogate bytes".b

      out
    end
  end
end
