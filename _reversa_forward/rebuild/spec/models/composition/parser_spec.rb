# frozen_string_literal: true

require "rails_helper"
require "open3"

# BR-MIGRATE-182..193 — Composition::Parser against the PHP oracle's parse_blocks().
#
# This is a DIFFERENTIAL spec, not a hand-written one: the expectations come from running
# the legacy, not from someone's reading of it. handoff.md's whole argument for the oracle
# is that the 431 rules "were verified by READING, never by executing" — so a parser spec
# that asserted what the author believed the grammar to be would reproduce exactly the
# weakness the oracle exists to remove.
RSpec.describe Composition::Parser do
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  THEME = "/workspace/WordPress/wp-content/themes/twentytwentyfive"

  # PHP has ONE array type, so `json_decode('{}', true)` yields `array()` and re-encodes as
  # `[]`. Ruby distinguishes them and is the one that is right; the PHP side is normalised
  # so the comparison is about the GRAMMAR rather than about PHP's type system.
  # Same family of hazard as T-02's contiguous-integer-key rule.
  def php_normalize(value)
    case value
    when Hash  then value.empty? ? [] : value.transform_values { |v| php_normalize(v) }
    when Array then value.map { |v| php_normalize(v) }
    else value
    end
  end

  def shape(blocks)
    blocks.map do |b|
      { "n" => b.block_name, "a" => php_normalize(b.attrs), "h" => b.inner_html,
        "c" => b.inner_content, "i" => shape(b.inner_blocks) }
    end
  end

  def oracle_parse(documents)
    script = <<~PHP
      <?php
      require_once '#{BOOTSTRAP}';
      function shape($bs){ return array_map(function($x){ return [
        'n'=>$x['blockName'], 'a'=>$x['attrs'], 'h'=>$x['innerHTML'],
        'c'=>$x['innerContent'], 'i'=>shape($x['innerBlocks'])]; }, $bs); }
      $in = json_decode(file_get_contents('php://stdin'), true);
      $out = [];
      foreach ($in as $k => $doc) { $out[$k] = shape(parse_blocks($doc)); }
      echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    PHP
    file = Tempfile.new(["parse", ".php"])
    file.write(script)
    file.close
    out, err, status = Open3.capture3("php", file.path, stdin_data: JSON.generate(documents))
    raise "PHP oracle failed: #{err[0, 400]}" unless status.success?
    raise "PHP oracle did not return JSON: #{out[0, 200]}" unless out.lstrip.start_with?("{")

    JSON.parse(out)
  ensure
    file&.unlink
  end

  def expect_identical(documents)
    expected = oracle_parse(documents)
    documents.each do |key, document|
      expect(shape(described_class.parse(document))).to eq(expected[key]), lambda {
        "#{key}: parse diverges from PHP parse_blocks()\n" \
          "  php:  #{JSON.generate(expected[key])[0, 400]}\n" \
          "  ruby: #{JSON.generate(shape(described_class.parse(document)))[0, 400]}"
      }
    end
  end

  describe "the real theme" do
    it "parses every twentytwentyfive template and part exactly as PHP does" do
      docs = {}
      Dir[File.join(THEME, "templates", "*.html")].sort.each { |f| docs["tpl:#{File.basename(f)}"] = File.read(f) }
      Dir[File.join(THEME, "parts", "*.html")].sort.each { |f| docs["part:#{File.basename(f)}"] = File.read(f) }
      expect(docs.size).to be >= 15
      expect_identical(docs)
    end

    it "parses all 98 block patterns exactly as PHP does" do
      docs = Dir[File.join(THEME, "patterns", "*.php")].sort
                .to_h { |f| ["pat:#{File.basename(f)}", File.read(f)] }
      expect(docs.size).to be >= 90
      expect_identical(docs)
    end
  end

  describe "the grammar's awkward corners" do
    it "matches PHP on malformed, hostile and unusual documents" do
      expect_identical(
        # A void block, and freeform content that is not a block at all.
        "void" => "<!-- wp:spacer /-->",
        "freeform" => "hello <b>world</b>",
        "mixed" => "before<!-- wp:paragraph --><p>x</p><!-- /wp:paragraph -->after",
        "nested" => "<!-- wp:group --><!-- wp:paragraph --><p>a</p><!-- /wp:paragraph --><!-- /wp:group -->",
        # A malformed attribute object must NOT lose the block, let alone the document.
        "badjson" => %(<!-- wp:x {"a":} --><p>y</p><!-- /wp:x -->),
        # Unbalanced delimiters are content, not errors.
        "unclosed" => "<!-- wp:group --><p>orphan</p>",
        "stray_close" => "<p>a</p><!-- /wp:group -->",
        "closer_with_attrs" => %(<!-- wp:g --><p>a</p><!-- /wp:g {"x":1} -->),
        # A third-party namespace keeps its prefix; a bare name gains `core/`.
        "ns" => %(<!-- wp:my-plugin/thing {"k":1} /-->),
        # The attribute sub-pattern has to survive braces inside strings. This is what the
        # possessive quantifier in the legacy regex is defending.
        "braces" => %(<!-- wp:q {"a":{"b":{"c":"}"}}} /-->),
        "emptyobj" => %(<!-- wp:q {"a":{},"b":[]} /-->),
        # /s in PCRE is /m in Ruby: without that, a pretty-printed attribute object stops
        # matching at the first newline.
        "multiline" => %(<!-- wp:group {\n  "x": 1\n} -->\n<p>m</p>\n<!-- /wp:group -->),
        # The corpus's adversarial text has to pass through untouched.
        "emoji" => "<!-- wp:paragraph --><p>\u{1F600} \u{1D518} \u{300C}\u65E5\u672C\u8A9E\u300D</p><!-- /wp:paragraph -->",
        "backslash" => '<!-- wp:code --><pre>C:\\Users\\thies</pre><!-- /wp:code -->'
      )
    end
  end

  describe "the corpus" do
    it "parses every post body in the seeded corpus exactly as PHP does" do
      docs = Publishing::Post.pluck(:id, :content).to_h { |id, c| ["post:#{id}", c.to_s] }
      skip "corpus not seeded — run bin/rails oracle:seed" if docs.empty?

      expect_identical(docs)
    end
  end

  describe "freeform content" do
    it "is preserved rather than discarded, which is how classic content survives" do
      blocks = described_class.parse("<p>classic editor content</p>")
      expect(blocks.length).to eq(1)
      expect(blocks.first).to be_freeform
      expect(blocks.first.inner_html).to eq("<p>classic editor content</p>")
    end
  end
end
