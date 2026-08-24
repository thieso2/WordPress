# frozen_string_literal: true

require "rails_helper"
require "json"
require "base64"
require "open3"

# PT-011 / BC-14 -- Egress::UrlPolicy against its executable definition,
# wp_http_validate_url() (wp-includes/http.php:559), rule for rule.
#
# BR-MIGRATE-246..255 (BR-HTTP-02..11). This is the DIFFERENTIAL half of the SSRF
# work: the same URL corpus is fed to the running oracle's wp_http_validate_url() and
# to Egress::UrlPolicy, and the accept/reject verdict -- and, on accept, the returned
# (kses-cleaned) string -- must be identical for every URL. The Gherkin scenarios in
# 11-egress-and-ssrf.feature prove the STRUCTURE of the deviation (one door, named
# escape hatch, re-validated hops); this spec proves the VALIDATION MATCHES BYTE FOR
# BYTE, so the rules are diffed against the legacy rather than against a Ruby-only
# restatement of them (AD-08).
#
# ⚠️ DEVIATION BR-HTTP-01 is NOT under test here: whether validation runs by default is
# an architectural property (BC-14). What is under test is that WHEN it runs, it reaches
# the legacy's verdict. So the corpus is compared against wp_http_validate_url() itself.
#
# NO REAL NETWORK. The oracle helper (oracle/http_validate.php) explains the discipline:
# every host is either an IP literal (which both sides match with the dotted-quad regex,
# skipping gethostbyname() entirely), the site's own host, or an RFC 6761 `.invalid`
# name (which resolves nowhere). The Ruby side is handed an IDENTITY resolver -- a stub
# that returns its input unchanged, which is exactly gethostbyname()'s failure signal --
# so an `.invalid` host is refused on both sides without a packet leaving the machine.
module HttpValidateOracle
  HELPER = File.expand_path("oracle/http_validate.php", __dir__)

  module_function

  def available?
    File.exist?(HttpValidateOracle::HELPER) &&
      system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  # Returns { verdicts: [String|nil per url], home: String }. nil == rejected;
  # a String == accepted, and it is the exact bytes wp_http_validate_url() returned.
  #
  # Memoized by corpus: a full wp-load is heavy, and under the whole suite a dozen other
  # oracle-differential specs are opening MySQL connections to wp_oracle at the same time,
  # so the corpus is run through the oracle EXACTLY ONCE and both examples share the
  # verdicts -- which also means the differential and its guard can never disagree about
  # what the oracle said.
  def run(urls)
    (@cache ||= {})[urls] ||= call(urls)
  end

  def call(urls)
    payload = JSON.generate("urls" => urls.map { |u| Base64.strict_encode64(u) })
    stdout, stderr, status = Open3.capture3("php", HELPER, stdin_data: payload)
    raise "http_validate oracle failed: #{stderr}" unless status.success?

    doc = JSON.parse(stdout)
    result = { verdicts: doc.fetch("results").map { |r| r.nil? ? nil : Base64.decode64(r).force_encoding("UTF-8") },
               home: doc.fetch("home") }

    # A control the legacy MUST accept (public IP, no port, clean). If it comes back
    # rejected the oracle process did not load cleanly -- fail LOUDLY here rather than
    # letting it read as a policy divergence a dozen assertions later.
    control = urls.index("http://8.8.8.8/")
    if control && result[:verdicts][control].nil?
      raise "http_validate oracle returned degenerate results (wp-load or DB failure): " \
            "the control URL http://8.8.8.8/ was rejected."
    end
    result
  end
end

