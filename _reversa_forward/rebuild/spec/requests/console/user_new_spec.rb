# frozen_string_literal: true

require_relative "console_spec_helper"

# console.user-new — user-new.php single-site "Add User" ("Username","Email","Password",
# "Add User"), created through edit_user() with no id. Verbatim validation strings.
RSpec.describe "console.user-new", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "renders the LITERAL title, required labels and submit button" do
    login_as("con_admin")
    get "/console/users/new"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to eq("Add User")
    expect(body_text).to include("Username").and include("Email").and include("Password").and include("Role")
    expect(doc.at_css("button[type=submit]").text.strip).to eq("Add User")
  end

  it "creates the user and assigns the role (a ROW)" do
    login_as("con_admin")
    expect {
      post "/console/users", params: { user_login: "newbie", email: "newbie@example.com",
                                       pass1: "s3cret-pass", pass2: "s3cret-pass", role: "author" }
    }.to change(Identity::User, :count).by(1)
    expect(response).to have_http_status(:see_other)
    created = Identity::User.find_by(login: "newbie")
    expect(created.email).to eq("newbie@example.com")
    expect(created.roles).to eq(["author"])
    expect(created.authenticate_and_upgrade("s3cret-pass")).to be_truthy
  end

  it "rejects a duplicate username with the LITERAL message, creating nothing" do
    login_as("con_admin")
    expect {
      post "/console/users", params: { user_login: "con_editor", email: "x@example.com",
                                       pass1: "s3cret-pass", pass2: "s3cret-pass" }
    }.not_to change(Identity::User, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("This username is already registered. Please choose another one.")
  end

  it "rejects a blank password with the LITERAL message" do
    login_as("con_admin")
    post "/console/users", params: { user_login: "nopass", email: "nopass@example.com", pass1: "", pass2: "" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("Please enter a password.")
  end

  it "rejects a missing email with the LITERAL message" do
    login_as("con_admin")
    post "/console/users", params: { user_login: "noemail", email: "", pass1: "s3cret-pass", pass2: "s3cret-pass" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(body_text).to include("Please enter an email address.")
  end

  it "denies a subscriber (create_users), 403" do
    login_as("con_subscriber")
    get "/console/users/new"
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to create users.")
  end
end
