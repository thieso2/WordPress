# frozen_string_literal: true

# PT-S001..PT-S018 -- Visual parity for the 18 LITERAL `web.*` screens
# (screen_modernization_decision.md, hybrid; target_screens.md § shared contract).
#
# These steps drive the REAL harness (AD-08, spec/parity/harness/): the screen is
# fetched from the running rebuild over HTTP, normalized with Parity::Normalizer --
# the transcription of golden/manifest.yaml § normalizationRules -- and diffed against
# the golden file captured from the oracle. Nothing here is asserted without a fetch
# and a byte comparison; a step that cannot reach either server FAILS, it never skips.
#
# Why HTTP and not Rack::Test: support/env.rb truncates every table before each
# scenario, so an in-process render would be of an EMPTY site. The development server
# on :3100 carries the corpus that `bin/rails oracle:seed` round-tripped from the oracle,
# which is the only data the goldens can be compared against.
#
# ⚠️ On the routes in the feature files. The 18 features were emitted by the Inspector
# BEFORE the corpus existed (their headers still read "BLOCKED ... capture pending"),
# and the routes they name -- "/hello-world/", "/sample-page/", "/post/",
# "/tag/sample/", "/author/admin/" -- are WordPress default-install slugs, not the
# seeded corpus. spec/parity/corpus/requests.yml is the authority: its `web.*` paths
# were RESOLVED from the oracle by tools/corpus_urls.php, and the goldens were captured
# from those paths. The render step therefore resolves the screen's corpus path and
# says so in the output when it differs from the feature's literal route. It does not
# silently substitute.

require "yaml"
require "nokogiri"
require Rails.root.join("spec/parity/harness/differ").to_s

