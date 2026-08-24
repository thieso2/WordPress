# frozen_string_literal: true

require "rails_helper"

# Composition::Serializer is the exact inverse of Composition::Parser. The contract that
# matters for the editor (DEV-012, D-3): serialize(parse(markup)) reproduces the original
# bytes, so a block the React island never touches is stored back unchanged, and a block it
# edits round-trips through the same grammar the Wave 3 differential specs verified against
# the live oracle. Ports wp-includes/blocks.php serialize_block* — asserted here to match.
RSpec.describe Composition::Serializer do
  def round_trip(markup)
    described_class.serialize(Composition::Parser.parse(markup))
  end

  describe "round-trips block markup byte-for-byte" do
    # The same adversarial shapes the parser spec defends, read from the other direction.
    {
      "paragraph"        => "<!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->",
      "attrs"            => %(<!-- wp:paragraph {"dropCap":true} --><p>Body</p><!-- /wp:paragraph -->),
      "void"             => %(<!-- wp:template-part {"slug":"header"} /-->),
      "void_no_attrs"    => "<!-- wp:site-logo /-->",
      "nested"           => %(<!-- wp:group --><div class="wp-block-group"><!-- wp:paragraph --><p>x</p><!-- /wp:paragraph --></div><!-- /wp:group -->),
      "ns"               => %(<!-- wp:my-plugin/thing {"k":1} /-->),
      "braces"           => %(<!-- wp:q {"a":{"b":{"c":"}"}}} /-->),
      "emptyobj"         => %(<!-- wp:q {"a":{},"b":[]} /-->),
      "unicode_attr"     => %(<!-- wp:heading {"content":"日本"} --><h2>日本</h2><!-- /wp:heading -->),
      "slash_attr"       => %(<!-- wp:image {"url":"https://x/y.png"} /-->),
      "emoji"            => "<!-- wp:paragraph --><p>\u{1F600}</p><!-- /wp:paragraph -->",
      "freeform"         => "<p>classic editor content</p>",
      "freeform_mixed"   => %(<p>lead</p><!-- wp:paragraph --><p>x</p><!-- /wp:paragraph -->)
    }.each do |name, markup|
      it name do
        expect(round_trip(markup)).to eq(markup)
      end
    end
  end

  describe "attribute encoding (serialize_block_attributes)" do
    it "escapes the comment-terminator and HTML-significant characters" do
      # WordPress rewrites --, <, >, &, and escaped-quote so the delimiter cannot be broken.
      markup = described_class.serialize([
        { "name" => "core/html", "attrs" => { "danger" => "a--b<c>d&e" }, "innerHTML" => "", "innerContent" => [] }
      ])
      expect(markup).to include('\\u002d\\u002d')
      expect(markup).to include('\\u003c').and include('\\u003e').and include('\\u0026')
      expect(markup).not_to include("a--b<c>d&e")
    end

    it "drops the implicit core/ namespace but keeps third-party namespaces" do
      core = described_class.serialize([{ "name" => "core/paragraph", "innerHTML" => "<p>x</p>", "innerContent" => ["<p>x</p>"] }])
      expect(core).to eq("<!-- wp:paragraph --><p>x</p><!-- /wp:paragraph -->")
      plugin = described_class.serialize([{ "name" => "acme/widget", "attrs" => {}, "innerHTML" => "", "innerContent" => [] }])
      expect(plugin).to eq("<!-- wp:acme/widget /-->")
    end
  end

  describe "editor Hash input (freshly inserted block without innerContent)" do
    it "falls back to innerHTML + inner blocks when innerContent is absent" do
      markup = described_class.serialize([
        { "name" => "core/paragraph", "attrs" => {}, "innerHTML" => "<p>new</p>", "innerBlocks" => [] }
      ])
      expect(markup).to eq("<!-- wp:paragraph --><p>new</p><!-- /wp:paragraph -->")
    end
  end

  describe "the seeded corpus" do
    it "serializes every parsed post body back to its exact bytes" do
      docs = Publishing::Post.pluck(:id, :content).reject { |_, c| c.to_s.empty? }
      skip "corpus not seeded — run bin/rails oracle:seed" if docs.empty?

      diverged = docs.reject { |_, content| round_trip(content) == content }
      expect(diverged.map(&:first)).to eq([]),
        lambda {
          id, content = docs.find { |i, _| i == diverged.first.first }
          got = round_trip(content)
          i = 0
          i += 1 while i < [content.length, got.length].min && content[i] == got[i]
          "post #{id} diverges at byte #{i}\n  orig: #{content[[0, i - 60].max, 160].inspect}\n  got:  #{got[[0, i - 60].max, 160].inspect}"
        }
    end
  end
end
