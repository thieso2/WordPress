# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-277: the AI client's HTTP goes through the validated egress door (the rebuild's
# stand-in for wp_safe_remote_request). The transport is always stubbed — no real provider is
# ever contacted — and the point being proven is that a blocked target is refused BEFORE any
# transport call, with no per-call opt-out.
RSpec.describe Assistance::AiClient do
  PUBLIC = "http://93.184.216.34/v1/messages"

  def transport_capturing(bucket)
    lambda do |method:, url:, headers: {}, body: nil|
      bucket << { method: method, url: url, headers: headers, body: body }
      Egress::Client::Response.new(status: 200, url: url, body: %({"ok":true}), headers: {})
    end
  end

  it "sends provider requests through Egress::Client" do
    calls = []
    client = described_class.new(egress: Egress::Client.new(transport: transport_capturing(calls)))
    response = client.post_json(PUBLIC, { model: "x", prompt: "hi" })

    expect(response.success?).to be(true)
    expect(calls.length).to eq(1)
    expect(calls.first[:method]).to eq(:post)
    expect(JSON.parse(calls.first[:body])).to eq("model" => "x", "prompt" => "hi")
    expect(calls.first[:headers]["content-type"]).to eq("application/json")
  end

  it "refuses an SSRF provider URL BEFORE any transport call (default-on, no opt-out)" do
    called = false
    transport = ->(**) { called = true; Egress::Client::Response.new(status: 200, url: "x", body: "{}", headers: {}) }
    client = described_class.new(egress: Egress::Client.new(transport: transport))
    expect {
      client.post_json("http://127.0.0.1/v1/messages", { model: "x" })
    }.to raise_error(Egress::UrlPolicy::Refused)
    expect(called).to be(false)
  end
end
