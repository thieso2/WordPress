# frozen_string_literal: true

# PT-011 -- Outbound requests. BC-14 Egress, BR-MIGRATE-245..257 (BR-HTTP-01..13),
# plus the four CONTINGENT package rules BR-MIGRATE-338/340/341/346
# (BR-FS-07/09/10, BR-UPD-04) that survive only because DEV-011 kept
# `console.theme-install` (parity_specs.md, ambiguity P-4).
#
# ⚠️ DEVIATION BR-HTTP-01, approved. In the legacy, SSRF validation is opt-in BY FUNCTION
# NAME: wp_safe_remote_get() sets `reject_unsafe_urls`, wp_remote_get() does not
# (F-HTTP-05, class-wp-http.php:284). Here there is one door, it validates, and the
# unsafe path is explicitly named. Every step below therefore asserts the TARGET's rule,
# and cites the legacy line the rule came from.
#
# Inspector contract: these steps observe what an outside caller of the system sees --
# a refusal, a response, an audit entry, a file on disk. Nothing here reaches for a
# callback, a validation name or a column default. The two collaborators that ARE
# inspected -- the transport and the destination -- are supplied BY THE CALLER, so
# "no connection was made" and "nothing was written" are observations about the outside
# world, not about the client's internals.
#
# NO REAL NETWORK CALLS: every scenario supplies its own transport and its own resolver.

require "tmpdir"

module EgressParitySupport
  # Records the order of externally visible events. The clock is frozen by
  # spec/parity/features/support/env.rb, so ordering cannot be read off timestamps.
  class OrderLog
    def initialize = @events = []
    attr_reader :events
    def record(name) = @events << name
    def index(name) = @events.index(name)
  end

  # A transport that never opens a socket and remembers everything it was asked to do.
  # "Refused before any connection is made" is `calls.empty?` on one of these.
  class RecordingTransport
    attr_reader :calls

    def initialize(&responder)
      @calls = []
      @responder = responder || ->(_req) { { status: 200, headers: {}, body: "ok" } }
    end

    def call(method:, url:, headers:, body:)
      @calls << { method: method, url: url, headers: headers, body: body }
      attrs = @responder.call(url)
      Egress::Client::Response.new(url: url, **attrs)
    end
  end

  # Wraps the trusted-key source so the caller can see WHEN verification consulted it.
  class RecordingKeys
    include Enumerable

    def initialize(keys, log)
      @keys = keys
      @log = log
    end

    def each(&block)
      @log.record(:trusted_keys_consulted)
      @keys.each(&block)
    end
  end

  # Wraps the extraction destination so the caller can see WHEN the first byte landed.
  class RecordingDestination
    def initialize(inner, log)
      @inner = inner
      @log = log
    end

    def write(name, bytes)
      @log.record(:file_written)
      @inner.write(name, bytes)
    end
  end

  # Builds a real gzipped tar in memory, so extraction is a real extraction and
  # "no file is extracted" is a real empty directory.
  def self.tarball(entries)
    require "rubygems/package"
    require "zlib"
    raw = StringIO.new(+"".b)
    Gem::Package::TarWriter.new(raw) do |tar|
      entries.each { |name, contents| tar.add_file(name, 0o644) { |io| io.write(contents) } }
    end
    gz = StringIO.new(+"".b)
    Zlib::GzipWriter.wrap(gz) { |w| w.write(raw.string) }
    gz.string
  end

  # An Ed25519 keypair and a DETACHED signature over the package's SHA-384 digest --
  # exactly what sodium_crypto_sign_verify_detached($sig, hash_file('sha384', $f, true), $key)
  # expects (wp-admin/includes/file.php:1483, 1508).
  def self.sign(content)
    key = OpenSSL::PKey.generate_key("ED25519")
    digest = OpenSSL::Digest.digest(Egress::SignatureVerifier::HASH_ALGORITHM, content)
    [Base64.strict_encode64(key.raw_public_key), Base64.strict_encode64(key.sign(nil, digest))]
  end
end

