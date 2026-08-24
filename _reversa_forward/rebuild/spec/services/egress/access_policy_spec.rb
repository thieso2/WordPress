# frozen_string_literal: true

require "rails_helper"
require "json"
require "base64"
require "open3"

# PT-011 / BC-14 -- Egress::AccessPolicy against its executable definition,
# WP_Http::block_request() (wp-includes/class-wp-http.php:895). BR-MIGRATE-257
# (BR-HTTP-13): the site-wide egress allowlist that WP_HTTP_BLOCK_EXTERNAL switches on
# and WP_ACCESSIBLE_HOSTS parameterises.
#
# The oracle's own wp-config.php hard-wires `WP_HTTP_BLOCK_EXTERNAL = true`, so the
# DIFFERENTIAL half here verifies the blocking-ON verdicts -- the own-host/localhost
# bypass, the comma split, the `*` wildcard translation and the inverse "in the list ⇒
# allow" logic -- against block_request() directly, per allowlist scenario. The
# default-OFF behaviour (WP_HTTP_BLOCK_EXTERNAL undefined ⇒ nothing blocked) cannot be
# reached on this oracle (its constant is fixed true), so it is asserted as a unit fact.
#
# NO REAL NETWORK: block_request() compares host strings only; it never resolves.
module BlockRequestOracle
  BRIDGE = File.expand_path("oracle/block_request.php", __dir__)

  module_function

  def available?
    File.exist?(BlockRequestOracle::BRIDGE) &&
      system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  # One fresh php process per scenario: block_request() caches WP_ACCESSIBLE_HOSTS in a
  # function static, so a process only ever sees one allowlist.
  def run(accessible_hosts, urls)
    payload = JSON.generate("accessible_hosts" => accessible_hosts,
                            "urls" => urls.map { |u| Base64.strict_encode64(u) })
    stdout, stderr, status = Open3.capture3("php", BRIDGE, stdin_data: payload)
    raise "block_request oracle failed: #{stderr}" unless status.success?

    doc = JSON.parse(stdout)
    { verdicts: doc.fetch("results"), site_host: doc.fetch("site_host"),
      blocking_enabled: doc.fetch("blocking_enabled") }
  end
end

RSpec.describe Egress::AccessPolicy do
  # A single URL set that reaches every branch of block_request(): a public host, the two
  # always-allowed hosts (localhost and the site's own host), a would-be wildcard match,
  # a subdomain, and an exact host.
  URLS = [
    "http://8.8.8.8/",              # public -> allowed only if listed
    "http://localhost/x",           # always allowed
    "http://127.0.0.1/x",           # the oracle's own host -> always allowed
    "http://api.wordpress.org/x",   # never listed below -> blocked
    "http://sub.example.com/x",     # matches *.example.com
    "http://example.com/x"          # matches example.com exactly
  ].freeze

  # accessible_hosts (as the WP_ACCESSIBLE_HOSTS string, or nil for "constant not set").
  SCENARIOS = [
    nil,                            # blocked with no allowlist -> only local hosts pass
    "example.com",                  # an exact single host
    "*.example.com, example.com",   # wildcard + exact, comma-separated
    "*.example.com",                # wildcard alone: example.com itself does NOT match
    "8.8.8.8, example.com"          # a literal IP in the list
  ].freeze

  describe "against block_request() (blocking mode on)" do
    before { skip "PHP oracle not available" unless BlockRequestOracle.available? }

    SCENARIOS.each do |accessible|
      it "reaches block_request()'s verdict for WP_ACCESSIBLE_HOSTS = #{accessible.inspect}" do
        oracle = BlockRequestOracle.run(accessible, URLS)
        skip "oracle is not in blocking mode" unless oracle[:blocking_enabled]

        policy = described_class.new(blocked: true, accessible_hosts: accessible,
                                     site_host: oracle[:site_host])

        divergences = URLS.each_with_index.filter_map do |url, i|
          expected = oracle[:verdicts][i]           # true == block
          actual = policy.block?(url)
          next if expected == actual

          "#{url.inspect}: oracle #{expected ? 'BLOCK' : 'ALLOW'}, rebuild #{actual ? 'BLOCK' : 'ALLOW'}"
        end

        expect(divergences).to be_empty,
          "AccessPolicy diverges from block_request() for #{accessible.inspect}:\n  #{divergences.join("\n  ")}"
      end
    end
  end

  describe "the default (WP_HTTP_BLOCK_EXTERNAL undefined)" do
    # block_request() line 897: "We don't need to block requests, because nothing is
    # blocked." Reproduced as: a disabled policy blocks nothing, whatever the URL.
    it "blocks nothing" do
      policy = described_class.disabled
      URLS.each { |url| expect(policy.block?(url)).to be(false) }
      expect(policy.block?("http://169.254.169.254/")).to be(false) # even the metadata IP
    end

    it "is what Egress::Client uses unless told otherwise, so egress is unchanged by default" do
      # The SSRF gate (UrlPolicy) still applies; the allowlist simply adds nothing.
      expect(Egress::Client.new.instance_variable_get(:@access_policy)).to be_a(described_class)
    end
  end

  describe ".from_env" do
    it "is off unless WP_HTTP_BLOCK_EXTERNAL is truthy, and reads WP_ACCESSIBLE_HOSTS raw" do
      off = described_class.from_env(env: {}, site_host: "self.test")
      expect(off.block?("http://8.8.8.8/")).to be(false)

      on = described_class.from_env(
        env: { "WP_HTTP_BLOCK_EXTERNAL" => "true", "WP_ACCESSIBLE_HOSTS" => "*.example.com" },
        site_host: "self.test"
      )
      expect(on.block?("http://8.8.8.8/")).to be(true)          # not listed
      expect(on.block?("http://sub.example.com/")).to be(false) # wildcard match
      expect(on.block?("http://self.test/")).to be(false)       # own host bypass
    end
  end
end
