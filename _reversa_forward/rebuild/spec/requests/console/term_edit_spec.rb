# frozen_string_literal: true

require_relative "console_spec_helper"

# console.term — edit-tag-form.php (:72 edit_item, :150 "Name", :155 "Slug", :178
# parent_item, :206 "Description", :301 "Update"), saved through wp_update_term(). Unique on
# (taxonomy, parent, slug) — the model's message is surfaced verbatim.
RSpec.describe "console.term", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:term) { create_term!(name: "Jazz", slug: "jazz") }

  it "redirects an unauthenticated request to /login" do
    get "/console/terms/category/#{term.id}/edit"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL category labels" do
    login_as("con_editor")
    get "/console/terms/category/#{term.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Edit Category")
    expect(body_text).to include("Name").and include("Slug").and include("Parent Category").and include("Description")
    expect(doc.at_css("button[type=submit]").text.strip).to eq("Update")
    expect(doc.at_css("#name")["value"]).to eq("Jazz")
  end

  it "saves the edited name/slug/description through the model" do
    login_as("con_editor")
    patch "/console/terms/category/#{term.id}", params: { name: "Bebop", slug: "bebop", description: "A style" }
    expect(response).to have_http_status(:see_other)
    term.reload
    expect(term.name).to eq("Bebop")
    expect(term.slug).to eq("bebop")
    expect(term.description).to eq("A style")
  end

  it "surfaces the model's (taxonomy,parent,slug) uniqueness message verbatim" do
    other = create_term!(name: "Swing", slug: "swing")
    login_as("con_editor")
    patch "/console/terms/category/#{term.id}", params: { name: "Jazz", slug: "swing" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("must be unique within its taxonomy and parent")
    expect(term.reload.slug).to eq("jazz")
    expect(other.reload.slug).to eq("swing")
  end

  it "denies an actor without manage_categories (403, LITERAL wp_die)" do
    login_as("con_subscriber")
    get "/console/terms/category/#{term.id}/edit"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to edit this item.")
  end

  it "404s an unknown taxonomy" do
    login_as("con_editor")
    get "/console/terms/nope/#{term.id}/edit"
    expect(response).to have_http_status(:not_found)
    expect(body_text).to include("Invalid taxonomy.")
  end
end
