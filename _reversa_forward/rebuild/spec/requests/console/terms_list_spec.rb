# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit-tags — the terms list (edit-tags.php, WP_Terms_List_Table). P-LIST over
# Classification::Term, EXACT pagination. LITERAL columns "Name / Description / Slug /
# Count". ⚠️ Count is PUBLISHED CONTENT ONLY (BR-MIGRATE-061).
RSpec.describe "console.edit-tags (Terms list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def post_tag_taxonomy
    Classification::Taxonomy.find_or_create_by!(name: "post_tag") { |t| t.hierarchical = false }
  end

  def create_tag!(name:, slug:)
    Classification::Term.create!(taxonomy: post_tag_taxonomy, name: name, slug: slug)
  end

  it "redirects an unauthenticated request to /login" do
    get "/console/terms/category"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "forbids an actor without manage_categories (subscriber)" do
    create_term!(name: "Jazz", slug: "jazz")
    login_as("con_subscriber")
    get "/console/terms/category"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL column headers and the terms as rows" do
    create_term!(name: "Jazz", slug: "jazz")
    create_term!(name: "Blues", slug: "blues")
    login_as("con_editor")
    get "/console/terms/category"
    expect(response).to have_http_status(:ok)
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Name", "Description", "Slug", "Count")
    expect(body_text).to include("Jazz").and include("Blues")
  end

  it "404s an unknown taxonomy" do
    login_as("con_editor")
    get "/console/terms/nope"
    expect(response).to have_http_status(:not_found)
  end

  # ── Defect 4: Description is a SORTABLE column (get_sortable_columns 'description'). ──
  it "renders the Description column header as a sort link" do
    create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    get "/console/terms/category"
    th = doc.at_css("th.column-description")
    expect(th["class"]).to include("sortable")
    expect(th.at_css("a")).not_to be_nil
    expect(th.at_css("a")["href"]).to include("orderby=description")
  end

  it "orders by description when asked" do
    create_term!(name: "Alpha", slug: "alpha", description: "zeta")
    create_term!(name: "Beta", slug: "beta", description: "alpha")
    login_as("con_editor")
    get "/console/terms/category", params: { orderby: "description", order: "asc" }
    expect(response).to have_http_status(:ok)
    names = doc.css("td.column-name a.row-title").map(&:text)
    expect(names).to eq(%w[Beta Alpha]) # description alpha < zeta
  end

  # ── Defect 5: the Count column is an <a> to the posts screen filtered by the term. ──
  it "wraps the count in a drill-down link (category → category_name query var)" do
    term = create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    get "/console/terms/category"
    cell = doc.at_css("td.column-count a")
    expect(cell).not_to be_nil
    expect(cell["href"]).to eq("/console/posts?category_name=jazz")
    expect(cell.text.strip).to eq(term.count.to_i.to_s)
  end

  it "uses the tag query var for post_tag counts" do
    create_tag!(name: "News", slug: "news")
    login_as("con_editor")
    get "/console/terms/post_tag"
    cell = doc.at_css("td.column-count a")
    expect(cell["href"]).to eq("/console/posts?tag=news")
  end

  # ── Defect 6: the View row action links to the term's public archive. ──
  it "offers a View row action to the public archive" do
    create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    get "/console/terms/category"
    view = doc.css(".row-actions .view a").first
    expect(view).not_to be_nil
    expect(view.text.strip).to eq("View")
    expect(view["href"]).to eq("/category/jazz")
  end

  it "points the post_tag View action at the tag archive" do
    create_tag!(name: "News", slug: "news")
    login_as("con_editor")
    get "/console/terms/post_tag"
    view = doc.css(".row-actions .view a").first
    expect(view["href"]).to eq("/tag/news")
  end

  # ── Defect 2: Quick Edit — the hidden inline data block and the affordance. ──
  it "emits the hidden inline data block and a Quick Edit affordance" do
    term = create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    get "/console/terms/category"
    block = doc.at_css("#inline_#{term.id}")
    expect(block).not_to be_nil
    expect(block.at_css(".name").text).to eq("Jazz")
    expect(block.at_css(".slug").text).to eq("jazz")
    expect(doc.at_css(".row-actions .editinline")).not_to be_nil
  end

  # ── Defect 1: the inline Add form (Name / Slug / Parent / Description). ──
  it "renders the Add Category form with all fields" do
    category_taxonomy
    login_as("con_editor")
    get "/console/terms/category"
    expect(doc.at_css("h2").text).to eq("Add Category")
    expect(doc.at_css("form input[name=name]")).not_to be_nil
    expect(doc.at_css("form input[name=slug]")).not_to be_nil
    expect(doc.at_css("form select[name=parent]")).not_to be_nil # category is hierarchical
    expect(doc.at_css("form textarea[name=description]")).not_to be_nil
    submits = doc.css("form button[type=submit]").map { |b| b.text.strip }
    expect(submits).to include("Add Category")
  end

  it "labels the Add form for tags (non-hierarchical, no parent field)" do
    post_tag_taxonomy
    login_as("con_editor")
    get "/console/terms/post_tag"
    expect(doc.at_css("h2").text).to eq("Add Tag")
    expect(doc.at_css("form select[name=parent]")).to be_nil
  end

  # ── Defect 3: the post-delete flash strings (edit-tag-messages 2 and 6). ──
  it "shows the single-delete message (message 2) after a single-row Delete" do
    term = create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    post "/console/terms/category/bulk",
         params: { bulk_action: "delete", single: "1", confirmed: "1", ids: [term.id] }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(body_text).to include("Category deleted.")
    expect(body_text).not_to include("item(s) deleted")
    expect(Classification::Term.where(id: term.id)).to be_empty
  end

  it "shows the bulk-delete message (message 6) after a bulk Delete" do
    a = create_term!(name: "Jazz", slug: "jazz")
    b = create_term!(name: "Blues", slug: "blues")
    login_as("con_editor")
    post "/console/terms/category/bulk",
         params: { bulk_action: "delete", confirmed: "1", ids: [a.id, b.id] }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(body_text).to include("Categories deleted.")
    expect(body_text).not_to include("item(s) deleted")
  end

  it "uses the Tag wording for post_tag deletes" do
    tag = create_tag!(name: "News", slug: "news")
    login_as("con_editor")
    post "/console/terms/post_tag/bulk",
         params: { bulk_action: "delete", single: "1", confirmed: "1", ids: [tag.id] }
    follow_redirect!
    expect(body_text).to include("Tag deleted.")
  end

  # ── Defect 1: create through wp_insert_term (needs the POST create route wired). ──
  it "creates a category through the Add form" do
    category_taxonomy
    login_as("con_editor")
    post "/console/terms/category", params: { name: "Reggae", slug: "reggae", description: "Off-beat" }
    expect(response).to have_http_status(:see_other)
    term = Classification::Term.find_by(slug: "reggae")
    expect(term).not_to be_nil
    expect(term.name).to eq("Reggae")
    follow_redirect!
    expect(body_text).to include("Category added.")
  end

  it "derives the slug from the name when the slug field is blank" do
    category_taxonomy
    login_as("con_editor")
    post "/console/terms/category", params: { name: "Deep House" }
    expect(response).to have_http_status(:see_other)
    expect(Classification::Term.find_by(name: "Deep House")&.slug).to eq("deep-house")
  end

  it "surfaces the uniqueness message when a duplicate slug is added" do
    create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    post "/console/terms/category", params: { name: "Jazz2", slug: "jazz" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("must be unique within its taxonomy and parent")
  end

  it "denies create to an actor without manage_categories with the LITERAL wp_die" do
    category_taxonomy
    login_as("con_subscriber")
    post "/console/terms/category", params: { name: "X", slug: "x" }
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to create terms in this taxonomy.")
  end

  # ── Defect 2: Quick Edit inline save (needs the POST inline route wired). ──
  it "saves name/slug through the inline-save endpoint and returns the updated row" do
    term = create_term!(name: "Jazz", slug: "jazz")
    login_as("con_editor")
    post "/console/terms/category/#{term.id}/inline", params: { name: "Swing", slug: "swing" }
    expect(response).to have_http_status(:ok)
    term.reload
    expect(term.name).to eq("Swing")
    expect(term.slug).to eq("swing")
    expect(response.body).to include("Swing")
  end

  it "denies inline save to an actor without edit rights" do
    term = create_term!(name: "Jazz", slug: "jazz")
    login_as("con_subscriber")
    post "/console/terms/category/#{term.id}/inline", params: { name: "Swing" }
    expect(response).to have_http_status(:forbidden)
    expect(term.reload.name).to eq("Jazz")
  end
end
