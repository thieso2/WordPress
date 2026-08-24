# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tempfile"

# Composition::Renderers::LayoutBlocks against the live PHP oracle.
#
# DIFFERENTIAL, for the reason parser_spec.rb gives: handoff.md's argument for standing up
# an oracle is that the 431 rules "were verified by READING, never by executing". A spec
# that asserted what this author believes `wp_get_layout_style()` does would reproduce
# exactly the weakness the oracle exists to remove. So every expectation below is the
# output of running WordPress 7.2-alpha-63330, not a transcription of it.
#
# Two things are asserted that the parity harness structurally CANNOT see:
#   * BR-MIGRATE-201's class ORDER — `bin/parity` normalizes by sorting class tokens;
#   * the `block-supports` stylesheet, which no screen prints until page assembly lands.
RSpec.describe Composition::Renderers::LayoutBlocks do
  LB_BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  LB_THEME = "/workspace/WordPress/wp-content/themes/twentytwentyfive"
  LB_FAMILY = %w[core/group core/columns core/column core/buttons core/button core/heading
              core/paragraph core/spacer core/separator core/list core/list-item
              core/quote core/cover].freeze

  # `is-style-<slug>--<n>`, the block style variation instance class. Not implemented; see
  # the "known gaps" group at the bottom, which asserts the size and shape of the gap
  # rather than hiding it.
  LB_VARIATION_CLASS = / is-style-\S+?--\d+\b/

  before(:all) do
    skip "no PHP oracle on PATH" unless system("php -v > /dev/null 2>&1")
    skip "oracle not installed" unless File.exist?(LB_BOOTSTRAP)
  end

  # ── the bridge ────────────────────────────────────────────────────────────────────────
  #
  # Every document is rendered in ONE PHP process, in order, and the block-supports store
  # is never reset — because `wp_unique_prefixed_id()` is a process-global static that
  # cannot be reset either, and the Ruby side mirrors that by threading ONE RenderContext
  # through the same documents in the same order. Resetting one and not the other is what
  # makes a differential spec lie.
  def oracle_render(documents)
    script = <<~PHP
      <?php
      require_once '#{LB_BOOTSTRAP}';
      $in  = json_decode(file_get_contents('php://stdin'), true);
      $out = [];
      foreach ($in as $k => $doc) {
        $html = '';
        foreach (parse_blocks($doc) as $b) { $html .= render_block($b); }
        $out[$k] = $html;
      }
      echo json_encode(
        ['html' => $out,
         'css'  => wp_style_engine_get_stylesheet_from_context('block-supports', ['prettify' => false])],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
      );
    PHP
    file = Tempfile.new(["render", ".php"])
    file.write(script)
    file.close
    out, err, status = Open3.capture3("php", file.path, stdin_data: JSON.generate(documents))
    raise "PHP oracle failed: #{err[0, 400]}" unless status.success?

    JSON.parse(out)
  ensure
    file&.unlink
  end

  # The rebuild's counterpart: one context, same order, same accumulation.
  #
  # The registry is narrowed to this family for the duration of the run. Other agents own
  # the other renderers and are landing them concurrently; a differential over THIS file
  # must not turn red because a sibling family is mid-flight, and a block outside the
  # family falls back to `Base`, which is what the corpus below is filtered to avoid.
  def rebuild_render(documents)
    ctx = Composition::RenderContext.new
    original = Composition::Renderers.registry.dup
    begin
      Composition::Renderers.registry.select! { |name, _| LB_FAMILY.include?(name) }
      html = documents.transform_values { |doc| Composition::Renderer.render(doc, ctx) }
      { "html" => html, "css" => described_class.block_supports_css(ctx) }
    ensure
      Composition::Renderers.registry.replace(original)
    end
  end

  # ── the corpus ────────────────────────────────────────────────────────────────────────
  #
  # Built from the real theme rather than invented: every template, every part and all 98
  # patterns are parsed, every block belonging to this family is extracted, and the ones
  # whose whole subtree is in the family are kept. That last filter is what makes the
  # comparison about THIS family: a `core/group` wrapping a `core/navigation` would differ
  # for reasons that belong to another agent's file.
  def serialize(block)
    return block.inner_html.to_s if block.block_name.nil?

    attrs = block.attrs.nil? || block.attrs.empty? ? "" : "#{described_class::Php.json_encode(block.attrs)} "
    name = block.block_name.sub(%r{\Acore/}, "")
    return "<!-- wp:#{name} #{attrs}/-->" if block.inner_content.empty?

    index = -1
    inner = block.inner_content.map do |chunk|
      next chunk unless chunk.nil?

      index += 1
      serialize(block.inner_blocks[index])
    end.join
    "<!-- wp:#{name} #{attrs}-->#{inner}<!-- /wp:#{name} -->"
  end

  def family_only?(block)
    return true if block.block_name.nil?
    return false unless LB_FAMILY.include?(block.block_name)

    block.inner_blocks.all? { |b| family_only?(b) }
  end

  def collect(blocks, into)
    blocks.each do |block|
      into << block if !block.block_name.nil? && LB_FAMILY.include?(block.block_name) && family_only?(block)
      collect(block.inner_blocks, into)
    end
  end

  let(:corpus) do
    found = []
    files = Dir[File.join(LB_THEME, "templates", "*.html")].sort +
            Dir[File.join(LB_THEME, "parts", "*.html")].sort +
            Dir[File.join(LB_THEME, "patterns", "*.php")].sort
    files.each { |path| collect(Composition::Parser.parse(File.read(path)), found) }
    documents = {}
    found.each_with_index do |block, i|
      markup = serialize(block)
      key = "#{block.block_name}##{i}"
      documents[key] = markup unless documents.value?(markup)
    end
    documents
  end

  describe "the real theme, block by block" do
      # ⚠️ KNOWN GAP — kept red-on-purpose as `pending`, never skipped.
      #
      # Two halves, both verified against the oracle, neither visible on any of the 25
      # golden screens (the only instance class the corpus renders is post-terms-1--2):
      #
      #   1. `Styling::Stylesheet#styles_for_block` does not port step 6 of
      #      `WP_Theme_JSON::get_styles_for_block` — the block style VARIATION rulesets
      #      (class-wp-theme-json.php:3834-3880, :4148-4165). So for a block-level
      #      variation the generated CSS is empty, and `StyleVariations.apply` then
      #      withholds the `is-style-<v>--<n>` class, faithfully to
      #      block-style-variations.php:188. The oracle emits both the class and
      #      `:root :where(p.is-style-text-subtitle--1){…}`.
      #   2. For elements-only variations the class IS emitted, but by the post-render
      #      fallback, which APPENDS it — after `wp-block-paragraph`. In the legacy it is
      #      a generic `render_block` filter (priority 10) and lands BEFORE the
      #      block-specific `render_block_core/paragraph` class (class-wp-block.php:717
      #      vs :732). BR-MIGRATE-201 ordering; the screen diff sorts class tokens and
      #      cannot see it, which is why this spec exists.
      #
      # `pending` means RSpec runs the example and FAILS THE BUILD if it starts passing,
      # so the gap cannot close silently. Closing it: port step 6 into packs/styling, then
      # move the variation class into a generic phase before `Supported#after_supports`.
    it "renders every instance of this family byte-identically to render_block()" do
      pending "block style variation rulesets (theme-json step 6) are not ported; see the note above"
      documents = corpus
      expect(documents.size).to be >= 300

      expected = oracle_render(documents)
      actual = rebuild_render(documents)

      diverged = documents.keys.reject do |key|
        want = expected["html"][key]
        # Instances whose ONLY divergence is the unimplemented block style variation class
        # are counted separately, immediately below, rather than silently tolerated here.
        want == actual["html"][key] || want.gsub(LB_VARIATION_CLASS, "") == actual["html"][key]
      end

      expect(diverged).to eq([]), lambda {
        key = diverged.first
        want = expected["html"][key]
        got = actual["html"][key]
        i = 0
        i += 1 while i < [want.length, got.length].min && want[i] == got[i]
        "#{diverged.length} of #{documents.size} instances diverge; first is #{key}\n" \
          "  php:  ...#{want[[0, i - 100].max, 220].inspect}\n" \
          "  ruby: ...#{got[[0, i - 100].max, 220].inspect}"
      }
    end

    it "produces a byte-identical block-supports stylesheet for the same corpus" do
      documents = corpus
      expected = oracle_render(documents)
      actual = rebuild_render(documents)

      expect(actual["css"]).to eq(expected["css"])
    end
  end

  # ── the ordering the parity harness cannot see ────────────────────────────────────────
  describe "BR-MIGRATE-201 — attribute values are space-concatenated, in writer order" do
    # ⚠️ `bin/parity compare` normalizes by SORTING class tokens, so the golden files agree
    # with any permutation of these names. The order is still part of the output and still
    # a rule, so it is asserted here, unsorted, against the oracle.
    let(:flex_group) do
      <<~HTML.strip
        <!-- wp:group {"align":"full","layout":{"type":"flex","flexWrap":"nowrap","justifyContent":"space-between"}} -->
        <div class="wp-block-group alignfull"><!-- wp:paragraph --><p>a</p><!-- /wp:paragraph --></div>
        <!-- /wp:group -->
      HTML
    end

    it "emits the classes in the order the legacy writes them, not sorted" do
      documents = { "flex" => flex_group }
      want = oracle_render(documents)["html"]["flex"]
      got = rebuild_render(documents)["html"]["flex"]

      expect(got).to eq(want)

      classes = got[/class="([^"]*)"/, 1].split
      # The SAVED classes first, then in order: the 5.9-era attribute classes, the layout
      # type class, the container hash class, and finally the compound block class that
      # global styles hook onto (layout.php:1333).
      expect(classes.first(2)).to eq(%w[wp-block-group alignfull])
      expect(classes.last).to eq("wp-block-group-is-layout-flex")
      expect(classes).to include("is-content-justification-space-between", "is-nowrap", "is-layout-flex")
      expect(classes).not_to eq(classes.sort)
    end

    it "is the same rule Styling::BlockSupports enforces for wrapper attributes" do
      # The thirteen blocks in this family are static: not one of their render callbacks
      # calls `get_block_wrapper_attributes()`, so `apply_block_supports()` never runs for
      # them and their class attribute is built by the `render_block` chain instead. The
      # rule is the same rule, so it is asserted directly against the pack.
      supports = Styling::BlockSupports.new
      supports.register("first", apply: ->(_t, _a) { { "class" => "one" } })
      supports.register("second", apply: ->(_t, _a) { { "class" => "two" } })
      supports.register("third", apply: ->(_t, _a) { { "class" => "" } })

      registry = Styling::BlockTypeRegistry.new
      registry.register(Styling::BlockType.new("core/group", attributes: {}))

      output = supports.apply_block_supports({ "blockName" => "core/group", "attrs" => {} }, registry)
      # "one two " — with the trailing space. `class-wp-block-supports.php:114` skips a
      # support only when its WHOLE return is `empty()`; `array('class' => '')` is not,
      # so the empty string is appended after a separator like any other value. The pack
      # reproduces that, and so does the oracle; it is recorded here because it looks like
      # a bug and is not one to fix.
      expect(output["class"]).to eq("one two ")
    end
  end

  # ── the PHP primitives the class-name hashes depend on ────────────────────────────────
  describe "Composition::Renderers::LayoutBlocks::Php" do
    def php_eval(expression)
      out, err, status = Open3.capture3(
        "php", "-r", "require_once '#{LB_BOOTSTRAP}'; echo #{expression};"
      )
      raise "PHP failed: #{err[0, 300]}" unless status.success?

      out
    end

    it "reproduces sanitize_title() for the values layout.php passes it" do
      %w[core/group core/columns core/list-item space-between horizontal stretch
         is-layout-flow is-layout-constrained].each do |value|
        expect(described_class::Php.sanitize_title(value))
          .to eq(php_eval("sanitize_title(#{value.inspect})")), "sanitize_title(#{value})"
      end
    end

    it "reproduces wp_json_encode() closely enough that md5 agrees" do
      # These are the exact shapes `wp_unique_id_from_values()` is handed at
      # layout.php:1267 and layout.php:1058 — a list whose first element is either an
      # empty PHP array (which encodes as `[]`, not `{}`) or a layout object.
      cases = [
        [{}, true, nil, false, "1.2rem", nil],
        [{ "type" => "flex", "flexWrap" => "nowrap", "justifyContent" => "space-between" },
         true, nil, false, "var(--wp--preset--spacing--50)", nil],
        [{ "type" => "constrained" }, true, "var:preset|spacing|60", false, "1.2rem",
         { "padding" => { "top" => "0", "left" => "var:preset|spacing|50" } }],
        [{ "type" => "grid", "columnCount" => 3 }, true, { "top" => "1rem" }, false, "1.2rem", nil]
      ]
      cases.each do |value|
        php = php_eval("wp_unique_id_from_values(json_decode(#{JSON.generate(JSON.generate(value))}, true), 'p-')")
        expect(described_class::Php.unique_id_from_values(value, "p-")).to eq(php), value.inspect
      end
    end

    it "escapes the way PHP's json_encode does — slashes and non-ASCII" do
      expect(described_class::Php.json_encode(["a/b", "é", "\u{1F600}"]))
        .to eq(php_eval("wp_json_encode(['a/b', 'é', '😀'])"))
    end
  end

  # ── the six resolved theme.json values the layout support reads ───────────────────────
  describe "Composition::Renderers::LayoutBlocks::GlobalStyles" do
    def php_json(expression)
      out, err, status = Open3.capture3(
        "php", "-r", "require_once '#{LB_BOOTSTRAP}'; echo wp_json_encode(#{expression});"
      )
      raise "PHP failed: #{err[0, 300]}" unless status.success?

      JSON.parse(out)
    end

    it "agrees with wp_get_global_settings() on every value the support reads" do
      settings = php_json("wp_get_global_settings()")
      described_class::GlobalStyles.reset!

      expect(described_class::GlobalStyles.use_root_padding_aware_alignments?)
        .to eq(settings["useRootPaddingAwareAlignments"] == true)
      # layout.php:1207 tests `isset()`, so what matters is presence, not truth.
      expect(described_class::GlobalStyles.has_block_gap_support?)
        .to eq(!settings.dig("spacing", "blockGap").nil?)
      expect(described_class::GlobalStyles.settings["layout"]).to eq(settings["layout"])
      expect(described_class::GlobalStyles.settings.dig("typography", "fluid"))
        .to eq(settings.dig("typography", "fluid"))
    end

    it "agrees with wp_get_global_styles() on the blockGap fallbacks" do
      styles = php_json("wp_get_global_styles()")
      described_class::GlobalStyles.reset!

      expect(described_class::GlobalStyles.root_block_gap).to eq(styles.dig("spacing", "blockGap"))
      %w[core/columns core/buttons core/quote core/group].each do |name|
        expect(described_class::GlobalStyles.block_gap_for(name))
          .to eq(styles.dig("blocks", name, "spacing", "blockGap")), name
      end
    end

    it "resolves the internal var:preset form the way WP_Theme_JSON::sanitize() does" do
      expect(described_class::GlobalStyles.block_gap_for("core/columns"))
        .to eq("var(--wp--preset--spacing--50)")
    end
  end

  # ── what each block does, stated once ─────────────────────────────────────────────────
  describe "the blocks" do
    def render_one(markup)
      rebuild_render({ "x" => markup })["html"]["x"]
    end

    def expect_matches_oracle(markup)
      documents = { "x" => markup }
      expect(rebuild_render(documents)["html"]["x"]).to eq(oracle_render(documents)["html"]["x"])
    end

    it "adds wp-block-paragraph to the first p — and LAST, because it is a filter" do
      # paragraph.php:38 registers `render_block_core/paragraph`, which runs AFTER the
      # whole `render_block` chain, so the class lands at the END of the attribute.
      html = render_one("<!-- wp:paragraph --><p class=\"x\">hi</p><!-- /wp:paragraph -->")
      expect(html).to eq(%(<p class="x wp-block-paragraph">hi</p>))
    end

    it "adds wp-block-heading to the first heading tag only" do
      expect_matches_oracle(
        "<!-- wp:heading --><h2>a</h2><!-- /wp:heading -->"
      )
      expect(render_one("<!-- wp:heading --><div><h3>a</h3><h3>b</h3></div><!-- /wp:heading -->"))
        .to eq("<div><h3 class=\"wp-block-heading\">a</h3><h3>b</h3></div>")
    end

    it "leaves an already-classed list alone rather than adding the class twice" do
      expect_matches_oracle(
        %(<!-- wp:list --><ul class="wp-block-list"><!-- wp:list-item --><li>a</li><!-- /wp:list-item --></ul><!-- /wp:list -->)
      )
    end

    it "renders NOTHING for an empty button (gutenberg#17221)" do
      markup = %(<!-- wp:buttons --><div class="wp-block-buttons"><!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link"></a></div><!-- /wp:button --></div><!-- /wp:buttons -->)
      expect(render_one(markup)).not_to include("wp-block-button__link")
      expect_matches_oracle(markup)
    end

    it "treats an HTML comment inside a button as still empty" do
      expect_matches_oracle(
        %(<!-- wp:button --><div class="wp-block-button"><a class="wp-block-button__link"><!-- c --></a></div><!-- /wp:button -->)
      )
    end

    it "resolves a percentage button width to the legacy width classes" do
      expect_matches_oracle(
        %(<!-- wp:button {"style":{"dimensions":{"width":"50%"}}} --><div class="wp-block-button"><a class="wp-block-button__link">go</a></div><!-- /wp:button -->)
      )
    end

    it "puts the layout classes on cover's INNER container, not on the wrapper" do
      # layout.php:1381 — the wrapper for the inner blocks is identified by the class
      # attribute the saved markup gave it, which for cover is `wp-block-cover__inner-container`.
      markup = <<~HTML.strip
        <!-- wp:cover {"customOverlayColor":"#000"} -->
        <div class="wp-block-cover"><span aria-hidden="true" class="wp-block-cover__background has-background-dim"></span><div class="wp-block-cover__inner-container"><!-- wp:paragraph --><p>a</p><!-- /wp:paragraph --></div></div>
        <!-- /wp:cover -->
      HTML
      html = render_one(markup)
      expect(html).to include(%(class="wp-block-cover__inner-container is-layout-flow wp-block-cover-is-layout-flow"))
      expect(html).not_to include(%(class="wp-block-cover is-layout-flow))
      expect_matches_oracle(markup)
    end

    it "gives a spacer with a child layout its wp-container-content class" do
      expect_matches_oracle(
        %(<!-- wp:spacer {"height":"0px","style":{"layout":{"selfStretch":"fixed","flexSize":"140px"}}} --><div style="height:0px" aria-hidden="true" class="wp-block-spacer"></div><!-- /wp:spacer -->)
      )
    end

    it "rewrites a literal font-size into the theme's fluid clamp()" do
      expect_matches_oracle(
        %(<!-- wp:heading {"style":{"typography":{"fontSize":"9.6rem"}}} --><h2 class="wp-block-heading" style="font-size:9.6rem">a</h2><!-- /wp:heading -->)
      )
    end

    it "leaves a font-size below the 14px floor alone" do
      expect_matches_oracle(
        %(<!-- wp:paragraph {"style":{"typography":{"fontSize":"12px"}}} --><p style="font-size:12px">a</p><!-- /wp:paragraph -->)
      )
    end
  end

  # ── gaps, stated rather than hidden ───────────────────────────────────────────────────
  describe "known gaps" do
    it "does not add the position support's sticky classes — the only other omission" do
      # `patterns/vertical-header.php`, reduced to the one group that carries
      # `style.position`. The oracle adds `wp-container-<n> is-position-sticky`; the `<n>`
      # is `wp_unique_id()`, a counter shared with every block on the page, which this
      # family cannot own. Everything else about the block matches.
      markup = <<~HTML.strip
        <!-- wp:group {"align":"wide","style":{"position":{"type":"sticky","top":"0px"},"spacing":{"padding":{"top":"var:preset|spacing|40","bottom":"var:preset|spacing|40"}}},"layout":{"type":"default"}} -->
        <div class="wp-block-group alignwide" style="padding-top:var(--wp--preset--spacing--40);padding-bottom:var(--wp--preset--spacing--40)"><!-- wp:paragraph --><p>a</p><!-- /wp:paragraph --></div>
        <!-- /wp:group -->
      HTML
      documents = { "sticky" => markup }
      want = oracle_render(documents)["html"]["sticky"]
      got = rebuild_render(documents)["html"]["sticky"]

      expect(want).to include("is-position-sticky")
      expect(got).not_to include("is-position-sticky")
      # Strip exactly the two classes the position support adds, and nothing is left over.
      expect(want.sub(/ wp-container-\d+ is-position-sticky/, "")).to eq(got)
    end

    it "does not add the block style variation instance class, and nothing else differs" do
      pending "half-closed: elements-only variations now carry the class (appended, wrong position); block-level ones still do not — see the note above"
      documents = corpus
      expected = oracle_render(documents)["html"]
      actual = rebuild_render(documents)["html"]

      affected = documents.keys.reject { |k| expected[k] == actual[k] }
      expect(affected).not_to be_empty, "the gap closed — delete this spec and the placeholder"
      affected.each do |key|
        expect(expected[key].gsub(LB_VARIATION_CLASS, "")).to eq(actual[key]), lambda {
          "#{key} diverges by something OTHER than the variation class"
        }
      end
    end
  end
end
