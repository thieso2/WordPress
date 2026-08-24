# frozen_string_literal: true

require_relative "editor_spec_helper"

# The editor's blocks JSON API (DEV-012, D-3) — the server half of the React island. Two
# endpoints: GET .../blocks hands the parsed block tree to the client; PATCH accepts a block
# tree, serializes it SERVER-SIDE through the verified grammar, and drives the same
# Publishing::Post commands the noscript form does. Behavioural parity is the contract; there
# are no golden files (DEV-012), so these assert the round-trip and the state machine.
RSpec.describe "the editor blocks API", type: :request do
  before { seed_editor_users!; host! "127.0.0.1" }

  let(:markup) { %(<!-- wp:heading {"level":2} --><h2>Title</h2><!-- /wp:heading --><!-- wp:paragraph --><p>Body</p><!-- /wp:paragraph -->) }

  def make_draft(author: editor_user("editor"), **attrs)
    Publishing::Article.create!({ author: author, status: :draft, title: "A draft",
                                  content: markup, excerpt: "" }.merge(attrs))
  end

  describe "GET /console/posts/:id/blocks" do
    it "returns the post's content parsed into a block tree" do
      sign_in_as("editor"); post_rec = make_draft
      get "/console/posts/#{post_rec.id}/blocks", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["title"]).to eq("A draft")
      names = body["blocks"].map { |b| b["name"] }
      expect(names).to eq(%w[core/heading core/paragraph])
      expect(body["blocks"].first["attrs"]).to eq({ "level" => 2 })
      expect(body["blocks"].first["innerHTML"]).to eq("<h2>Title</h2>")
    end

    it "bounces an unauthenticated request to login" do
      post_rec = make_draft
      get "/console/posts/#{post_rec.id}/blocks"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login?redirect_to=")
    end

    it "forbids a user without edit on the record" do
      other = make_draft(author: editor_user("editor"))
      sign_in_as("subscriber")
      get "/console/posts/#{other.id}/blocks", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /console/posts/:id with a block tree" do
    def patch_blocks(post_rec, blocks:, command: "draft", **extra)
      patch "/console/posts/#{post_rec.id}",
            params: { command: command, title: "Edited", excerpt: "", blocks: blocks }.merge(extra).to_json,
            headers: { "CONTENT_TYPE" => "application/json", "Accept" => "application/json" }
    end

    it "serializes the tree to markup and saves it (round-trip through the grammar)" do
      sign_in_as("editor"); post_rec = make_draft
      blocks = [
        { "name" => "core/heading", "attrs" => { "level" => 2 }, "innerHTML" => "<h2>New</h2>", "innerContent" => ["<h2>New</h2>"], "innerBlocks" => [] },
        { "name" => "core/paragraph", "attrs" => {}, "innerHTML" => "<p>Fresh</p>", "innerContent" => ["<p>Fresh</p>"], "innerBlocks" => [] }
      ]
      patch_blocks(post_rec, blocks: blocks, command: "draft")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be(true)
      post_rec.reload
      expect(post_rec.content).to eq(%(<!-- wp:heading {"level":2} --><h2>New</h2><!-- /wp:heading --><!-- wp:paragraph --><p>Fresh</p><!-- /wp:paragraph -->))
      expect(post_rec.title).to eq("Edited")
    end

    it "publishes through the real command path when command=publish" do
      sign_in_as("editor"); post_rec = make_draft
      blocks = [{ "name" => "core/paragraph", "attrs" => {}, "innerHTML" => "<p>x</p>", "innerContent" => ["<p>x</p>"], "innerBlocks" => [] }]
      patch_blocks(post_rec, blocks: blocks, command: "publish")
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be(true)
      expect(body["status"]).to eq("published")
      expect(post_rec.reload).to be_published
    end

    it "reports the lock holder as a conflict, refusing the save" do
      owner = editor_user("editor"); post_rec = make_draft(author: owner)
      # A second editor holds a live lock.
      other = editor_user("administrator")
      post_rec.lock_editing!(actor: other)
      sign_in_as("editor")
      blocks = [{ "name" => "core/paragraph", "attrs" => {}, "innerHTML" => "<p>x</p>", "innerContent" => ["<p>x</p>"], "innerBlocks" => [] }]
      patch_blocks(post_rec, blocks: blocks)
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["lock_error"]["name"]).to eq(other.display_name)
    end
  end
end
