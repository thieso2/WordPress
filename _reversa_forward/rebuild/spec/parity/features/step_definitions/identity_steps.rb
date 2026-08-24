# frozen_string_literal: true

# PT-006 -- Sessions and request tokens. BR-MIGRATE-111..126 (BR-AUTH-01..16), T-10.
#
# The load-bearing scenario is BR-AUTH-15: destroying a session invalidates every
# outstanding token issued under it. That is ONE invariant spanning two legacy modules
# (users-roles-capabilities and authentication-and-sessions), which is why
# target_architecture.md merges them into BC-05 Identity -- they fail together.
#
# Inspector contract (paradigm_decision.md): assert what an outside observer sees.
# Nothing below asks whether a callback fired, whether a foreign key says CASCADE, or
# whether nonces are rows or a derived MAC. Every assertion is "present this, observe
# that", so the model is free to change its mind about mechanism.

# Prefixed, and the helper below with them: step files share one global namespace and
# one World, and several agents are writing into this directory at once.
IDENTITY_CREDENTIAL = "correct horse battery staple"

# Digests produced by the live oracle, not by this suite, so the phpass and bcrypt
# examples exercise real WordPress output rather than a Ruby re-implementation of it:
#
#   php -r 'require ".../_bootstrap.php";
#           $ph = new PasswordHash(8, true); echo $ph->HashPassword($pw);
#           echo password_hash($pw, PASSWORD_BCRYPT);'
#
# Both are the digest of IDENTITY_CREDENTIAL. The oracle also confirms that the vanilla
# $2y$ one is not the target format -- wp_password_needs_rehash('$2y$...') === true --
# which is what makes "bcrypt" a legitimate row of T-10's Scenario Outline and not a
# no-op. (T-10: "copy the digest verbatim ... the plaintext is unavailable by
# construction", so a seeded fixture is the only honest way to reach this state.)
IDENTITY_ORACLE_DIGESTS = {
  "phpass" => "$P$BRBst7kTlWzz6zS24pp/PobaemalbZ.",
  "bcrypt" => "$2y$12$ljaQG3kaFlPktWggQnzg8.79Vov1N8k8yCidSGZ3L7rq.ScDj1cFm"
}.freeze

def identity_user(login, digest: nil)
  user = Identity::User.create!(login: login, email: "#{login}@example.com",
                                nicename: login.tr("_", "-"), password: IDENTITY_CREDENTIAL)
  # A legacy digest is written after creation because that is how T-10 loads it: the
  # column is copied verbatim from wp_users.user_pass, never round-tripped through the
  # target's hasher.
  user.update_column(:password_digest, digest) if digest
  user.reload
end

# ── A valid credential establishes a session ──────────────────────────────────

Given("a user with a valid credential") do
  @user = identity_user("session_holder")
  @credential = IDENTITY_CREDENTIAL
end

When("the user authenticates") do
  @authenticated = @user.authenticate_and_upgrade(@credential)
  @session_token = @user.start_session! if @authenticated
end

Then("a session exists for that user") do
  expect(@authenticated).to be_truthy
  # "a session exists" is observed the way a later request would observe it: by
  # presenting the token, not by counting rows.
  expect(Identity::Session.authenticate(@session_token)&.user_id).to eq(@user.id)
end

Then("the session has an expiry instant") do
  expect(Identity::Session.authenticate(@session_token).expires_at).to be > Time.current
end

# ── BR-AUTH-15: destroying a session invalidates every outstanding token ──────

Given("an authenticated user with an outstanding request token") do
  @user = identity_user("token_holder")
  @session_token = @user.start_session!
  @action = "parity-action"
  @nonce = Identity::Nonce.issue(@action, session_token: @session_token)
  # The token is outstanding: it verifies right now. Without this the scenario would
  # pass just as well against a nonce implementation that never verifies anything.
  expect(Identity::Nonce.verify(@nonce, @action, session_token: @session_token)).to be_truthy
end

When("the user's session is destroyed") do
  @user.end_session!(@session_token)
end

Then("the outstanding token is rejected") do
  # BR-MIGRATE-123 / BR-AUTH-13: verification answers 1, 2 or false -- never true. The
  # rejection is the literal `false`, and `be_falsey` would also accept nil from a
  # method that quietly stopped answering.
  expect(Identity::Nonce.verify(@nonce, @action, session_token: @session_token)).to be(false)
end

Then("no action authorised by that token succeeds") do
  # Not merely "verify said no": the guarded operation must not run. The guard belongs
  # to the system (Identity::Nonce.guard), so this asserts the system's refusal rather
  # than the test's own if-statement.
  performed = false
  result = Identity::Nonce.guard(@nonce, @action, session_token: @session_token) { performed = true }
  expect(performed).to be(false)
  expect(result).to be_nil
end

# ── Destroying all sessions invalidates tokens across every device ────────────

Given("a user with two active sessions on different devices") do
  @user = identity_user("two_devices")
  @session_tokens = [
    @user.start_session!(ip: "203.0.113.10", user_agent: "device-a"),
    @user.start_session!(ip: "203.0.113.11", user_agent: "device-b")
  ]
  expect(@session_tokens.uniq.length).to eq(2)
end

Given("an outstanding request token issued under each") do
  @action = "parity-action"
  @nonces = @session_tokens.map { |t| Identity::Nonce.issue(@action, session_token: t) }
  @session_tokens.zip(@nonces).each do |token, nonce|
    expect(Identity::Nonce.verify(nonce, @action, session_token: token)).to be_truthy
  end
  # Sessions are the binding material (BR-MIGRATE-125): two devices, two tokens.
  expect(@nonces.uniq.length).to eq(2)
