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

  it "renders the FULL alt-text help sentence, verbatim (media.php:3261, DEV-009)" do
    login_as("con_editor")
    get "/console/media/#{asset.id}/edit"
    expect(body_text).to include(
      "Learn how to describe the purpose of the image. Leave empty if the image is purely decorative."
    )
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

# console.media-new — wp-admin/media-new.php. The upload screen the Media Library's
# "Add Media File" action links to. GET renders "Upload Media" + media_upload_form(); the
# no-JS Browser Uploader POST stores the file and lands on the Media Library.
#
# ⚠️ The route GET/POST /console/media/new and its AD-04 declaration are applied by the
# integrator (returned in routes_to_add / declarations_to_add); until then these examples
# raise a routing/Undeclared error in isolation.
RSpec.describe "console.media-new (Upload Media)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/media/new"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL 'Upload Media' title and the upload form" do
    login_as("con_editor")
    get "/console/media/new"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Upload Media")
    expect(doc.at_css("input#async-upload[type=file]")).not_to be_nil
    expect(body_text).to include("Drop files to upload")
    # "Select Files" is the browse button's VALUE attribute (includes/media.php:2277), so
    # it lives in the markup, not in the document text.
    expect(doc.at_css("input#plupload-browse-button")[:value]).to eq("Select Files")
  end

  it "denies an actor without upload_files with the verbatim wp_die message (403)" do
    login_as("con_subscriber")
    get "/console/media/new"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to upload files.")
  end

  it "stores an uploaded file and redirects to the Media Library (Browser Uploader path)" do
    require_relative "../../models/library/support/fixtures"
    Library::SpecFixtures.seed_media_settings!
    fixtures = Library::SpecFixtures.build
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)

    login_as("con_author")
    file = Rack::Test::UploadedFile.new(fixtures["small.png"], "image/png", true, original_filename: "small.png")
    expect {
      post "/console/media/new", params: { "async-upload" => file }
    }.to change(Library::Asset, :count).by(1)
    expect(response).to have_http_status(:see_other)
    expect(response.headers["Location"]).to end_with("/console/media")
    expect(Library::Asset.last.uploader).to eq(actor("con_author"))
  end
end
