# frozen_string_literal: true

require_relative "editor_spec_helper"

# console.post-new / console.post / console.site-editor — the editor SHELL (target_screens.md
# § The editor, DEV-012). ⚠️ These verify the SERVER-SIDE contract only: the auth gate, the
# edit lock, autosave/revisions, and the publish/schedule state machine. The Gutenberg canvas
# is the deferred React island (DEV-012, D-3) and has no server-side behaviour to assert.
RSpec.describe "the editor shell", type: :request do
  before do
    seed_editor_users!
    host! "127.0.0.1"
  end

  def make_draft(author: editor_user("editor"), **attrs)
    Publishing::Article.create!({ author: author, status: :draft, title: "A draft",
                                  content: "<!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->",
                                  excerpt: "" }.merge(attrs))
  end

  # ── The auth gate: auth_redirect() (wp-admin/admin.php:104) ───────────────────────
  describe "the authentication gate" do
    it "bounces an unauthenticated request to the login screen with redirect_to (BR-MIGRATE-325)" do
      get "/console/posts/new"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("http://127.0.0.1/login?redirect_to=%2Fconsole%2Fposts%2Fnew")
    end

    it "bounces an unauthenticated site-editor request too" do
      get "/console/site-editor"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login?redirect_to=")
    end
  end

  # ── console.post-new: get_default_post_to_edit inserts an auto-draft ───────────────
  describe "GET /console/posts/new" do
    it "creates an auto_draft and opens its edit screen (includes/post.php:14-33)" do
      sign_in_as("editor")
      expect { get "/console/posts/new" }.to change(Publishing::Article.where(status: :auto_draft), :count).by(1)
      post = Publishing::Article.in_auto_draft.order(:id).last
      expect(response).to redirect_to(edit_console_post_path(post))
      expect(post.author_id).to eq(editor_user("editor").id)
    end

    it "creates a page auto_draft when post_type=page" do
      sign_in_as("editor")
      get "/console/posts/new", params: { post_type: "page" }
      expect(Publishing::Page.in_auto_draft.count).to eq(1)
    end

    it "refuses a user without the create capability, writing no row (subscriber)" do
      sign_in_as("subscriber")
      expect { get "/console/posts/new" }.not_to change(Publishing::Post, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── console.post: the edit screen + lock acquisition ──────────────────────────────
  describe "GET /console/posts/:id/edit" do
    it "renders the shell with the LITERAL title and the honest placeholder, and acquires the lock" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post)

      expect(response).to have_http_status(:ok)
      expect(edoc.at_css("title").text).to include("Edit Post")
      expect(response.body).to include("Add title")               # edit-form-blocks.php:281
      expect(response.body).to include("Type / to choose a block") # :275
      expect(response.body).to include("deferred: react-island (DEV-012, D-3)")
      expect(post.reload.edit_lock_by_id).to eq(editor_user("editor").id)
      expect(post.edit_lock_at).to be_present
    end

    it "titles a fresh auto_draft 'Add Post' (post-new.php:54), not 'Edit Post'" do
      post = Publishing::Article.create!(author: editor_user("editor"), status: :auto_draft,
                                         title: "", content: "", excerpt: "")
      sign_in_as("editor")
      get edit_console_post_path(post)
      expect(edoc.at_css("title").text).to include("Add Post")
    end

    it "forbids a user who cannot edit the record (subscriber on someone else's draft)" do
      post = make_draft
      sign_in_as("subscriber")
      get edit_console_post_path(post)
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── The publish / schedule state machine (BR-MIGRATE-029/030) ─────────────────────
  describe "PATCH /console/posts/:id — the control strip" do
    it "Save Draft persists content through the real command path and records a revision" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post) # acquire the lock

      expect do
        patch console_post_path(post), params: { command: "draft", title: "Edited title",
                                                 content: post.content, excerpt: "x" }
      end.to change { post.revisions.regular.count }.by(1)
      expect(response).to redirect_to(edit_console_post_path(post))
      expect(post.reload.title).to eq("Edited title")
      expect(post.status).to eq("draft")
    end

    it "Publish publishes immediately and allocates a slug on first publication (BR-MIGRATE-032)" do
      post = make_draft(slug: nil)
      sign_in_as("editor")
      get edit_console_post_path(post)

      patch console_post_path(post), params: { command: "publish", title: post.title,
                                               content: post.content, excerpt: "" }
      expect(post.reload.status).to eq("published")
      expect(post.slug).to be_present
      expect(post.published_at).to be_present
    end

    it "Schedule with an instant ≥ 60 s ahead becomes `scheduled` (the 60-second threshold)" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post)

      at = (Time.current + 10.minutes)
      patch console_post_path(post), params: { command: "schedule",
                                               published_at: at.strftime("%Y-%m-%dT%H:%M"),
                                               title: post.title, content: post.content, excerpt: "" }
      expect(post.reload.status).to eq("scheduled")
    end

    it "Schedule with an instant closer than 60 s publishes now (BR-MIGRATE-030)" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post)

      at = (Time.current + 20.seconds)
      patch console_post_path(post), params: { command: "schedule",
                                               published_at: at.strftime("%Y-%m-%dT%H:%M:%S"),
                                               title: post.title, content: post.content, excerpt: "" }
      expect(post.reload.status).to eq("published")
    end
  end

  # ── Autosave (wp_create_post_autosave, includes/post.php:1957) ────────────────────
  describe "POST /console/posts/:id/autosave" do
    it "creates one autosave revision per author and overwrites it in place" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post)

      expect do
        post_autosave(post, title: "v1", content: "c1")
      end.to change { post.revisions.autosaves.count }.by(1)
      expect(JSON.parse(response.body)["message"]).to eq("Your latest changes were saved as a revision.")

      # A second autosave by the same author overwrites — still one row (:1975).
      expect { post_autosave(post, title: "v2", content: "c2") }
        .not_to change { post.revisions.autosaves.count }
    end

    it "deletes the autosave and returns no id when it equals the record (:1982)" do
      post = make_draft
      sign_in_as("editor")
      get edit_console_post_path(post)
      post_autosave(post, title: "draft-ish", content: "c")
      expect(post.revisions.autosaves.count).to eq(1)

      post_autosave(post, title: post.title, content: post.content, excerpt: post.excerpt)
      expect(post.revisions.autosaves.count).to eq(0)
      expect(JSON.parse(response.body)["autosave_id"]).to be_nil
    end
  end

  # ── Post locking (wp_check_post_lock / wp_set_post_lock / wp_refresh_post_lock) ────
  describe "the edit lock across two editors" do
    it "shows the takeover notice to the second editor instead of stealing the lock" do
      post = make_draft(author: editor_user("author"))
      sign_in_as("editor")
      get edit_console_post_path(post) # editor holds the lock

      # A different editor (administrator can edit others' posts) opens the same post.
      sign_out
      sign_in_as("administrator")
      get edit_console_post_path(post)

      expect(response).to have_http_status(:ok)
      # includes/post.php:96 (LITERAL), display name filled in.
      expect(response.body).to include("Console Editor is currently editing this post. Do you want to take over?")
      expect(response.body).to include("Take over")
      # The lock was NOT reassigned by merely viewing.
      expect(post.reload.edit_lock_by_id).to eq(editor_user("editor").id)
    end

    it "the lock heartbeat answers a supplanted holder with the legacy's lock_error string" do
      post = make_draft(author: editor_user("author"))
      sign_in_as("administrator")
      get edit_console_post_path(post) # admin holds the lock

      sign_out
      sign_in_as("editor")
      # The editor's heartbeat now finds the admin holding a live lock.
      lock_ping(post)
      body = JSON.parse(response.body)
      expect(body.dig("lock_error", "text"))
        .to eq("Console Administrator has taken over and is currently editing.")
    end

    it "Take over seizes the lock (the get-post-lock handler)" do
      post = make_draft(author: editor_user("author"))
      sign_in_as("editor")
      get edit_console_post_path(post)

      sign_out
      sign_in_as("administrator")
      post_steal(post)
      expect(post.reload.edit_lock_by_id).to eq(editor_user("administrator").id)
    end

    it "a lock older than the 150 s window is ignored and silently overwritten (includes/post.php:1739)" do
      post = make_draft(author: editor_user("author"))
      sign_in_as("editor")
      get edit_console_post_path(post)

      sign_out
      sign_in_as("administrator")
      travel(151.seconds) do
        get edit_console_post_path(post)
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("is currently editing this post")
        expect(post.reload.edit_lock_by_id).to eq(editor_user("administrator").id) # overwritten
      end
    end
  end

  # ── console.site-editor ───────────────────────────────────────────────────────────
  describe "GET /console/site-editor" do
    it "admits an administrator (edit_theme_options) with the honest placeholder" do
      sign_in_as("administrator")
      get "/console/site-editor"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("deferred: react-island (DEV-012, D-3)")
    end

    it "forbids an editor, who lacks edit_theme_options" do
      sign_in_as("editor")
      get "/console/site-editor"
      expect(response).to have_http_status(:forbidden)
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────────────
  def post_autosave(post, **params)
    post autosave_console_post_path(post), params: params, headers: csrf_header
  end

  def lock_ping(post)
    post lock_console_post_path(post), headers: csrf_header
  end

  def post_steal(post)
    post steal_console_post_path(post), headers: csrf_header
  end

  # Request specs skip forgery verification by default; the header is set for realism where
  # the endpoint is a fetch/XHR in the browser.
  def csrf_header = {}

  # Drop the session cookie so the next sign_in establishes a fresh actor.
  def sign_out
    cookies.delete(Auth::SessionCookie::COOKIE)
  end
end