end

When("all sessions for that user are destroyed") do
  @user.end_all_sessions!
end

Then("both tokens are rejected") do
  @session_tokens.zip(@nonces).each do |token, nonce|
    expect(Identity::Nonce.verify(nonce, @action, session_token: token)).to be(false)
  end
end

# ── An expired session is not accepted ────────────────────────────────────────

Given("a session whose expiry instant has passed") do
  @user = identity_user("expired_session")
  @session_token = @user.start_session!(ttl: 1.hour)
  @action = "parity-action"
  @nonce = Identity::Nonce.issue(@action, session_token: @session_token)
  expect(Identity::Session.authenticate(@session_token)).to be_present

  # The session reaches its expiry instant by the clock moving, not by being written
  # into the past: "expired" has to mean the same thing to the system as it will in
  # production. Two hours is well inside one 12-hour nonce tick (BR-MIGRATE-122), so
  # nothing below can be explained away by the token ageing out instead.
  travel 2.hours
end

When("a request presents that session") do
  @presented = Identity::Session.authenticate(@session_token)
end

Then("the request is treated as unauthenticated") do
  expect(@presented).to be_nil
  # The same consequence as destruction, reached a different way: no live session, no
  # session identity, so a token minted under it stops verifying (BR-AUTH-15). An
  # implementation that expired the row but kept honouring its tokens would pass the
  # first line of this step and fail the second.
  expect(Identity::Nonce.verify(@nonce, @action, session_token: @session_token)).to be(false)
end

# ── Sessions are ROWS now, not usermeta['session_tokens'] ─────────────────────

Given("a user with an active session and an application password") do
  @user = identity_user("deletable")
  @session_token = @user.start_session!
  Identity::ApplicationPassword.create!(user: @user, name: "parity client",
                                        digest: BCrypt::Password.create("app-pw"))
  @user_id = @user.id
  expect(Identity::Session.where(user_id: @user_id)).not_to be_empty
  expect(Identity::ApplicationPassword.where(user_id: @user_id)).not_to be_empty
end

When("the user is deleted") do
  # Deleted through the DATABASE, not through the association. `dependent: :destroy`
  # would prove only that the association option is spelled correctly; the guarantee
  # under AD-05 is the foreign key, and a row removed by any other writer -- a console,
  # a batch job, the erasure pipeline -- must leave the same state behind.
  ActiveRecord::Base.connection.execute("DELETE FROM users WHERE id = #{@user_id}")
end

Then("no session rows reference that user") do
  expect(Identity::Session.where(user_id: @user_id).count).to eq(0)
end

Then("no application password rows reference that user") do
  expect(Identity::ApplicationPassword.where(user_id: @user_id).count).to eq(0)
end

# ── T-10: legacy digests remain verifiable and are upgraded on use ────────────

Given("a user whose stored digest is in {string} format") do |format|
  digest = IDENTITY_ORACLE_DIGESTS.fetch(format)
  @user = identity_user("legacy_#{format}", digest: digest)
  @digest_before = @user.password_digest
  expect(@digest_before).to eq(digest)
end

When("the user authenticates with the correct credential") do
  @authenticated = @user.authenticate_and_upgrade(IDENTITY_CREDENTIAL)
end

Then("authentication succeeds") do
  expect(@authenticated).to be_truthy
end

Then("the stored digest is rehashed to the target algorithm") do
  after = @user.reload.password_digest
  expect(after).not_to eq(@digest_before)
  # "The target algorithm" is observed as behaviour, not as a prefix: the stored digest
  # still verifies the same credential, and presenting that credential again no longer
  # changes anything at rest. A digest that kept being rewritten on every login would
  # satisfy "it changed" while failing T-10 outright.
  expect(@user.authenticate_and_upgrade(IDENTITY_CREDENTIAL)).to be_truthy
  expect(@user.reload.password_digest).to eq(after)
  expect(@user.authenticate_and_upgrade("wrong credential")).to be_falsey
end

# ── T-10: "never leave a user with a digest that accidentally verifies" ───────

Given("a user whose stored digest is empty or malformed") do
  # Both halves of the sentence, because they arrive by different routes: an EMPTY
  # source digest becomes the disabled sentinel, and a MALFORMED one that no format
  # recognises becomes it too -- but a digest can also be malformed in the column, and
  # that path must not raise instead of refusing.
  @users = {
    empty: identity_user("digest_empty", digest: Seeding::Transformations.password_digest("")),
    malformed: identity_user("digest_malformed", digest: "not-a-real-hash")
  }
end

When("any credential is presented") do
  # "Any": the correct one, the sentinel value itself, the literal stored bytes, and
  # nothing at all. The stored-bytes case is the one T-10 warns about -- a digest that
  # accidentally verifies is usually one compared against itself.
  candidates = [IDENTITY_CREDENTIAL, "", Seeding::Transformations::DISABLED_DIGEST,
                "not-a-real-hash", nil]
  @outcomes = @users.transform_values do |user|
    candidates.map { |c| user.authenticate_and_upgrade(c) }
  end
end

Then("authentication fails") do
  # `results.uniq` rather than the `all` matcher: Cucumber's World mixes in Capybara's
  # DSL, whose `all` finder shadows RSpec's `all` matcher and turns this into a page
  # query. Same assertion, no ambiguity.
  @outcomes.each do |label, results|
    expect(results.uniq).to eq([false]), "#{label} digest verified something: #{results.inspect}"
  end
end
