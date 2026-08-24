# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# BR-MIGRATE-356 (BR-SH-05): the site-health async tests, exposed over REST. Only the
# loopback test has an analogue here (BR-MIGRATE-355 → the job queue). The endpoint returns
# get_test_loopback_requests()'s document verbatim and gates on view_site_health_checks,
# which AD-01 expresses directly as install_plugins (RoleCatalogue → administrators). The
# denial envelope is the REST server's (rest_forbidden, 401 anon / 403 authenticated).
RSpec.describe "Site Health REST (/wp-json/wp-site-health/v1)", type: :request do
  include ConsoleSpecHelper

  before do
    host! "127.0.0.1"
    seed_console_accounts!
  end

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  let(:path) { "/wp-json/wp-site-health/v1/tests/loopback-requests" }

  it "denies an anonymous caller with rest_forbidden 401 (rest_authorization_required_code)" do
    get path
    expect(response).to have_http_status(:unauthorized)
    expect(json["code"]).to eq("rest_forbidden")
  end

  it "denies an authenticated caller without install_plugins with 403" do
    get path, headers: bearer(actor("con_subscriber"))
    expect(response).to have_http_status(:forbidden)
    expect(json["code"]).to eq("rest_forbidden")
  end

  it "returns the loopback test document for an administrator (install_plugins)" do
    get path, headers: bearer(actor("con_admin"))
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to eq("application/json; charset=UTF-8")
    body = json
    expect(body["test"]).to eq("loopback_requests")
    expect(body["badge"]).to eq("label" => "Performance", "color" => "blue")
    expect(%w[good recommended critical]).to include(body["status"])
    expect(body["description"]).to start_with("<p>").and(end_with("</p>"))
    expect(body["label"]).to be_in(["Your site can perform loopback requests",
                                    "Your site could not complete a loopback request"])
  end

  # The namespace is deliberately NOT advertised in the REST index (one served route is not
  # the legacy's full wp-site-health/v1 surface) — the index still lists only oembed + wp/v2.
  it "does not advertise wp-site-health/v1 in the discovery index" do
    get "/wp-json/"
    expect(json["namespaces"]).to eq(%w[oembed/1.0 wp/v2])
  end
end
