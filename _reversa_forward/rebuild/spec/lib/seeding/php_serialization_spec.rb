# frozen_string_literal: true

require "rails_helper"
require "seeding/php_serialization"

# T-02: PHP serialize() -> jsonb. RISK-006.
#
# These expectations are not guesses about the format: each fixture below was produced by
# running `serialize()` in PHP 8.4 against the live oracle, so the parser is checked
# against the thing it has to read rather than against a description of it.
RSpec.describe Seeding::PhpSerialization do
  def parse(raw) = described_class.parse(raw).last

  describe "scalars" do
    it "maps the five scalar tags directly" do
      expect(parse('s:5:"plain";')).to eq("plain")
      expect(parse("i:42;")).to eq(42)
      expect(parse("d:3.5;")).to eq(3.5)
      expect(parse("b:1;")).to be(true)
      expect(parse("b:0;")).to be(false)
      expect(parse("N;")).to be_nil
    end

    it "treats a value that is not serialized at all as itself" do
      # maybe_unserialize()'s behaviour: most option values are plain strings.
      expect(parse("just a string")).to eq("just a string")
      expect(described_class.parse("just a string").first).to eq(:unserialized)
    end
  end

  describe "arrays" do
    it "maps a contiguous integer-keyed array to a JSON array" do
      expect(parse('a:3:{i:0;s:1:"a";i:1;s:1:"b";i:2;s:1:"c";}')).to eq(%w[a b c])
    end

    it "maps a non-contiguous integer-keyed array to a JSON object" do
      # PHP's array/list duality: 0,5,10 is not a list, and flattening it to one would
      # silently reindex the caller's data.
      expect(parse('a:2:{i:0;s:4:"zero";i:5;s:4:"five";}')).to eq("0" => "zero", "5" => "five")
    end

    it "maps a string-keyed array to a JSON object" do
      expect(parse('a:1:{s:1:"k";s:1:"v";}')).to eq("k" => "v")
    end

    it "handles nesting" do
      expect(parse('a:1:{s:1:"a";a:1:{s:1:"b";s:4:"deep";}}')).to eq("a" => { "b" => "deep" })
    end
  end

  describe "4-byte UTF-8 (RISK-014)" do
    # ⚠️ The length prefix on s: is a BYTE count, not a character count. Reading it as
    # characters silently truncates every emoji-bearing string in the corpus — and the
    # corpus carries them on purpose.
    it "reads the length prefix as bytes, not characters" do
      emoji = "a\u{1F600}b\u{1F9EC}"   # 2 ASCII + 2 four-byte code points = 10 bytes
      payload = %(s:#{emoji.bytesize}:"#{emoji}";)
      expect(emoji.length).to eq(4)
      expect(emoji.bytesize).to eq(10)
      expect(payload).to include("s:10:")
      expect(parse(payload)).to eq(emoji)
      expect(parse(payload).bytesize).to eq(10)
    end

    it "returns UTF-8 tagged strings even though it scans bytes" do
      astral = "\u{1F600}"
      expect(parse(%(s:#{astral.bytesize}:"#{astral}";)).encoding).to eq(Encoding::UTF_8)
    end
  end

  describe "backslashes (T-08)" do
    it "copies bytes and never unslashes" do
      # "Adding an unslash pass here would corrupt every legitimate backslash in the
      #  corpus." The parser must be transparent to them.
      raw = 'C:\\Users\\thies'
      expect(parse(%(s:#{raw.bytesize}:"#{raw}";))).to eq(raw)
    end
  end

  describe "objects — no automatic mapping" do
    it "raises rather than guessing a class mapping" do
      expect { parse('O:8:"stdClass":0:{}') }
        .to raise_error(described_class::UnmappableObject, /stdClass/)
    end
  end

  describe "malformed input" do
    it "raises rather than returning a partial value" do
      expect { parse('a:5:{s:1:"a";') }.to raise_error(described_class::ParseError)
      expect { parse('s:99:"short";') }.to raise_error(described_class::ParseError)
    end
  end
end
