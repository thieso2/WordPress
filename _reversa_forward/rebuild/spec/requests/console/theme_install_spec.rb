# frozen_string_literal: true

require "rails_helper"
require_relative "console_spec_helper"

# console.theme-install — theme-install.php. The install/download path is exercised at the
# service level (spec/services/egress/theme_installer_spec.rb) with a stubbed transport; no
# request-level spec makes a real external call. Here we assert the screen chrome, the AD-04
# gate, and that SSRF validation is DEFAULT-ON — a loopback directory URL is refused
# synchronously, before any socket, so it needs no network to observe.
RSpec.describe "console.theme-install", type: :request do
  before { seed_console_accounts! }

  it "redirects an unauthenticated request to /login" do
    get "/console/themes/new"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login")
  end

  it "forbids an actor without install_themes (subscriber)" do
    login_as("con_subscriber")
    get "/console/themes/new"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the idle state with the LITERAL title" do
    login_as("con_admin")
    get "/console/themes/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Themes")
  end

  it "refuses an SSRF directory URL default-on (A valid URL was not provided.)" do
    login_as("con_admin")
    get "/console/themes/new", params: { directory: "http://127.0.0.1/themes.json" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A valid URL was not provided.")
  end
end
