# frozen_string_literal: true

require "rails_helper"

# web.attachment — the screen IS a 301, not a page. canonical.php:553 with
# `wp_attachment_pages_enabled` = '0' redirects every attachment permalink to the file
# (`wp_get_attachment_url()`, post.php:7191). golden-web-attachment.html is the oracle's
# capture of exactly that: `REDIRECT <SITE>/wp-content/uploads/2026/08/oracle-image.png`.
RSpec.describe "Web::AttachmentsController", type: :request do
  ATTACHMENT_GOLDEN = Rails.root.join("spec/parity/golden/golden-web-attachment.html")

  before do
    Library::Asset.create!(
      title: %(Asset "oracle-image.png" 😀),
      # BR-MIGRATE-033 / utf8_uri_encode (formatting.php:1160): the slug is stored the
      # way sanitize_title() wrote it — non-ASCII bytes percent-encoded, lowercase hex.
      slug: "asset-oracle-image-png-%f0%9f%98%80",
      mime_type: "image/png", byte_size: 1, width: 1600, height: 1200,
      metadata: { "file" => "2026/08/oracle-image.png" }
    )
  end

  # The corpus URL, spec/parity/corpus/requests.yml:71 — the attachment slug's emoji
  # arrives percent-encoded and Rails decodes it; the controller re-encodes for the
  # lookup against the stored slug.
  it "301-redirects the attachment permalink to the file, as the golden records" do
    get "/2026/03/some-parent-post/asset-oracle-image-png-%f0%9f%98%80/"

    expect(response).to have_http_status(:moved_permanently)
    golden = File.read(ATTACHMENT_GOLDEN)
    expect("REDIRECT #{response.location.sub(%r{https?://[^/]+}, "<SITE>")}").to eq(golden)
  end

  # `<attachment permalink>/embed/` — class-wp-rewrite.php:1145 registers the embed rule
  # for attachments as well, but redirect_canonical() runs on `template_redirect`, before
  # template-loader.php ever asks is_embed(), and canonical.php:553 fires on
  # is_attachment() alone. Oracle: 301 to the file, identical to the bare permalink.
  it "301-redirects the attachment's /embed/ variant to the file too" do
    get "/2026/03/some-parent-post/asset-oracle-image-png-%f0%9f%98%80/embed/"

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/wp-content/uploads/2026/08/oracle-image.png")
  end

  it "does not redirect an unknown attachment slug" do
    expect(Library::Asset.find_by(slug: "no-such-asset")).to be_nil
    # The 404 body is the block-theme not-found screen, owned by the parity corpus;
    # here only the status decision is under test.
    get "/2026/03/some-parent-post/no-such-asset/"
    expect(response).to have_http_status(:not_found)
  end
end
