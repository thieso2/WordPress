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
end
