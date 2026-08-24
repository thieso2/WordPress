# frozen_string_literal: true

require "json"
require "open3"
require_relative "markup_helper"

RSpec.describe Markup::Decoder do
  describe "named character references" do
    it "ships the complete, frozen HTML5 table" do
      # The HTML5 specification freezes this list; the legacy ships 2,231 entries as a
      # precomputed WP_Token_Map and this port exports the same set verbatim.
      expect(Markup::NamedCharacterReferences::TABLE.size).to eq(2231)
    end

    it "decodes semicolon-terminated references" do
      expect(described_class.decode_text_node("&amp;&lt;&gt;&quot;&apos;")).to eq(%(&<>"'))
      expect(described_class.decode_text_node("&nbsp;")).to eq(" ")
      expect(described_class.decode_text_node("&CounterClockwiseContourIntegral;")).to eq("∳")
    end

    it "decodes the legacy semicolon-less references" do
      expect(described_class.decode_text_node("&amp&lt&gt&AMP&LT&GT")).to eq("&<>&<>")
      expect(described_class.decode_text_node("&notit;")).to eq("¬it;")
    end

    it "takes the longest match, which is what makes &notin; different from &not" do
      expect(described_class.decode_text_node("&notin;")).to eq("∉")
      expect(described_class.decode_text_node("&not;")).to eq("¬")
    end

    it "leaves an ambiguous ampersand alone inside an attribute value" do
      # In attribute context a semicolon-less reference followed by an alphanumeric or
      # `=` is literal text; in a text node the same bytes decode.
      expect(described_class.decode_attribute("&ampx")).to eq("&ampx")
      expect(described_class.decode_text_node("&ampx")).to eq("&x")
      expect(described_class.decode_attribute("&amp=")).to eq("&amp=")
      expect(described_class.decode_attribute("&amp;x")).to eq("&x")
    end

    it "leaves text that is not a reference untouched" do
      expect(described_class.decode_text_node("&NotAnEntity;")).to eq("&NotAnEntity;")
      expect(described_class.decode_text_node("a & b")).to eq("a & b")
      expect(described_class.decode_text_node("&")).to eq("&")
    end
  end

  describe "numeric character references" do
    it "decodes decimal and hexadecimal forms" do
      expect(described_class.decode_text_node("&#38;&#x26;&#X26;")).to eq("&&&")
      expect(described_class.decode_text_node("&#128512;&#x1F600;")).to eq("\u{1F600}\u{1F600}")
    end

    it "ignores leading zeros" do
      expect(described_class.decode_text_node("&#00000038;")).to eq("&")
    end

    it "remaps the C1 control range as if it were Windows-1252" do
      expect(described_class.decode_text_node("&#128;")).to eq("€")
      expect(described_class.decode_text_node("&#x93;")).to eq("“")
      # …but only for numeric references; a raw byte is never remapped.
      expect(described_class.decode_text_node("\x80".b).b).to eq("\x80".b)
    end

    it "replaces surrogates and out-of-range code points with U+FFFD" do
      expect(described_class.decode_text_node("&#xD800;")).to eq("�")
      expect(described_class.decode_text_node("&#x110000;")).to eq("�")
      expect(described_class.decode_text_node("&#0;")).to eq("�")
    end

    it "leaves a reference with no digits as plain text" do
      expect(described_class.decode_text_node("&#;")).to eq("&#;")
      expect(described_class.decode_text_node("&#x;")).to eq("&#x;")
    end

    it "keeps NULL distinct from a reference that decodes to zero" do
      expect(described_class.decode_text_node("\x00".b).b).to eq("\x00".b)
      expect(described_class.decode_text_node("&#x00;")).to eq("�")
    end
  end

  describe "differential parity with the PHP oracle" do
    # A broad sample of the entity table plus the pathological forms, decoded in both
    # contexts on both sides.
    let(:samples) do
      names = Markup::NamedCharacterReferences::TABLE.keys
      sampled = names.each_slice(7).map(&:first).map { |name| "&#{name}" }
      sampled + [
        "&amp", "&ampx", "&amp=", "&amp;x", "&notit;", "&not", "&notin;", "&NotAnEntity;",
        "&#38;", "&#x26;", "&#X26;", "&#0;", "&#x00;", "&#;", "&#x;", "&#xD800;",
        "&#x110000;", "&#xFFFFFF;", "&#128;", "&#x9F;", "&#00000038;", "&&&", "&",
        "a&b&amp;c", "&lt;script&gt;", "&Tab;&NewLine;", "&#13;&#10;",
        "\u{1F600}&#x1F600;", "&#x1F600&#x1F600;", "text with no references at all"
      ]
    end

    it "decodes every sample identically in both contexts" do
      skip "PHP oracle unavailable" unless MarkupOracle.available?

      payload = JSON.generate(samples.map { |s| Base64.strict_encode64(s.b) })
      script = <<~'PHP'
        $inputs = json_decode( stream_get_contents( STDIN ), true );
        $out = array();
        foreach ( $inputs as $encoded ) {
          $text = base64_decode( $encoded );
          $out[] = array(
            base64_encode( WP_HTML_Decoder::decode_text_node( $text ) ),
            base64_encode( WP_HTML_Decoder::decode_attribute( $text ) )
          );
        }
        echo json_encode( $out );
      PHP

      out, err, status = Open3.capture3(
        "php", "-r", "require #{MarkupOracle::BOOTSTRAP.inspect}; #{script}", stdin_data: payload
      )
      raise "oracle failed: #{err}" unless status.success?

      expected = JSON.parse(out)
      actual = samples.map do |sample|
        [Base64.strict_encode64(described_class.decode_text_node(sample.b)),
         Base64.strict_encode64(described_class.decode_attribute(sample.b))]
      end

      samples.each_with_index do |sample, index|
        expect(actual[index]).to eq(expected[index]), "diverged for #{sample.inspect}"
      end
      expect(samples.length).to be > 300
    end
  end

  describe "attribute_starts_with" do
    it "compares against the decoded value without decoding the whole thing" do
      expect(described_class.attribute_starts_with("&amp;lorem", "&l")).to be true
      expect(described_class.attribute_starts_with("javascript&#58;x", "javascript:")).to be true
      expect(described_class.attribute_starts_with("JAVASCRIPT:x", "javascript:",
                                                   "ascii-case-insensitive")).to be true
      expect(described_class.attribute_starts_with("https://x", "javascript:")).to be false
    end
  end
end
