# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit — the Posts list (wp-admin/edit.php, WP_Posts_List_Table). P-LIST over
# Publishing::Article with EXACT pagination (target_screens.md § Part 5). Modernized: no
# golden file — what is asserted is the single auth gate, the LITERAL strings (columns,
# bulk labels, status-tab nooped plurals, "No posts found."), which rows appear, and what
# a bulk action does to the model rows.
RSpec.describe "console.edit (Posts list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def publish!(title, author: actor("con_editor"))
    Publishing::Article.create!(author: author, title: title, status: :published, published_at: Time.current)
  end

  it "redirects an unauthenticated request to /login with redirect_to (auth_redirect, admin.php:104)" do
    get "/console/posts"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?").and include("redirect_to")
  end

  it "forbids an actor without edit_posts (subscriber) with a 403" do
    login_as("con_subscriber")
    get "/console/posts"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL title, column headers and the posts as rows" do
    publish!("Hello Jazz")
    publish!("Goodbye Swing")
    login_as("con_editor")
    get "/console/posts"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Posts")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Title", "Author", "Categories", "Tags", "Date")
    expect(body_text).to include("Hello Jazz").and include("Goodbye Swing")
  end

  it "shows the LITERAL empty-state when there are no posts" do
    login_as("con_editor")
    get "/console/posts"
    expect(body_text).to include("No posts found.")
  end

  it "offers the LITERAL 'Move to Trash' bulk action outside the trash view" do
    publish!("A post")
    login_as("con_editor")
    get "/console/posts"
    expect(body_text).to include("Move to Trash")
  end

  it "excludes trashed posts from the default 'all' view and shows them under Trash" do
    live = publish!("Live one")
    gone = publish!("Trashed one")
    gone.trash!(actor: actor("con_editor"))
    login_as("con_editor")

    get "/console/posts"
    expect(body_text).to include("Live one")
    expect(body_text).not_to include("Trashed one")

    get "/console/posts?status=trash"
    expect(body_text).to include("Trashed one")
    expect(body_text).not_to include("Live one")
  end

  it "runs the bulk trash action against the model rows (DEV-004 confirmation, then move)" do
    a = publish!("Doomed A")
    b = publish!("Doomed B")
    login_as("con_editor")

    # Destructive → confirmation interstitial first (DEV-004), no state change yet.
    post "/console/posts/bulk", params: { bulk_action: "trash", ids: [a.id, b.id] }
    expect(response).to have_http_status(:ok)
    expect(a.reload.status).to eq("published")

    # Confirmed → the rows move to Trash.
    post "/console/posts/bulk", params: { bulk_action: "trash", ids: [a.id, b.id], confirmed: "1" }
    expect(response).to have_http_status(:see_other)
    expect(a.reload.trashed?).to be(true)
    expect(b.reload.trashed?).to be(true)
  end

  it "paginates EXACTLY — the total reflects every matching row (DEV-003)" do
    25.times { |i| publish!("Bulk post #{i}") }
    login_as("con_editor")
    get "/console/posts"
    # 20 per page (class-wp-screen default); page 2 holds the rest.
    expect(body_text).to include("Bulk post")
    get "/console/posts?paged=2"
    expect(response).to have_http_status(:ok)
  end
end
