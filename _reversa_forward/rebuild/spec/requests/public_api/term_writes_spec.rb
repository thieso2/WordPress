# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# /wp/v2/categories and /wp/v2/tags — the WRITE half of WP_REST_Terms_Controller.
# Gutenberg's Post sidebar creates a category or a tag INLINE, so this is on the editor's
# critical path. Every code, message and status below was read off the live oracle
# (WordPress 7.2-alpha) before it was written here, including the two DIFFERENT
# `term_exists` messages the hierarchical and flat taxonomies produce.
RSpec.describe "REST API — term writes", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }

  let(:categories) do
    Classification::Taxonomy.find_or_create_by!(name: "category") { |t| t.hierarchical = true }
  end
  let(:tags) do
    Classification::Taxonomy.find_or_create_by!(name: "post_tag") { |t| t.hierarchical = false }
  end

  before { seed_console_accounts! }

  describe "POST /wp/v2/categories" do
    it "creates the term, answers 201 + Location, and derives the slug from the name" do
      categories
      post "/wp-json/wp/v2/categories", params: { name: "Oracle Cat A", description: "desc <b>x</b>" },
                                        headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to end_with("/wp-json/wp/v2/categories/#{json["id"]}")
      expect(json["name"]).to eq("Oracle Cat A")
      expect(json["slug"]).to eq("oracle-cat-a")
      expect(json["taxonomy"]).to eq("category")
      expect(json["parent"]).to eq(0)
      expect(json["count"]).to eq(0)
      expect(Classification::Term.find(json["id"]).taxonomy).to eq(categories)
    end

    # rest_send_allow_header(): the same list the `Allow` header carries.
    it "reports the writable methods in targetHints.allow for a caller who holds them" do
      categories
      post "/wp-json/wp/v2/categories", params: { name: "Hinted" }, headers: bearer(actor("con_admin"))
      expect(json.dig("_links", "self", 0, "targetHints", "allow"))
        .to eq(%w[GET POST PUT PATCH DELETE])
      expect(response.headers["Allow"]).to eq("GET, POST, PUT, PATCH, DELETE")
    end

    it "shows only GET in targetHints to an anonymous reader" do
      term = Classification::Term.create!(taxonomy: categories, name: "Read Only", slug: "read-only")
      get "/wp-json/wp/v2/categories/#{term.id}"
      expect(json.dig("_links", "self", 0, "targetHints", "allow")).to eq(%w[GET])
      expect(response.headers["Allow"]).to eq("GET")
    end

    it "is rest_cannot_create for an anonymous caller (401)" do
      categories
      post "/wp-json/wp/v2/categories", params: { name: "nope" }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_create",
                         "message" => "Sorry, you are not allowed to create terms in this taxonomy.",
                         "data" => { "status" => 401 })
    end

    it "is the SAME refusal at 403 once a non-privileged identity is present" do
      categories
      post "/wp-json/wp/v2/categories", params: { name: "nope" },
                                        headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("rest_cannot_create")
      expect(json["data"]).to eq("status" => 403)
    end

    it "is rest_missing_callback_param when `name` is absent" do
      categories
      post "/wp-json/wp/v2/categories", params: {}, headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_missing_callback_param",
                         "message" => "Missing parameter(s): name",
                         "data" => { "status" => 400, "params" => ["name"] })
    end

    it "is term_exists (with the term_id) for a duplicate name under the same parent" do
      existing = Classification::Term.create!(taxonomy: categories, name: "Uncategorized",
                                              slug: "uncategorized")
      post "/wp-json/wp/v2/categories", params: { name: "Uncategorized" },
                                        headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "term_exists",
                         "message" => "A term with the name provided already exists with this parent.",
                         "data" => { "status" => 400, "term_id" => existing.id })
    end

    # wp_unique_term_slug(): the same NAME under a DIFFERENT parent is allowed, and the
    # slug takes the parent's slug as a suffix.
    it "allows the same name under a different parent and suffixes the slug with the parent's" do
      parent = Classification::Term.create!(taxonomy: categories, name: "Top Category", slug: "top-category")
      Classification::Term.create!(taxonomy: categories, name: "Uncategorized", slug: "uncategorized")
      post "/wp-json/wp/v2/categories", params: { name: "Uncategorized", parent: parent.id },
                                        headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      expect(json["slug"]).to eq("uncategorized-top-category")
      expect(json["parent"]).to eq(parent.id)
    end

    it "suffixes a numerically colliding explicit slug" do
      Classification::Term.create!(taxonomy: categories, name: "Uncategorized", slug: "uncategorized")
      post "/wp-json/wp/v2/categories", params: { name: "Something Else", slug: "uncategorized" },
                                        headers: bearer(actor("con_admin"))
      expect(json["slug"]).to eq("uncategorized-2")
    end

    it "is rest_term_invalid (400) for a parent that names nothing" do
      categories
      post "/wp-json/wp/v2/categories", params: { name: "pp", parent: 99_999 },
                                        headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_term_invalid",
                         "message" => "Parent term does not exist.",
                         "data" => { "status" => 400 })
    end
  end

  describe "POST /wp/v2/tags" do
    it "creates a flat term with no `parent` field in the response" do
      tags
      post "/wp-json/wp/v2/tags", params: { name: "OTag One" }, headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:created)
      expect(json).not_to have_key("parent")
      expect(json["taxonomy"]).to eq("post_tag")
      expect(json["slug"]).to eq("otag-one")
    end

    it "refuses a duplicate name ANYWHERE in a flat taxonomy, with the flat message" do
      existing = Classification::Term.create!(taxonomy: tags, name: "OTag One", slug: "otag-one")
      post "/wp-json/wp/v2/tags", params: { name: "OTag One" }, headers: bearer(actor("con_admin"))
      expect(json).to eq("code" => "term_exists",
                         "message" => "A term with the name provided already exists in this taxonomy.",
                         "data" => { "status" => 400, "term_id" => existing.id })
    end

    it "is rest_taxonomy_not_hierarchical when a parent is supplied" do
      parent = Classification::Term.create!(taxonomy: tags, name: "Anything", slug: "anything")
      post "/wp-json/wp/v2/tags", params: { name: "OTag Two", parent: parent.id },
                                  headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_taxonomy_not_hierarchical",
                         "message" => "Cannot set parent term, taxonomy is not hierarchical.",
                         "data" => { "status" => 400 })
    end
  end

  describe "POST|PUT /wp/v2/categories/:id" do
    let!(:term) { Classification::Term.create!(taxonomy: categories, name: "Before", slug: "before") }

    it "updates name, slug and description over POST" do
      post "/wp-json/wp/v2/categories/#{term.id}",
           params: { name: "Oracle Cat B", slug: "oracle-cat-b", description: "upd" },
           headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json.values_at("name", "slug", "description")).to eq(["Oracle Cat B", "oracle-cat-b", "upd"])
      expect(term.reload.name).to eq("Oracle Cat B")
    end

    it "accepts PUT for the same action" do
      put "/wp-json/wp/v2/categories/#{term.id}", params: { description: "via put" },
                                                  headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(term.reload.description).to eq("via put")
    end

    it "is rest_cannot_update (403) for a non-privileged identity" do
      post "/wp-json/wp/v2/categories/#{term.id}", params: { name: "hax" },
                                                   headers: bearer(actor("con_subscriber"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_update",
                         "message" => "Sorry, you are not allowed to edit this term.",
                         "data" => { "status" => 403 })
    end

    it "is rest_term_invalid (404) for an id that names nothing" do
      post "/wp-json/wp/v2/categories/999999", params: { name: "x" },
                                               headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_term_invalid",
                         "message" => "Term does not exist.",
                         "data" => { "status" => 404 })
    end
  end

  describe "DELETE /wp/v2/categories/:id" do
    let!(:term) { Classification::Term.create!(taxonomy: categories, name: "Doomed", slug: "doomed") }

    it "refuses without force: terms have no trash state (501)" do
      delete "/wp-json/wp/v2/categories/#{term.id}", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_implemented)
      expect(json).to eq("code" => "rest_trash_not_supported",
                         "message" => "Terms do not support trashing. Set 'force=true' to delete.",
                         "data" => { "status" => 501 })
      expect(Classification::Term.exists?(term.id)).to be(true)
    end

    it "deletes with force=true and answers {deleted, previous} — previous carries NO _links" do
      delete "/wp-json/wp/v2/categories/#{term.id}?force=true", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:ok)
      expect(json["deleted"]).to be(true)
      expect(json["previous"]).to include("id" => term.id, "name" => "Doomed", "slug" => "doomed")
      expect(json["previous"]).not_to have_key("_links")
      expect(Classification::Term.exists?(term.id)).to be(false)
    end

    # capabilities.php:738-744 — the taxonomy's DEFAULT term can never be deleted, by
    # anybody, and Access::TermPolicy is where that lives.
    it "refuses to delete the taxonomy's default term even for an administrator" do
      Configuration::Setting.set("default_category", term.id)
      delete "/wp-json/wp/v2/categories/#{term.id}?force=true", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_delete",
                         "message" => "Sorry, you are not allowed to delete this term.",
                         "data" => { "status" => 403 })
    end

    it "is rest_term_invalid (404) for an unknown id" do
      delete "/wp-json/wp/v2/categories/999999?force=true", headers: bearer(actor("con_admin"))
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("rest_term_invalid")
    end
  end

  describe "collection headers Gutenberg reads" do
    it "carries X-WP-Total, X-WP-TotalPages, Link and the CORS expose header" do
      3.times { |i| Classification::Term.create!(taxonomy: categories, name: "T#{i}", slug: "t#{i}") }
      get "/wp-json/wp/v2/categories?per_page=2"
      expect(response.headers["X-WP-Total"]).to eq("3")
      expect(response.headers["X-WP-TotalPages"]).to eq("2")
      expect(response.headers["Link"]).to include('rel="next"')
      expect(response.headers["Access-Control-Expose-Headers"]).to eq("X-WP-Total, X-WP-TotalPages, Link")
    end
  end
end
