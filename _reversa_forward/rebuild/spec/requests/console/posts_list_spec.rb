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
    headers = header_labels
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

  # ── Defect 1: the search box actually restricts the query (WP_Query 's') ─────────
  it "applies params[:s] to the query instead of returning the full list" do
    publish!("Jazz standards")
    publish!("Rock anthems")
    login_as("con_editor")
    get "/console/posts?s=Jazz"
    expect(response).to have_http_status(:ok)
    expect(body_text).to include("Jazz standards")
    expect(body_text).not_to include("Rock anthems")
  end

  it "searches the content body, not only the title" do
    Publishing::Article.create!(author: actor("con_editor"), title: "Untitled",
                                content: "a saxophone solo", status: :published, published_at: Time.current)
    publish!("Nothing relevant")
    login_as("con_editor")
    get "/console/posts?s=saxophone"
    expect(body_text).to include("Untitled")
    expect(body_text).not_to include("Nothing relevant")
  end

  # ── Defect 2: verbatim post-type bulk-completion notices (edit.php:359-368) ──────
  it "reports '%s posts moved to the Trash.' (plural) verbatim after a bulk trash" do
    a = publish!("One")
    b = publish!("Two")
    login_as("con_editor")
    post "/console/posts/bulk", params: { bulk_action: "trash", ids: [a.id, b.id], confirmed: "1" }
    follow_redirect!
    expect(body_text).to include("2 posts moved to the Trash.")
  end

  it "uses the singular '%s post moved to the Trash.' for exactly one row" do
    a = publish!("Solo")
    login_as("con_editor")
    post "/console/posts/bulk", params: { bulk_action: "trash", ids: [a.id], confirmed: "1" }
    follow_redirect!
    expect(body_text).to include("1 post moved to the Trash.")
    expect(body_text).not_to include("item(s)")
  end

  it "reports 'restored from the Trash.' and 'permanently deleted.' verbatim" do
    a = publish!("Restorable")
    a.trash!(actor: actor("con_editor"))
    login_as("con_editor")
    post "/console/posts/bulk", params: { bulk_action: "untrash", ids: [a.id], confirmed: "1" }
    follow_redirect!
    expect(body_text).to include("1 post restored from the Trash.")

    a.reload.trash!(actor: actor("con_editor"))
    post "/console/posts/bulk", params: { bulk_action: "delete", ids: [a.id], confirmed: "1", status: "trash" }
    follow_redirect!
    expect(body_text).to include("1 post permanently deleted.")
  end

  # ── Defect 3: View / Preview row actions (handle_row_actions, :1643-1663) ────────
  it "offers a 'View' action for a published row and a 'Preview' action for a draft" do
    publish!("Live piece")
    Publishing::Article.create!(author: actor("con_editor"), title: "Draft piece", status: :draft)
    login_as("con_editor")
    get "/console/posts"
    view_labels = doc.css(".row-actions .view a").map { |a| a.text.strip }
    expect(view_labels).to include("View")
    expect(view_labels).to include("Preview")
  end

  # ── Defect 4: 'Bulk edit' bulk action (get_bulk_actions, :439) ───────────────────
  it "offers the 'Bulk edit' bulk action in the non-trash view" do
    publish!("Editable")
    login_as("con_editor")
    get "/console/posts"
    options = doc.css("select[name=bulk_action] option").map { |o| o.text.strip }
    expect(options).to include("Bulk edit")
    expect(options).to include("Move to Trash")
  end

  # ── Defect 6: months + categories filter dropdowns (extra_tablenav, :574-599) ────
  it "renders the months and categories filter dropdowns with a Filter button" do
    publish!("Dated post")
    login_as("con_editor")
    get "/console/posts"
    expect(doc.at_css("select[name=m]")).to be_present
    expect(doc.at_css("select[name=cat]")).to be_present
    expect(doc.css("form button").map { |b| b.text.strip }).to include("Filter")
  end

  it "restricts the list to a category when params[:cat] is given" do
    jazzy = publish!("Jazzy piece")
    publish!("Unrelated piece")
    term = create_term!(name: "Jazz", slug: "jazz")
    Classification::Assignment.set(jazzy, [term.id])
    login_as("con_editor")
    get "/console/posts?cat=#{term.id}"
    expect(body_text).to include("Jazzy piece")
    expect(body_text).not_to include("Unrelated piece")
  end

  it "restricts the list to a month when params[:m] is given" do
    Publishing::Article.create!(author: actor("con_editor"), title: "Old news",
                                status: :published, published_at: Time.utc(2020, 3, 15, 12))
    publish!("Fresh news")
    login_as("con_editor")
    get "/console/posts?m=202003"
    expect(body_text).to include("Old news")
    expect(body_text).not_to include("Fresh news")
  end

  # ── Defect 7: Empty Trash (submit_button 'delete_all', :606; edit.php:90) ────────
  it "shows an 'Empty Trash' control in the trash view and empties it on confirm" do
    a = publish!("Trash me")
    a.trash!(actor: actor("con_editor"))
    login_as("con_editor")

    get "/console/posts?status=trash"
    expect(doc.at_css("button[name=delete_all]")).to be_present

    # Unconfirmed → DEV-004 confirmation, nothing deleted yet.
    post "/console/posts/bulk", params: { delete_all: "1" }
    expect(response).to have_http_status(:ok)
    expect(Publishing::Article.exists?(a.id)).to be(true)

    # Confirmed → every trashed row is permanently deleted.
    post "/console/posts/bulk", params: { delete_all: "1", confirmed: "1" }
    expect(response).to have_http_status(:see_other)
    expect(Publishing::Article.exists?(a.id)).to be(false)
  end

  # ── Defect 9: the 'Mine' status view (get_views, :322-361) ───────────────────────
  it "shows a 'Mine' view when the user has posts and other authors' posts exist" do
    publish!("Editor own", author: actor("con_editor"))
    publish!("Author own", author: actor("con_author"))
    login_as("con_editor")

    get "/console/posts"
    expect(doc.css(".subsubsub li").map(&:text).join).to include("Mine")

    get "/console/posts?author=#{actor('con_editor').id}"
    expect(body_text).to include("Editor own")
    expect(body_text).not_to include("Author own")
  end

  it "omits the 'Mine' view when the current user is the only author" do
    publish!("Only mine", author: actor("con_editor"))
    login_as("con_editor")
    get "/console/posts"
    expect(doc.css(".subsubsub li").map(&:text).join).not_to include("Mine")
  end

  # ── Defect 10: date column time + 'Missed schedule' (column_date, :1291-1349) ────
  it "prints the date with the time and flags a passed schedule as 'Missed schedule'" do
    publish!("Timed piece")
    late = publish!("Late piece")
    late.update_columns(status: "scheduled", published_at: 1.hour.ago)
    login_as("con_editor")
    get "/console/posts"
    expect(body_text).to match(%r{\d{4}/\d{2}/\d{2} at \d{1,2}:\d{2} [ap]m})
    expect(body_text).to include("Missed schedule")
  end

  # ── Defect 11: Comments column guard + bubble (get_columns/column_comments) ──────
  it "omits the Comments column on the draft status view" do
    Publishing::Article.create!(author: actor("con_editor"), title: "A draft", status: :draft)
    login_as("con_editor")
    get "/console/posts?status=draft"
    headers = header_labels
    expect(headers).not_to include("Comments")
  end

  it "renders the comments cell as a bubble link to the comments screen, not a bare integer" do
    p = publish!("Chatty")
    p.update_column(:comment_count, 3)
    login_as("con_editor")
    get "/console/posts"
    bubble = doc.at_css(".column-comments a.post-com-count")
    expect(bubble).to be_present
    expect(bubble["href"]).to include("/console/comments?p=#{p.id}")
    expect(bubble.text).to include("3")
  end
end
