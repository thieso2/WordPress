# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# The `/wp-json/*` READ surface + the permission model (public_api, BR-MIGRATE-234..244).
# The console screens are MODERNIZED but the REST contract is LITERAL: the JSON shape,
# the LITERAL error codes/messages, and the permission DEFAULTS are reproduced verbatim
# from class-wp-rest-server.php. Values here are cross-checked field-by-field against the
# live oracle in the handoff; these specs pin the observable contract that does not depend
# on the oracle's exact fixture rows.
RSpec.describe "REST API (/wp-json)", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  describe "discovery index" do
    it "resolves at /wp-json/ with the site header the golden pages' <link rel=api.w.org> points at" do
      get "/wp-json/"
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq("application/json; charset=UTF-8")
      body = json
      expect(body["name"]).to eq(Configuration::Setting["blogname"].to_s)
      expect(body["url"]).to eq(Configuration::Setting["home"].to_s)
      expect(body["namespaces"]).to eq(%w[oembed/1.0 wp/v2])
      expect(body["authentication"]).to eq([])
      expect(body["routes"]).to include("/", "/wp/v2/posts", "/oembed/1.0/embed")
      expect(body["_links"]).to eq("help" => [{ "href" => "https://developer.wordpress.org/rest-api/" }])
    end

    it "filters to a single namespace at /wp-json/wp/v2" do
      get "/wp-json/wp/v2"
      expect(response).to have_http_status(:ok)
      expect(json["routes"].keys).to all(satisfy { |k| k == "/" || k.start_with?("/wp/v2") })
    end
  end

  # class-wp-rest-server.php:1096 — rest_no_route, HTTP 404, for any method.
  describe "rest_no_route" do
    it "answers 404 with the LITERAL envelope for an unmatched path" do
      get "/wp-json/wp/v2/does-not-exist"
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_no_route",
                         "message" => "No route was found matching the URL and request method.",
                         "data" => { "status" => 404 })
    end

    it "answers 404 for a non-GET verb too (routes.rb via: :all)" do
      delete "/wp-json/wp/v2/whatever"
      expect(json["code"]).to eq("rest_no_route")
    end
  end

  # ── The permission model, class-wp-rest-server.php:1252-1262 ──────────────────
  describe "permission defaults (BR-MIGRATE-237/238/239)" do
    it "BR-REST-05: a route with NO permission callback is fully PUBLIC" do
      # /wp/v2/types declares no `permission` — reachable anonymously.
      get "/wp-json/wp/v2/types"
      expect(response).to have_http_status(:ok)
      expect(json).to have_key("post")
    end

    it "BR-REST-06: a denial is 401 for an anonymous caller" do
      seed_console_accounts!
      draft = Publishing::Article.create!(author: actor("con_editor"), title: "Secret",
                                          status: :draft)
      get "/wp-json/wp/v2/posts/#{draft.id}"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_forbidden",
                         "message" => "Sorry, you are not allowed to do that.",
                         "data" => { "status" => 401 })
    end

    it "BR-REST-06: the SAME denial is 403 once a (non-privileged) identity is present" do
      seed_console_accounts!
      draft = Publishing::Article.create!(author: actor("con_editor"), title: "Secret",
                                          status: :draft)
      get "/wp-json/wp/v2/posts/#{draft.id}", headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json["data"]).to eq("status" => 403)
    end

    it "BR-REST-04: users/me with no identity DENIES with the rest_not_logged_in envelope (401)" do
      get "/wp-json/wp/v2/users/me"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_not_logged_in",
                         "message" => "You are not currently logged in.",
                         "data" => { "status" => 401 })
    end

    it "users/me returns the authenticated actor over a Bearer token" do
      seed_console_accounts!
      get "/wp-json/wp/v2/users/me", headers: bearer(actor("con_author"))
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(actor("con_author").id)
    end
  end

  # A published post is public; a draft is not. Retrieval::PostQuery (trusted:false) can
  # never widen the collection past `published`.
  describe "posts read surface" do
    it "serves a published post and its rendered content" do
      seed_console_accounts!
      post = Publishing::Article.create!(author: actor("con_editor"), title: "Hi", status: :published,
                                         published_at: Time.current, slug: "hi")
      get "/wp-json/wp/v2/posts/#{post.id}"
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("publish")
      expect(json["title"]).to eq("rendered" => "Hi")
      expect(json.dig("content", "protected")).to be(false)
    end

    it "invalid id is rest_post_invalid_id (404)" do
      get "/wp-json/wp/v2/posts/999999"
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("rest_post_invalid_id")
    end
  end

  # /wp/v2/comments — only APPROVED comments on a published post are visible anonymously.
  describe "comments read surface" do
    it "serves approved comments and hides pending ones" do
      seed_console_accounts!
      post = Publishing::Article.create!(author: actor("con_editor"), title: "P", status: :published,
                                         published_at: Time.current, slug: "p")
      approved = Discussion::Comment.create!(post: post, author_name: "A", author_email: "a@x.com",
                                             content: "yes", status: "approved", submitted_at: Time.current)
      Discussion::Comment.create!(post: post, author_name: "B", author_email: "b@x.com",
                                  content: "no", status: "pending", submitted_at: Time.current)
      get "/wp-json/wp/v2/comments?post=#{post.id}"
      expect(response).to have_http_status(:ok)
      ids = json.map { |c| c["id"] }
      expect(ids).to include(approved.id)
      expect(json.map { |c| c["status"] }.uniq).to eq(["approved"])
    end

    it "a pending comment item denies an anonymous caller (401)" do
      seed_console_accounts!
      post = Publishing::Article.create!(author: actor("con_editor"), title: "P2", status: :published,
                                         published_at: Time.current, slug: "p2")
      held = Discussion::Comment.create!(post: post, author_name: "B", author_email: "b@x.com",
                                         content: "no", status: "pending", submitted_at: Time.current)
      get "/wp-json/wp/v2/comments/#{held.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # types/taxonomies/statuses are declared metadata (DEV-002), not stored rows.
  describe "schema metadata" do
    it "lists all 11 post types with the attachment rest_base -> media" do
      get "/wp-json/wp/v2/types"
      expect(json.keys).to include("post", "page", "attachment", "wp_block")
      expect(json.dig("attachment", "rest_base")).to eq("media")
    end

    it "lists taxonomies with category hierarchical" do
      get "/wp-json/wp/v2/taxonomies"
      expect(json.dig("category", "hierarchical")).to be(true)
    end

    it "shows only the public `publish` status to an anonymous caller" do
      get "/wp-json/wp/v2/statuses"
      expect(json.keys).to eq(["publish"])
      expect(json.dig("publish", "name")).to eq("Published")
    end
  end

  # oembed/1.0/embed — the target of the golden pages' json+oembed <link>.
  describe "oembed" do
    it "resolves a published post URL to a rich oembed document" do
      seed_console_accounts!
      post = Publishing::Article.create!(author: actor("con_editor"), title: "Embed me",
                                         status: :published, published_at: Time.current, slug: "embed-me")
      url = Composition::Renderers::PostBlocks::Links.permalink(post)
      get "/wp-json/oembed/1.0/embed", params: { url: url }
      expect(response).to have_http_status(:ok)
      expect(json["type"]).to eq("rich")
      expect(json["version"]).to eq("1.0")
      expect(json["title"]).to eq("Embed me")
      expect(json["width"]).to eq(600)
      expect(json["height"]).to eq(338)
      expect(json["html"]).to include('class="wp-embedded-content"')
    end

    it "an unresolvable URL is oembed_invalid_url (404)" do
      get "/wp-json/oembed/1.0/embed", params: { url: "http://127.0.0.1/nope/" }
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("oembed_invalid_url")
    end
  end
end
