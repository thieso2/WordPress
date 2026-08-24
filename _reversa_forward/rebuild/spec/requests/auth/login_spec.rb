# frozen_string_literal: true

require_relative "auth_spec_helper"

# auth.login -- wp-login.php `case 'login'` (:1301-1590), wp_signon() (user.php:41),
# wp_authenticate_username_password (:153), wp_authenticate_email_password (:242).
#
# DIFFERENTIAL: each error case below is POSTed to the oracle's wp-login.php and to
# /login, and the notice the two print is compared after href normalization
# (DEV-006). The redirect contract (safe redirect_to, capability-based landing,
# reauth) is compared on its observable: the Location header's path.
RSpec.describe "auth.login", type: :request do
  before do
    skip "the PHP oracle is not available" unless oracle_available?
    seed_oracle_users!
    host! "127.0.0.1"
  end

  # [label, log, pwd, rememberme, redirect_to]
  LOGIN_ERROR_CASES = [
    ["both empty", "", "", nil, nil],
    ["empty password", "oracle_editor", "", nil, nil],
    ["empty username", "", "x", nil, nil],
    ["unknown username", "nobody", "x", nil, nil],
    ["wrong password, by username", "oracle_editor", "wrong", nil, nil],
    ["wrong password, by username, odd case", "Oracle_Editor", "wrong", nil, nil],
    ["unknown email", "nobody@example.com", "x", nil, nil],
    ["wrong password, by email", "oracle_editor@example.com", "wrong", nil, nil],
    ["username with markup", "<b>oracle</b>_editor", "wrong", nil, nil],
    ["username with an @ that is not an email", "not@an@email", "x", nil, nil],
    ["whitespace-only password", "oracle_editor", "   ", nil, nil]
  ].freeze

  describe "the error notice matches the oracle byte for byte (href-normalized)" do
    LOGIN_ERROR_CASES.each do |label, log, pwd, remember, redirect|
      it label do
        oracle = AuthOracle.login(log: log, pwd: pwd, rememberme: remember, redirect_to: redirect)
        expect(oracle.status).to eq(200)

        with_test_cookie
        post "/login", params: { log: log, pwd: pwd, rememberme: remember, redirect_to: redirect, testcookie: "1" }.compact
        expect(response).to have_http_status(:unprocessable_content)
        expect(error_notice).to eq(oracle.error_notice)
        expect(message_notice).to eq(oracle.message_notice)
        # wp-login.php:1483: the typed identifier survives only incorrect_password /
        # empty_password; the password field is always empty.
        expect(field("user_login")).to eq(oracle.field("user_login"))
        expect(field("user_pass")).to eq("")
        expect(aria("user_login")).to eq(oracle.aria("user_login"))
      end
    end
  end

  describe "the cookie check (wp-login.php:1363-1371)" do
    it "shows the oracle's cookie-blocked string when the test cookie is not returned" do
      # Driven with WRONG credentials on purpose: wp-login.php runs the cookie block
      # (:1354-1372) after wp_signon regardless of its result, and the test_cookie error
      # overrides whatever wp_signon returned -- so this reaches the exact string with NO
      # write to the oracle (a failed wp_signon sets no cookie and clears no key).
      oracle = AuthOracle.login(log: "oracle_editor", pwd: "wrong", cookies: {})
      expect(oracle.error_notice).to include("Cookies are blocked or not supported by your browser")

      post "/login", params: { log: "oracle_editor", pwd: "wrong", testcookie: "1" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to eq(oracle.error_notice)
    end

    it "starts no session for valid credentials when the browser did not return the test cookie" do
      # Rebuild-only: a successful oracle login here would persist a session token into
      # the shared corpus (RISK-002). The rebuild's refusal is observable on its own db.
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to include("Cookies are blocked or not supported by your browser")
      expect(Identity::Session.count).to eq(0)
      expect(cookies[Auth::SessionCookie::COOKIE]).to be_blank
    end

    it "sets the test cookie on every visit to the form" do
      get "/login"
      expect(response).to have_http_status(:ok)
      expect(cookies[Auth::SessionCookie::TEST_COOKIE]).to eq(Auth::SessionCookie::TEST_COOKIE_VALUE)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "a successful login" do
    # The oracle's success path writes a session token and clears user_activation_key,
    # so it is driven through the rolled-back bridge (support/auth_oracle.php), never
    # over live HTTP. The bridge returns the capability facts wp-login.php:1415-1428
    # branches on; the rebuild's landing must follow the same rule.
    it "establishes a session, sets the cookie and lands an editor on the console (admin_url())" do
      caps = auth_bridge({ op: "signon", log: "oracle_editor", pwd: "pw-editor" }).first
      expect(caps["edit_posts"]).to be(true)

      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      expect(response).to have_http_status(:see_other)
      # edit_posts holder -> admin_url() (the console), not the profile.
      expect(response.headers["Location"]).to end_with("/console")
      session = Identity::Session.authenticate(session_token_from_cookies)
      expect(session.user.login).to eq("oracle_editor")
      # BR-AUTH-09: 2 days without remember-me.
      expect(session.expires_at).to be_within(5.seconds).of(2.days.from_now)
    end

    it "accepts the email address as the identifier (wp_authenticate_email_password)" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor@example.com", pwd: "pw-editor", testcookie: "1" }
      expect(response).to have_http_status(:see_other)
      expect(Identity::Session.count).to eq(1)
    end

    it "trims the password the way wp_authenticate() does (pluggable.php:690)" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "  pw-editor  ", testcookie: "1" }
      expect(response).to have_http_status(:see_other)
    end

    it "lands a subscriber (read, no edit_posts) on the profile, matching the oracle's capability set" do
      caps = auth_bridge({ op: "signon", log: "oracle_subscriber", pwd: "pw-subscriber" }).first
      expect(caps["edit_posts"]).to be(false)
      expect(caps["read"]).to be(true)

      with_test_cookie
      post "/login", params: { log: "oracle_subscriber", pwd: "pw-subscriber", testcookie: "1" }
      # read but not edit_posts -> admin_url('profile.php') (wp-login.php:1421).
      expect(response.headers["Location"]).to end_with(Auth::BaseController::PROFILE_PATH)
    end

    it "honours a same-host redirect_to and refuses a foreign one (wp_validate_redirect)" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1", redirect_to: "/2026/03/hello-world/" }
      expect(response.headers["Location"]).to end_with("/2026/03/hello-world/")
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1", redirect_to: "https://evil.example/x" }
      expect(response.headers["Location"]).to end_with("/console")
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1", redirect_to: "//evil.example/x" }
      expect(response.headers["Location"]).to end_with("/console")
    end

    it "issues a 14-day session with Remember Me and a cookie that outlives it by 12 hours (BR-AUTH-09)" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1", rememberme: "forever" }
      session = Identity::Session.last
      expect(session.expires_at).to be_within(5.seconds).of(14.days.from_now)
      set_cookie = response.headers["Set-Cookie"].to_s
      expect(set_cookie).to match(/wordpress_logged_in=.*expires=/i)
      expires = Time.httpdate(set_cookie[/wordpress_logged_in=[^\n]*?expires=([^;]+)/i, 1])
      expect(expires).to be_within(5.seconds).of(14.days.from_now + 12.hours)
    end

    it "clears an outstanding password-reset key (wp_signon(), user.php:122)" do
      user = Identity::User.find_by!(login: "oracle_editor")
      key = Identity::PasswordReset.issue_key!(user)
      expect(Identity::PasswordReset.check(key, "oracle_editor").first).to eq(user)
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      expect(Identity::PasswordReset.check(key, "oracle_editor")).to eq([nil, :invalid_key])
    end

    it "with reauth renders the clean form and starts no session (wp-login.php:1432, :1464)" do
      # Rebuild-only: a reauth POST with valid credentials still runs wp_signon on the
      # oracle (a session-token write) before suppressing the login, so it is not driven
      # over live HTTP. The oracle's own answer -- a 200 with a clean form and no error
      # notice -- was confirmed manually during development (bin/oracle up; curl -i
      # 'wp-login.php?reauth=1' with valid creds -> 200, no #login_error).
      with_test_cookie
      post "/login?reauth=1", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(error_notice).to be_nil
      expect(Identity::Session.count).to eq(0)
    end
  end

  describe "the GET messages (wp-login.php:1440-1459)" do
    it "shows the logged-out message with the oracle's string" do
      oracle = AuthOracle.get("/wp-login.php?loggedout=true")
      get "/login", params: { loggedout: "true" }
      expect(message_notice).to eq(oracle.message_notice)
      expect(message_notice).to eq("<p>You are now logged out.</p>")
      expect(aria("user_login")).to eq("login-message")
    end

    it "shows the registration-disabled error with the oracle's string" do
      oracle = AuthOracle.get("/wp-login.php?registration=disabled")
      get "/login", params: { registration: "disabled" }
      expect(error_notice).to eq(oracle.error_notice)
    end

    it "renders the literal labels" do
      get "/login"
      html = response.body
      expect(html).to include("Username or Email Address").and include(">Password<").and include("Remember Me")
        .and include('value="Log In"').and include("Lost your password?").and include('aria-label="Show password"')
      # users_can_register is '0': no Register link (wp-login.php:1581).
      expect(html).not_to include(">Register<")
      Configuration::Setting.set("users_can_register", "1")
      get "/login"
      expect(response.body).to include(">Register<")
    end
  end

  describe "auth.logout (DELETE /session)" do
    it "destroys the session row, clears the cookie and lands on the logged-out message" do
      with_test_cookie
      post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
      token = session_token_from_cookies
      expect(Identity::Session.authenticate(token)).to be_present

      delete "/session"
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/login?loggedout=true")
      expect(Identity::Session.authenticate(token)).to be_nil
      follow_redirect!
      expect(message_notice).to eq("<p>You are now logged out.</p>")
    end

    it "runs for a logged-out browser too (wp-login.php:804 does not require a user)" do
      delete "/session"
      expect(response).to have_http_status(:see_other)
    end

    it "honours a safe redirect_to and refuses a foreign one" do
      delete "/session", params: { redirect_to: "/2026/" }
      expect(response.headers["Location"]).to end_with("/2026/")
      delete "/session", params: { redirect_to: "https://evil.example/" }
      expect(response.headers["Location"]).to end_with("/console")
    end
  end
end
