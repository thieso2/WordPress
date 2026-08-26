# frozen_string_literal: true

require "rails_helper"

# The feed endpoint on every permastruct, and the RSD document.
#
# `bin/parity compare` owns the BYTES of these — eleven feed screens and the RSD are in the
# corpus and are compared against the oracle's own output. What it cannot own is the arms
# the corpus has no data for: a queried object that does not exist, and the verb split on
# /xmlrpc.php. Those are here.
RSpec.describe "Feed endpoints", type: :request do
  before { host! "127.0.0.1" }

  let(:author) do
    Identity::User.create!(login: "feeder", email: "feeder@example.com", nicename: "feeder",
                           display_name: "Feeder", password: "pw-feeder-1")
  end

  def article!(title, status: :published)
    Publishing::Article.create!(author: author, title: title, status: status,
                                published_at: status == :published ? Time.current : nil)
  end

  describe "a queried object that does not exist" do
    it "404s an unknown category feed" do
      get "/category/no-such-category/feed/"
      expect(response).to have_http_status(:not_found)
    end

    it "404s an unknown tag feed" do
      get "/tag/no-such-tag/feed/"
      expect(response).to have_http_status(:not_found)
    end

    it "404s an unknown author feed" do
      get "/author/nobody/feed/"
      expect(response).to have_http_status(:not_found)
    end

    it "404s an unknown post's comment feed" do
      get "/2026/03/no-such-post/feed/"
      expect(response).to have_http_status(:not_found)
    end

    it "404s an unknown page's comment feed" do
      get "/no-such-page/feed/"
      expect(response).to have_http_status(:not_found)
    end

    # An author with no posts is a 200 empty feed, not a 404 — the queried object exists.
    # Same asymmetry BR-MIGRATE-045 draws for the archive screen.
    it "serves an EMPTY feed for an author who exists but has no posts" do
      author
      get "/author/feeder/feed/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<channel>")
      expect(response.body).not_to include("<item>")
    end
  end

  # A search feed always exists — there is no queried object to miss.
  it "serves a 200 empty search feed when nothing matches" do
    get "/search/zzzznotfoundzzzz/feed/rss2/"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("<item>")
  end

  it "serves the atom variant of an archive feed" do
    article!("Findable")
    get "/author/feeder/feed/atom/"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("application/atom+xml")
  end

  # A post's comment feed is still a view of that POST: an unreadable record has no
  # readable comment feed either, or the feed becomes a side door onto a private post's
  # title and discussion — the same hole RISK-023 V3 closed on /comments/feed/.
  it "404s the comment feed of a PRIVATE post for an anonymous visitor" do
    secret = Publishing::Article.create!(author: author, title: "Secret", status: :private)
    Discussion::Comment.create!(post: secret, author_name: "Jane", author_email: "j@example.com",
                                content: "Private discussion", status: "approved",
                                kind: "comment", submitted_at: Time.current)

    get "/2026/03/#{secret.slug}/feed/"

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Private discussion")
  end

  describe "/xmlrpc.php" do
    # `isset( $_GET['rsd'] )` is a PRESENCE test — xmlrpc.php:31.
    it "serves the RSD document for ?rsd" do
      get "/xmlrpc.php?rsd"
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to start_with("text/xml")
      expect(response.body).to include('<rsd version="1.0"').and include("<engineName>WordPress</engineName>")
    end

    it "takes the rsd arm for a valueless ?rsd= too (isset, not truthiness)" do
      get "/xmlrpc.php?rsd="
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<rsd")
    end

    # xmlrpc.php accepts POST only; the legacy answers anything else 405 + Allow: POST.
    it "answers a bare GET with 405 and Allow: POST" do
      get "/xmlrpc.php"
      expect(response).to have_http_status(:method_not_allowed)
      expect(response.headers["Allow"]).to eq("POST")
    end
  end
end