World(Module.new do
  def egress_log = @egress_log ||= EgressParitySupport::OrderLog.new

  # A stub for gethostbyname() (BR-MIGRATE-251). Hosts not listed resolve to themselves,
  # which is the legacy's failure signal, so an unlisted host is refused rather than
  # silently looked up on a real network.
  def egress_resolver
    @egress_resolver ||= lambda do |host|
      { "internal.parity.test" => "192.168.1.10",
        "metadata.parity.test" => "169.254.169.254",
        "public.parity.test" => "198.143.164.252" }.fetch(host, host)
    end
  end

  def egress_client(transport)
    Egress::Client.new(transport: transport, resolver: egress_resolver,
                       home_url: "https://rebuild.parity.test")
  end

  def capture_refusal
    yield
    nil
  rescue Egress::UrlPolicy::Refused => e
    e
  end
end)

# ── The default door ──────────────────────────────────────────────────────────

Given("a URL resolving to a private network address") do
  # A HOSTNAME, not a literal: the interesting SSRF case is the one where the address is
  # only known after resolution (BR-MIGRATE-252, 192.168.0.0/16).
  @url = "http://internal.parity.test/admin"
  expect(egress_resolver.call("internal.parity.test")).to eq("192.168.1.10")
end

Given("a URL using the {string} scheme") do |scheme|
  # BR-MIGRATE-246 (BR-HTTP-02): only http and https are accepted.
  @url = { "file" => "file:///etc/passwd",
           "ftp" => "ftp://public.parity.test/pub/x",
           "gopher" => "gopher://public.parity.test/1/x" }.fetch(scheme)
end

Given("a permitted URL that redirects to a private network address") do
  @url = "http://public.parity.test/start"
  @redirect_target = "http://internal.parity.test/secrets"
  @transport = EgressParitySupport::RecordingTransport.new do |url|
    if url == @url
      { status: 302, headers: { "Location" => @redirect_target }, body: "" }
    else
      { status: 200, headers: {}, body: "should never be fetched" }
    end
  end
end

When("the default outbound client requests it") do
  @transport ||= EgressParitySupport::RecordingTransport.new
  @refusal = capture_refusal { @response = egress_client(@transport).get(@url) }
end

When("the default outbound client follows the redirect") do
  @refusal = capture_refusal { @response = egress_client(@transport).get(@url) }
end

When("the explicitly-unsafe client requests it") do
  Egress::UnsafeClient.clear_audit_log!
  @transport = EgressParitySupport::RecordingTransport.new
  @response = Egress::UnsafeClient.new(transport: @transport,
                                       reason: "parity: deliberate loopback probe").get(@url)
end

Then("the request is refused") do
  expect(@refusal).to be_a(Egress::UrlPolicy::Refused)
  expect(@response).to be_nil
end

Then("the request is refused before any connection is made") do
  expect(@refusal).to be_a(Egress::UrlPolicy::Refused)
  # The transport is the caller's own object. It was never asked to do anything, so the
  # refusal cannot have happened after a connection: there was no connection.
  expect(@transport.calls).to be_empty
end

Then("the redirect target is refused") do
  expect(@refusal).to be_a(Egress::UrlPolicy::Refused)
  expect(@refusal.url).to eq(@redirect_target)
  # The first hop was permitted and fetched; the second was refused. Exactly one
  # connection was made, which is what "re-validated at each hop" means from outside.
  expect(@transport.calls.map { |c| c[:url] }).to eq([@url])
end

Then("the request proceeds") do
  expect(@response.status).to eq(200)
  expect(@transport.calls.map { |c| c[:url] }).to eq([@url])
end

Then("the use of the unsafe path is recorded") do
  entry = Egress::UnsafeClient.audit_log.last
  expect(entry).to be_present
  expect(entry.url).to eq(@url)
  expect(entry.method).to eq(:get)
  expect(entry.reason).to eq("parity: deliberate loopback probe")
  expect(entry.call_site).to include("egress_steps.rb")
end

# ── Exactly one validating door ───────────────────────────────────────────────
#
# A structural assertion, in the same spirit as authorization_steps.rb shelling out to
# bin/check_cycles: BC-14's whole reason to exist is that the unsafe path cannot be
# reached without writing its name, and that is a property of the SOURCE, not of a
# single request.

