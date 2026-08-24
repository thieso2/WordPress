# frozen_string_literal: true

require "rails_helper"

# console.theme-install's remote directory listing. The transport is stubbed — the parity
# suite and these specs NEVER make a real external call (spec/parity/features/11) — and the
# assertions are that SSRF validation is default-on (BR-HTTP-01) and that the listing maps
# to the screen's fields.
RSpec.describe Egress::ThemeDirectory do
  # A dotted-quad public IP so no DNS is involved: UrlPolicy checks the literal against its
  # 13 blocked ranges directly. 93.184.216.34 is public and passes.
  PUBLIC = "http://93.184.216.34/themes.json"

  def transport_returning(status:, body:, headers: {})
    resp_status, resp_body, resp_headers = status, body, headers
    lambda do |method:, url:, headers: {}, body: nil|
      Egress::Client::Response.new(status: resp_status, url: url, body: resp_body, headers: resp_headers)
    end
  end

  def client(transport)
    Egress::Client.new(transport: transport)
  end

  it "lists themes from the directory JSON" do
    body = { "themes" => [
      { "name" => "Twenty Twenty-Four", "slug" => "twentytwentyfour", "version" => "1.3",
        "download_link" => "http://93.184.216.34/t24.zip", "screenshot_url" => "http://x/s.png" }
    ] }.to_json
    entries = described_class.new(client: client(transport_returning(status: 200, body: body))).list(PUBLIC)

    expect(entries.length).to eq(1)
    expect(entries.first.name).to eq("Twenty Twenty-Four")
    expect(entries.first.install_url).to eq("http://93.184.216.34/t24.zip")
  end

  it "refuses an SSRF target BEFORE any transport call (default-on, BR-HTTP-01)" do
    called = false
    transport = ->(**) { called = true; Egress::Client::Response.new(status: 200, url: "x", body: "{}", headers: {}) }
    # 127.0.0.1 is the loopback range — blocked. The refusal carries the legacy message.
    expect {
      described_class.new(client: client(transport)).list("http://127.0.0.1/themes.json")
    }.to raise_error(Egress::UrlPolicy::Refused, "A valid URL was not provided.")
    expect(called).to be(false)
  end

  it "raises Unavailable on a non-2xx directory" do
    expect {
      described_class.new(client: client(transport_returning(status: 500, body: ""))).list(PUBLIC)
    }.to raise_error(Egress::ThemeDirectory::Unavailable)
  end
end
