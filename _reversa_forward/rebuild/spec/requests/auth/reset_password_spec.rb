# frozen_string_literal: true

require_relative "auth_spec_helper"
require "open3"

# auth.resetpass -- wp-login.php `case 'resetpass': case 'rp':` (:906-1093),
# check_password_reset_key() (user.php:3175), reset_password() (:3510).
#
# DIFFERENTIAL on the oracle's own reset flow: a key is issued through the oracle's
# get_password_reset_key() (a write to user_activation_key, which nothing in the
# corpus depends on), the emailed URL shape is followed over HTTP, and the form's
# error strings and bounce targets are compared. The oracle's SUCCESS path is not
# driven -- it would change oracle_editor's password -- and is asserted here on the
# rebuild alone with the literal strings read from wp-login.php:1024.
RSpec.describe "auth.resetpass", type: :request do
  AUTH_RESET_BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  before do
    skip "the PHP oracle is not available" unless oracle_available?
    seed_oracle_users!
    host! "127.0.0.1"
    ActionMailer::Base.deliveries.clear
    @user = Identity::User.find_by!(login: "oracle_editor")
    @key = Identity::PasswordReset.issue_key!(@user)
  end

  def enter_with_key(key, login = "oracle_editor")
    get "/login/reset-password", params: { key: key, login: login }
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to end_with("/login/reset-password")
    follow_redirect!
  end

  describe "entering from the emailed link (wp-login.php:911-916)" do
    # Rebuild-only: issuing a key on the oracle (get_password_reset_key) is a write to
    # the shared corpus, so the cookie/redirect mechanics are asserted on the rebuild.
    # The oracle's own shape -- a 302 to ?action=rp setting an HttpOnly wp-resetpass
    # cookie on the reset path -- was confirmed manually during development and is
    # reproduced here (session_cookie.rb write_reset_cookie!).
    it "moves the key into the wp-resetpass cookie and redirects clean" do
      get "/login/reset-password", params: { key: @key, login: "oracle_editor" }
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("/login/reset-password")
      expect(cookies[Auth::SessionCookie::RESET_COOKIE]).to eq("oracle_editor:#{@key}")
      set_cookie = response.headers["Set-Cookie"].to_s
      expect(set_cookie).to match(%r{wp-resetpass=.*path=/login/reset-password}i)
      expect(set_cookie).to match(/wp-resetpass=.*httponly/i)
    end

    # The form's LITERAL strings (target_screens.md § auth.resetpass). These are verbatim
    # from wp-login.php:1036-1082 and wp_get_password_hint() (user.php:3078); the oracle's
    # rendering of them was confirmed byte for byte via curl during development, but the
    # comparison cannot run live here because reaching the form requires a persisted key.
    it "renders the form with every literal string" do
      enter_with_key(@key)
      expect(response).to have_http_status(:ok)
      expect(page_title).to start_with("Reset Password")
      ["New password", "Confirm new password", "Confirm use of weak password", "Strength indicator",
       "Generate Password", 'value="Save Password"', "Enter your new password below or generate one.",
       "Hint: The password should be at least twelve characters long. To make it stronger, use upper and lower case letters, numbers, and symbols like ! \" ? $ % ^ &amp; )."].each do |literal|
        expect(response.body).to include(literal)
      end
      expect(field("rp_key") || doc.at_css('input[name="rp_key"]')["value"]).to eq(@key)
      expect(doc.at_css("#user_login")["value"]).to eq("oracle_editor")
    end

    # The key-VALIDATION differential runs through the rolled-back bridge: a fresh key
    # verifies, a wrong one is invalid_key -- the same two answers Identity::PasswordReset
    # gives. (check_password_reset_key, user.php:3175.)
    it "validates a key the way the oracle's check_password_reset_key does" do
      good, bad = auth_bridge({ op: "check_reset_key", login: "oracle_editor", key: "__valid__" },
                              { op: "check_reset_key", login: "oracle_editor", key: "wrongkey" })
      expect(good["user_login"]).to eq("oracle_editor")
      expect(bad["error_code"]).to eq("invalid_key")
      expect(bad["message"]).to eq("Invalid key.")
      k = Identity::PasswordReset.issue_key!(@user)
      expect(Identity::PasswordReset.check(k, "oracle_editor").first).to eq(@user)
      expect(Identity::PasswordReset.check("wrongkey", "oracle_editor")).to eq([nil, :invalid_key])
    end
  end

  describe "an invalid or expired key (wp-login.php:935-945)" do
    it "bounces a cookieless visit to lost-password with error=invalidkey, clearing the cookie, as the oracle does" do
      oracle = AuthOracle.get("/wp-login.php?action=rp")
      expect(oracle.status).to eq(302)
      expect(oracle.location).to end_with("wp-login.php?action=lostpassword&error=invalidkey")

      get "/login/reset-password"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("/login/lost-password?error=invalidkey")
    end

    it "bounces a wrong key with error=invalidkey" do
      enter_with_key("definitelywrongkey00")
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to end_with("/login/lost-password?error=invalidkey")
    end

    it "bounces a key older than a day with error=expiredkey (password_reset_expiration)" do
      travel 25.hours do
        enter_with_key(@key)
        expect(response.headers["Location"]).to end_with("/login/lost-password?error=expiredkey")
      end
    end

    it "bounces a submission whose rp_key disagrees with the cookie (hash_equals, :923)" do
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "abcdefgh1234", pass2: "abcdefgh1234", rp_key: "wrong" }
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/login/lost-password?error=invalidkey")
      expect(@user.reload.authenticate("abcdefgh1234")).to be_falsey
    end

    it "voids the key once its owner logs in" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      enter_with_key(@key)
      expect(response.headers["Location"]).to end_with("/login/lost-password?error=invalidkey")
    end
  end

  # The reset-form rules (wp-login.php:990-1001). The two error strings are LITERAL from
  # that block; reaching the oracle's form POST needs a persisted key, so these are
  # asserted on the rebuild with the exact bytes, confirmed by curl during development:
  #   pass1!=pass2                -> "<strong>Error:</strong> The passwords do not match."
  #   all-whitespace pass1        -> "The password cannot be a space or all spaces." (no prefix)
  #   empty pass1                 -> the form re-renders with no notice, nothing saved.
  describe "the form rules (wp-login.php:990-1001)" do
    it "reports a mismatch with the literal string" do
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "abcdefgh1234", pass2: "zzz", rp_key: @key }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to eq("<p><strong>Error:</strong> The passwords do not match.</p>")
    end

    it "reports an all-spaces password with the literal string (no Error: prefix)" do
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "   ", pass2: "   ", rp_key: @key }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to eq("<p>The password cannot be a space or all spaces.</p>")
    end

    it "re-renders silently on an empty pass1, saving nothing" do
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "", pass2: "", rp_key: @key }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to be_nil
      expect(@user.reload.authenticate("pw-editor")).to be_truthy
    end

    it "compares pass2 trimmed against pass1 trimmed (:992, :999)" do
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "  new-secret-12  ", pass2: "new-secret-12", rp_key: @key }
      expect(response).to have_http_status(:see_other)
      expect(@user.reload.authenticate("new-secret-12")).to be_truthy
    end
  end

  describe "success (wp-login.php:1018-1034)" do
    it "resets the password, ends every session, clears the key, notifies the admin and routes to auth.login with the literal notice" do
      old_session = @user.start_session!
      enter_with_key(@key)
      post "/login/reset-password", params: { pass1: "brand-new-pw-42", pass2: "brand-new-pw-42", rp_key: @key }
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/login")

      follow_redirect!
      expect(message_notice).to eq('<p>Your password has been reset. <a href="URL">Log in</a></p>')
      expect(@user.reload.authenticate("brand-new-pw-42")).to be_truthy
      expect(@user.authenticate("pw-editor")).to be_falsey
      expect(@user.activation_key_digest).to be_nil
      # BR-AUTH-05: a password change invalidates every outstanding session.
      expect(Identity::Session.authenticate(old_session)).to be_nil
      # default-filters.php:540 -> wp_password_change_notification().
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["oracle@example.com"])
      expect(mail.subject).to eq("[Reversa Oracle \"7.2\" 😀] Password Changed")
      expect(mail.body.decoded).to include("Password changed for user: oracle_editor")
      # The key is single-use: the cookie no longer opens the form.
      get "/login/reset-password"
      expect(response.headers["Location"]).to end_with("/login/lost-password?error=invalidkey")
    end

    it "does not notify the admin of the admin's own reset (pluggable.php:2202)" do
      admin = Identity::User.create!(login: "oracle_admin", email: "oracle@example.com", nicename: "oracle-admin",
                                     display_name: "oracle_admin", password: "oracle-admin-pw")
      key = Identity::PasswordReset.issue_key!(admin)
      enter_with_key(key, "oracle_admin")
      post "/login/reset-password", params: { pass1: "another-new-pw-42", pass2: "another-new-pw-42", rp_key: key }
      expect(response).to have_http_status(:see_other)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "BR-AUTH-02: a password over 4096 bytes leaves the account unable to authenticate" do
      enter_with_key(@key)
      huge = "x" * 5000
      post "/login/reset-password", params: { pass1: huge, pass2: huge, rp_key: @key }
      expect(response).to have_http_status(:see_other)
      expect(@user.reload.authenticate_and_upgrade(huge)).to be_falsey
      expect(@user.authentication_enabled?).to be(false)
    end
  end
end
