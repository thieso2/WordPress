# frozen_string_literal: true

require_relative "auth_spec_helper"

# auth.register -- wp-login.php `case 'register'` (:1095-1201). The validation strings
# are compared against the oracle's register_new_user() in
# spec/models/identity/registration_differential_spec.rb; this spec covers the SCREEN:
# the gate, the redirect, the form, the notifications and the check-email exit.
RSpec.describe "auth.register", type: :request do
  before do
    skip "the PHP oracle is not available" unless oracle_available?
    seed_oracle_users!
    host! "127.0.0.1"
    ActionMailer::Base.deliveries.clear
  end

  it "bounces to the login screen's registration=disabled error when users_can_register is off, as the oracle does" do
    oracle = AuthOracle.get("/wp-login.php?action=register")
    expect(oracle.status).to eq(302)
    expect(oracle.location).to end_with("wp-login.php?registration=disabled")

    get "/register"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/login?registration=disabled")
    post "/register", params: { user_login: "newbie", user_email: "newbie@example.com" }
    expect(response).to have_http_status(:found)
    follow_redirect!
    expect(error_notice).to eq("<p><strong>Error:</strong> User registration is currently not allowed.</p>")
  end

  context "when registration is open" do
    before { Configuration::Setting.set("users_can_register", "1") }

    it "renders the literal form" do
      get "/register"
      expect(response).to have_http_status(:ok)
      expect(page_title).to start_with("Registration Form")
      expect(response.body).to include("Register For This Site").and include(">Username<").and include(">Email<")
        .and include("Registration confirmation will be emailed to you.").and include('value="Register"')
        .and include("Lost your password?")
    end

    it "re-renders with the legacy error and both typed values kept" do
      post "/register", params: { user_login: "bad name!", user_email: "not-an-email" }
      expect(response).to have_http_status(:unprocessable_content)
      # Two errors -> the list branch. The strings are verified against the oracle's
      # register_new_user() in registration_differential_spec; here the notice must
      # carry both, in order.
      expect(error_notice).to start_with("<ul class=\"login-error-list\">").and end_with("</ul>")
      expect(error_notice).to include("<strong>Error:</strong> This username is invalid because it uses illegal characters. Please enter a valid username.")
        .and include("<strong>Error:</strong> The email address is not correct.")
      expect(field("user_login")).to eq("bad name!")
      expect(field("user_email")).to eq("not-an-email")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "creates the user with the default role, mails both notifications and routes to auth.checkemail" do
      post "/register", params: { user_login: "Newbie One", user_email: "newbie@example.com" }
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/login/check-email?checkemail=registered")

      user = Identity::User.find_by!(login: "Newbie One")
      expect(user.roles).to eq(["subscriber"])
      expect(user.display_name).to eq("Newbie One")
      expect(user.nicename).to eq("newbie-one")

      subjects = ActionMailer::Base.deliveries.map { |m| [m.to, m.subject] }
      expect(subjects).to include([["oracle@example.com"], "[Reversa Oracle \"7.2\" 😀] New User Registration"])
      expect(subjects).to include([["newbie@example.com"], "[Reversa Oracle \"7.2\" 😀] Login Details"])
      admin_mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("New User Registration") }
      expect(admin_mail.body.decoded).to include("New user registration on your site Reversa Oracle \"7.2\" 😀:")
        .and include("Username: Newbie One").and include("Email: newbie@example.com")
      user_mail = ActionMailer::Base.deliveries.find { |m| m.subject.include?("Login Details") }
      expect(user_mail.body.decoded).to include("To set your password, visit the following address:")
      key = user_mail.body.decoded[/[?&]key=([A-Za-z0-9]{20})/, 1]
      expect(Identity::PasswordReset.check(key, "Newbie One").first).to eq(user)

      follow_redirect!
      expect(message_notice).to eq('<p>Registration complete. Please check your email, then visit the <a href="URL">login page</a>.</p>')
    end

    it "honours a safe redirect_to over the check-email exit (wp-login.php:1127)" do
      post "/register", params: { user_login: "newbie2", user_email: "newbie2@example.com", redirect_to: "/2026/" }
      expect(response.headers["Location"]).to end_with("/2026/")
    end
  end
end
