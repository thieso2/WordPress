# frozen_string_literal: true

require_relative "console_spec_helper"

# console.profile — profile.php (IS_PROFILE_PAGE): "Profile", "Update Profile". ⚠️ DEV-008:
# no admin_color; DEV-005: no colour schemes. No role editor (no self-promotion).
RSpec.describe "console.profile", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/profile"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL title and submit label for the current user" do
    login_as("con_author")
    get "/console/profile"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Profile")
    expect(doc.at_css("button[type=submit]").text.strip).to eq("Update Profile")
    expect(doc.at_css("#email")["value"]).to eq("con_author@example.com")
  end

  it "⚠️ DEV-008: no admin_color control on the profile screen" do
    login_as("con_author")
    get "/console/profile"
    expect(response.body).not_to include("admin_color")
  end

  it "saves the current user's own fields" do
    login_as("con_author")
    patch "/console/profile", params: { email: "author2@example.com", display_name: "Auth Or", url: "author.example" }
    expect(response).to have_http_status(:see_other)
    u = actor("con_author")
    expect(u.email).to eq("author2@example.com")
    expect(u.display_name).to eq("Auth Or")
    expect(u.url).to eq("http://author.example")
  end

  it "a password change keeps THIS browser signed in (session re-issued, BR-AUTH-05)" do
    login_as("con_author")
    patch "/console/profile", params: { pass1: "brand-new-pw-1", pass2: "brand-new-pw-1" }
    expect(response).to have_http_status(:see_other)
    # the acting browser survives its own password change
    get "/console/profile"
    expect(response).to have_http_status(:ok)
    expect(actor("con_author").authenticate_and_upgrade("brand-new-pw-1")).to be_truthy
  end
end
