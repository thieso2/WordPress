# frozen_string_literal: true

require_relative "markup_helper"

RSpec.describe Markup::Processor do
  def fragment(html)
    described_class.create_fragment(html)
  end

  def tags(processor)
    names = []
    names << processor.get_tag while processor.next_tag
    names
  end

  describe "BR-MIGRATE-223: HTML5 tree construction with both stacks" do
    it "opens and closes elements in document order without building a tree" do
      processor = fragment("<div><p>one</p><p>two</p></div>")
      trace = []
      while processor.next_token
        next unless processor.get_token_type == "#tag"

        trace << "#{processor.tag_closer? ? '/' : ''}#{processor.get_tag}"
      end

      expect(trace).to eq(%w[DIV P /P P /P /DIV])
    end

    it "closes an open P when a block-level element opens" do
      processor = fragment("<p>one<div>two</div>")
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY])

      processor.next_tag("P")
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY P])

      processor.next_tag("DIV")
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY DIV])
    end

    it "implies TBODY and TR inside a table" do
      processor = fragment("<table><td>cell</td></table>")

      expect(tags(processor)).to eq(%w[TABLE TBODY TR TD])
    end

    it "keeps the stack of open elements available while parsing" do
      processor = fragment("<figure><img></figure>")
      processor.next_tag("IMG")

      stack = processor.state.stack_of_open_elements.stack.map(&:node_name)
      expect(stack).to eq(%w[HTML FIGURE IMG])
    end

    it "tracks formatting elements on the list of active formatting elements" do
      processor = fragment("<b>bold</b>")
      processor.next_tag("B")

      names = processor.state.active_formatting_elements.walk_down.map(&:node_name)
      expect(names).to eq(["B"])
    end

    it "fences the list of active formatting elements with markers" do
      processor = fragment("<b><marquee>x</marquee></b>")
      processor.next_tag("MARQUEE")

      names = processor.state.active_formatting_elements.walk_down.map(&:node_name)
      expect(names).to eq(["B", Markup::ActiveFormattingElements::MARKER])
    end

    it "closes the previous list item when a new one opens" do
      processor = fragment("<ul><li>one<li>two</ul>")
      depths = []
      while processor.next_tag
        depths << [processor.get_tag, processor.get_current_depth]
      end

      expect(depths).to eq([["UL", 3], ["LI", 4], ["LI", 4]])
    end

    it "treats void elements as opening and immediately closing" do
      processor = fragment("<p><br><img></p>")
      expect(processor.expects_closer).to be_nil

      processor.next_tag("BR")
      expect(processor.expects_closer).to be false

      processor.next_tag("IMG")
      expect(processor.expects_closer).to be false
    end

    it "enters foreign content for SVG and returns to HTML afterwards" do
      processor = fragment("<svg><circle></circle></svg><p>after</p>")

      processor.next_tag("SVG")
      expect(processor.get_namespace).to eq("svg")

      processor.next_tag("CIRCLE")
      expect(processor.get_namespace).to eq("svg")

      processor.next_tag("P")
      expect(processor.get_namespace).to eq("html")
    end
  end

  describe "BR-MIGRATE-224: fragment parsing requires a context element, defaulting to <body>" do
    it "defaults the context to BODY, which is why HTML and BODY lead every path" do
      processor = fragment("<p>x</p>")

      expect(processor.context_node.node_name).to eq("BODY")
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY])
    end

    it "starts in the in-body insertion mode because of that context" do
      processor = fragment("")

      expect(processor.state.insertion_mode)
        .to eq(Markup::ProcessorState::INSERTION_MODE_IN_BODY)
    end

    it "counts the context in the depth from the very first token" do
      processor = fragment("<div><p></p></div>")
      expect(processor.get_current_depth).to eq(2)

      processor.next_token
      expect(processor.get_current_depth).to eq(3)

      processor.next_token
      expect(processor.get_current_depth).to eq(4)
    end

    it "refuses any context other than <body> through this entry point" do
      expect(described_class.create_fragment("<td>x</td>", "<table>")).to be_nil
      expect(described_class.create_fragment("<p>x</p>", "<div>")).to be_nil
    end

    it "refuses a non-UTF-8 encoding rather than guessing at the bytes" do
      expect(described_class.create_fragment("<p>x</p>", "<body>", "ISO-8859-1")).to be_nil
      expect(described_class.create_full_parser("<p>x</p>", "ISO-8859-1")).to be_nil
    end

    it "drops a TD in BODY context, which is the point of having a context at all" do
      processor = fragment("<td />Inside TD?</td>")
      seen = []
      seen << [processor.get_token_name, processor.get_modifiable_text] while processor.next_token

      expect(seen).to eq([["#text", "Inside TD?"]])
    end

    it "parses a whole document without a context element" do
      processor = described_class.create_full_parser("<!DOCTYPE html><html><body><p>x</p></body></html>")

      expect(processor.context_node).to be_nil
      expect(tags(processor)).to eq(%w[HTML HEAD BODY P])
    end
  end

  describe "BR-MIGRATE-225: unsupported constructs raise instead of producing wrong output" do
    it "raises rather than reconstructing active formatting elements" do
      processor = fragment("<b><i>bold italic</b> italic</i>")
      nil while processor.next_token

      expect(processor.get_last_error).to eq(described_class::ERROR_UNSUPPORTED)
      expect(processor.get_unsupported_exception).to be_a(Markup::UnsupportedException)
      expect(processor.get_unsupported_exception.message)
        .to eq("Cannot reconstruct active formatting elements when advancing and rewinding is required.")
    end

    it "raises rather than foster-parenting content out of a table" do
      processor = fragment("<table>text<tr><td>c</td></tr></table>")
      nil while processor.next_token

      expect(processor.get_unsupported_exception.message).to eq("Foster parenting is not supported.")
    end

    it "raises rather than pretending to support PLAINTEXT" do
      processor = fragment("<plaintext>everything else")
      nil while processor.next_token

      expect(processor.get_unsupported_exception.message).to eq("Cannot process PLAINTEXT elements.")
    end

    it "carries enough context on the exception to reconstruct the failure" do
      processor = fragment("<div><p><b>x</p>y</b>")
      nil while processor.next_token

      error = processor.get_unsupported_exception
      expect(error.token_name).to eq("#text")
      expect(error.token_at).to be_a(Integer)
      expect(error.token).to eq("y")
      expect(error.stack_of_open_elements).to eq(%w[HTML DIV])
      expect(error.active_formatting_elements).to eq(%w[B])
    end

    it "stops permanently once it has aborted, rather than limping on" do
      processor = fragment("<b><i>bold italic</b> italic</i>")
      nil while processor.next_token

      expect(processor.next_token).to be false
      expect(processor.next_tag).to be false
      expect(processor.get_tag).to be_nil
    end

    it "reports the failure through the API instead of letting the exception escape" do
      processor = fragment("<plaintext>x")

      expect { nil while processor.next_token }.not_to raise_error
      expect(processor.get_last_error).to eq("unsupported")
    end

    it "yields every token up to the point where it gives up" do
      processor = fragment("<p>fine</p><table>text</table>")
      seen = []
      seen << processor.get_token_name while processor.next_token

      expect(seen.first(3)).to eq(%w[P #text P])
      expect(processor.get_last_error).to eq(described_class::ERROR_UNSUPPORTED)
    end
  end

  describe "BR-MIGRATE-226: ancestor querying without a DOM or XPath" do
    it "reports the full path from the root to the matched element" do
      processor = fragment("<p><strong><em><img></em></strong></p>")
      processor.next_tag("IMG")

      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY P STRONG EM IMG])
    end

    # PHP arrays are values, so `get_breadcrumbs()` hands back a copy that the caller can
    # keep and mutate. Returning the live Array would silently rewrite every path a caller
    # had already collected; the differential harness `dup`s, so only this catches it.
    it "returns a copy the caller may keep and mutate, as PHP's value semantics do" do
      processor = fragment("<div><p>x</p></div>")
      processor.next_tag("DIV")
      kept = processor.get_breadcrumbs
      kept << "MUTATED"
      processor.next_tag("P")

      expect(kept).to eq(%w[HTML BODY DIV MUTATED])
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY DIV P])
    end

    it "matches a breadcrumb suffix, not the whole path" do
      processor = fragment("<div><span><figure><img></figure></span></div>")
      processor.next_tag("IMG")

      expect(processor.matches_breadcrumbs(%w[figure img])).to be true
      expect(processor.matches_breadcrumbs(%w[span figure img])).to be true
      expect(processor.matches_breadcrumbs(%w[span img])).to be false
    end

    it "treats * as exactly one element, never as any number of them" do
      processor = fragment("<div><span><figure><img></figure></span></div>")
      processor.next_tag("IMG")

      expect(processor.matches_breadcrumbs(["span", "*", "img"])).to be true
      expect(processor.matches_breadcrumbs(["div", "*", "img"])).to be false
    end

    it "matches breadcrumbs case-insensitively" do
      processor = fragment("<figure><img></figure>")
      processor.next_tag("IMG")

      expect(processor.matches_breadcrumbs(%w[FIGURE IMG])).to be true
      expect(processor.matches_breadcrumbs(%w[Figure Img])).to be true
    end

    it "matches everything when there are no constraints" do
      processor = fragment("<div></div>")
      processor.next_tag

      expect(processor.matches_breadcrumbs([])).to be true
    end

    it "drives next_tag with a breadcrumb query" do
      html = "<figure><img src=1></figure><img src=2><figure><img src=3></figure>"
      processor = fragment(html)

      expect(processor.next_tag(breadcrumbs: %w[FIGURE IMG])).to be true
      expect(processor.get_attribute("src")).to eq("1")

      expect(processor.next_tag(breadcrumbs: %w[FIGURE IMG])).to be true
      expect(processor.get_attribute("src")).to eq("3")

      expect(processor.next_tag(breadcrumbs: %w[FIGURE IMG])).to be false
    end

    it "honours match_offset on a breadcrumb query" do
      processor = fragment("<div><p>a</p><p>b</p><p>c</p></div>")

      expect(processor.next_tag(breadcrumbs: %w[DIV P], match_offset: 2)).to be true
      expect(processor.get_modifiable_text).to eq("")

      processor.next_token
      expect(processor.get_modifiable_text).to eq("b")
    end

    it "tracks depth as elements open and close" do
      processor = fragment("<div><p></p></div>")
      depths = [processor.get_current_depth]
      depths << processor.get_current_depth while processor.next_token

      expect(depths).to eq([2, 3, 4, 3, 2])
    end
  end

  describe "virtual tokens" do
    it "reports elements the algorithm implied but the document never wrote" do
      processor = described_class.create_full_parser("<p>x")
      names = []
      names << processor.get_tag while processor.next_tag

      expect(names).to eq(%w[HTML HEAD BODY P])
    end

    it "exposes no attributes on a virtual token, because it has no text" do
      processor = described_class.create_full_parser("<p class=x>y")
      processor.next_tag("HTML")

      expect(processor.get_attribute("class")).to be_nil
      expect(processor.get_attribute_names_with_prefix("")).to be_nil
      expect(processor.set_attribute("id", "no")).to be false
      expect(processor.set_bookmark("nope")).to be false
    end
  end

  describe "BR-MIGRATE-221 in the tree parser: seek replays tree construction" do
    it "returns to a bookmarked element with its breadcrumbs intact" do
      processor = fragment("<div><section><p>one</p></section><p>two</p></div>")
      processor.next_tag("P")
      processor.set_bookmark("first-p")

      processor.next_tag("P")
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY DIV P])

      expect(processor.seek("first-p")).to be true
      expect(processor.get_breadcrumbs).to eq(%w[HTML BODY DIV SECTION P])
    end
  end
end
