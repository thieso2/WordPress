# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# POST /wp/v2/media — the endpoint Gutenberg's media library uploads through, plus the
# item write actions. Both request shapes the legacy accepts are exercised, because they
# do NOT share an error family: a refused store answers rest_upload_sideload_error through
# the raw body and rest_upload_unknown_error through multipart (verified on the oracle).
#
# The bytes go through Library::Asset.upload! — the same path Web::UploadsController uses.
# Nothing here re-implements storage, naming or sub-size generation.
RSpec.describe "REST API — media writes", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  # A real PNG, built rather than checked in, so the image pipeline has something to
  # probe: 64x64 is below every registered subsize, so no variants are generated.
  def png_bytes(width = 64, height = 64)
    rows = +""
    height.times do |y|
      rows << "\x00".b
      width.times { |x| rows << [(x * 4) % 256, (y * 4) % 256, 128].pack("C3") }
    end
    chunk = lambda do |type, data|
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end
    "\x89PNG\r\n\x1a\n".b +
      chunk.call("IHDR".b, [width, height, 8, 2, 0, 0, 0].pack("NNC5")) +
      chunk.call("IDAT".b, Zlib::Deflate.deflate(rows)) +
      chunk.call("IEND".b, "".b)
  end

  before { seed_console_accounts! }

  let(:disposition) { { "Content-Disposition" => 'attachment; filename="oracle-test.png"', "CONTENT_TYPE" => "image/png" } }

  describe "POST /wp/v2/media — the raw-body shape" do
    it "stores the bytes and answers 201 + Location in edit context" do
      post "/wp-json/wp/v2/media", params: png_bytes,
                                   headers: disposition.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to end_with("/wp-json/wp/v2/media/#{json["id"]}")
      expect(json["type"]).to eq("attachment")
      expect(json["status"]).to eq("inherit")
      expect(json["mime_type"]).to eq("image/png")
      expect(json["media_type"]).to eq("image")
      expect(json["slug"]).to eq("oracle-test")
      expect(json["filename"]).to eq("oracle-test.png")
      expect(json.dig("media_details", "width")).to eq(64)
      expect(json.dig("media_details", "height")).to eq(64)
      expect(json["source_url"]).to end_with("/oracle-test.png")
      # edit context: every rendered field gains its raw sibling.
      expect(json.dig("title", "raw")).to eq("oracle-test")
      expect(json).to have_key("permalink_template")
      expect(json).to have_key("missing_image_sizes")
      # An UNATTACHED asset reports `post: null`, not 0 — the oracle's own answer.
      expect(json["post"]).to be_nil
      asset = Library::Asset.find(json["id"])
      expect(asset.original).to be_attached
      expect(asset.uploader_id).to eq(actor("con_admin").id)
    end

    it "takes the title, alt text and caption from the request" do
      post "/wp-json/wp/v2/media?title=A+Nice+Picture&alt_text=Alt+here&caption=Cap+text",
           params: png_bytes, headers: disposition.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:created)
      expect(json.dig("title", "raw")).to eq("A Nice Picture")
      expect(json["alt_text"]).to eq("Alt here")
      expect(json.dig("caption", "raw")).to eq("Cap text")
      expect(json["slug"]).to eq("a-nice-picture")
    end

    it "attaches to a post the caller may edit and reports wp:attached-to" do
      article = Publishing::Article.create!(author: actor("con_admin"), title: "Host", status: :published,
                                            published_at: Time.current, slug: "host")
      post "/wp-json/wp/v2/media?post=#{article.id}", params: png_bytes,
                                                      headers: disposition.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:created)
      expect(json["post"]).to eq(article.id)
      expect(json.dig("_links", "wp:attached-to", 0, "id")).to eq(article.id)
      expect(json.dig("_links", "curies", 0, "name")).to eq("wp")
    end

    it "is rest_cannot_create (401) for an anonymous caller — the POSTS controller's message" do
      post "/wp-json/wp/v2/media", params: png_bytes, headers: disposition
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_create",
                         "message" => "Sorry, you are not allowed to create posts as this user.",
                         "data" => { "status" => 401 })
    end

    it "is the same refusal at 403 for an identity without upload_files" do
      post "/wp-json/wp/v2/media", params: png_bytes,
                                   headers: disposition.merge(bearer(actor("con_subscriber")))
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("rest_cannot_create")
      expect(json["data"]).to eq("status" => 403)
    end

    it "is rest_cannot_edit when attaching to a post the caller may not edit" do
      article = Publishing::Article.create!(author: actor("con_editor"), title: "Not yours",
                                            status: :published, published_at: Time.current,
                                            slug: "not-yours")
      post "/wp-json/wp/v2/media?post=#{article.id}", params: png_bytes,
                                                      headers: disposition.merge(bearer(actor("con_author")))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_edit",
                         "message" => "Sorry, you are not allowed to upload media to this post.",
                         "data" => { "status" => 403 })
    end

    it "is rest_upload_no_data (400) for an empty body" do
      post "/wp-json/wp/v2/media", params: "", headers: disposition.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_upload_no_data",
                         "message" => "No data supplied.",
                         "data" => { "status" => 400 })
    end

    it "is rest_upload_no_content_disposition (400) when the header is missing" do
      post "/wp-json/wp/v2/media", params: png_bytes,
                                   headers: { "CONTENT_TYPE" => "image/png" }.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_upload_no_content_disposition",
                         "message" => "No Content-Disposition supplied.",
                         "data" => { "status" => 400 })
    end

    it "is rest_upload_invalid_disposition (400) when the header carries no filename" do
      post "/wp-json/wp/v2/media", params: png_bytes,
                                   headers: { "Content-Disposition" => "attachment",
                                              "CONTENT_TYPE" => "image/png" }.merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("rest_upload_invalid_disposition")
      expect(json["message"]).to eq("Invalid Content-Disposition supplied. Content-Disposition needs " \
                                    'to be formatted as `attachment; filename="image.png"` or similar.')
    end

    it "is rest_upload_sideload_error (500) for a forbidden file type on THIS shape" do
      post "/wp-json/wp/v2/media", params: "hello",
                                   headers: { "Content-Disposition" => 'attachment; filename="bad.xyz"',
                                              "CONTENT_TYPE" => "application/octet-stream" }
                                   .merge(bearer(actor("con_admin")))
      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("code" => "rest_upload_sideload_error",
                         "message" => "Sorry, you are not allowed to upload this file type.",
                         "data" => { "status" => 500 })
    end
  end

  describe "POST /wp/v2/media — the multipart shape (what Gutenberg's FormData sends)" do
    def upload_part(name = "big.png", bytes = png_bytes)
      Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", true, original_filename: name)
    end

    it "stores the part and applies the sibling form fields" do
      post "/wp-json/wp/v2/media",
           params: { file: upload_part, title: "Multipart Title", alt_text: "MP alt" },
           headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      expect(json.dig("title", "raw")).to eq("Multipart Title")
      expect(json["alt_text"]).to eq("MP alt")
      expect(json["slug"]).to eq("multipart-title")
      expect(json["filename"]).to eq("big.png")
    end

    it "generates the registered sub-sizes for a large enough image" do
      post "/wp-json/wp/v2/media", params: { file: upload_part("wide.png", png_bytes(1200, 400)) },
                                   headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      sizes = json.dig("media_details", "sizes")
      expect(sizes.keys).to include("thumbnail", "medium", "large", "full")
      expect(sizes.dig("full", "width")).to eq(1200)
      expect(sizes.dig("medium", "source_url")).to include("/wp-content/uploads/")
    end

    # The DIFFERENT code for the same refusal — this is the point of the two methods.
    it "is rest_upload_unknown_error (500) for a forbidden file type on THIS shape" do
      part = Rack::Test::UploadedFile.new(StringIO.new("hello"), "application/octet-stream", true,
                                          original_filename: "bad.xyz")
      post "/wp-json/wp/v2/media", params: { file: part }, headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("code" => "rest_upload_unknown_error",
                         "message" => "Sorry, you are not allowed to upload this file type.",
                         "data" => { "status" => 500 })
    end
  end

  describe "POST|PUT /wp/v2/media/:id" do
    let!(:asset) do
      Library::Asset.upload!(io: StringIO.new(png_bytes), filename: "editable.png",
                             uploader: actor("con_author"))
    end

    it "edits alt text, caption and title" do
      post "/wp-json/wp/v2/media/#{asset.id}",
           params: { alt_text: "Alt here", caption: "Cap text", title: "New Title" },
           headers: bearer(actor("con_author"))
      expect(response).to have_http_status(:ok)
      expect(json["alt_text"]).to eq("Alt here")
      expect(json.dig("caption", "raw")).to eq("Cap text")
      expect(json.dig("title", "raw")).to eq("New Title")
      expect(asset.reload.alt_text).to eq("Alt here")
    end

    it "accepts a {raw: …} object for a rendered/raw field pair, as the legacy does" do
      put "/wp-json/wp/v2/media/#{asset.id}", params: { title: { raw: "Object Title" } },
                                              headers: bearer(actor("con_author"))
      expect(response).to have_http_status(:ok)
      expect(asset.reload.title).to eq("Object Title")
    end

    it "is rest_cannot_edit (403) for someone else's attachment" do
      post "/wp-json/wp/v2/media/#{asset.id}", params: { alt_text: "hax" },
                                               headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_edit",
                         "message" => "Sorry, you are not allowed to edit this post.",
                         "data" => { "status" => 403 })
    end

    it "is rest_post_invalid_id (404) for an id that names nothing" do
      post "/wp-json/wp/v2/media/999999", params: { alt_text: "x" },
                                          headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_post_invalid_id",
                         "message" => "Invalid post ID.",
                         "data" => { "status" => 404 })
    end
  end

  describe "DELETE /wp/v2/media/:id" do
    let!(:asset) do
      Library::Asset.upload!(io: StringIO.new(png_bytes), filename: "doomed.png",
                             uploader: actor("con_admin"))
    end

    it "refuses without force: an attachment has no trash state (501)" do
      delete "/wp-json/wp/v2/media/#{asset.id}", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_implemented)
      expect(json).to eq("code" => "rest_trash_not_supported",
                         "message" => "The post does not support trashing. Set 'force=true' to delete.",
                         "data" => { "status" => 501 })
      expect(Library::Asset.exists?(asset.id)).to be(true)
    end

    it "force=true destroys the row and answers {deleted, previous}" do
      delete "/wp-json/wp/v2/media/#{asset.id}?force=true", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json["deleted"]).to be(true)
      expect(json["previous"]).to include("id" => asset.id)
      expect(json["previous"]).not_to have_key("_links")
      expect(Library::Asset.exists?(asset.id)).to be(false)
    end

    it "is rest_cannot_delete (403) for someone else's attachment" do
      delete "/wp-json/wp/v2/media/#{asset.id}?force=true", headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_delete",
                         "message" => "Sorry, you are not allowed to delete this post.",
                         "data" => { "status" => 403 })
    end
  end

  describe "collection headers Gutenberg reads" do
    it "carries X-WP-Total, X-WP-TotalPages and Link" do
      article = Publishing::Article.create!(author: actor("con_admin"), title: "Gallery",
                                            status: :published, published_at: Time.current,
                                            slug: "gallery")
      3.times do |i|
        Library::Asset.create!(slug: "img-#{i}", title: "Img #{i}", mime_type: "image/png",
                               byte_size: 10, attached_to_id: article.id)
      end
      get "/wp-json/wp/v2/media?per_page=2"
      expect(response.headers["X-WP-Total"]).to eq("3")
      expect(response.headers["X-WP-TotalPages"]).to eq("2")
      expect(response.headers["Link"]).to include('rel="next"')
    end
  end
end
