# frozen_string_literal: true

require_relative "auth_spec_helper"

# auth.lostpassword (DEV-010: also `retrievepassword`) and auth.checkemail --
# wp-login.php:843-933 and :1203-1235, retrieve_password() (user.php:3261).
#
# DIFFERENTIAL for every string the oracle can show WITHOUT sending mail: the oracle
# has no mail transport, so its success path ends in `retrieve_password_email_failure`;
# that string is compared too, by making the rebuild's delivery fail.
RSpec.describe "auth.lostpassword", type: :request do
  before do
    skip "the PHP oracle is not available" unless oracle_available?
    seed_oracle_users!
    host! "127.0.0.1"
    ActionMailer::Base.deliveries.clear
  end

  LOST_PASSWORD_CASES = [
    ["empty", ""],
    ["whitespace only", "   "],
    ["unknown username", "nobody"],
    ["unknown email", "nobody@example.com"],
    ["an @ at position 0", "@oracle_editor"],
    ["markup", "<b>nobody</b>"]
  ].freeze

  LOST_PASSWORD_CASES.each do |label, value|
    it "prints the oracle's error for #{label}" do
      oracle = AuthOracle.lost_password(user_login: value)
      expect(oracle.status).to eq(200)
      post "/login/lost-password", params: { user_login: value }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to eq(oracle.error_notice)
      expect(field("user_login")).to eq(oracle.field("user_login"))
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "renders the literal help text, label and button, like the oracle" do
    oracle = AuthOracle.get("/wp-login.php?action=lostpassword")
    get "/login/lost-password"
    expect(response).to have_http_status(:ok)
    expect(page_title).to start_with("Lost Password")
    expect(oracle.title).to start_with("Lost Password")
    help = "Please enter your username or email address. You will receive an email message with instructions on how to reset your password."
    expect(oracle.body).to include(help)
    expect(response.body).to include(help).and include("Username or Email Address").and include('value="Get New Password"')
  end

  it "shows the invalid/expired key errors the reset screen bounces back with, byte for byte" do
    %w[invalidkey expiredkey].each do |code|
      oracle = AuthOracle.get("/wp-login.php?action=lostpassword&error=#{code}")
      get "/login/lost-password", params: { error: code }
      expect(error_notice).to eq(oracle.error_notice)
    end
  end

  it "issues a key, mails the literal message and routes to auth.checkemail on success" do
    post "/login/lost-password", params: { user_login: "oracle_editor" }
    expect(response).to have_http_status(:see_other)
    expect(response.headers["Location"]).to end_with("/login/check-email?checkemail=confirm")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(["oracle_editor@example.com"])
    # user.php:3410: the subject names the DECODED site title.
    expect(mail.subject).to eq("[Reversa Oracle \"7.2\" 😀] Password Reset")
    body = mail.body.decoded
    expect(body).to include("Someone has requested a password reset for the following account:")
      .and include("Site Name: Reversa Oracle \"7.2\" 😀").and include("Username: oracle_editor")
      .and include("If this was a mistake, ignore this email and nothing will happen.")
      .and include("To reset your password, visit the following address:")
      .and include("This password reset request originated from the IP address 127.0.0.1.")
    key = body[/[?&]key=([A-Za-z0-9]{20})/, 1]
    expect(key).to be_present
    expect(Identity::PasswordReset.check(key, "oracle_editor").first).to eq(Identity::User.find_by!(login: "oracle_editor"))

    follow_redirect!
    oracle = AuthOracle.get("/wp-login.php?checkemail=confirm")
    expect(message_notice).to eq(oracle.message_notice)
    expect(page_title).to start_with("Check your email")
  end

  it "finds the account by email, then by login, with the case the legacy uses (user.php:3274-3282)" do
    post "/login/lost-password", params: { user_login: "ORACLE_EDITOR@example.com" }
    expect(response).to have_http_status(:see_other)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["oracle_editor@example.com"])
  end

  it "reports a mail failure with the oracle's string (user.php:3433)" do
    # retrieve_password() writes the reset key before wp_mail() fails, so the oracle side
    # runs through the rolled-back bridge, not live HTTP. The oracle's mailer is
    # unconfigured, so its retrieve_password ends in retrieve_password_email_failure --
    # the exact string the rebuild shows when its own delivery raises.
    result = auth_bridge({ op: "retrieve_password", user_login: "oracle_editor" }).first
    expect(result["error_codes"]).to eq(["retrieve_password_email_failure"])
    # href-normalized, like every notice comparison here (DEV-006): the support link
    # differs in the rebuild by construction.
    oracle_message = AuthOracle.normalize("<p>#{result["errors"].first["message"]}</p>")

    allow(Auth::Mailer).to receive(:password_reset).and_raise(StandardError, "no transport")
    post "/login/lost-password", params: { user_login: "oracle_editor" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(error_notice).to eq(oracle_message)
  end

  it "shows the registered message on auth.checkemail, byte for byte, and nothing for an unknown value" do
    oracle = AuthOracle.get("/wp-login.php?checkemail=registered")
    get "/login/check-email", params: { checkemail: "registered" }
    expect(message_notice).to eq(oracle.message_notice)
    get "/login/check-email", params: { checkemail: "other" }
    expect(message_notice).to be_nil
    expect(page_title).to start_with("Check your email")
  end
end
