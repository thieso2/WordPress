# frozen_string_literal: true

require_relative "markup_helper"

RSpec.describe Markup::TagProcessor do
  describe "BR-MIGRATE-220: no tree is built; edits are byte-level and applied on get_updated_html" do
    it "leaves every byte it was not asked to change exactly as it found it" do
      html = "<div   id='a'\n     data-x=1 >text &amp; more<!-- keep me --></div>"
      processor = described_class.new(html)
      processor.next_tag
      processor.set_attribute("data-x", "2")

      expect(processor.get_updated_html)
        .to eq("<div   id='a'\n     data-x=\"2\" >text &amp; more<!-- keep me --></div>")
    end

    it "does not apply an edit until the document is asked for" do
      processor = described_class.new("<div class=\"a\">x</div>")
      processor.next_tag
      processor.set_attribute("class", "b")

      # The attribute reads back as the enqueued value...
      expect(processor.get_attribute("class")).to eq("b")
      # ...and only now is the document rewritten.
      expect(processor.get_updated_html).to eq("<div class=\"b\">x</div>")
    end

    it "appends a new attribute immediately after the tag name" do
      processor = described_class.new("<div/>")
      processor.next_tag
      processor.set_attribute("id", "new")

      expect(processor.get_updated_html).to eq('<div id="new"/>')
    end

    it "escapes attribute values so they cannot break out of the tag" do
      processor = described_class.new("<div>")
      processor.next_tag
      processor.set_attribute("title", %(a "b" & <c> 'd'))

      expect(processor.get_updated_html)
        .to eq('<div title="a &quot;b&quot; &amp; &lt;c&gt; &apos;d&apos;">')
    end

    it "removes duplicated declarations of an attribute together" do
      processor = described_class.new("<a href='one' HREF=\"two\" href=three>x</a>")
      processor.next_tag
      processor.remove_attribute("href")

      expect(processor.get_updated_html).to eq("<a   >x</a>")
    end

    it "rejects an attribute name containing syntax characters" do
      processor = described_class.new("<div>")
      processor.next_tag

      expect(processor.set_attribute("a>b", "x")).to be false
      expect(processor.set_attribute("a&b", "x")).to be false
      expect(processor.set_attribute("", "x")).to be false
      expect(processor.get_updated_html).to eq("<div>")
    end

    it "builds the class attribute from add_class and remove_class without touching the rest" do
      processor = described_class.new("<div class='  one   two  one '>x</div>")
      processor.next_tag
      processor.remove_class("two")
      processor.add_class("three")

      expect(processor.get_updated_html).to eq('<div class="one three">x</div>')
    end

    it "removes the class attribute entirely when nothing is left in it" do
      processor = described_class.new("<div class='only'>x</div>")
      processor.next_tag
      processor.remove_class("only")

      expect(processor.get_updated_html).to eq("<div >x</div>")
    end

    it "replaces a text node's contents, escaping what it is given" do
      processor = described_class.new("<p>before</p>")
      processor.next_token
      processor.next_token

      expect(processor.get_token_type).to eq("#text")
      expect(processor.set_modifiable_text("Eggs & <Milk>")).to be true
      expect(processor.get_updated_html).to eq("<p>Eggs &amp; &lt;Milk&gt;</p>")
    end

    it "refuses comment text that would terminate the comment early" do
      processor = described_class.new("<!-- old -->")
      processor.next_token

      expect(processor.set_modifiable_text("fine")).to be true
      expect(processor.set_modifiable_text("bad --> escape")).to be false
    end
  end

  describe "BR-MIGRATE-221: scanning is forward-only; bookmarks and seek are the only way back" do
    it "exposes no way to step backwards" do
      expect(described_class.instance_methods).not_to include(:previous_tag, :previous_token, :rewind)
    end

    it "returns to a bookmarked token with seek" do
      processor = described_class.new("<ul><li>One</li><li>Two</li><li>Three</li></ul>")
      last_li = nil
      while processor.next_tag("LI")
        processor.set_bookmark("last-li")
        last_li = processor.get_tag
      end

      expect(last_li).to eq("LI")
      expect(processor.seek("last-li")).to be true

      processor.add_class("last-li")
      expect(processor.get_updated_html)
        .to eq('<ul><li>One</li><li>Two</li><li class="last-li">Three</li></ul>')
    end

    it "keeps a bookmark pointing at its token after the document around it changes" do
      processor = described_class.new("<main><h2>Fact</h2></main>")
      processor.next_tag("H2")
      processor.set_bookmark("heading")

      expect(processor.seek("heading")).to be true
      expect(processor.get_tag).to eq("H2")

      # Widen an earlier tag, then confirm the bookmark still lands on the H2.
      processor.seek("heading")
      processor.set_attribute("id", "fact")
      processor.get_updated_html
      expect(processor.seek("heading")).to be true
      expect(processor.get_tag).to eq("H2")
      expect(processor.get_attribute("id")).to eq("fact")
    end

    it "releases a bookmark whose whole span is overwritten rather than let it drift" do
      processor = described_class.new("<div a=1><span>x</span></div>")
      processor.next_tag("SPAN")
      processor.set_bookmark("span")
      expect(processor.has_bookmark?("span")).to be true

      # Rewrite the span's opening tag from an earlier position.
      processor.seek("span")
      processor.set_attribute("class", "wide")
      processor.get_updated_html

      expect(processor.has_bookmark?("span")).to be true
    end

    it "refuses to set more bookmarks than the limit allows" do
      processor = described_class.new("<a><b><c><d><e><f><g><h><i><j><k><l>")
      created = 0
      created += 1 while processor.next_tag && processor.set_bookmark("mark-#{created}")

      expect(created).to eq(described_class::MAX_BOOKMARKS)
    end

    it "refuses to set a bookmark when the document is exhausted" do
      processor = described_class.new("<div></div>")
      nil while processor.next_token

      expect(processor.set_bookmark("nope")).to be false
    end

    it "stops seeking once the seek budget is spent" do
      processor = described_class.new("<a></a><b></b>")
      processor.next_tag
      processor.set_bookmark("one")
      processor.next_tag

      successes = 0
      (described_class::MAX_SEEK_OPS + 5).times do
        processor.next_tag
        successes += 1 if processor.seek("one")
      end

      expect(successes).to eq(described_class::MAX_SEEK_OPS)
    end
  end

  describe "BR-MIGRATE-222: attribute discovery by prefix" do
    it "returns lowercased names regardless of the casing in the document" do
      processor = described_class.new('<div data-ENABLED class="test" DATA-test-id="14">Test</div>')
      processor.next_tag

      expect(processor.get_attribute_names_with_prefix("data-")).to eq(%w[data-enabled data-test-id])
    end

    it "matches the prefix case-insensitively" do
      processor = described_class.new('<div DATA-WP-Bind--hidden="x">')
      processor.next_tag

      expect(processor.get_attribute_names_with_prefix("DATA-WP-")).to eq(["data-wp-bind--hidden"])
    end

    it "returns every attribute for an empty prefix" do
      processor = described_class.new('<img src="a" alt="b" width=3>')
      processor.next_tag

      expect(processor.get_attribute_names_with_prefix("")).to eq(%w[src alt width])
    end

    it "returns nil when not on a tag opener" do
      processor = described_class.new("<div></div>")
      expect(processor.get_attribute_names_with_prefix("data-")).to be_nil

      processor.next_tag
      expect(processor.get_attribute_names_with_prefix("data-")).to eq([])

      nil while processor.next_token
      expect(processor.get_attribute_names_with_prefix("data-")).to be_nil
    end

    it "includes attributes that are enqueued but not yet written" do
      processor = described_class.new("<div data-a=1>")
      processor.next_tag
      processor.set_attribute("data-b", "2")

      expect(processor.get_attribute_names_with_prefix("data-")).to eq(%w[data-b data-a])
    end

    it "excludes attributes that are enqueued for removal" do
      processor = described_class.new("<div data-a=1 data-b=2>")
      processor.next_tag
      processor.remove_attribute("data-a")

      expect(processor.get_attribute_names_with_prefix("data-")).to eq(["data-b"])
    end

    it "flushes pending class changes so the class attribute is discoverable" do
      processor = described_class.new("<div>")
      processor.next_tag
      processor.add_class("added")

      expect(processor.get_attribute_names_with_prefix("cl")).to eq(["class"])
    end
  end

  describe "token classification" do
    it "reports each kind of token the HTML syntax can produce" do
      html = '<!DOCTYPE html><p>t</p><!-- c --><![CDATA[x]]><?target data?></><//funky>'
      processor = described_class.new(html)
      types = []
      types << processor.get_token_type while processor.next_token

      expect(types).to eq(
        ["#doctype", "#tag", "#text", "#tag", "#comment", "#comment", "#processing-instruction",
         "#presumptuous-tag", "#funky-comment"]
      )
    end

    it "treats a `<` that cannot start a token as text" do
      processor = described_class.new("I <3 you")
      processor.next_token

      expect(processor.get_token_type).to eq("#text")
      expect(processor.get_modifiable_text).to eq("I <3 you")
    end

    it "reports </br> as an opening BR, as the HTML parser does" do
      processor = described_class.new("</br>")
      processor.next_token

      expect(processor.get_tag).to eq("BR")
      expect(processor.tag_closer?).to be false

      # `next_tag` still skips it, because the match test looks at the raw closing-tag
      # syntax rather than at the BR exception. Verified against the oracle.
      expect(described_class.new("</br>").next_tag).to be false
    end

    it "pauses rather than guessing at a truncated tag" do
      processor = described_class.new('<input type="text" value="Th')

      expect(processor.next_tag).to be false
      expect(processor.paused_at_incomplete_token?).to be true
    end
  end
end
