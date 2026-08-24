# frozen_string_literal: true

require_relative "console_spec_helper"

# console.edit-comments — the Comments list (edit-comments.php, WP_Comments_List_Table).
# P-LIST over Discussion::Comment, EXACT pagination. LITERAL columns / bulk labels / tabs /
# "No comments found." Approve/spam/trash change the model row's status.
RSpec.describe "console.edit-comments (Comments list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:article) { create_article! }

  it "redirects an unauthenticated request to /login" do
    get "/console/comments"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "forbids an actor without edit_posts (subscriber)" do
    login_as("con_subscriber")
    get "/console/comments"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL title, column headers and the comment rows" do
    create_comment!(post: article, author_name: "Alice", content: "First thought")
    login_as("con_editor")
    get "/console/comments"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Comments")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Author", "Comment", "In response to", "Submitted on")
    expect(body_text).to include("Alice").and include("First thought")
  end

  it "shows the LITERAL 'No comments found.' empty-state" do
    login_as("con_editor")
    get "/console/comments"
    expect(body_text).to include("No comments found.")
  end

  it "approves selected comments through the model (non-destructive, no confirm step)" do
    c = create_comment!(post: article, status: "pending")
    login_as("con_editor")
    post "/console/comments/bulk", params: { bulk_action: "approve", ids: [c.id] }
    expect(response).to have_http_status(:see_other)
    expect(c.reload.status).to eq("approved")
  end

  it "marks selected comments as spam only after the DEV-004 confirmation" do
    c = create_comment!(post: article, status: "approved")
    login_as("con_editor")
    post "/console/comments/bulk", params: { bulk_action: "spam", ids: [c.id] }
    expect(response).to have_http_status(:ok)          # interstitial
    expect(c.reload.status).to eq("approved")
    post "/console/comments/bulk", params: { bulk_action: "spam", ids: [c.id], confirmed: "1" }
    expect(response).to have_http_status(:see_other)
    expect(c.reload.status).to eq("spam")
  end
end