OUTBOUND_PRIMITIVES = {
  "Net::HTTP" => /(?<![A-Za-z_:])Net::HTTP/,
  "open-uri" => /(?<![A-Za-z_:])(URI\.open|OpenURI|open-uri)/,
  "raw sockets" => /(?<![A-Za-z_:])(TCPSocket|Socket\.tcp|OpenSSL::SSL::SSLSocket)/,
  "an HTTP gem" => /(?<![A-Za-z_:])(Faraday|HTTParty|RestClient|Excon|Typhoeus|HTTPX|Curl::)/
}.freeze

def egress_offenders(files)
  files.filter_map do |file|
    source = File.read(file)
    hits = OUTBOUND_PRIMITIVES.select { |_label, pattern| source.match?(pattern) }.keys
    next if hits.empty?
    # Naming Egress::UnsafeClient is the deliberate act. Anything else is a second door.
    next if source.match?(/Egress::UnsafeClient/)

    "#{file} reaches the network directly (#{hits.join(", ")}) without naming Egress::UnsafeClient"
  end
end

Given("the application's outbound request surface") do
  root = Rails.root
  # Everything that could open a socket, except BC-14 itself -- which is the door.
  @surface = (Dir[root.join("app/**/*.rb")] + Dir[root.join("lib/**/*.rb")] +
              Dir[root.join("packs/*/app/**/*.rb")])
             .reject { |f| f.start_with?(root.join("app/services/egress").to_s) }
             .sort
  expect(@surface).not_to be_empty

  # The scan is only worth anything if it can fail. Prove it can, on a planted call site,
  # before applying it to the real tree.
  Dir.mktmpdir do |dir|
    planted = File.join(dir, "violation.rb")
    File.write(planted, "def fetch(url) = Net::HTTP.get(URI(url))\n")
    expect(egress_offenders([planted])).not_to be_empty
    File.write(planted, "def fetch(url) = Egress::UnsafeClient.new.get(url)\n")
    expect(egress_offenders([planted])).to be_empty
  end
end

Then("every outbound path routes through the egress client") do
  expect(egress_offenders(@surface)).to be_empty
end

Then("no code path issues an unvalidated request without naming the unsafe client") do
  # Same scan, stated the other way round: the ONLY files permitted to hold an
  # unvalidated call site are the ones that say Egress::UnsafeClient out loud.
  unnamed = egress_offenders(@surface)
  expect(unnamed).to be_empty, "unvalidated egress:\n  #{unnamed.join("\n  ")}"

  # ...and "naming the unsafe client" is not a no-op label on an identical code path.
  # The exact URL the named client will fetch is refused by the default one, without a
  # connection. Both facts are read off the CALLER's own transport.
  probe = EgressParitySupport::RecordingTransport.new
  blocked = "http://internal.parity.test/admin"
  expect { egress_client(probe).get(blocked) }.to raise_error(Egress::UrlPolicy::Refused)
  expect(probe.calls).to be_empty
  named = Egress::UnsafeClient.new(transport: probe, reason: "parity: scan control")
  expect(named.get(blocked).status).to eq(200)
  expect(probe.calls.map { |c| c[:url] }).to eq([blocked])
end

# ── The downloaded package (CONTINGENT on DEV-011) ────────────────────────────

Given("a theme package downloaded from a remote directory") do
  @package_body = EgressParitySupport.tarball("twentyparity/style.css" => "/* theme */\n")
  public_key, signature = EgressParitySupport.sign(@package_body)
  @trusted_keys = EgressParitySupport::RecordingKeys.new([public_key], egress_log)
  @package_url = "https://public.parity.test/theme/twentyparity.1.0.zip"
  @transport = EgressParitySupport::RecordingTransport.new do |_url|
    { status: 200, headers: { "X-Content-Signature" => signature }, body: @package_body }
  end
  @package = Egress::Package.download(@package_url, client: egress_client(@transport),
                                                    trusted_keys: @trusted_keys)
end

Given("a downloaded package whose signature does not verify") do
  @package_body = EgressParitySupport.tarball("twentyparity/style.css" => "/* theme */\n")
  # A well-formed 64-byte Ed25519 signature over DIFFERENT content: the right length,
  # the right shape, the wrong package. This is a verification failure (BR-FS-10), not
  # the malformed-signature skip of BR-FS-09.
  public_key, = EgressParitySupport.sign(@package_body)
  _, other_signature = EgressParitySupport.sign("a different package")
  @trusted_keys = EgressParitySupport::RecordingKeys.new([public_key], egress_log)
  @package_url = "https://public.parity.test/theme/twentyparity.1.0.zip"
  @transport = EgressParitySupport::RecordingTransport.new do |_url|
    { status: 200, headers: { "X-Content-Signature" => other_signature }, body: @package_body }
  end
  @package = Egress::Package.download(@package_url, client: egress_client(@transport),
                                                    trusted_keys: @trusted_keys)
