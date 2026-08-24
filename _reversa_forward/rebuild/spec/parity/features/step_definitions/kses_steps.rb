# frozen_string_literal: true

# PT-005 -- Sanitizing untrusted HTML. BR-MIGRATE-292..307; owner overrides
# BR-KSES-01/04/05/06/07 and BR-FMT-04.
#
# This is the ONLY parity flow that is DIFFERENTIAL rather than comparative: every
# scenario below runs the same bytes through the Ruby port (packs/sanitizing) AND through
# the live PHP oracle, and the assertion is on both. The oracle is the executable
# definition of the rules (AD-08); a Ruby-only expectation would be the port agreeing
# with itself. Where the oracle is not reachable the step FAILS -- it never skips.
#
# RISK-005 exists because of this port: the five owner-override rules reproduce the
# PCRE allowlist verbatim under Onigmo. The pack's own differential harness
# (packs/sanitizing/spec/differential/) fuzzes 30 functions over 5,497 entries; the
# steps here reuse its corpus and its oracle driver rather than re-inventing either.

require "yaml"
require Rails.root.join("packs/sanitizing/spec/differential/oracle").to_s
require Rails.root.join("packs/sanitizing/spec/differential/corpus").to_s
require Rails.root.join("packs/sanitizing/spec/differential/known_divergences").to_s