module ScreenParity
  MANIFEST = "/workspace/WordPress/_reversa_sdd/screens/golden/manifest.yaml"
  REBUILD_URL = ENV.fetch("REBUILD_URL", "http://127.0.0.1:3100")
  START_REBUILD = "(setsid nohup env RAILS_ENV=development bin/rails server -p 3100 -b 127.0.0.1 " \
                  "> /tmp/rails.log 2>&1 < /dev/null &)"

  # manifest.yaml § normalizationRules -> Parity::Normalizer's rule keys. The two
  # the manifest declares OFF (trimTrailingSpaces, stripAnsiColors) have no key because
  # the normalizer has no such behaviour; `seedRandom` is delivered as the generated-id
  # normalization (normalizer.rb GENERATED_ID_PATTERNS -- PHP's RNG cannot be seeded
  # from outside the process).
  RULE_KEYS = {
    "lineEndings" => :line_endings,
    "normalizeUtf8" => :normalize_utf8,
    "injectClock" => :inject_clock,
    "stripNonces" => :strip_nonces,
    "stripAutoincrementIds" => :strip_autoincrement_ids,
    "stripGuid" => :strip_guid,
    "collapseWhitespaceBetweenTags" => :collapse_whitespace_between_tags,
    "sortClassAttributeTokens" => :sort_class_attribute_tokens,
  }.freeze

  # ── The token contract (target_screens.md § shared contract, BR-GS-06/07) ──────
  # spec.token_binding:
  #   css_custom_properties: "--wp--preset--{category}--{slug}"
  #   utility_classes: ".has-{slug}-color, .has-{slug}-background-color"
  #   root_custom_property_selector: ":root"
  #   root_block_selector: "body"
  # The properties theme.json tokens govern: colour, spacing, typography.
  TOKEN_PROPERTY = /\A(?:color|background-color|background|padding(?:-[a-z-]+)?|margin(?:-[a-z-]+)?|gap|row-gap|column-gap|font-size|font-family)\z/
  # A reference into the token system. `--wp--style--*` are theme.json-derived
  # (block-gap, root padding) and resolve to presets themselves.
  TOKEN_REF = /var\(--wp--(?:preset|style|custom)--/
  # CSS keywords that are not values of their own.
  KEYWORDS = %w[0 inherit initial unset currentcolor transparent auto none].freeze
  TOKEN_CATEGORIES = %w[color spacing font-size font-family].freeze

  Surfaces = Struct.new(:root_tokens, :style_attributes, :utility_rules, :body_rule, :block_supports,
                        keyword_init: true)

  module_function

  def manifest
    @manifest ||= YAML.safe_load_file(MANIFEST, permitted_classes: [Time, Date])
  end

  def manifest_rules
    manifest.fetch("normalizationRules").each_with_object({}) { |rule, acc| acc.merge!(rule) }
  end

  def manifest_screen(name)
    manifest.fetch("screens").find { |s| s["name"] == name } or raise "#{name} is not in #{MANIFEST}"
  end

  def corpus
    @corpus ||= Parity::Differ.new.corpus
  end

  def corpus_entry(screen)
    corpus.find { |e| e["screen"] == screen } or raise "#{screen} is not in #{Parity::Differ::CORPUS}"
  end

  # The feature's traceability header names the screen: `#   screen: web.single (SCR-0131)`.
  def screen_of(feature_file)
    File.read(feature_file)[/^#\s+screen:\s+(web\.[a-z0-9_]+)/, 1] or
      raise "#{feature_file} has no `screen:` traceability header"
  end

  def oracle = Parity::OracleClient.new
  def normalizer = Parity::Normalizer.new

  def fetch_rebuild(path)
    Parity::OracleClient.new(base_url: REBUILD_URL).get(path)
  rescue Parity::OracleClient::Unreachable
    raise Parity::OracleClient::Unreachable,
          "The rebuild is not reachable at #{REBUILD_URL}. Start it with:\n  #{START_REBUILD}"
  end

  # Exactly what bin/parity does with a response (differ.rb): a redirect IS the
  # screen's behaviour and is captured as its Location; anything else as its body.
  def normalized(response)
    if response.status.between?(300, 399)
      normalizer.call("REDIRECT #{response.location}", content_type: "text/plain")
    else
      normalizer.call(response.body, content_type: response.content_type)
    end
  end

  def declarations(css)
    css.to_s.split(";").filter_map do |decl|
      prop, value = decl.split(":", 2)
      next if value.nil?

      [prop.strip.downcase, value.strip.sub(/\s*!important\z/i, "")]
    end
  end

  def loose?(prop, value)
    TOKEN_PROPERTY.match?(prop) && !TOKEN_REF.match?(value) && !KEYWORDS.include?(value.downcase)
  end

  def surfaces(html)
    doc = Nokogiri::HTML(html)
    global = doc.at_css("style#global-styles-inline-css")&.text.to_s
    Surfaces.new(
      root_tokens: global.scan(/:root\{([^}]*)\}/).flatten.join(";"),
      style_attributes: doc.css("[style]").map { |node| node["style"] },
      utility_rules: global.scan(/\.has-[a-z0-9-]+-(?:color|background-color|font-size|font-family)\{([^}]*)\}/).flatten,
      body_rule: global[/(?:\A|\})body\{([^}]*)\}/, 1],
      block_supports: doc.at_css("style#core-block-supports-inline-css")&.text.to_s
    )
  end

  # Screens that carry no theme token system, by legacy construction. The literal
  # mode forbids changing them (they are byte-compared), so the token invariant has
  # nothing to evaluate there -- recorded, not papered over.
  def tokenless_reason(screen, response)
    case screen
    when "web.attachment"
      "web.attachment is a 301 to the file (canonical.php:553, wp_attachment_pages_enabled=0; " \
      "deferred item D-7): HTTP #{response.status}, no document, no stylesheet."
    when "web.embed"
      "web.embed is core's iframe template (wp-includes/embed-template.php + css/wp-embed-template.css), " \
      "which theme.json does not style: it emits no :root presets and its colours are literals " \
      "in the legacy. Literal mode reproduces it byte-for-byte, so the invariant cannot hold here."
    end
  end
end

Before("@visual-parity") do |scenario|
  @screen = ScreenParity.screen_of(scenario.location.file)
end

# ── Given ─────────────────────────────────────────────────────────────────────
Given("the parity oracle seeded with the agreed corpus") do
  @oracle = ScreenParity.oracle
  home = @oracle.get("/") # raises Parity::OracleClient::Unreachable -- RISK-001, never skipped
  expect(home.status).to eq(200)
  # tools/seed.php:327 -- the corpus's own site title (4-byte UTF-8 and quotes on purpose).
  expect(home.body.dup.force_encoding(Encoding::UTF_8)).to include("Reversa Oracle &quot;7.2&quot; 😀")
end

Given("a golden capture of {string} taken from the oracle") do |screen|
  expect(screen).to eq(@screen), "feature header says #{@screen}, scenario says #{screen}"
  entry = ScreenParity.corpus_entry(screen)
  @golden_file = File.join(Parity::Differ::GOLDEN_DIR, entry.fetch("golden"))
  expect(File).to exist(@golden_file), "no golden for #{screen}: run `bin/parity capture` (D-4)"
  @golden = File.read(@golden_file)
  expect(@golden).not_to be_empty

  manifest = ScreenParity.manifest_screen(screen)
  expect(manifest["present"]).to be(true), "manifest.yaml still reports present:false for #{screen} (DEV-001)"
  expect(manifest["file"]).to eq(entry["golden"])
  @content_type = screen == "web.attachment" ? "text/plain" : "text/html"
