# frozen_string_literal: true

require "digest"
require_relative "normalizer"
require_relative "oracle_client"

module Parity
  # The response-diff harness (AD-08, spec/parity/).
  #
  # Two jobs:
  #   1. CAPTURE — record the oracle's normalized responses as golden files. This is
  #      deferred item D-4: "Run the golden capture, then remove the DEV-001 exception."
  #   2. COMPARE — replay the corpus against the rebuild and diff against the goldens.
  #
  # parity_specs.md sets the bar at ZERO UNEXPLAINED DIVERGENCE, not a percentage:
  # "A percentage threshold assumes divergences are noise. Here they are not: AD-01
  #  removes the hook system, so the documented default becomes the permanent, only
  #  behaviour — there is no filter to correct it afterwards. A 1% tolerance would
  #  permanently bake in whatever fell inside it."
  #
  # So every diff must resolve to one of four recorded categories, and anything else is
  # a defect. `EXPLAINED` below is that list, and it is deliberately short.
  class Differ
    ROOT = File.expand_path("..", __dir__)
    GOLDEN_DIR = File.join(ROOT, "golden")
    CORPUS = File.join(ROOT, "corpus", "requests.yml")

    # The four categories parity_specs.md § "Parity accepted" criteria admits.
    EXPLAINED = {
      "T-07/BR-POST-10" => "guid becomes a UUID in the target; feeds expose it, so feed " \
                           "output differs by design. Normalized, not ignored.",
      "T-06"            => "one terms row per (term, taxonomy) pair: term-id sharing is gone. " \
                           "Any diff that depends on shared term ids is expected.",
      "DEV-001"         => "the 18 literal screens had no golden capture until Wave 0 ran it.",
    }.freeze

    Result = Struct.new(:screen, :path, :status, :outcome, :detail, keyword_init: true)

    def initialize(oracle: OracleClient.new, normalizer: Normalizer.new, io: $stdout)
      @oracle = oracle
      @normalizer = normalizer
      @io = io
    end

    def corpus
      require "yaml"
      YAML.safe_load_file(CORPUS).fetch("requests")
    end

    # ── D-4: run the golden capture ──────────────────────────────────────────────
    def capture!
      FileUtils.mkdir_p(GOLDEN_DIR)
      results = corpus.map do |entry|
        response = @oracle.get(entry["path"])
        expected_status = entry["expect_status"] || 200
        if response.status != expected_status
          next Result.new(screen: entry["screen"], path: entry["path"], status: response.status,
                          outcome: :status_mismatch,
                          detail: "expected HTTP #{expected_status}, got #{response.status}")
        end

        # A redirect IS the screen's behaviour when the oracle redirects (see
        # web.attachment). Capture the normalized Location rather than an empty body,
        # so the contract is comparable instead of vacuous.
        normalized = if response.status >= 300 && response.status < 400
                       @normalizer.call("REDIRECT #{response.location}", content_type: "text/plain")
                     else
                       @normalizer.call(response.body, content_type: response.content_type)
                     end
        filename = entry["golden"] || "golden-#{entry["screen"].tr(".", "-")}.txt"
        File.write(File.join(GOLDEN_DIR, filename), normalized)

        Result.new(screen: entry["screen"], path: entry["path"], status: response.status,
                   outcome: :captured,
                   detail: "#{filename}  sha256=#{Digest::SHA256.hexdigest(normalized)[0, 16]}  " \
                           "#{normalized.bytesize} bytes")
      end
      render(results, "golden capture (D-4)")
      results
    end

    # ── COMPARE — replay the corpus against the rebuild ──────────────────────────
    # `fetch` is a callable taking a path and returning [status, body, content_type],
    # so the harness does not care whether the rebuild is reached over HTTP or through
    # Rack::Test.
    def compare(fetch:)
      results = corpus.map do |entry|
        golden_file = File.join(GOLDEN_DIR, entry["golden"] || "golden-#{entry["screen"].tr(".", "-")}.txt")
        unless File.exist?(golden_file)
          next Result.new(screen: entry["screen"], path: entry["path"], outcome: :no_golden,
                          detail: "no golden file — run `bin/parity capture` first (D-4)")
        end

        status, body, content_type = fetch.call(entry["path"])
        actual = @normalizer.call(body, content_type: content_type)
        expected = File.read(golden_file)

        if actual == expected
          Result.new(screen: entry["screen"], path: entry["path"], status: status,
                     outcome: :match, detail: "#{actual.bytesize} bytes")
        else
          Result.new(screen: entry["screen"], path: entry["path"], status: status,
                     outcome: :diverged, detail: unified_diff(expected, actual))
        end
      end
      render(results, "parity comparison")
      results
    end

    def unified_diff(expected, actual, context: 2)
      a = expected.lines
      b = actual.lines
      first = (0...[a.length, b.length].max).find { |i| a[i] != b[i] } || 0
      window = [first - context, 0].max
      out = ["    first divergence at line #{first + 1} of #{[a.length, b.length].max}"]
      (window...[first + context + 1, [a.length, b.length].max].min).each do |i|
        out << "      oracle #{i + 1}: #{a[i]&.chomp&.slice(0, 160).inspect}"
        out << "      target #{i + 1}: #{b[i]&.chomp&.slice(0, 160).inspect}"
      end
      out.join("\n")
    end

    def render(results, title)
      @io.puts
      @io.puts "── #{title} ─────────────────────────────────────────"
      results.each do |r|
        symbol = { captured: "●", match: "✓", diverged: "✗", no_golden: "○",
                   status_mismatch: "!" }.fetch(r.outcome, "?")
        @io.puts format("  %s %-28s %-52s %s", symbol, r.screen, r.path.to_s.slice(0, 52), r.outcome)
        @io.puts "      #{r.detail}" if r.detail && r.outcome != :captured
        @io.puts "      #{r.detail}" if r.outcome == :captured
      end
      bad = results.count { |r| %i[diverged status_mismatch].include?(r.outcome) }
      @io.puts
      @io.puts bad.zero? ? "  #{results.length} request(s), no unexplained divergence." : "  ❌ #{bad} divergence(s)."
      @io.puts
    end
  end
end
