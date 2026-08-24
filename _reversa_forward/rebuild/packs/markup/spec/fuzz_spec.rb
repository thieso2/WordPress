# frozen_string_literal: true

require "json"
require "base64"
require "open3"
require_relative "markup_helper"
require_relative "support/traces"

# Randomised differential fuzzing against the PHP oracle.
#
# The hand-written corpus in spec/fixtures/corpus.json covers the cases a person thinks
# of. This covers the ones nobody thinks of: fragments concatenated at random produce
# misnesting, truncation and interleaving that no fixture list reaches. The seeds are
# fixed so a failure is reproducible; the pieces include the astral, quote and backslash
# material the migration brief insists the corpus must contain.
RSpec.describe "html-api randomised differential fuzzing" do
  PIECES = [
    "<div>", "</div>", "<p>", "</p>", "<b>", "</b>", "<i>", "</i>", "<a href=x>", "</a>",
    "<table>", "</table>", "<tr>", "</tr>", "<td>", "</td>", "<tbody>", "<caption>",
    "</caption>", "<ul>", "<li>", "</ul>", "<span class='a b'>", "</span>", "<br>",
    "<img src=1>", "<input>", "<script>x</script>", "<style>y</style>",
    "<textarea>t</textarea>", "<!-- c -->", "<!doctype html>", "text", "&amp;", "&#38;",
    "&notit;", "\u{1F600}", "𝔘𝔫𝔦", "C:\\Users\\thies", %(He said "it's a test"), "\x00",
    "\n", " ", "<svg>", "</svg>", "<math>", "<!", "<?", "</>", "<>", "<3", "<![CDATA[x]]>",
    "</3>", "<form>", "</form>", "<select>", "<option>", "<h1>", "</h1>", "<template>",
    "</template>", "<noscript>", "<head>", "<body>", "</body>", "</html>",
    "<font color=red>", "<nobr>", "<applet>", "<marquee>", "<frameset>", "<frame>",
    "<col>", "<colgroup>", "<dl>", "<dt>", "<dd>", "<pre>\n", "<title>t</title>",
    "<iframe>i</iframe>", "<xmp>x</xmp>", "a=1", '"', "'", "=", "/", ">", "<", "&",
    "-->", "--!>"
  ].freeze

  FIELDS = %w[tags paused tree error message mutated prefixes full full_error
              full_message seek].freeze

  def self.generate(seed, count)
    random = Random.new(seed)
    Array.new(count) do
      Array.new(random.rand(1..12)) { PIECES[random.rand(PIECES.length)] }.join
    end
  end

  def self.oracle_for(inputs)
    script = File.expand_path("support/dump_tokens.php", __dir__)
    payload = JSON.generate(inputs.map { |input| Base64.strict_encode64(input.b) })
    out, err, status = Open3.capture3("php", script, stdin_data: payload)
    raise "PHP oracle failed: #{err}" unless status.success?
    # A fatal inside the WordPress bootstrap is answered with a wp_die() HTML page on
    # stdout, not a non-zero exit, so JSON.parse would report an unrelated syntax error.
    raise "PHP oracle did not return JSON: #{out[0, 200]}" unless out.start_with?("[")

    JSON.parse(out)
  end

  [20_260_822, 1].each do |seed|
    context "with seed #{seed}" do
      before(:all) { skip "PHP oracle unavailable" unless MarkupOracle.available? }

      if MarkupOracle.available?
        inputs = generate(seed, 75)
        expected = oracle_for(inputs)

        it "matches the oracle on all #{inputs.length} generated documents" do
          divergences = inputs.each_with_index.filter_map do |html, index|
            actual = MarkupTraces.trace(html)
            field = FIELDS.find { |name| actual[name] != expected[index][name] }
            "#{html.inspect} diverged on #{field}" if field
          end

          expect(divergences).to be_empty
        end
      end
    end
  end
end
