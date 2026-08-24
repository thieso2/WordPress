# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit-tags — the terms list (edit-tags.php, WP_Terms_List_Table). P-LIST over
# Classification::Term, EXACT pagination. LITERAL columns "Name / Description / Slug /
# Count". ⚠️ Count is PUBLISHED CONTENT ONLY (BR-MIGRATE-061).
RSpec.describe "console.edit-tags (Terms list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/terms/category"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "forbids an actor without manage_categories (subscriber)" do
    create_term!(name: "Jazz", slug: "jazz")
    login_as("con_subscriber")
    get "/console/terms/category"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL column headers and the terms as rows" do
    create_term!(name: "Jazz", slug: "jazz")
    create_term!(name: "Blues", slug: "blues")
    login_as("con_editor")
    get "/console/terms/category"
    expect(response).to have_http_status(:ok)
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Name", "Description", "Slug", "Count")
    expect(body_text).to include("Jazz").and include("Blues")
  end

  it "404s an unknown taxonomy" do
    login_as("con_editor")
    get "/console/terms/nope"
    expect(response).to have_http_status(:not_found)
  end
end
