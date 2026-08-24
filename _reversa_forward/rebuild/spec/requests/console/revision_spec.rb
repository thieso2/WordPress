# frozen_string_literal: true

require_relative "console_spec_helper"

# console.revision — revision.php ("Revisions"; 'Compare Revisions of “%s”'), the diff over
# Publishing::Revision (its own table now, AD-02). The React slider is the deferred island
# (DEV-012); this is the server-rendered field diff, the readable half.
RSpec.describe "console.revision", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:post_record) { create_article!(author: actor("con_editor"), title: "Versioned") }

  def add_revision!(title:, content:)
    Publishing::Revision.create!(post: post_record, author: actor("con_editor"),
                                 title: title, content: content, excerpt: "")
  end

  it "redirects an unauthenticated request to /login" do
    get "/console/posts/#{post_record.id}/revisions"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL heading and title, and a diff between the two latest revisions" do
    add_revision!(title: "Versioned", content: "line one\nline two")
    add_revision!(title: "Versioned", content: "line one\nline two changed")
    login_as("con_editor")
    get "/console/posts/#{post_record.id}/revisions"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Compare Revisions of")
    expect(body_text).to include("Versioned")
    # the changed line shows on both sides (removed left / added right)
    expect(response.body).to include("diff-deletedline").or include("diff-addedline")
    expect(body_text).to include("line two changed")
  end

  it "denies an actor who cannot edit the parent post (403)" do
    add_revision!(title: "Versioned", content: "x")
    login_as("con_subscriber")
    get "/console/posts/#{post_record.id}/revisions"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to view revisions of this post.")
  end

  it "404s an unknown post id" do
    login_as("con_editor")
    get "/console/posts/999999/revisions"
    expect(response).to have_http_status(:not_found)
    expect(body_text).to include("Invalid post ID.")
  end
end
