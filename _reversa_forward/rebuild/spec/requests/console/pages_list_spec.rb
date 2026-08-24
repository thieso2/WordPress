# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit (pages variant) — the Pages list (edit.php?post_type=page). P-LIST over
# Publishing::Page, EXACT pagination. LITERAL "Pages" / "Add Page" / "No pages found." and
# NO category/tag columns (the page type registers no taxonomies).
RSpec.describe "console.edit (Pages list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def page!(title) = Publishing::Page.create!(author: actor("con_editor"), title: title, status: :published, published_at: Time.current)

  it "redirects an unauthenticated request to /login" do
    get "/console/pages"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL 'Pages' title and omits the taxonomy columns" do
    page!("About us")
    login_as("con_editor")
    get "/console/pages"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Pages")
    headers = header_labels
    expect(headers).to include("Title", "Author", "Date")
    expect(headers).not_to include("Categories")
    expect(headers).not_to include("Tags")
    expect(body_text).to include("About us")
  end

  it "shows the LITERAL 'No pages found.' empty-state" do
    login_as("con_editor")
    get "/console/pages"
    expect(body_text).to include("No pages found.")
  end

  # ── Defect 2 (page variant): '%s page moved to the Trash.' (edit.php:372-381) ────
  it "reports the verbatim page-noun bulk notice, not the generic 'item(s)'" do
    a = page!("Contact")
    b = page!("Team")
    login_as("con_editor")
    post "/console/pages/bulk", params: { bulk_action: "trash", ids: [a.id, b.id], confirmed: "1" }
    follow_redirect!
    expect(body_text).to include("2 pages moved to the Trash.")
    expect(body_text).not_to include("item(s)")
  end

  # ── Defect 8: hierarchical default ordering + nested indentation (:167, :849) ────
  it "orders pages hierarchically — a parent precedes its child, which is indented" do
    parent = Publishing::Page.create!(author: actor("con_editor"), title: "Parent page",
                                      status: :published, published_at: Time.current, menu_order: 0)
    Publishing::Page.create!(author: actor("con_editor"), title: "Child page",
                             status: :published, published_at: Time.current, menu_order: 0, parent: parent)
    login_as("con_editor")
    get "/console/pages"
    expect(response).to have_http_status(:ok)

    titles = doc.css(".column-title .row-title").map { |a| a.text.strip }
    expect(titles.index("Parent page")).to be < titles.index("Child page")

    child_cell = doc.css(".column-title").find { |td| td.text.include?("Child page") }
    parent_cell = doc.css(".column-title").find { |td| td.text.include?("Parent page") }
    # The child carries the em-dash indentation prefix; the (published) parent does not.
    expect(child_cell.text).to include("—")
    expect(parent_cell.text).not_to include("—")
  end

  it "keeps the flat sort when an explicit sortable column is chosen (?orderby=title)" do
    parent = Publishing::Page.create!(author: actor("con_editor"), title: "Zeta parent",
                                      status: :published, published_at: Time.current, menu_order: 0)
    Publishing::Page.create!(author: actor("con_editor"), title: "Alpha child",
                             status: :published, published_at: Time.current, menu_order: 0, parent: parent)
    login_as("con_editor")
    get "/console/pages?orderby=title&order=asc"
    titles = doc.css(".column-title .row-title").map { |a| a.text.strip }
    # Flat title sort: Alpha before Zeta regardless of parentage.
    expect(titles.index("Alpha child")).to be < titles.index("Zeta parent")
  end
end
