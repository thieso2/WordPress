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

# ── Behavioral-parity fixes (WP_Media_List_Table) ─────────────────────────────────────
RSpec.describe "console.upload (row actions / filters / attach)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  # An asset with a stored file so wp_get_attachment_url() is non-empty (Copy URL /
  # Download file are gated on it, class-wp-media-list-table.php:864/876).
  def filed_asset!(**attrs)
    create_asset!(**{ metadata: { "file" => "2026/08/beach.png" } }.merge(attrs))
  end

  it "renders View, Copy URL and Download file row actions (_get_row_actions)" do
    filed_asset!(slug: "beach", title: "Beach photo", uploader: actor("con_editor"))
    login_as("con_editor")
    get "/console/media"
    labels = doc.css(".row-actions a, .row-actions button").map(&:text).map(&:strip)
    expect(labels).to include("Edit", "Delete Permanently", "View", "Copy URL", "Download file")
  end

  it "omits Copy URL / Download file when the asset has no file URL" do
    create_asset!(slug: "nofile", title: "No file", uploader: actor("con_editor"), metadata: {})
    login_as("con_editor")
    get "/console/media"
    labels = doc.css(".row-actions a, .row-actions button").map(&:text).map(&:strip)
    expect(labels).to include("View")
    expect(labels).not_to include("Copy URL")
  end

  it "links the author name to the author-filtered list (column_author)" do
    ed = actor("con_editor")
    filed_asset!(slug: "beach", title: "Beach photo", uploader: ed)
    login_as("con_editor")
    get "/console/media"
    link = doc.at_css("tbody .column-author a")
    expect(link).not_to be_nil
    expect(link["href"]).to eq("/console/media?author=#{ed.id}")
    expect(link.text.strip).to eq(ed.display_name)
  end

  it "shows the '(no author)' fallback when the asset has no uploader" do
    create_asset!(slug: "orphan", title: "Orphan", uploader: nil)
    login_as("con_editor")
    get "/console/media"
    expect(doc.at_css("tbody .column-author").text).to include("(no author)")
  end

  it "renders the get_views attachment-filter tabs (All media items / Images / Unattached / Mine)" do
    filed_asset!(slug: "beach", title: "Beach photo", uploader: actor("con_editor"), mime_type: "image/png")
    login_as("con_editor")
    get "/console/media"
    tabs = doc.css(".subsubsub a").map(&:text).map(&:strip)
    expect(tabs).to include("All media items", "Images", "Unattached", "Mine")
  end

  it "narrows the list to unattached items via attachment-filter=detached" do
    parent = create_article!(title: "Parent post")
    filed_asset!(slug: "attached", title: "Attached shot", uploader: actor("con_editor"), attached_to_id: parent.id)
    filed_asset!(slug: "loose", title: "Loose shot", uploader: actor("con_editor"))
    login_as("con_editor")
    get "/console/media", params: { "attachment-filter" => "detached" }
    expect(body_text).to include("Loose shot")
    expect(body_text).not_to include("Attached shot")
  end

  it "narrows the list by author (upload.php?author=ID)" do
    ed = actor("con_editor")
    au = actor("con_author")
    filed_asset!(slug: "by-editor", title: "Editor shot", uploader: ed)
    filed_asset!(slug: "by-author", title: "Author shot", uploader: au)
    login_as("con_editor")
    get "/console/media", params: { author: au.id }
    expect(body_text).to include("Author shot")
    expect(body_text).not_to include("Editor shot")
  end

  it "narrows the list by mime group via attachment-filter=post_mime_type:image" do
    filed_asset!(slug: "pic", title: "A picture", uploader: actor("con_editor"), mime_type: "image/png")
    create_asset!(slug: "clip", title: "A movie", uploader: actor("con_editor"), mime_type: "video/mp4",
                  metadata: { "file" => "2026/08/clip.mp4" })
    login_as("con_editor")
    get "/console/media", params: { "attachment-filter" => "post_mime_type:image" }
    expect(body_text).to include("A picture")
    expect(body_text).not_to include("A movie")
  end

  it "renders a Detach control for an attached item and detaches on POST (doaction 'detach')" do
    parent = create_article!(title: "Parent post")
    asset = filed_asset!(slug: "attached", title: "Attached shot", uploader: actor("con_editor"),
                         attached_to_id: parent.id)
    login_as("con_editor")
    get "/console/media"
    expect(doc.css("tbody .column-parent").text).to include("Detach")

    post "/console/media/bulk", params: { bulk_action: "detach", ids: [asset.id] }
    expect(response).to have_http_status(:see_other)
    expect(asset.reload.attached_to_id).to be_nil
    follow_redirect!
    expect(body_text).to include("Media file detached.")
  end

  it "renders an Attach link for an unattached item and attaches on POST (doaction 'attach')" do
    parent = create_article!(title: "Parent post")
    asset = filed_asset!(slug: "loose", title: "Loose shot", uploader: actor("con_editor"))
    login_as("con_editor")
    get "/console/media"
    expect(doc.css("tbody .column-parent").text).to include("Attach")

    post "/console/media/bulk", params: { bulk_action: "attach", ids: [asset.id], found_post_id: parent.id }
    expect(response).to have_http_status(:see_other)
    expect(asset.reload.attached_to_id).to eq(parent.id)
    follow_redirect!
    expect(body_text).to include("Media file attached.")
  end
end