end

Given("the oracle runs with the injected clock and fixed seed from the manifest") do
  rules = ScreenParity.manifest_rules
  @clock = rules.fetch("injectClock")
  @seed = rules.fetch("seedRandom")
  expect(@clock).to eq("2026-01-01T00:00:00Z")
  expect(@seed).to eq(42)
  # Neither can be set inside the oracle's PHP process from outside. The manifest's
  # strategy ("fake-clock + fixed-seed + seeded corpus") is delivered as: the seeded
  # corpus pins every date (tools/seed.php § 13b), and the harness normalizes the two
  # per-request sources of nondeterminism (normalizer.rb TIME_PATTERNS and
  # GENERATED_ID_PATTERNS). Prove both normalizations are live before relying on them.
  n = ScreenParity.normalizer
  expect(n.call("2026-08-22T10:11:12+00:00", content_type: "text/plain")).to eq("<TIME>")
  expect(n.call('aria-controls="wp-embed-share-tab-wordpress-1-3624864193"', content_type: "text/html"))
    .to include("wp-embed-share-tab-wordpress-1-<UID>")
  @oracle = ScreenParity.oracle
  expect(@oracle.available?).to be(true), "oracle unreachable -- bin/oracle up"
end

# ── When ──────────────────────────────────────────────────────────────────────
# Also matched with `Given` by the token scenario; cucumber matches on text.
When("the target renders the route {string}") do |route|
  entry = ScreenParity.corpus_entry(@screen)
  @path = entry.fetch("path")
  if route != @path
    log "route #{route.inspect} is the Inspector's pre-corpus placeholder; #{@screen}'s " \
        "corpus-resolved permalink is #{@path.inspect} (spec/parity/corpus/requests.yml) -- rendering that."
  end

  @response = ScreenParity.fetch_rebuild(@path)
  expected_status = entry["expect_status"] || 200
  expect(@response.status).to eq(expected_status),
    "#{@screen}: expected HTTP #{expected_status} for #{@path}, got #{@response.status}"
  @actual = ScreenParity.normalized(@response)
  @rendered_html = @response.body.dup.force_encoding(Encoding::UTF_8)
end

When("{string} is captured twice") do |screen|
  expect(screen).to eq(@screen)
  path = ScreenParity.corpus_entry(screen).fetch("path")
  @oracle_captures = Array.new(2) { ScreenParity.normalized(@oracle.get(path)) }
  # The same precondition holds for the side being compared: a rebuild that is not
  # reproducible cannot be green five runs in a row either.
  @target_captures = Array.new(2) { ScreenParity.normalized(ScreenParity.fetch_rebuild(path)) }
end

# ── Then ──────────────────────────────────────────────────────────────────────
Then("the rendered output matches the golden capture") do
  expect(@actual).to eq(@golden), lambda {
    "#{@screen} (#{@path}) diverges from #{File.basename(@golden_file)}:\n" +
      Parity::Differ.new.unified_diff(@golden, @actual)
  }

  # web.comments is "a PARTIAL, not a route" (18-comments.feature): the whole page
  # already matched above; the region the screen names is extracted and compared on
  # its own so the partial is asserted by name, not by inclusion.
  if @screen == "web.comments"
    golden_region = Nokogiri::HTML(@golden).at_css(".wp-block-comments")
    actual_region = Nokogiri::HTML(@actual).at_css(".wp-block-comments")
    expect(golden_region).not_to be_nil, "no .wp-block-comments region in the golden"
    expect(actual_region).not_to be_nil, "no .wp-block-comments region in the rendered output"
    expect(actual_region.to_html).to include("wp-block-comments-title")
    expect(actual_region.to_html).to eq(golden_region.to_html)
  end
end

Then("the comparison applies only the normalization rules declared in the manifest") do
  declared = ScreenParity.manifest_rules
  applied = ScreenParity.normalizer.instance_variable_get(:@rules)

  # Every rule the manifest declares ON is the one in effect, with the same value...
  ScreenParity::RULE_KEYS.each do |manifest_key, rule_key|
    expect(applied[rule_key]).to eq(declared.fetch(manifest_key)),
      "#{manifest_key}: manifest says #{declared[manifest_key].inspect}, normalizer applies #{applied[rule_key].inspect}"
  end
  # ...every rule the normalizer applies is declared...
  expect(applied.keys - ScreenParity::RULE_KEYS.values).to be_empty
  # ...and the rules declared OFF are really off.
  expect(declared["trimTrailingSpaces"]).to be(false)
  expect(ScreenParity.normalizer.call("<p>a </p>", content_type: "text/html")).to eq("<p>a </p>")
  expect(declared["stripAnsiColors"]).to be(false)
  expect(ScreenParity.normalizer.call("\e[31mx\e[0m", content_type: "text/plain")).to eq("\e[31mx\e[0m")
  expect(declared["seedRandom"]).to eq(42)

  # The golden is a fixed point of the normalizer: it was produced by exactly these
  # rules, and re-applying them changes nothing. A golden that normalized further would
  # mean the comparison was made in a space the manifest does not describe.
  expect(ScreenParity.normalizer.call(@golden, content_type: @content_type)).to eq(@golden)
