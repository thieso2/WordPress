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

  # The row-actions cell (rendered under the primary column) as one text blob.
  def row_actions_text
    doc.css(".row-actions").map(&:text).join(" ")
  end

  # ── Defects 1/2 — spam and trash row actions (class-wp-comments-list-table.php:814/824/834).
  it "shows Not Spam + Delete Permanently (not Edit / not Spam) on a spam row" do
    create_comment!(post: article, status: "spam", content: "Spammy body")
    login_as("con_editor")
    get "/console/comments?status=spam"
    expect(response).to have_http_status(:ok)
    text = row_actions_text
    expect(text).to include("Not Spam").and include("Delete Permanently")
    expect(text).not_to include("Edit")
    # the no-op 'Spam' link must be gone on an already-spam row: the 'unspam' action
    # renders (span.unspam) but the plain 'spam' action must not (span.spam).
    expect(doc.at_css(".row-actions .unspam")).to be_present
    expect(doc.at_css(".row-actions .spam")).to be_nil
    expect(doc.at_css(".row-actions .delete")).to be_present
    expect(text).not_to include("Restore")
  end

  it "shows Restore + Delete Permanently (not Edit) on a trash row" do
    create_comment!(post: article, status: "trashed", content: "Trashed body")
    login_as("con_editor")
    get "/console/comments?status=trash"
    expect(response).to have_http_status(:ok)
    text = row_actions_text
    expect(text).to include("Restore").and include("Delete Permanently")
    expect(text).not_to include("Edit")
  end

  # ── Defect 4 — the All view offers BOTH Approve and Unapprove on every row (:786).
  it "renders both Approve and Unapprove on the All view" do
    create_comment!(post: article, status: "pending")
    login_as("con_editor")
    get "/console/comments"
    text = row_actions_text
    expect(text).to include("Approve").and include("Unapprove").and include("Edit")
  end

  # ── Defect 3 — Reply and Quick Edit row actions on non-spam/non-trash rows (:861/:871).
  it "renders Reply and Quick Edit row actions on a normal row" do
    create_comment!(post: article, status: "pending")
    login_as("con_editor")
    get "/console/comments"
    text = row_actions_text
    expect(text).to include("Reply").and include("Quick Edit")
    expect(doc.at_css(".row-actions .reply a")).to be_present
    expect(doc.at_css(".row-actions .quickedit a")).to be_present
  end

  # ── Defect 7 — the 'Mine' status tab filters to the current user's own comments (:250).
  it "lists a 'Mine' tab and filters to the actor's own comments (user_id)" do
    editor = actor("con_editor")
    create_comment!(post: article, user: editor, content: "My own note")
    create_comment!(post: article, content: "Someone else's note")
    login_as("con_editor")
    get "/console/comments"
    expect(doc.css(".subsubsub").text).to include("Mine")
    get "/console/comments?status=mine"
    expect(body_text).to include("My own note")
    expect(body_text).not_to include("Someone else's note")
  end

  # ── Defect 8 — Author and 'In response to' columns are sortable (:574).
  it "marks Author and 'In response to' columns sortable" do
    login_as("con_editor")
    get "/console/comments"
    expect(doc.at_css("th.column-author.sortable a")).to be_present
    expect(doc.at_css("th.column-response.sortable a")).to be_present
  end

  it "orders by author when orderby=author is requested" do
    create_comment!(post: article, author_name: "Zoe", content: "z-body")
    create_comment!(post: article, author_name: "Amy", content: "a-body")
    login_as("con_editor")
    get "/console/comments?orderby=author&order=asc"
    names = doc.css("td.column-author strong").map(&:text)
    expect(names.index("Amy")).to be < names.index("Zoe")
  end

  # ── Defect 5 — the comment-type filter dropdown (:521) and its LITERAL strings.
  it "renders the comment-type dropdown with its LITERAL options and a Filter button" do
    create_comment!(post: article)
    login_as("con_editor")
    get "/console/comments"
    select = doc.at_css("select#filter-by-comment-type")
    expect(select).to be_present
    expect(select.css("option").map(&:text).map(&:strip)).to eq(["All comment types", "Comments", "Pings"])
    expect(body_text).to include("Filter")
  end

  it "filters to pings when comment_type=pings" do
    create_comment!(post: article, kind: "comment", content: "Real comment")
    create_comment!(post: article, kind: "pingback", content: "A pingback")
    login_as("con_editor")
    get "/console/comments?comment_type=pings"
    expect(body_text).to include("A pingback")
    expect(body_text).not_to include("Real comment")
  end

  # ── Defect 6 — Empty Spam / Empty Trash purge submit (:449).
  it "shows the 'Empty Spam' submit on the Spam view when items exist" do
    create_comment!(post: article, status: "spam")
    login_as("con_editor")
    get "/console/comments?status=spam"
    expect(body_text).to include("Empty Spam")
  end

  it "shows the 'Empty Trash' submit on the Trash view when items exist" do
    create_comment!(post: article, status: "trashed")
    login_as("con_editor")
    get "/console/comments?status=trash"
    expect(body_text).to include("Empty Trash")
  end

  it "empties the Spam view through the DEV-004 confirmation" do
    c = create_comment!(post: article, status: "spam")
    login_as("con_editor")
    post "/console/comments/bulk", params: { status: "spam", delete_all: "1" }
    expect(response).to have_http_status(:ok) # confirmation interstitial
    expect(Discussion::Comment.exists?(c.id)).to be(true)
    post "/console/comments/bulk", params: { bulk_action: "delete", ids: [c.id], confirmed: "1" }
    expect(response).to have_http_status(:see_other)
    expect(Discussion::Comment.exists?(c.id)).to be(false)
  end

  # ── Defect 9 — unspam/untrash restore the PRIOR status, not always pending
  # (comment.php:326/:340 wp_untrash_comment / wp_unspam_comment).
  it "restores an approved comment from Spam back to approved (not pending)" do
    c = create_comment!(post: article, status: "pending")
    c.approve!            # records an 'approved' verdict
    c.mark_spam!          # now spam
    login_as("con_editor")
    post "/console/comments/bulk", params: { status: "spam", bulk_action: "unspam", ids: [c.id] }
    expect(response).to have_http_status(:see_other)
    expect(c.reload.status).to eq("approved")
  end

  it "restores an approved comment from Trash back to approved (not pending)" do
    c = create_comment!(post: article, status: "pending")
    c.approve!
    c.trash!
    login_as("con_editor")
    post "/console/comments/bulk", params: { status: "trash", bulk_action: "untrash", ids: [c.id] }
    expect(response).to have_http_status(:see_other)
    expect(c.reload.status).to eq("approved")
  end

  it "restores a pending comment from Spam back to pending" do
    c = create_comment!(post: article, status: "pending")
    c.unapprove!          # records a 'pending' verdict
    c.mark_spam!
    login_as("con_editor")
    post "/console/comments/bulk", params: { status: "spam", bulk_action: "unspam", ids: [c.id] }
    expect(response).to have_http_status(:see_other)
    expect(c.reload.status).to eq("pending")
  end
end
