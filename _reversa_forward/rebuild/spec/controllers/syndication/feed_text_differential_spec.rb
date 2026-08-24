# frozen_string_literal: true

require "rails_helper"
require "json"
require "base64"
require "open3"

# Differential spec for the two transforms Syndication::FeedText ports itself
# rather than reusing from packs/sanitizing:
#
#   * ent2ncr()            — wp-includes/formatting.php:4168 (the $to_ncr table)
#   * wp_staticize_emoji() — wp-includes/formatting.php:6137 (+ wp_encode_emoji, :6116)
#
# Everything else FeedText composes is either already covered by the sanitizing
# pack's own differential suite or is exercised end-to-end by the seven byte-identical
# syndication goldens. Rule: prefer differential evidence over hand-written fixtures —
# the PHP oracle is the expected value here, not a transcription of it.
RSpec.describe "Syndication::FeedText vs the PHP oracle" do
  BOOTSTRAP = File.expand_path("../../../../oracle/wordpress/tools/_bootstrap.php", __dir__)

  PHP_RUNNER = <<~'PHP'
    require $argv[1];
    $in = json_decode(stream_get_contents(STDIN), true);
    $results = array();
    foreach ($in['cases'] as $case) {
      $arg = base64_decode($case['arg']);
      switch ($case['fn']) {
        case 'ent2ncr':            $out = ent2ncr($arg); break;
        case 'wp_staticize_emoji': $out = wp_staticize_emoji($arg); break;
        default:                   $out = null;
      }
      $results[] = $out === null ? null : base64_encode($out);
    }
    echo json_encode(array('results' => $results));
  PHP

  # The corpus deliberately covers: every emoji shape the seeded corpus contains
  # (single, ZWJ family, flag), astral NON-emoji (must survive untouched), the
  # ignore-block tags, entity-bearing text, and the `|` oddity in the ent2ncr table.
  CORPUS = [
    "",
    "plain ascii only",
    "Emoji 😀🧬🚀 · Math 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𝕬𝖑𝖌𝖊𝖇𝖗𝖆 · CJK-Ext-B 𠜎𠜱𠝹 · ZWJ 👨‍👩‍👧‍👦 · Flag 🇯🇵",
    "<p>inside a tag alt=\"😀\" stays</p> outside 😀 converts",
    "<pre>😀 ignored</pre> after 😀",
    "<code>😀</code><textarea>😀</textarea>😀",
    "already encoded &#x1f600; entity",
    "He said &quot;it&#039;s a test&quot; &amp; more &hellip; &laquo;fr&raquo;",
    "pipe | becomes an entity",
    "&lt;a href=&quot;x&quot;&gt; « 日本語 » ‘curly’ “already curly”",
    "mixed 😀 and &mdash; and 𝔘",
    "éèê accents stay",
    "🇯🇵🇺🇸 two flags back to back",
    "family👨‍👩‍👧‍👦family",
  ].freeze

  before(:all) do
    skip "PHP oracle not available" unless File.exist?(BOOTSTRAP) && system("which php > /dev/null 2>&1")
  end

  def oracle(fn, inputs)
    payload = JSON.generate(cases: inputs.map { |s| { fn: fn, arg: Base64.strict_encode64(s) } })
    out, err, status = Open3.capture3("php", "-r", PHP_RUNNER, BOOTSTRAP, stdin_data: payload)
    raise "PHP oracle failed (#{status.exitstatus}): #{err}" unless status.success? && !out.empty?

    JSON.parse(out).fetch("results").map { |r| Base64.decode64(r).force_encoding(Encoding::UTF_8) }
  end

  { "ent2ncr" => ->(s) { Syndication::FeedText.ent2ncr(s) },
    "wp_staticize_emoji" => ->(s) { Syndication::FeedText.staticize_emoji(s) } }.each do |fn, ruby|
    it "#{fn} matches the oracle byte-for-byte over the corpus" do
      expected = oracle(fn, CORPUS)
      mismatches = CORPUS.each_with_index.filter_map do |input, i|
        actual = ruby.call(input)
        next if actual == expected[i]

        "input: #{input.inspect}\n  php : #{expected[i].inspect}\n  ruby: #{actual.inspect}"
      end
      expect(mismatches).to be_empty, -> { "#{mismatches.size}/#{CORPUS.size} diverge:\n#{mismatches.join("\n")}" }
    end
  end
end