end

Then("colour, spacing and typography resolve to theme token custom properties") do
  reason = ScreenParity.tokenless_reason(@screen, @response)
  pending(reason) if reason

  @surfaces = ScreenParity.surfaces(@rendered_html)

  # BR-GS-06: the presets are delivered on :root...
  ScreenParity::TOKEN_CATEGORIES.each do |category|
    expect(@surfaces.root_tokens).to include("--wp--preset--#{category}--"),
      "no --wp--preset--#{category}--* custom property on :root"
  end
  # BR-GS-07: ...the utility classes resolve to them...
  expect(@surfaces.utility_rules).not_to be_empty
  @surfaces.utility_rules.each do |rule|
    expect(rule).to match(/var\(--wp--preset--/), "utility rule does not resolve to a preset: #{rule}"
  end
  # ...and the root block's colour and typography are token references, not values.
  expect(@surfaces.body_rule).not_to be_nil, "no body{} root-block rule in global-styles"
  body = ScreenParity.declarations(@surfaces.body_rule).to_h
  %w[background-color color font-family font-size].each do |prop|
    expect(body[prop]).to match(/\Avar\(--wp--preset--#{prop == 'background-color' ? 'color' : prop}--/),
      "body #{prop} is #{body[prop].inspect}, not a preset reference"
  end
end

Then("no colour, spacing or typography value appears as a loose literal") do
  reason = ScreenParity.tokenless_reason(@screen, @response)
  pending(reason) if reason

  # The scanner must be able to see a literal, or an empty result proves nothing.
  expect(ScreenParity.loose?("color", "#fff")).to be(true)
  expect(ScreenParity.loose?("padding-top", "1.5rem")).to be(true)
  expect(ScreenParity.loose?("padding-top", "var(--wp--preset--spacing--30)")).to be(false)
  expect(ScreenParity.loose?("margin-top", "0")).to be(false)

  @surfaces ||= ScreenParity.surfaces(@rendered_html)
  expect(@surfaces.style_attributes).not_to be_empty, "no style attributes to inspect"

  loose = []
  @surfaces.style_attributes.each do |css|
    ScreenParity.declarations(css).each { |p, v| loose << "style=\"#{css}\" -> #{p}:#{v}" if ScreenParity.loose?(p, v) }
  end
  @surfaces.utility_rules.each do |css|
    ScreenParity.declarations(css).each { |p, v| loose << "utility rule #{p}:#{v}" if ScreenParity.loose?(p, v) }
  end
  ScreenParity.declarations(@surfaces.body_rule).each { |p, v| loose << "body #{p}:#{v}" if ScreenParity.loose?(p, v) }

  expect(loose).to be_empty, "loose literals on #{@screen}:\n  #{loose.join("\n  ")}"

  # Outside the contract's binding surfaces: the layout block support
  # (core-block-supports-inline-css, wp_get_layout_style) carries whatever blockGap a
  # pattern AUTHORED. Twenty Twenty-Five's own patterns/hidden-written-by.php:13 sets
  # "blockGap":"0.2em", which literal mode reproduces byte-for-byte on every screen that
  # renders that pattern. It is a legacy-authored literal, not a binding defect, so it is
  # reported rather than asserted -- and it is not hidden either.
  authored = ScreenParity.declarations(@surfaces.block_supports.to_s.gsub(/[^{}]*\{|\}/, ";"))
                         .select { |p, v| ScreenParity.loose?(p, v) }
  log "layout-support literals authored by the legacy theme on #{@screen}: " \
      "#{authored.map { |p, v| "#{p}:#{v}" }.join(', ')}" unless authored.empty?
end

Then("both captures are byte-identical") do
  expect(@oracle_captures.first).not_to be_empty
  expect(@oracle_captures.first).to eq(@oracle_captures.last), lambda {
    "oracle is not reproducible for #{@screen}:\n" +
      Parity::Differ.new.unified_diff(@oracle_captures.first, @oracle_captures.last)
  }
  expect(@target_captures.first).to eq(@target_captures.last), lambda {
    "rebuild is not reproducible for #{@screen}:\n" +
      Parity::Differ.new.unified_diff(@target_captures.first, @target_captures.last)
  }
end