end

Given("a package carrying a signature of incorrect length") do
  @package_body = EgressParitySupport.tarball("twentyparity/style.css" => "/* theme */\n")
  public_key, = EgressParitySupport.sign(@package_body)
  @trusted_keys = [public_key]
  # base64 of 3 bytes. SODIUM_CRYPTO_SIGN_BYTES is 64 (confirmed against the oracle).
  @malformed_signature = Base64.strict_encode64("foo")
  @package = Egress::Package.new(url: "https://public.parity.test/theme/twentyparity.1.0.zip",
                                 content: @package_body, signatures: [@malformed_signature],
                                 trusted_keys: @trusted_keys)
end

When("the package is processed") do
  @extract_root = Dir.mktmpdir("parity-egress")
  destination = EgressParitySupport::RecordingDestination.new(
    Egress::Package::DirectoryDestination.new(@extract_root), egress_log
  )
  @install_error = begin
    @installed = @package.install!(into: destination)
    nil
  rescue Egress::Package::Rejected => e
    e
  end
end

When("verification runs") do
  @verification = @package.verification
end

Then("its signature is verified against the trusted keys") do
  expect(@install_error).to be_nil
  expect(@package).to be_verified
  expect(egress_log.index(:trusted_keys_consulted)).to be_present

  # "against the TRUSTED KEYS" -- proven by swapping them. The same bytes and the same
  # signature, checked against a different trusted set, are refused.
  other_key, = EgressParitySupport.sign("some other package")
  stranger = Egress::Package.new(url: @package_url, content: @package.content,
                                 signatures: @package.signatures, trusted_keys: [other_key])
  expect { stranger.install!(into: Egress::Package::DirectoryDestination.new(Dir.mktmpdir)) }
    .to raise_error(Egress::Package::Rejected)
end

Then("verification happens before any file is extracted") do
  # Both events are recorded by objects the CALLER supplied -- the key source and the
  # destination -- so this is an ordering observed from outside, not an assertion about
  # how Egress::Package is written. BR-MIGRATE-346 (BR-UPD-04).
  expect(egress_log.index(:trusted_keys_consulted)).to be < egress_log.index(:file_written)
  expect(Dir.glob(File.join(@extract_root, "**/*")).select { |f| File.file?(f) }).not_to be_empty
end

Then("no file is extracted") do
  expect(egress_log.index(:file_written)).to be_nil
  expect(Dir.glob(File.join(@extract_root, "**/*"))).to be_empty
end

Then("the failure is reported") do
  # Rule 4, no copy editing: the code and the message are the legacy's, verbatim
  # (verify_file_signature(), wp-admin/includes/file.php:1516, confirmed against the
  # running oracle).
  expect(@install_error).to be_a(Egress::Package::Rejected)
  expect(@install_error.error_code).to eq("signature_verification_failed")
  expect(@install_error.message).to eq(
    'The authenticity of <span class="code">twentyparity.1.0.zip</span> could not be verified.'
  )
end

Then("that signature is skipped and counted") do
  # BR-MIGRATE-340 (BR-FS-09): skipped, and COUNTED -- the legacy surfaces the tally as
  # `skipped_sig` in the error data, so the count is observable output, not a private
  # tally. Skipped means never offered to a key: the key source is untouched.
  expect(@verification.skipped_signatures).to eq(1)
  expect(@verification.skipped_keys).to eq(0)
end

Then("the package is not treated as verified") do
  expect(@verification).not_to be_verified
  expect(@verification.error_code).to eq("signature_verification_failed")
  expect(@package).not_to be_verified
end

# The scenarios above extract into real temporary directories, because "no file is
# extracted" is only worth asserting against a real filesystem. Clean them up.
After do
  FileUtils.remove_entry(@extract_root) if @extract_root && File.directory?(@extract_root)
end