RSpec.describe Egress::UrlPolicy do
  before { skip "PHP oracle not available" unless HttpValidateOracle.available? }

  # gethostbyname() failure signal: an unlisted host resolves to itself. Every corpus
  # host is either an IP literal (never reaches this) or a `.invalid` name (which the
  # oracle's gethostbyname() also fails to resolve), so the two sides agree WITHOUT a
  # network. See the oracle helper's header for why this is sound.
  IDENTITY_RESOLVER = ->(host) { host }

  # One row per behaviour the legacy body exhibits, grouped by the rule it exercises.
  # Hosts are IP literals unless a rule specifically needs resolution to be observed.
  CORPUS = [
    # ── BR-HTTP-02 (246): only http/https survive kses_bad_protocol ──────────────
    "http://8.8.8.8/",
    "https://8.8.8.8/",
    "HTTP://8.8.8.8/",              # kses lowercases the scheme; case-fold compare passes.
    "HtTpS://8.8.8.8/",
    "ftp://8.8.8.8/",
    "gopher://8.8.8.8/",
    "file:///etc/passwd",
    "javascript:alert(1)",
    "data:text/plain,hi",
    "//8.8.8.8/x",                 # protocol-relative: no scheme for kses to strip, so accepted.

    # ── BR-HTTP-03 (247): kses as detection -- any change beyond case = reject ────
    "http://8.8.8.8/\x00",         # a control byte kses removes -> altered -> reject.
    "htt p://8.8.8.8/",

    # ── BR-HTTP-04 (248): userinfo rejected ──────────────────────────────────────
    "http://user:pass@8.8.8.8/",
    "http://user@8.8.8.8/",
    "http://8.8.8.8:8080@evil.invalid/",   # user=8.8.8.8, pass=8080, host=evil.invalid.

    # ── BR-HTTP-05 (249): host chars : # ? [ ] rejected (excludes IPv6 literals) ──
    "http://[::1]/",
    "http://[fe80::1]/",
    "http://ex#ample.invalid/",    # '#' begins a fragment -> host 'ex' -> unresolvable.
    "http://ex?ample.invalid/",    # '?' begins a query    -> host 'ex' -> unresolvable.

    # ── BR-HTTP-06 (250): own-host bypasses every IP-range check ──────────────────
    # The oracle's own host is 127.0.0.1 (a loopback IP that would otherwise be blocked).
    "http://127.0.0.1/",
    "http://127.0.0.1:8099/",      # own host + own port -> the last-resort port bypass.
    "http://127.0.0.1:81/",        # own host, but a foreign port -> still refused.

    # ── BR-HTTP-07 (251): resolution failure (host unchanged) = reject ────────────
    "http://nonexistent.invalid/",
    "http://sub.nonexistent.invalid/",
    "http://999.999.999.999/",     # not a dotted quad -> resolver -> fails -> reject.
    "http://08.8.8.8/",            # leading-zero octet is not the regex's quad -> resolve -> fail.

    # ── BR-HTTP-08 (252): the 13 blocked IPv4 ranges, each boundary probed ────────
    "http://127.1.2.3/",           # 127/8 loopback (not the own host, so genuinely blocked)
    "http://10.0.0.5/",            # 10/8 private
    "http://0.0.0.0/",             # 0/8 this-network
    "http://172.16.0.1/",          # 172.16/12 lower edge
    "http://172.31.255.254/",      # 172.16/12 upper edge
    "http://172.15.0.1/",          # just below -> allowed
    "http://172.32.0.1/",          # just above -> allowed
    "http://192.168.1.1/",         # 192.168/16 private
    "http://192.0.0.1/",           # 192.0.0/24 IETF
    "http://192.0.2.5/",           # 192.0.2/24 TEST-NET-1
    "http://192.0.3.5/",           # adjacent /24 -> allowed
    "http://192.88.99.1/",         # 6to4 relay anycast
    "http://198.51.100.7/",        # TEST-NET-2
    "http://203.0.113.9/",         # TEST-NET-3
    "http://169.254.169.254/",     # link-local AND cloud metadata -- the SSRF trophy.
    "http://169.254.0.1/",         # 169.254/16 lower edge
    "http://100.64.0.1/",          # 100.64/10 CGNAT lower edge
    "http://100.127.255.254/",     # CGNAT upper edge
    "http://100.63.0.1/",          # just below CGNAT -> allowed
    "http://100.128.0.1/",         # just above CGNAT -> allowed
    "http://198.18.0.1/",          # 198.18/15 benchmarking
    "http://198.19.255.254/",      # benchmarking upper edge
    "http://198.20.0.1/",          # just above -> allowed
    "http://224.0.0.1/",           # 224/4 multicast lower edge
    "http://239.1.2.3/",           # multicast upper edge
    "http://240.0.0.1/",           # 240/4 reserved
    "http://255.255.255.255/",     # broadcast
    "http://1.2.3.4/",             # an ordinary public address -> allowed

    # ── BR-HTTP-10/11 (254/255): ports. Explicit -> 80/443/8080 only; none -> pass ─
    "http://8.8.8.8:80/",
    "http://8.8.8.8:443/",
    "http://8.8.8.8:8080/",
    "http://8.8.8.8:8443/",        # not in the safe set -> reject.
    "http://8.8.8.8:81/",
    "http://8.8.8.8:0/",           # empty($port) is TRUE for 0 -> treated as no port -> pass.
    "http://8.8.8.8:00/",          # parse_url gives 0 -> same as above.
    "http://8.8.8.8:/",            # empty authority port -> no port -> pass.
    "http://8.8.8.8/",             # no port at all -> pass.
    "https://8.8.8.8:443/path?q=1#frag",

    # ── parse_url leniency vs URI.parse strictness ───────────────────────────────
    "http://8.8.8.8/pa th",        # a space in the PATH -- host is still 8.8.8.8.
    "http://8.8.8.8/%00",          # an encoded byte in the path -- untouched.
    "http://.8.8.8.8./",           # leading/trailing dots trimmed off the host.
    "http://8.8.8.8",              # no path.

    # ── the pre-checks: type, empty, is_numeric ──────────────────────────────────
    "1234",                        # is_numeric() -> reject.
    "3.14",                        # is_numeric() (float) -> reject.
    "0x1A",                        # NOT is_numeric() in PHP -> falls through -> host checks.
    ""                             # empty -> reject.
  ].freeze

  it "reaches wp_http_validate_url()'s exact verdict for every URL in the corpus" do
    oracle = HttpValidateOracle.run(CORPUS)
    home = oracle[:home]

    divergences = CORPUS.each_with_index.filter_map do |url, i|
      expected = oracle[:verdicts][i]
      actual = described_class.validate(url, resolver: IDENTITY_RESOLVER, home_url: home)
      next if expected == actual

      "#{url.inspect}\n    oracle:  #{expected.nil? ? 'REJECT' : "ACCEPT #{expected.inspect}"}" \
        "\n    rebuild: #{actual.nil? ? 'REJECT' : "ACCEPT #{actual.inspect}"}"
    end

    expect(divergences).to be_empty,
      "Egress::UrlPolicy diverges from wp_http_validate_url():\n\n#{divergences.join("\n\n")}"
  end

  # A guard on the guard: the corpus is only worth running if it actually reaches BOTH
  # verdicts and both branches of the interesting rules. If a future edit makes every
  # row accept (or every row reject), the differential above would still pass vacuously.
  it "exercises both verdicts and the SSRF-critical rejections" do
    oracle = HttpValidateOracle.run(CORPUS)
    verdicts = oracle[:verdicts]

    expect(verdicts.count(&:nil?)).to be > 5           # real rejections present
    expect(verdicts.count { |v| !v.nil? }).to be > 5    # real acceptances present

    # The cloud-metadata address MUST be among the rejections -- that is the whole point.
    metadata_index = CORPUS.index("http://169.254.169.254/")
    expect(verdicts[metadata_index]).to be_nil
    expect(described_class.permitted?("http://169.254.169.254/", resolver: IDENTITY_RESOLVER,
                                                                  home_url: oracle[:home])).to be(false)
  end
end
