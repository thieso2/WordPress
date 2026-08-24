# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"
require "zlib"
require "stringio"
require "base64"

# console.theme-install's install action. AD-02: an install writes ROWS, not files — a
# Presentation::Theme plus its Composition::Template rows. The package is signature-verified
# BEFORE extraction, unconditionally (the BC-14 inversion of the legacy soft-fail default);
# an unverified package installs NOTHING. The transport is stubbed; no real egress.
RSpec.describe Egress::ThemeInstaller do
  # A minimal but real .tar.gz of a theme directory.
  def tarball(files)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        files.each do |name, bytes|
          tar.add_file_simple(name, 0o644, bytes.bytesize) { |f| f.write(bytes) }
        end
      end
    end
    io.string
  end

  let(:theme_files) do
    {
      "greenfield/style.css" => "/*\nTheme Name: Greenfield\nVersion: 2.0\n*/\n",
      "greenfield/theme.json" => { "version" => 3, "settings" => {} }.to_json,
      "greenfield/templates/index.html" => "<!-- wp:paragraph --><p>hi</p><!-- /wp:paragraph -->",
      "greenfield/parts/header.html" => "<!-- wp:site-title /-->"
    }
  end
  let(:content) { tarball(theme_files) }

  # An Ed25519 keypair; the trusted set is the public key, base64'd, exactly as
  # wp_trusted_keys() stores it.
  let(:signing_key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key_b64) { Base64.strict_encode64(signing_key.raw_public_key) }
  # The signature is over the SHA-384 DIGEST of the content (file.php:1483), detached.
  let(:signature_b64) do
    digest = OpenSSL::Digest.digest("SHA384", content)
    Base64.strict_encode64(signing_key.sign(nil, digest))
  end

  let(:package_url) { "http://93.184.216.34/greenfield.tar.gz" }

  # A transport that answers the package GET with the tarball and the signature header.
  def transport(signature:)
    body_bytes = content
    lambda do |method:, url:, headers: {}, body: nil|
      # The .sig sibling 404s (the signature travels in the header here); returning the
      # tarball for it would feed binary to signatures_alongside's split.
      next Egress::Client::Response.new(status: 404, url: url, body: "", headers: {}) if url.end_with?(".sig")

      hdrs = signature ? { "x-content-signature" => signature } : {}
      Egress::Client::Response.new(status: 200, url: url, body: body_bytes, headers: hdrs)
    end
  end

  def client(signature:)
    Egress::Client.new(transport: transport(signature: signature))
  end

  before { Configuration::Setting.set("trusted_signing_keys", [public_key_b64]) }

  it "installs a verified package as an inactive theme with its templates (rows, not files)" do
    installer = described_class.new(client: client(signature: signature_b64),
                                    trusted_keys: Egress::TrustedKeys.default)
    theme = installer.install(package_url)

    expect(theme).to be_persisted
    expect(theme.slug).to eq("greenfield")
    expect(theme.name).to eq("Greenfield")
    expect(theme.version).to eq("2.0")
    expect(theme.active?).to be(false)   # install ≠ activate (themes.php separates them)

    templates = Composition::Template.where(theme_slug: "greenfield")
    expect(templates.where(kind: "template").pluck(:slug)).to include("index")
    expect(templates.where(kind: "part").pluck(:slug)).to include("header")
  end

  it "rejects an UNSIGNED package and writes nothing (verification is unconditional)" do
    installer = described_class.new(client: client(signature: nil),
                                    trusted_keys: Egress::TrustedKeys.default)
    expect { installer.install(package_url) }.to raise_error(Egress::Package::Rejected)
    expect(Presentation::Theme.where(slug: "greenfield")).not_to exist
    expect(Composition::Template.where(theme_slug: "greenfield")).not_to exist
  end

  it "rejects a package signed by an untrusted key" do
    other = OpenSSL::PKey.generate_key("ED25519")
    bad_sig = Base64.strict_encode64(other.sign(nil, OpenSSL::Digest.digest("SHA384", content)))
    installer = described_class.new(client: client(signature: bad_sig),
                                    trusted_keys: Egress::TrustedKeys.default)
    expect { installer.install(package_url) }.to raise_error(Egress::Package::Rejected)
    expect(Presentation::Theme.where(slug: "greenfield")).not_to exist
  end

  it "refuses an SSRF package URL before any download (default-on)" do
    installer = described_class.new(client: client(signature: signature_b64))
    expect { installer.install("http://10.0.0.5/x.tar.gz") }
      .to raise_error(Egress::UrlPolicy::Refused, "A valid URL was not provided.")
  end
end
