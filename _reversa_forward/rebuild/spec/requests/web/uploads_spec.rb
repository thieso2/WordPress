# frozen_string_literal: true

require "rails_helper"
require_relative "../../models/library/support/fixtures"

# POST /console/media — wp_ajax_upload_attachment() (wp-admin/includes/ajax-actions.php:2596)
# behind an API-shaped door. The envelope and every message are the legacy's.
RSpec.describe "POST /console/media", type: :request do
  before(:all) { @fixtures = Library::SpecFixtures.build }
  before do
    Library::SpecFixtures.seed_media_settings!
    FileUtils.rm_rf(ActiveStorage::Blob.service.root)
  end

  def user(role, login: "uploader")
    u = Identity::User.create!(login: login, email: "#{login}@example.com", nicename: login,
                               display_name: login, password: "pw-#{login}")
    u.assign_role(role)
    u
  end

  def upload(name, headers: {}, **params)
    file = Rack::Test::UploadedFile.new(@fixtures[name], "application/octet-stream", true, original_filename: name)
    post "/console/media", params: { file: file }.merge(params), headers: headers
    response.parsed_body
  end

  def bearer(u) = { "Authorization" => "Bearer #{u.start_session!}" }

  it "is declared :authenticated — no actor, no upload (AD-04)" do
    upload("small.png")
    expect(response).to have_http_status(:forbidden)
    expect(Library::Asset.count).to eq(0)
  end

  it "stores the asset for an author (upload_files) and answers with the attachment" do
    author = user("author")
    body = upload("oracle-image.png", headers: bearer(author), alt_text: "An image", caption: "A caption")
    expect(response).to have_http_status(:ok)
    expect(body["success"]).to be(true)
    data = body["data"]
    expect(data["name"]).to eq("oracle-image")
    expect(data["title"]).to eq("oracle-image")
    expect(data["mime"]).to eq("image/png")
    expect(data["type"]).to eq("image")
    expect(data["subtype"]).to eq("png")
    expect(data["url"]).to end_with("/wp-content/uploads/oracle-image.png").or end_with(".png")
    expect(data["alt"]).to eq("An image")
    expect(data["caption"]).to eq("A caption")
    expect(data["author"]).to eq(author.id.to_s)
    # wp_prepare_attachment_for_js() lists only image_size_names_choose's default
    # (media.php:4750) plus `full` -- verified against the oracle's async-upload.php.
    expect(data["sizes"].keys).to eq(%w[thumbnail medium large full])
    expect(data["sizes"]["thumbnail"]).to include("width" => 150, "height" => 150, "orientation" => "landscape")
    expect(Library::Asset.find(data["id"]).uploader_id).to eq(author.id)
  end

  it "refuses a subscriber with the legacy's message, in the legacy's envelope" do
    body = upload("small.png", headers: bearer(user("subscriber")))
    expect(response).to have_http_status(:ok)
    expect(body).to eq("success" => false,
                       "data" => { "message" => "Sorry, you are not allowed to upload files.", "filename" => "small.png" })
  end

  it "refuses a forbidden type with the legacy's message and escapes the filename" do
    body = upload("evil.php", headers: bearer(user("author")))
    expect(body).to eq("success" => false,
                       "data" => { "message" => "Sorry, you are not allowed to upload this file type.",
                                   "filename" => "evil.php" })
  end

  it "refuses attaching to a post the actor may not edit, and attaches when they may" do
    author = user("author")
    other = user("author", login: "other")
    theirs = Publishing::Article.create!(title: "Theirs", content: "", excerpt: "", slug: "theirs",
                                         status: "published", published_at: Time.utc(2026, 3, 15, 9), author_id: other.id)
    body = upload("small.png", headers: bearer(author), post_id: theirs.id)
    expect(body["data"]["message"]).to eq("Sorry, you are not allowed to attach files to this post.")

    body = upload("small.png", headers: bearer(author), post_id: 999_999)
    expect(body["data"]["message"]).to eq("Sorry, you are not allowed to attach files to this post.")
    # isset( $_REQUEST['post_id'] ) is true for "" and "0" too (ajax-actions.php:2619).
    body = upload("small.png", headers: bearer(author), post_id: "")
    expect(body["data"]["message"]).to eq("Sorry, you are not allowed to attach files to this post.")

    mine = Publishing::Article.create!(title: "Mine", content: "", excerpt: "", slug: "mine",
                                       status: "published", published_at: Time.utc(2026, 3, 15, 9), author_id: author.id)
    body = upload("small.png", headers: bearer(author), post_id: mine.id)
    expect(body["success"]).to be(true)
    asset = Library::Asset.find(body["data"]["id"])
    expect(asset.attached_to_id).to eq(mine.id)
    # media_handle_upload(): the parent's date decides the folder.
    expect(asset.file).to eq("2026/03/small.png")
    expect(body["data"]["uploadedTo"]).to eq(mine.id)

    # A page never backdates the upload (media.php:303): it lands in the current month.
    page = Publishing::Page.create!(title: "A page", content: "", excerpt: "", slug: "a-page",
                                    status: "published", published_at: Time.utc(2026, 3, 15, 9), author_id: author.id)
    body = upload("small.png", headers: bearer(author), post_id: page.id)
    expect(body["success"]).to be(true)
    expect(Library::Asset.find(body["data"]["id"]).file).not_to start_with("2026/03/")
  end

  it "answers a missing file with the upload-test failure" do
    post "/console/media", params: {}, headers: bearer(user("author"))
    expect(response.parsed_body["data"]["message"]).to eq("Specified file failed upload test.")
  end

  it "serves the stored file at its legacy URL" do
    body = upload("oracle-image.png", headers: bearer(user("author")))
    get "/wp-content/uploads/#{body['data']['sizes']['thumbnail']['url'].split('/wp-content/uploads/').last}"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.body.bytesize).to be > 0
    get "/wp-content/uploads/2026/08/nope.png"
    expect(response).to have_http_status(:not_found)
  end
end
