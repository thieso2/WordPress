# frozen_string_literal: true

require_relative "console_spec_helper"

# console.upload — the Media Library list (upload.php, WP_Media_List_Table). P-LIST over
# Library::Asset, ESTIMATED pagination (DEV-003). LITERAL title "Media Library", columns
# "File / Author / Uploaded to / Date", "No media files found."
RSpec.describe "console.upload (Media list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/media"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL 'Media Library' title, column headers and the asset rows" do
    create_asset!(slug: "beach", title: "Beach photo")
    login_as("con_editor")
    get "/console/media"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Media Library")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("File", "Author", "Uploaded to", "Date")
    expect(body_text).to include("Beach photo")
  end

  it "shows the LITERAL 'No media files found.' empty-state" do
    login_as("con_editor")
    get "/console/media"
    expect(body_text).to include("No media files found.")
  end
end