module KsesParity
  # The legacy file is READ ONLY. It is read here only to prove the port did not
  # paraphrase it ("no pattern has been rewritten for idiom").
  LEGACY_KSES = "/workspace/WordPress/wp-includes/kses.php"
  PORT_KSES = Rails.root.join("packs/sanitizing/app/sanitizing/kses.rb").to_s

  ALLOWED = Sanitizing::Tables::ALLOWED_PROTOCOLS

  module_function

  def legacy_source
    @legacy_source ||= File.read(LEGACY_KSES, encoding: "UTF-8")
  end

  def port_source
    @port_source ||= File.read(PORT_KSES, encoding: "UTF-8")
  end

  # Pulls one pattern literal out of kses.php. Raises when the anchor text is not
  # found: a silently empty match would make every "verbatim" assertion vacuous.
  def legacy_literal(regex)
    match = legacy_source.match(regex)
    raise "legacy pattern not found in #{LEGACY_KSES}: #{regex.inspect}" unless match

    match[1]
  end

  # The ONLY translation the port is allowed to apply (README.md §3.1): PCRE's
  # whole-subject `^`/`$` become `\A`/`(?=\n?\z)`. Anything else is a rewrite.
  def pcre_anchors_to_onigmo(pattern)
    pattern.sub(/\A\^/, '\A').gsub(/\$(?=[)|]|\z)/, Sanitizing::Bytes::PCRE_EOS)
  end

  # /x mode: comments and whitespace carry no meaning, so both sides are compared
  # without them.
  def strip_extended(pattern)
    pattern.gsub(/#[^\n]*/, "").gsub(/\s+/, "")
  end

  # One call to the PHP oracle. `fn` is one of the names php/oracle.php dispatches.
  def php(fn, input)
    raise "PHP oracle unavailable (RISK-001): #{Sanitizing::Oracle::BOOTSTRAP} / php on PATH" unless Sanitizing::Oracle.available?

    result = Sanitizing::Oracle.run([[fn, input]]).first
    raise "PHP oracle returned non-string for #{fn}(#{input.inspect})" if result.nil?

    result
  end

  def bytes(str) = Sanitizing::Bytes.binary(str)

  # BR-KSES-04's four steps, individually, so an ORDER can be asserted rather than
  # only the end result. Each is the same primitive the port's
  # `wp_kses_bad_protocol_once2` uses (kses.rb) -- nothing is reimplemented here.
  STEPS = {
    decode: ->(s) { Sanitizing::Kses.wp_kses_decode_entities(s) },
    strip_ws: ->(s) { s.gsub(/\s/n, "".b) },
    no_null: ->(s) { Sanitizing::Kses.wp_kses_no_null(s) },
    lower: ->(s) { s.downcase },
  }.freeze
  LEGACY_ORDER = %i[decode strip_ws no_null lower].freeze

  def apply(order, scheme)
    order.reduce(bytes(scheme)) { |acc, step| STEPS.fetch(step).call(acc) }
  end
end

# ── BR-KSES-01: an allowlist ────────────────────────────────────────────────────
Given("untrusted content containing a script element") do
  @input = "<p>Safe paragraph with <strong>bold</strong>.</p><script>alert('xss')</script>"
  expect(@input).to match(%r{<script>.*</script>}i) # the premise, so the Then is not vacuous
end

Given("untrusted content containing a link with an event-handler attribute") do
  @input = '<a href="https://example.com/" onmouseover="steal(document.cookie)">legitimate link</a>'
  expect(@input).to include("onmouseover=")
end

When("the content is sanitized") do
  # wp_kses_post() is the post-content context (BR-KSES-09), wp-includes/kses.php.
  @output = Sanitizing::Kses.wp_kses_post(@input)
  @php_output = KsesParity.php("wp_kses_post", @input)
end

Then("the script element is absent from the output") do
  expect(@output).not_to match(/<\s*\/?\s*script/i)
  expect(KsesParity.bytes(@output)).to eq(@php_output), "Ruby #{@output.inspect} != PHP #{@php_output.inspect}"
end

Then("the link element remains") do
  expect(@output).to match(%r{<a href="https://example\.com/">legitimate link</a>})
end

Then("the event-handler attribute is absent") do
  expect(@output).not_to match(/on[a-z]+\s*=/i)
  expect(KsesParity.bytes(@output)).to eq(@php_output), "Ruby #{@output.inspect} != PHP #{@php_output.inspect}"
end

# ── OVERRIDE — BR-KSES-04: four normalisation steps, in one order ───────────────
Given("a URL attribute whose scheme is obfuscated with entities, whitespace and null bytes") do
  # Built so that ONLY the legacy order resolves it to `https`:
  #   &#72; -> 'H'   decoded, then must be lowercased AFTER decoding
  #   &#9;  -> TAB   decoded, then must be stripped AFTER decoding
  #   &#0;  -> NUL   decoded, then must be removed AFTER decoding
  #   literal TAB and literal NUL exercise the same two steps on raw bytes.
  @scheme = "&#72;t\tt&#9;p&#0;\0S"
  @attribute = "#{@scheme}://example.com/path"
end

When("the attribute is normalized") do
  @normalized = Sanitizing::Kses.wp_kses_bad_protocol_once2(KsesParity.bytes(@scheme), KsesParity::ALLOWED)
  @output = Sanitizing::Kses.wp_kses_bad_protocol(@attribute, KsesParity::ALLOWED)
  @php_output = KsesParity.php("wp_kses_bad_protocol", @attribute)
end

Then("entities are decoded, whitespace stripped, null bytes removed and the result lowercased") do
  # The scheme survives as `https:` only if all four steps ran.
  expect(@normalized).to eq("https:".b)
  expect(KsesParity.apply(KsesParity::LEGACY_ORDER, @scheme)).to eq("https".b)
  expect(KsesParity.bytes(@output)).to eq("https://example.com/path".b)
  expect(KsesParity.bytes(@output)).to eq(@php_output), "Ruby #{@output.inspect} != PHP #{@php_output.inspect}"
end

Then("the normalisation order matches the legacy implementation exactly") do
  # 1. Behaviour: the input is order-sensitive. Every ordering that differs from the
  #    legacy in a way that matters yields something other than `https`.
  other_orders = %i[decode strip_ws no_null lower].permutation.reject { |o| o == KsesParity::LEGACY_ORDER }
  distinguishing = other_orders.reject { |o| KsesParity.apply(o, @scheme) == "https".b }
  expect(distinguishing).not_to be_empty, "the fixture does not distinguish orderings"
  # Orderings that agree with the legacy are exactly those where decode still comes
  # first (strip/null/lower commute with each other once entities are decoded).
  # (`all` is Capybara's finder inside the cucumber World, so the matcher is spelled out.)
  (other_orders - distinguishing).each { |o| expect(o.first).to eq(:decode), "order #{o.inspect} agreed with the legacy" }
  distinguishing.each { |o| expect(o.first).not_to eq(:decode), "order #{o.inspect} should have agreed" }

  # 2. Source: wp_kses_bad_protocol_once2() in kses.php:2136 calls the four steps in
  #    this order, and so does the port. Read from the files, not remembered.
  legacy_fn = KsesParity.legacy_source[/function wp_kses_bad_protocol_once2\(.*?\n\}/m]
  expect(legacy_fn).to be_a(String)
  legacy_calls = ["wp_kses_decode_entities(", "preg_replace( '/\\s/'", "wp_kses_no_null(", "strtolower("]
  legacy_positions = legacy_calls.map { |c| legacy_fn.index(c) or raise "#{c.inspect} not in wp_kses_bad_protocol_once2()" }
  expect(legacy_positions).to eq(legacy_positions.sort)

  port_fn = KsesParity.port_source[/def wp_kses_bad_protocol_once2\(.*?\n    end/m]
  port_calls = ["wp_kses_decode_entities(scheme)", "gsub(/\\s/n", "wp_kses_no_null(scheme)", ".downcase"]
  port_positions = port_calls.map { |c| port_fn.index(c) or raise "#{c.inspect} not in Kses.wp_kses_bad_protocol_once2" }
  expect(port_positions).to eq(port_positions.sort)
end

# ── OVERRIDE — BR-KSES-05: four spellings of the colon ──────────────────────────
Given("a URL attribute using {string} as its scheme separator") do |encoding|
  @encoding = encoding
  @disallowed = "javascript#{encoding}alert(1)"
  @allowed = "https#{encoding}//example.com/"
end

When("the attribute is sanitized") do
  @output = Sanitizing::Kses.wp_kses_bad_protocol(@disallowed, KsesParity::ALLOWED)
  @php_output = KsesParity.php("wp_kses_bad_protocol", @disallowed)
  if @allowed
    @allowed_output = Sanitizing::Kses.wp_kses_bad_protocol(@allowed, KsesParity::ALLOWED)
    @allowed_php = KsesParity.php("wp_kses_bad_protocol", @allowed)
  end
end

Then("the scheme is recognised and evaluated against the allowlist") do
  # Recognised: the separator was found, so the scheme was split off and judged.
  # A disallowed scheme leaves the URL schemeless (BR-KSES-08)...
  expect(KsesParity.bytes(@output)).to eq("alert(1)".b)
  # ...and an allowed one is re-emitted with a PLAIN colon, which is only possible
  # if the encoded separator was recognised as a colon and rebuilt from the allowlist.
  expect(KsesParity.bytes(@allowed_output)).to eq("https://example.com/".b)
  expect(KsesParity.bytes(@output)).to eq(@php_output), "Ruby #{@output.inspect} != PHP #{@php_output.inspect}"
  expect(KsesParity.bytes(@allowed_output)).to eq(@allowed_php), "Ruby #{@allowed_output.inspect} != PHP #{@allowed_php.inspect}"
end

# ── OVERRIDE — BR-KSES-06: truncated colon entities ─────────────────────────────
Given("a URL attribute containing a truncated colon entity") do
  @disallowed = "javascript&#58alert(1)" # no trailing `;`
  @allowed = nil
end

Then("the entity is repaired before the scheme is split from the remainder") do
  # Without the repair the split finds no separator at all, so nothing would be judged.
  expect(KsesParity.bytes(@disallowed).split(Sanitizing::Kses::COLON_SPLIT, 2).length).to eq(1)
  repaired = KsesParity.bytes(@disallowed).gsub(Sanitizing::Kses::TRUNCATED_COLON) { "#{Regexp.last_match(1)};".b }
  expect(repaired).to eq("javascript&#58;alert(1)".b)
  expect(repaired.split(Sanitizing::Kses::COLON_SPLIT, 2)).to eq(["javascript".b, "alert(1)".b])
  # And the real entry point reaches the same verdict as PHP.
  expect(KsesParity.bytes(@output)).to eq("alert(1)".b)
  expect(KsesParity.bytes(@output)).to eq(@php_output), "Ruby #{@output.inspect} != PHP #{@php_output.inspect}"
  # The repair precedes the split in the legacy (kses.php:2100 then :2101) and in the port.
  legacy_fn = KsesParity.legacy_source[/function wp_kses_bad_protocol_once\(.*?\n\}/m]
  expect(legacy_fn.index("preg_replace( '/(&#0*58(?![;0-9])")).to be < legacy_fn.index("preg_split(")
  port_fn = KsesParity.port_source[/def wp_kses_bad_protocol_once\(.*?\n    end/m]
  expect(port_fn.index("TRUNCATED_COLON")).to be < port_fn.index("COLON_SPLIT")
end

# ── OVERRIDE — BR-KSES-07: feed: recursion, two levels ──────────────────────────
Given("a URL attribute with a feed scheme wrapping another scheme") do
  @disallowed = "feed:javascript:alert(1)"
  @allowed = "feed:https://example.com/"
  @depths = {
    2 => "feed:feed:https://example.com/",   # inner scheme at level 2: still examined
    3 => "feed:feed:feed:https://example.com/", # level 3: the legacy refuses (returns '')
  }
end

Then("the inner scheme is evaluated against the allowlist") do
  expect(KsesParity.bytes(@output)).to eq("feed:alert(1)".b)       # inner javascript: stripped
  expect(KsesParity.bytes(@allowed_output)).to eq("feed:https://example.com/".b) # inner https: kept
  expect(KsesParity.bytes(@output)).to eq(@php_output)
  expect(KsesParity.bytes(@allowed_output)).to eq(@allowed_php)
end

Then("recursion stops at two levels") do
  @depths.each do |depth, input|
    ruby = KsesParity.bytes(Sanitizing::Kses.wp_kses_bad_protocol(input, KsesParity::ALLOWED))
    php = KsesParity.php("wp_kses_bad_protocol", input)
    expect(ruby).to eq(php), "depth #{depth}: Ruby #{ruby.inspect} != PHP #{php.inspect}"
  end
  expect(KsesParity.bytes(Sanitizing::Kses.wp_kses_bad_protocol(@depths[2], KsesParity::ALLOWED))).to eq(@depths[2].b)
  expect(KsesParity.bytes(Sanitizing::Kses.wp_kses_bad_protocol(@depths[3], KsesParity::ALLOWED))).to eq("".b)
  # kses.php:2107 `if ( $count > 2 ) return '';` -- the cap is a literal 2 in both.
  expect(KsesParity.legacy_source).to include("if ( $count > 2 ) {")
  expect(KsesParity.port_source).to include("return ''.b if count > 2")
end

# ── RISK-005: the differential harness itself ───────────────────────────────────
Given("the XSS bypass corpus") do
  @corpus = Sanitizing::Corpus.all
  expect(@corpus.size).to be > 5_000
  expect(@corpus).to include(Sanitizing::Corpus::KSES) # corpus.php's payload set is in it
end

Given("the legacy PHP implementation available as an oracle") do
  # RISK-001: fail, never skip.
  expect(Sanitizing::Oracle.available?).to be(true),
    "PHP oracle unavailable: #{Sanitizing::Oracle::BOOTSTRAP} or no php on PATH"
  expect(KsesParity.php("wp_kses_post", "<b>probe</b><script>x</script>")).to eq("<b>probe</b>x".b)
end

# The kses-family subjects php/oracle.php dispatches. Same lambdas as the pack's
# differential_spec.rb; listed here because that constant lives inside an RSpec block.
KSES_SUBJECTS = {
  "wp_kses_post" => ->(s) { Sanitizing::Kses.wp_kses_post(s) },
  "wp_kses_data" => ->(s) { Sanitizing::Kses.wp_kses_data(s) },
  "wp_kses_strip" => ->(s) { Sanitizing::Kses.wp_kses(s, "strip") },
  "wp_kses_user_description" => ->(s) { Sanitizing::Kses.wp_kses(s, "user_description") },
  "wp_kses_bad_protocol" => ->(s) { Sanitizing::Kses.wp_kses_bad_protocol(s, Sanitizing::Tables::ALLOWED_PROTOCOLS) },
  "wp_kses_normalize_entities" => ->(s) { Sanitizing::Kses.wp_kses_normalize_entities(s) },
  "wp_kses_decode_entities" => ->(s) { Sanitizing::Kses.wp_kses_decode_entities(s) },
  "wp_kses_no_null" => ->(s) { Sanitizing::Kses.wp_kses_no_null(s) },
  "wp_kses_stripslashes" => ->(s) { Sanitizing::Kses.wp_kses_stripslashes(s) },
  "safecss_filter_attr" => ->(s) { Sanitizing::Css.safecss_filter_attr(s) },
}.freeze

When("each corpus entry is sanitized by both implementations") do
  @mismatches = []
  @known = Hash.new(0)
  @compared = 0
  KSES_SUBJECTS.each do |name, ruby|
    expected = Sanitizing::Oracle.run(@corpus.map { |input| [name, input] })
    @corpus.each_with_index do |input, i|
      actual = begin
        KsesParity.bytes(ruby.call(input))
      rescue StandardError => e
        "<<RUBY RAISED #{e.class}: #{e.message}>>".b
      end
      @compared += 1
      next if actual == expected[i]

      if Sanitizing::KnownDivergences.known?(name, input, expected[i], actual)
        @known[name] += 1
      else
        @mismatches << "#{name}\n  input: #{input.inspect}\n  php  : #{expected[i].inspect}\n  ruby : #{actual.inspect}"
      end
    end
  end
end

Then("the outputs are byte-identical for every entry") do
  expect(@compared).to eq(@corpus.size * KSES_SUBJECTS.size)
  expect(@mismatches).to be_empty, lambda {
    "#{@mismatches.size}/#{@compared} comparisons diverge:\n\n#{@mismatches.first(10).join("\n\n")}" \
      "#{@mismatches.size > 10 ? "\n… and #{@mismatches.size - 10} more" : ''}"
  }
  # The only accepted exception is D-1 (README.md §5), and only on the kses entry
  # points. An exception on any other subject would be an undocumented divergence.
  expect(@known.keys - Sanitizing::KnownDivergences::KSES_SUBJECTS).to be_empty
end

Then("no pattern has been rewritten for idiom") do
  # Each owner-override pattern is compared to the literal in wp-includes/kses.php,
  # read from disk. The only permitted change is the documented anchor translation.
  kses = Sanitizing::Kses

  truncated = KsesParity.legacy_literal(%r{preg_replace\( '/(\(&#0\*58\(\?!\[;0-9\]\)\|&#x0\*3a\(\?!\[;a-f0-9\]\)\))/i'})
  expect(kses::TRUNCATED_COLON.source).to eq(truncated)
  expect(kses::TRUNCATED_COLON.options & Regexp::IGNORECASE).not_to eq(0)

  colon = KsesParity.legacy_literal(%r{preg_split\( '/(:\|&#0\*58;\|&#x0\*3a;\|&colon;)/i'})
  # README.md §3.6: wrapped in a NON-capturing group because String#split, unlike
  # preg_split, would otherwise inject the separator into the result.
  expect(kses::COLON_SPLIT.source.delete_prefix("(?:").delete_suffix(")").gsub('\:', ":")).to eq(colon)
  expect(kses::COLON_SPLIT.options & Regexp::IGNORECASE).not_to eq(0)

  token = KsesParity.legacy_literal(/\$token_pattern = <<<REGEX\n~\n(.*?)\n~x\nREGEX;/m)
  expect(KsesParity.strip_extended(kses::SPLIT_PATTERN.source))
    .to eq(KsesParity.strip_extended(KsesParity.pcre_anchors_to_onigmo(token)))
  expect(kses::SPLIT_PATTERN.options & Regexp::EXTENDED).not_to eq(0)

  bogus = KsesParity.legacy_literal(%r{preg_match\( '~(\^\(\?:</\[\^a-zA-Z\]\[\^>\]\*>\|<!\[a-z\]\[\^>\]\*>\)\$)~'})
  expect(kses::BOGUS_COMMENT.source).to eq(KsesParity.pcre_anchors_to_onigmo(bogus))

  element = KsesParity.legacy_literal(%r{preg_match\( '%(\^<\\s\*\(/\\s\*\)\?\(\[a-zA-Z0-9-\]\+\)\(\[\^>\]\*\)>\?\$)%'})
  expect(kses::ELEMENT_PATTERN.source).to eq(KsesParity.pcre_anchors_to_onigmo(element))

  # And the implementation is still regular expressions (owner override 2, Q5).
  expect(kses::SPLIT_PATTERN).to be_a(Regexp)
  expect(kses::ELEMENT_PATTERN).to be_a(Regexp)
end

# ── @invariant: the one guarantee the target ADDS (F-FMT-02) ────────────────────
Given("a value that has not passed through the sanitizing pack") do
  @unsanitized = '<b>plain string</b><script>alert(1)</script>'
  expect(@unsanitized).to be_a(String)
  expect(@unsanitized).not_to be_a(Sanitizing::SafeHtml)
end

When("code attempts to render it as trusted markup") do
  # Rendering code asserts the type before interpolating (safe_html.rb). This is the
  # call every trusted-markup sink makes.
  @rejection = begin
    Sanitizing::SafeHtml.assert!(@unsanitized)
    nil
  rescue TypeError => e
    e
  end
  @forged = begin
    Sanitizing::SafeHtml.new(@unsanitized)
    nil
  rescue ArgumentError => e
    e
  end
end

Then("the type system rejects the value") do
  expect(@rejection).to be_a(TypeError)
  expect(@rejection.message).to include("expected Sanitizing::SafeHtml, got String")
  # The type cannot be forged around the pack either.
  expect(@forged).to be_a(ArgumentError)
  # And the same bytes, once through the allowlist, are accepted -- so the rejection
  # is about provenance, not content.
  sanitized = Sanitizing::SafeHtml.from_post_content(@unsanitized)
  expect(Sanitizing::SafeHtml.assert!(sanitized)).to equal(sanitized)
  expect(sanitized.to_s).to eq("<b>plain string</b>alert(1)")
end
