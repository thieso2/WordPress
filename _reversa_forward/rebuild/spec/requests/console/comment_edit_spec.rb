# frozen_string_literal: true

require_relative "console_spec_helper"

# console.comment — edit-form-comment.php (:22 title, :48 "Author", :60/:66/:72 field
# labels, :406 "Update"), saved through edit_comment() (includes/comment.php:54).
RSpec.describe "console.comment", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:comment) { create_comment! }

  it "redirects an unauthenticated request to /login (auth_redirect, admin.php:104)" do
    get "/console/comments/#{comment.id}/edit"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
    expect(response.headers["Location"]).to include("redirect_to=")
  end

  it "renders the LITERAL page title and field labels" do
    login_as("con_editor")
    get "/console/comments/#{comment.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Edit Comment")
    expect(body_text).to include("Author").and include("Name").and include("Email").and include("URL")
    expect(body_text).to include("Save").and include("Status:")
    expect(doc.at_css("button[type=submit]").text.strip).to eq("Update")
    # the current values are pre-filled
    expect(doc.at_css("#name")["value"]).to eq("Jane")
    expect(doc.at_css("#email")["value"]).to eq("jane@example.com")
  end

  it "saves the edited fields and status through the model (row state matches)" do
    login_as("con_editor")
    patch "/console/comments/#{comment.id}", params: {
      newcomment_author: "Janet", newcomment_author_email: "janet@example.com",
      newcomment_author_url: "https://janet.example", content: "Edited body",
      comment_status: "1"
    }
    expect(response).to have_http_status(:see_other)
    comment.reload
    expect(comment.author_name).to eq("Janet")
    expect(comment.author_email).to eq("janet@example.com")
    expect(comment.content).to eq("Edited body")
    expect(comment.status).to eq("approved") # legacy '1' → approved
  end

  it "denies an actor without edit_comment with the LITERAL wp_die message (403)" do
    login_as("con_subscriber")
    get "/console/comments/#{comment.id}/edit"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to edit this comment.")
  end

  it "404s an id that names no comment" do
    login_as("con_editor")
    get "/console/comments/999999/edit"
    expect(response).to have_http_status(:not_found)
    expect(body_text).to include("Invalid comment ID.")
  end

  # ── Defect 10 — the submitdelete link in the editor (edit-form-comment.php:403). With
  # trash enabled the label is the LITERAL "Move to Trash"; it posts to the shared bulk
  # endpoint (a trash, routed through the DEV-004 confirmation).
  it "renders the 'Move to Trash' delete link in the editor" do
    login_as("con_editor")
    get "/console/comments/#{comment.id}/edit"
    del = doc.at_css("#delete-action .submitdelete")
    expect(del).to be_present
    expect(del.text.strip).to eq("Move to Trash")
    form = del.ancestors("form").first
    expect(form["action"]).to eq("/console/comments/bulk")
  end

  it "trashing from the editor goes through the confirmation and then trashes" do
    login_as("con_editor")
    # the delete link posts an unconfirmed trash → interstitial (DEV-004)
    post "/console/comments/bulk", params: { bulk_action: "trash", confirmed: "0", ids: [comment.id] }
    expect(response).to have_http_status(:ok)
    expect(comment.reload.status).not_to eq("trashed")
    post "/console/comments/bulk", params: { bulk_action: "trash", confirmed: "1", ids: [comment.id] }
    expect(response).to have_http_status(:see_other)
    expect(comment.reload.status).to eq("trashed")
  end

  # ── Defect 3 — the Reply row action leads to a reply endpoint that creates a child
  # comment (class-wp-comments-list-table.php:871). Needs the reply route the integrator
  # applies (routes_to_add / declarations_to_add); skipped until then so the suite stays
  # green in isolation.
  context "the Reply endpoint (requires the applied reply route)" do
    before do
      unless Rails.application.routes.url_helpers.respond_to?(:reply_console_comment_path)
        skip "reply route pending integrator (see routes_to_add/declarations_to_add)"
      end
    end

    it "renders a reply form with the LITERAL Comment/Reply strings" do
      login_as("con_editor")
      get "/console/comments/#{comment.id}/reply"
      expect(response).to have_http_status(:ok)
      expect(body_text).to include("Comment").and include("Reply")
    end

    it "creates a child comment on the parent's post" do
      login_as("con_editor")
      parent = comment # materialise the lazy `let` BEFORE counting, or its own row counts
      expect do
        post "/console/comments/#{parent.id}/reply", params: { content: "A moderator reply" }
      end.to change { Discussion::Comment.count }.by(1)
      expect(response).to have_http_status(:see_other)
      child = Discussion::Comment.order(:id).last
      expect(child.parent_id).to eq(comment.id)
      expect(child.post_id).to eq(comment.post_id)
      expect(child.content).to eq("A moderator reply")
    end

    it "denies a subscriber the reply form (edit_comment gate)" do
      login_as("con_subscriber")
      get "/console/comments/#{comment.id}/reply"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
