# frozen_string_literal: true

require_relative "auth_spec_helper"

# BR-AUTH-15 / BR-MIGRATE-125, end to end over HTTP: the session the login screen
# establishes is the binding material of every nonce, and DELETE /session revokes them
# all. This is the surface-level form of parity feature 06 ("Destroying a session
# invalidates every outstanding token") and of feature 12's coupling 5 ("Destroying a
# session invalidates authority granted elsewhere"): the token is minted from the
# browser's cookie, the logout goes through the controller, and the refusal is
# observed through Identity::Nonce.guard -- the guard every other context uses.
RSpec.describe "session authority (BR-AUTH-15)", type: :request do
  before do
    seed_oracle_users!
    host! "127.0.0.1"
  end

  def log_in
    with_test_cookie
    post "/login", params: { log: "oracle_editor", pwd: "pw-editor", testcookie: "1" }
    expect(response).to have_http_status(:see_other)
    session_token_from_cookies
  end

  it "mints nonces bound to the cookie's session and rejects them all after DELETE /session" do
    token = log_in
    nonce = Identity::Nonce.issue("publish-post", session_token: token)
    expect(Identity::Nonce.verify(nonce, "publish-post", session_token: token)).to eq(1)

    delete "/session"
    expect(response).to have_http_status(:see_other)

    expect(Identity::Nonce.verify(nonce, "publish-post", session_token: token)).to be(false)
    performed = false
    expect(Identity::Nonce.guard(nonce, "publish-post", session_token: token) { performed = true }).to be_nil
    expect(performed).to be(false)
  end

  it "a nonce minted under one device's session does not verify under another's (BR-MIGRATE-125)" do
    token_a = log_in
    nonce_a = Identity::Nonce.issue("publish-post", session_token: token_a)
    token_b = log_in
    expect(token_b).not_to eq(token_a)
    expect(Identity::Nonce.verify(nonce_a, "publish-post", session_token: token_b)).to be(false)
    expect(Identity::Nonce.verify(nonce_a, "publish-post", session_token: token_a)).to eq(1)
  end

  it "a password reset ends every session, so their nonces stop verifying too (BR-AUTH-05)" do
    token = log_in
    nonce = Identity::Nonce.issue("publish-post", session_token: token)
    user = Identity::User.find_by!(login: "oracle_editor")
    Identity::PasswordReset.reset!(user, "a-different-password-1")
    expect(Identity::Nonce.verify(nonce, "publish-post", session_token: token)).to be(false)
  end

  it "a logged-out browser resolves to no actor and an expired session resolves to none either" do
    get "/login"
    expect(controller.send(:current_actor)).to be_nil

    token = log_in
    get "/login"
    expect(controller.send(:current_actor)&.login).to eq("oracle_editor")
    travel 3.days do
      get "/login"
      expect(controller.send(:current_actor)).to be_nil
      expect(Identity::Session.authenticate(token)).to be_nil
    end
  end

  it "BR-AUTH-08: a POST gets one hour's grace on an expired session, a GET does not" do
    token = log_in
    # 30 minutes past a 2-day expiry: inside the one-hour POST grace, outside the
    # strict window a GET uses (pluggable.php:806).
    travel 2.days + 30.minutes do
      expect(Identity::Session.authenticate(token, grace: 0)).to be_nil
      expect(Identity::Session.authenticate(token, grace: Identity::Session::POST_GRACE)).to be_present
      get "/login"
      expect(controller.send(:current_actor)).to be_nil
    end
    # 90 minutes past: outside the grace too, so even a POST no longer resolves it.
    travel 2.days + 90.minutes do
      expect(Identity::Session.authenticate(token, grace: Identity::Session::POST_GRACE)).to be_nil
    end
  end
end
