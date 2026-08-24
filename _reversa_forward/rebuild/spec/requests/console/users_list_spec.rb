# frozen_string_literal: true

require_relative "console_spec_helper"

# console.users — the Users list (users.php, WP_Users_List_Table). P-LIST over
# Identity::User, EXACT pagination. list_users is administrator-only. LITERAL columns
# "Username / Name / Email / Role / Posts", role filter tabs, "No users found."
RSpec.describe "console.users (Users list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/users"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "forbids an actor without list_users (editor)" do
    login_as("con_editor")
    get "/console/users"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL title, column headers and the seeded accounts as rows" do
    login_as("con_admin")
    get "/console/users"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Users")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Username", "Name", "Email", "Role", "Posts")
    expect(body_text).to include("con_admin").and include("con_editor").and include("con_subscriber")
  end

  it "filters to a role tab (Subscriber) showing only that role's members" do
    login_as("con_admin")
    get "/console/users?role=subscriber"
    expect(response).to have_http_status(:ok)
    expect(body_text).to include("con_subscriber")
    expect(body_text).not_to include("con_editor@example.com")
  end
end
