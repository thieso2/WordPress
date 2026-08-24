# frozen_string_literal: true

require_relative "console_spec_helper"

# console.user-edit — user-edit.php ("Edit User"; Personal Options/Name/Contact Info/Account
# Management; "Update User"), saved through edit_user( $id ). Roles are ROWS.
RSpec.describe "console.user-edit", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  let(:target) { actor("con_subscriber") }

  it "redirects an unauthenticated request to /login" do
    get "/console/users/#{target.id}/edit"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "renders the LITERAL title, section headings and submit label" do
    login_as("con_admin")
    get "/console/users/#{target.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Edit User")
    expect(body_text).to include("Personal Options").and include("Contact Info").and include("Account Management")
    expect(body_text).to include("Display name publicly as").and include("Website").and include("New Password")
    expect(doc.at_css(".console-main button[type=submit]").text.strip).to eq("Update User")
  end

  it "⚠️ DEV-008: no admin_color field is rendered" do
    login_as("con_admin")
    get "/console/users/#{target.id}/edit"
    expect(response.body).not_to include("admin_color")
    expect(body_text).not_to include("Admin Color Scheme")
  end

  it "saves email, website, display name through the model" do
    login_as("con_admin")
    patch "/console/users/#{target.id}", params: { email: "changed@example.com", url: "example.org", display_name: "Subby" }
    expect(response).to have_http_status(:see_other)
    target.reload
    expect(target.email).to eq("changed@example.com")
    expect(target.url).to eq("http://example.org") # scheme ensured, includes/user.php:615
    expect(target.display_name).to eq("Subby")
  end

  it "replaces the role (rows) when promoting" do
    login_as("con_admin")
    patch "/console/users/#{target.id}", params: { role: "author" }
    expect(response).to have_http_status(:see_other)
    expect(target.reload.roles).to eq(["author"])
  end

  it "surfaces the LITERAL invalid-email message" do
    login_as("con_admin")
    patch "/console/users/#{target.id}", params: { email: "not-an-email" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("The email address is not correct.")
    expect(target.reload.email).to eq("con_subscriber@example.com")
  end

  it "surfaces the LITERAL password-mismatch message" do
    login_as("con_admin")
    patch "/console/users/#{target.id}", params: { pass1: "abc12345", pass2: "different" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("Passwords do not match. Please enter the same password in both password fields.")
  end

  it "denies a subscriber editing ANOTHER user (edit_users), 403" do
    login_as("con_subscriber")
    get "/console/users/#{actor('con_author').id}/edit"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to edit this user.")
  end

  it "BR-CAP-07: a user may edit THEMSELVES with no capability (empty set ALLOWS)" do
    login_as("con_subscriber")
    get "/console/users/#{actor('con_subscriber').id}/edit"
    expect(response).to have_http_status(:ok)
  end

  it "refuses an ineligible role with the LITERAL wp_die message (403), saving nothing" do
    login_as("con_admin")
    patch "/console/users/#{target.id}", params: { role: "wizard" }
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to give users that role.")
    expect(target.reload.roles).to eq(["subscriber"])
  end
end
