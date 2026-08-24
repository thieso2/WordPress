# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit (pages variant) — the Pages list (edit.php?post_type=page). P-LIST over
# Publishing::Page, EXACT pagination. LITERAL "Pages" / "Add Page" / "No pages found." and
# NO category/tag columns (the page type registers no taxonomies).
RSpec.describe "console.edit (Pages list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def page!(title) = Publishing::Page.create!(author: actor("con_editor"), title: title, status: :published, published_at: Time.current)

  it "redirects an unauthenticated request to /login" do
    get "/console/pages"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL 'Pages' title and omits the taxonomy columns" do
    page!("About us")
    login_as("con_editor")
    get "/console/pages"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Pages")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Title", "Author", "Date")
    expect(headers).not_to include("Categories")
    expect(headers).not_to include("Tags")
    expect(body_text).to include("About us")
  end

  it "shows the LITERAL 'No pages found.' empty-state" do
    login_as("con_editor")
    get "/console/pages"
    expect(body_text).to include("No pages found.")
  end
end
