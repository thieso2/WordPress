# frozen_string_literal: true

require_relative "console_spec_helper"

# console.media — the attachment edit fields (media.php: "Title", "Caption",
# "Alternative Text"; edit_item "Edit Media", post.php:100). 🔑 alt text is a COLUMN.
RSpec.describe "console.media", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:asset) { create_asset! }

  it "redirects an unauthenticated request to /login" do
    get "/console/media/#{asset.id}/edit"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL media labels including Alternative Text" do
    login_as("con_editor")
    get "/console/media/#{asset.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Edit Media")
    expect(body_text).to include("Alternative Text").and include("Caption").and include("Title")
    expect(doc.at_css("#attachment_alt")["value"]).to eq("old alt")
  end

  it "saves alt text (a column now), caption and title through the model" do
    login_as("con_editor")
    patch "/console/media/#{asset.id}", params: { title: "New title", alt: "A cat on a mat", caption: "New caption" }
    expect(response).to have_http_status(:see_other)
    asset.reload
    expect(asset.alt_text).to eq("A cat on a mat")
    expect(asset.caption).to eq("New caption")
    expect(asset.title).to eq("New title")
  end

  it "strips tags from alt text (get_attachment_fields_to_save)" do
    login_as("con_editor")
    patch "/console/media/#{asset.id}", params: { alt: "<b>bold</b> alt" }
    expect(asset.reload.alt_text).to eq("bold alt")
  end

  it "denies an actor without edit_others_posts on an unowned asset (403)" do
    login_as("con_subscriber")
    get "/console/media/#{asset.id}/edit"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to edit this attachment.")
  end
end
