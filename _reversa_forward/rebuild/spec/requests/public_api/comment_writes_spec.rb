# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# /wp/v2/comments — the WRITE half of WP_REST_Comments_Controller.
#
# ⚠️ The headline rule, and it is the LEGACY's: this surface never admits an anonymous
# author. create_item_permissions_check() lets one through only when the
# `rest_allow_anonymous_comments` filter says so, and it defaults to false — AD-01 removes
# the filter, so the default is permanent. Confirmed against the live oracle.
RSpec.describe "REST API — comment writes", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  before { seed_console_accounts! }

  let(:article) do
    Publishing::Article.create!(author: actor("con_editor"), title: "Open post", status: :published,
                                published_at: Time.current, slug: "open-post", comment_status: "open")
  end

  describe "POST /wp/v2/comments" do
    it "creates the comment, answers 201 + Location, and fills the author from the actor" do
      post "/wp-json/wp/v2/comments", params: { post: article.id, content: "Hello <b>world</b>" },
                                      headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to end_with("/wp-json/wp/v2/comments/#{json["id"]}")
      expect(json["post"]).to eq(article.id)
      expect(json["author"]).to eq(actor("con_admin").id)
      expect(json["author_name"]).to eq("con_admin")
      expect(json["type"]).to eq("comment")
      expect(Discussion::Comment.find(json["id"]).post_id).to eq(article.id)
    end

    # :520 — the create response is served in `edit` context, so it carries the fields a
    # `view` response withholds.
    it "answers in EDIT context: content.raw plus the three author forensics fields" do
      post "/wp-json/wp/v2/comments", params: { post: article.id, content: "Raw me" },
                                      headers: bearer(actor("con_admin"))
      expect(json.dig("content", "raw")).to eq("Raw me")
      expect(json).to have_key("author_email")
      expect(json).to have_key("author_ip")
      expect(json).to have_key("author_user_agent")
    end

    it "is rest_comment_login_required (401) for an anonymous caller, whatever it sends" do
      post "/wp-json/wp/v2/comments", params: { post: article.id, content: "anon",
                                                author_name: "Bob", author_email: "bob@example.com" }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_comment_login_required",
                         "message" => "Sorry, you must be logged in to comment.",
                         "data" => { "status" => 401 })
    end

    it "is rest_comment_invalid_post_id (403) with no `post` at all" do
      post "/wp-json/wp/v2/comments", params: { content: "x" }, headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_comment_invalid_post_id",
                         "message" => "Sorry, you are not allowed to create this comment without a post.",
                         "data" => { "status" => 403 })
    end

    it "gives the SAME refusal for a `post` that names nothing" do
      post "/wp-json/wp/v2/comments", params: { post: 999_999, content: "x" },
                                      headers: bearer(actor("con_admin"))
      expect(json["code"]).to eq("rest_comment_invalid_post_id")
      expect(response).to have_http_status(:forbidden)
    end

    it "is rest_comment_content_invalid (400) for empty content" do
      post "/wp-json/wp/v2/comments", params: { post: article.id, content: "" },
                                      headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_comment_content_invalid",
                         "message" => "Invalid comment content.",
                         "data" => { "status" => 400 })
    end

    it "is rest_comment_closed (403) when the post's discussion is closed" do
      closed = Publishing::Article.create!(author: actor("con_editor"), title: "Closed",
                                           status: :published, published_at: Time.current,
                                           slug: "closed-post", comment_status: "closed")
      post "/wp-json/wp/v2/comments", params: { post: closed.id, content: "x" },
                                      headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_comment_closed",
                         "message" => "Sorry, comments are closed for this item.",
                         "data" => { "status" => 403 })
    end

    it "is rest_comment_draft_post (403) on an unpublished post" do
      draft = Publishing::Article.create!(author: actor("con_editor"), title: "Draft",
                                          status: :draft, slug: "draft-post", comment_status: "open")
      post "/wp-json/wp/v2/comments", params: { post: draft.id, content: "x" },
                                      headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_comment_draft_post",
                         "message" => "Sorry, you are not allowed to create a comment on this post.",
                         "data" => { "status" => 403 })
    end

    # :668-700 — three arguments only a moderator may set.
    it "is rest_comment_invalid_author (403) when a non-moderator names someone else" do
      post "/wp-json/wp/v2/comments",
           params: { post: article.id, content: "x", author: actor("con_admin").id },
           headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_comment_invalid_author",
                         "message" => "Sorry, you are not allowed to edit 'author' for comments.",
                         "data" => { "status" => 403 })
    end

    it "is rest_comment_invalid_status (403) when a non-moderator sets a status" do
      post "/wp-json/wp/v2/comments",
           params: { post: article.id, content: "x", status: "approved" },
           headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_comment_invalid_status",
                         "message" => "Sorry, you are not allowed to edit 'status' for comments.",
                         "data" => { "status" => 403 })
    end

    # The moderation pipeline is Discussion::Comment.moderate's, not a second copy: an
    # administrator is `privileged?` there, so the verdict is `approved` with no checks.
    it "auto-approves a moderator's own comment (BR-CMT-05)" do
      post "/wp-json/wp/v2/comments", params: { post: article.id, content: "moderator speaks" },
                                      headers: bearer(actor("con_admin"))
      expect(json["status"]).to eq("approved")
    end

    # wp_allow_comment()'s WP_Error arm, re-statused by the REST controller (:490).
    it "re-statuses the pipeline's duplicate rejection to 409" do
      2.times do
        post "/wp-json/wp/v2/comments", params: { post: article.id, content: "say it twice" },
                                        headers: bearer(actor("con_admin"))
      end
      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("comment_duplicate")
      expect(json["data"]).to eq("status" => 409)
    end
  end

  describe "POST|PUT /wp/v2/comments/:id" do
    let!(:comment) do
      Discussion::Comment.create!(post: article, user: actor("con_admin"), author_name: "con_admin",
                                  author_email: "con_admin@example.com", content: "Original body",
                                  status: "approved", submitted_at: Time.current)
    end

    it "edits the content and moves the status" do
      post "/wp-json/wp/v2/comments/#{comment.id}", params: { content: "edited content", status: "hold" },
                                                    headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json.dig("content", "raw")).to eq("edited content")
      expect(json["status"]).to eq("hold")
      expect(comment.reload.status).to eq("pending")
    end

    it "accepts PUT for the same action" do
      put "/wp-json/wp/v2/comments/#{comment.id}", params: { content: "put body" },
                                                   headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(comment.reload.content).to include("put body")
    end

    it "is rest_cannot_edit (403) for a non-privileged identity" do
      post "/wp-json/wp/v2/comments/#{comment.id}", params: { content: "hax" },
                                                    headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_edit",
                         "message" => "Sorry, you are not allowed to edit this comment.",
                         "data" => { "status" => 403 })
    end

    it "is rest_comment_invalid_id (404) for an id that names nothing" do
      post "/wp-json/wp/v2/comments/999999", params: { content: "x" },
                                             headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_comment_invalid_id",
                         "message" => "Invalid comment ID.",
                         "data" => { "status" => 404 })
    end
  end

  describe "DELETE /wp/v2/comments/:id" do
    let!(:comment) do
      Discussion::Comment.create!(post: article, user: actor("con_admin"), author_name: "con_admin",
                                  author_email: "con_admin@example.com", content: "Trash me",
                                  status: "approved", submitted_at: Time.current)
    end

    # A comment DOES support trashing — unlike a term or an attachment.
    it "trashes without force and answers the comment with status `trash`" do
      delete "/wp-json/wp/v2/comments/#{comment.id}", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("trash")
      expect(comment.reload.status).to eq("trashed")
    end

    it "is rest_already_trashed (410) the second time" do
      delete "/wp-json/wp/v2/comments/#{comment.id}", headers: bearer(actor("con_admin"))
      delete "/wp-json/wp/v2/comments/#{comment.id}", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:gone)
      expect(json).to eq("code" => "rest_already_trashed",
                         "message" => "The comment has already been trashed.",
                         "data" => { "status" => 410 })
    end

    it "force=true destroys the row and answers {deleted, previous} without _links" do
      delete "/wp-json/wp/v2/comments/#{comment.id}?force=true", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json["deleted"]).to be(true)
      expect(json["previous"]).to include("id" => comment.id)
      expect(json["previous"]).not_to have_key("_links")
      expect(Discussion::Comment.exists?(comment.id)).to be(false)
    end

    it "is rest_cannot_delete (403) for a non-privileged identity" do
      delete "/wp-json/wp/v2/comments/#{comment.id}", headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_delete",
                         "message" => "Sorry, you are not allowed to delete this comment.",
                         "data" => { "status" => 403 })
    end

    it "is rest_comment_invalid_id (404) for an unknown id" do
      delete "/wp-json/wp/v2/comments/999999", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("rest_comment_invalid_id")
    end
  end

  describe "collection headers Gutenberg reads" do
    it "carries X-WP-Total, X-WP-TotalPages and Link" do
      3.times do |i|
        Discussion::Comment.create!(post: article, author_name: "A#{i}", author_email: "a#{i}@x.com",
                                    content: "c#{i}", status: "approved", submitted_at: Time.current)
      end
      get "/wp-json/wp/v2/comments?per_page=2"
      expect(response.headers["X-WP-Total"]).to eq("3")
      expect(response.headers["X-WP-TotalPages"]).to eq("2")
      expect(response.headers["Link"]).to include('rel="next"')
    end
  end
end
