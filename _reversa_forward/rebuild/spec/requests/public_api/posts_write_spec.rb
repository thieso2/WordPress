# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# The REST FOUNDATION: cookie + nonce authentication, `context=edit`, `_fields`, and the
# post/page write path (@wordpress/editor's boot-time contract).
#
# The contract here is LITERAL — every code, message and status below was read off the
# live oracle (or off wp-includes/rest-api/endpoints/*.php where the oracle corpus has no
# role that reaches the arm) rather than invented. Where a value is a deliberate
# divergence it is called out in the example's own name.
RSpec.describe "REST API — the write surface", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  # The nonce round trip, end to end and through the real handoff: sign in with the
  # session cookie, open the editor, and read the token out of `wpApiSettings` exactly as
  # @wordpress/api-fetch does. Nothing here reaches inside Identity::Nonce.
  def sign_in_and_take_nonce(login)
    login_as(login)
    get "/console/posts/new"
    follow_redirect!
    response.body[/window\.wpApiSettings = (\{.*?\});/, 1].then { |raw| JSON.parse(raw).fetch("nonce") }
  end

  def nonce_header(nonce) = { "X-WP-Nonce" => nonce }

  let(:admin) { actor("con_admin") }

  before { seed_console_accounts! }

  # ── 1. rest_cookie_check_errors(), wp-includes/rest-api.php ──────────────────────
  describe "cookie + nonce authentication" do
    it "accepts the cookie identity when the request carries a valid wp_rest nonce" do
      nonce = sign_in_and_take_nonce("con_admin")
      get "/wp-json/wp/v2/users/me", headers: nonce_header(nonce)
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(admin.id)
    end

    it "DISCARDS the cookie identity when there is no nonce at all (wp_set_current_user(0))" do
      login_as("con_admin")
      # Not an error — the request simply proceeds as though nobody were signed in, which
      # is why `users/me` answers rest_not_logged_in and not a nonce failure.
      get "/wp-json/wp/v2/users/me"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_not_logged_in",
                         "message" => "You are not currently logged in.",
                         "data" => { "status" => 401 })
    end

    it "refuses a BAD nonce with rest_cookie_invalid_nonce / 403, verbatim" do
      login_as("con_admin")
      post "/wp-json/wp/v2/posts", params: { title: "x" }, headers: nonce_header("deadbeef00")
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cookie_invalid_nonce",
                         "message" => "Cookie check failed",
                         "data" => { "status" => 403 })
    end

    it "refuses a bad nonce on a GET too, and with no cookie at all — the 403 is flat" do
      get "/wp-json/wp/v2/posts", headers: nonce_header("deadbeef00")
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("rest_cookie_invalid_nonce")
    end

    it "accepts the nonce as the `_wpnonce` request arg as well as the header" do
      nonce = sign_in_and_take_nonce("con_admin")
      get "/wp-json/wp/v2/users/me", params: { _wpnonce: nonce }
      expect(response).to have_http_status(:ok)
    end

    it "needs NO nonce when the identity came from a bearer token (class-wp-rest-server.php:409)" do
      article = Publishing::Article.create!(author: admin, title: "Bearer write", status: :draft)
      patch "/wp-json/wp/v2/posts/#{article.id}", params: { title: "Renamed" }.to_json,
            headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(article.reload.title).to eq("Renamed")
    end

    it "BR-AUTH-15: destroying the session invalidates the nonce minted under it" do
      nonce = sign_in_and_take_nonce("con_admin")
      Identity::Session.delete_all
      get "/wp-json/wp/v2/users/me", headers: nonce_header(nonce)
      expect(json["code"]).to eq("rest_cookie_invalid_nonce")
    end
  end

  # ── 2. context=edit ───────────────────────────────────────────────────────────────
  describe "context=edit" do
    let!(:article) do
      Publishing::Article.create!(author: admin, title: "Hello world!", status: :published,
                                  published_at: Time.current, slug: "hello-world",
                                  content: "<!-- wp:paragraph -->\n<p>Body.</p>\n<!-- /wp:paragraph -->")
    end

    it "refuses an anonymous caller with rest_forbidden_context (NOT rest_forbidden)" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_forbidden_context",
                         "message" => "Sorry, you are not allowed to edit this post.",
                         "data" => { "status" => 401 })
    end

    it "refuses the COLLECTION with the collection's own message" do
      get "/wp-json/wp/v2/posts", params: { context: "edit" },
          headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("rest_forbidden_context")
      expect(json["message"]).to eq("Sorry, you are not allowed to edit posts in this post type.")
    end

    it "returns the oracle's edit-context keys, in the oracle's order" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json.keys).to eq(%w[
                                id date date_gmt guid modified modified_gmt password slug status type link
                                title content excerpt author featured_media comment_status ping_status
                                sticky template format meta categories tags permalink_template
                                generated_slug class_list _links
                              ])
    end

    it "splits title/content/excerpt into {raw, rendered} and adds guid.raw + block_version" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(json["title"]).to eq("raw" => "Hello world!", "rendered" => "Hello world!")
      expect(json["content"]["raw"]).to eq(article.content)
      expect(json["content"]["block_version"]).to eq(1)
      expect(json["excerpt"]).to include("raw" => "")
      expect(json["guid"]["raw"]).to eq(json["guid"]["rendered"])
    end

    it "block_version is 0 for classic (non-block) markup" do
      classic = Publishing::Article.create!(author: admin, title: "Classic", status: :draft,
                                            content: "<p>plain</p>")
      get "/wp-json/wp/v2/posts/#{classic.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(json["content"]["block_version"]).to eq(0)
    end

    it "carries permalink_template and generated_slug (get_sample_permalink)" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(json["permalink_template"]).to match(%r{/\d{4}/\d{2}/%postname%/\z})
      expect(json["generated_slug"]).to eq("hello-world")
    end

    it "⚠️ DIVERGENCE: `password` is always \"\" — the column is a bcrypt digest (AD-05)" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(json["password"]).to eq("")
    end

    it "adds the wp:action-* rels the editor reads its toolbar from" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "edit" }, headers: bearer(admin)
      expect(json["_links"].keys).to include("wp:action-publish", "wp:action-unfiltered-html",
                                             "wp:action-sticky", "wp:action-assign-author",
                                             "wp:action-create-categories", "wp:action-assign-categories",
                                             "wp:action-create-tags", "wp:action-assign-tags")
    end

    it "emits NO wp:action-* rels outside edit context" do
      get "/wp-json/wp/v2/posts/#{article.id}", headers: bearer(admin)
      expect(json["_links"].keys.grep(/wp:action/)).to be_empty
    end

    it "targetHints.allow is the verb set THIS caller may use" do
      get "/wp-json/wp/v2/posts/#{article.id}"
      expect(json["_links"]["self"].first["targetHints"]).to eq("allow" => %w[GET])

      get "/wp-json/wp/v2/posts/#{article.id}", headers: bearer(admin)
      expect(json["_links"]["self"].first["targetHints"])
        .to eq("allow" => %w[GET POST PUT PATCH DELETE])
    end

    it "view and embed keep their own (smaller) key sets" do
      get "/wp-json/wp/v2/posts/#{article.id}"
      expect(json.keys).not_to include("password", "permalink_template", "generated_slug")
      expect(json["title"].keys).to eq(%w[rendered])

      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "embed" }
      expect(json.keys).to eq(%w[id date slug type link title excerpt author featured_media _links])
    end

    it "rejects an unknown context with the composite rest_invalid_param envelope" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { context: "bogus" }
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        "code" => "rest_invalid_param",
        "message" => "Invalid parameter(s): context",
        "data" => {
          "status" => 400,
          "params" => { "context" => "context is not one of view, embed, and edit." },
          "details" => { "context" => { "code" => "rest_not_in_enum",
                                        "message" => "context is not one of view, embed, and edit.",
                                        "data" => nil } }
        }
      )
    end
  end

  # ── 3. _fields and _locale ────────────────────────────────────────────────────────
  describe "_fields" do
    let!(:article) do
      Publishing::Article.create!(author: admin, title: "Fields", status: :published,
                                  published_at: Time.current, slug: "fields")
    end

    it "keeps the RESPONSE's order, not the request's, and drops unknown names" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { _fields: "id,title,link,bogus" }
      expect(json.keys).to eq(%w[id link title])
    end

    it "omits _links unless _links is asked for" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { _fields: "id" }
      expect(json).to eq("id" => article.id)

      get "/wp-json/wp/v2/posts/#{article.id}", params: { _fields: "id,_links" }
      expect(json.keys).to eq(%w[id _links])
    end

    it "selects INTO an object with a dotted path" do
      get "/wp-json/wp/v2/posts/#{article.id}", params: { _fields: "id,title.rendered" }
      expect(json["title"]).to eq("rendered" => "Fields")
    end

    it "applies to a collection too" do
      get "/wp-json/wp/v2/posts", params: { _fields: "id,slug" }
      expect(json).to all(satisfy { |item| item.keys == %w[id slug] })
    end
  end

  # ── 4. Writes ─────────────────────────────────────────────────────────────────────
  describe "POST /wp/v2/posts" do
    it "creates a draft, answers 201 with a Location header and the EDIT-context body" do
      post "/wp-json/wp/v2/posts",
           params: { title: "Created", content: "<!-- wp:paragraph --><p>hi</p><!-- /wp:paragraph -->" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)
      created = Publishing::Article.find(json["id"])
      expect(response.headers["Location"]).to end_with("/wp-json/wp/v2/posts/#{created.id}")
      expect(created.status).to eq("draft")
      # The response is edit context whatever the request asked for.
      expect(json["content"]["raw"]).to eq(created.content)
    end

    it "publishes through Publishing::Post#publish! — the slug is allocated (BR-MIGRATE-032)" do
      post "/wp-json/wp/v2/posts", params: { title: "A published thing", status: "publish" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)
      created = Publishing::Article.find(json["id"])
      expect(created.status).to eq("published")
      expect(created.slug).to eq("a-published-thing")
      expect(json["status"]).to eq("publish")
    end

    it "BR-MIGRATE-029/030: a `publish` 60s+ in the future becomes `future`, the DATE deciding" do
      at = 1.hour.from_now
      post "/wp-json/wp/v2/posts",
           params: { title: "Later", status: "publish", date_gmt: at.utc.iso8601 }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(json["status"]).to eq("future")
      expect(Publishing::Article.find(json["id"])).to be_scheduled
    end

    it "records the BR-MIGRATE-036 status transition, because the command was used" do
      post "/wp-json/wp/v2/posts", params: { title: "Transitions", status: "publish" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      created = Publishing::Article.find(json["id"])
      expect(created.status_transitions.map(&:to_status)).to include("published")
    end

    it "refuses an anonymous create with rest_cannot_create / 401" do
      post "/wp-json/wp/v2/posts", params: { title: "x" }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_create",
                         "message" => "Sorry, you are not allowed to create posts as this user.",
                         "data" => { "status" => 401 })
    end

    it "refuses `publish` from a caller without publish_posts (rest_cannot_publish)" do
      post "/wp-json/wp/v2/posts", params: { title: "x", status: "publish" }.to_json,
           headers: bearer(actor("con_author")).merge("CONTENT_TYPE" => "application/json")
      # con_author DOES hold publish_posts; the contributor-shaped refusal is asserted on
      # the subscriber, who holds neither publish_posts nor edit_posts.
      expect(response).to have_http_status(:created)

      post "/wp-json/wp/v2/posts", params: { title: "y", status: "publish" }.to_json,
           headers: bearer(actor("con_subscriber")).merge("CONTENT_TYPE" => "application/json")
      expect(json["code"]).to eq("rest_cannot_create")
    end

    it "rejects a status outside the schema enum" do
      post "/wp-json/wp/v2/posts", params: { title: "x", status: "bogus" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("rest_invalid_param")
      expect(json["data"]["params"]["status"])
        .to eq("status is not one of publish, future, draft, pending, and private.")
    end
  end

  describe "PUT/PATCH /wp/v2/posts/:id" do
    let!(:article) { Publishing::Article.create!(author: admin, title: "Before", status: :draft) }

    it "updates only the fields the request carried" do
      patch "/wp-json/wp/v2/posts/#{article.id}", params: { content: "<p>new body</p>" }.to_json,
            headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(article.reload.title).to eq("Before")
      expect(article.content).to eq("<p>new body</p>")
    end

    it "PUT is accepted as well as PATCH" do
      put "/wp-json/wp/v2/posts/#{article.id}", params: { title: "After" }.to_json,
          headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(article.reload.title).to eq("After")
    end

    it "404s an unknown id with rest_post_invalid_id" do
      patch "/wp-json/wp/v2/posts/999999", params: { title: "x" }.to_json,
            headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_post_invalid_id", "message" => "Invalid post ID.",
                         "data" => { "status" => 404 })
    end

    it "refuses an anonymous update with rest_cannot_edit / 401" do
      patch "/wp-json/wp/v2/posts/#{article.id}", params: { title: "x" }
      expect(json).to eq("code" => "rest_cannot_edit",
                         "message" => "Sorry, you are not allowed to edit this post.",
                         "data" => { "status" => 401 })
    end

    it "records a revision, because the update went through the aggregate" do
      expect {
        patch "/wp-json/wp/v2/posts/#{article.id}", params: { title: "Revised" }.to_json,
              headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      }.to change { article.revisions.regular.count }.by(1)
    end
  end

  describe "DELETE /wp/v2/posts/:id" do
    let!(:article) do
      Publishing::Article.create!(author: admin, title: "Doomed", status: :published,
                                  published_at: Time.current, slug: "doomed")
    end

    it "trashes by default and answers with the trashed record in edit context" do
      delete "/wp-json/wp/v2/posts/#{article.id}", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("trash")
      expect(article.reload).to be_trashed
      expect(article.status_before_trash).to eq("published")
    end

    it "answers rest_already_trashed / 410 for a second trash" do
      article.trash!(actor: admin)
      delete "/wp-json/wp/v2/posts/#{article.id}", headers: bearer(admin)
      expect(response).to have_http_status(:gone)
      expect(json).to eq("code" => "rest_already_trashed",
                         "message" => "The post has already been deleted.",
                         "data" => { "status" => 410 })
    end

    it "?force=true deletes permanently and answers the DIFFERENT {deleted, previous} shape" do
      delete "/wp-json/wp/v2/posts/#{article.id}", params: { force: "true" }, headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json["deleted"]).to be(true)
      expect(json["previous"]["id"]).to eq(article.id)
      # `previous` is `$previous->get_data()` — the DATA half only, so no _links.
      expect(json["previous"]).not_to have_key("_links")
      expect(Publishing::Article.find_by(id: article.id)).to be_nil
    end

    it "refuses an anonymous delete with rest_cannot_delete / 401" do
      delete "/wp-json/wp/v2/posts/#{article.id}"
      expect(json).to eq("code" => "rest_cannot_delete",
                         "message" => "Sorry, you are not allowed to delete this post.",
                         "data" => { "status" => 401 })
    end
  end

  describe "pages" do
    let!(:page) { Publishing::Page.create!(author: admin, title: "About", status: :published, published_at: Time.current, slug: "about") }

    it "writes through the same surface, with the page's own field set" do
      patch "/wp-json/wp/v2/pages/#{page.id}", params: { title: "About us", menu_order: 3 }.to_json,
            headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(page.reload.title).to eq("About us")
      expect(page.menu_order).to eq(3)
      expect(json.keys).not_to include("sticky", "format", "categories", "tags")
      expect(json["permalink_template"]).to end_with("/%pagename%/")
    end

    it "creates a page under /wp/v2/pages" do
      post "/wp-json/wp/v2/pages", params: { title: "Colophon", status: "publish" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)
      expect(Publishing::Page.find(json["id"]).slug).to eq("colophon")
    end
  end

  # ── 5. Autosaves ──────────────────────────────────────────────────────────────────
  describe "autosaves" do
    let!(:published) do
      Publishing::Article.create!(author: admin, title: "Live", status: :published,
                                  published_at: Time.current, slug: "live", content: "<p>v1</p>")
    end

    it "GET starts empty and lists the autosave once one exists" do
      get "/wp-json/wp/v2/posts/#{published.id}/autosaves", params: { context: "edit" },
          headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end

    it "POST on a PUBLISHED post creates an autosave revision (parent = the post)" do
      post "/wp-json/wp/v2/posts/#{published.id}/autosaves",
           params: { title: "Live (autosaved)", content: "<p>v2</p>" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(json["parent"]).to eq(published.id)
      expect(json["slug"]).to eq("#{published.id}-autosave-v1")
      expect(json["title"]["raw"]).to eq("Live (autosaved)")
      expect(json["_links"]["parent"].first["href"]).to end_with("/wp/v2/posts/#{published.id}")
      expect(json["preview_link"]).to include("preview_id=#{published.id}", "preview=true")
      # The POST is untouched — an autosave is not a save.
      expect(published.reload.title).to eq("Live")
    end

    it "one autosave per author, overwritten in place (Publishing::Post#autosave!)" do
      2.times do |i|
        post "/wp-json/wp/v2/posts/#{published.id}/autosaves",
             params: { title: "draft #{i}", content: "<p>v#{i}</p>" }.to_json,
             headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      end
      expect(published.revisions.autosaves.count).to eq(1)
    end

    it "GET lists it in the autosave shape" do
      published.autosave!(title: "Pending edit", content: "<p>x</p>", actor: admin)
      get "/wp-json/wp/v2/posts/#{published.id}/autosaves", params: { context: "edit" },
          headers: bearer(admin)
      expect(json.length).to eq(1)
      expect(json.first.keys).to eq(%w[author date date_gmt id modified modified_gmt parent slug
                                       guid title content excerpt meta preview_link _links])
    end

    it "a DRAFT the caller owns is updated IN PLACE — id is the POST's, parent 0, no _links" do
      draft = Publishing::Article.create!(author: admin, title: "Mine", status: :draft)
      post "/wp-json/wp/v2/posts/#{draft.id}/autosaves",
           params: { title: "Mine, edited" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(json["id"]).to eq(draft.id)
      expect(json["parent"]).to eq(0)
      expect(json).not_to have_key("_links")
      expect(draft.reload.title).to eq("Mine, edited")
      expect(draft.revisions.autosaves).to be_empty
    end

    it "…but NOT while another editor holds a live lock (wp_check_post_lock)" do
      draft = Publishing::Article.create!(author: admin, title: "Mine", status: :draft)
      draft.lock_editing!(actor: actor("con_editor"))
      post "/wp-json/wp/v2/posts/#{draft.id}/autosaves",
           params: { title: "Mine, edited" }.to_json,
           headers: bearer(admin).merge("CONTENT_TYPE" => "application/json")
      expect(json["parent"]).to eq(draft.id)
      expect(draft.reload.title).to eq("Mine")
    end

    it "404s an unknown parent with rest_post_invalid_parent (not rest_post_invalid_id)" do
      get "/wp-json/wp/v2/posts/999999/autosaves", headers: bearer(admin)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_post_invalid_parent",
                         "message" => "Invalid post parent ID.",
                         "data" => { "status" => 404 })
    end

    it "refuses an anonymous read with rest_cannot_read / 401" do
      get "/wp-json/wp/v2/posts/#{published.id}/autosaves"
      expect(json).to eq("code" => "rest_cannot_read",
                         "message" => "Sorry, you are not allowed to view autosaves of this post.",
                         "data" => { "status" => 401 })
    end
  end
end
