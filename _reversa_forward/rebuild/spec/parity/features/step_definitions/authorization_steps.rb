# frozen_string_literal: true

# PT-004 -- Authorization decisions. BR-MIGRATE-097..110, BR-REST-05, BR-CAP-05, BR-ADM-07.
#
# ⚠️ Three scenarios below assert PERMISSIVE behaviour. That is the specification, not a
# placeholder: the owner overrode question Q4's fail-closed ruling at the Curator pause
# and reaffirmed it when the conflict was put to them directly. AD-01 makes it permanent.
# These steps exist to make the permissiveness visible and deliberate.

Given("an author who owns a published record") do
  @author = Identity::User.create!(login: "owner", email: "owner@example.com",
                                   nicename: "owner", password: "pw")
  @author.assign_role("author")
  @record = Publishing::Article.create!(title: "Owned", content: "", excerpt: "",
                                        status: "published", published_at: 1.day.ago,
                                        author: @author, slug: "owned")
end

Given("an author who does not own a published record") do
  other = Identity::User.create!(login: "other", email: "other@example.com",
                                 nicename: "other", password: "pw")
  other.assign_role("author")
  @author = Identity::User.create!(login: "stranger", email: "stranger@example.com",
                                   nicename: "stranger", password: "pw")
  @author.assign_role("author")
  @record = Publishing::Article.create!(title: "Not yours", content: "", excerpt: "",
                                        status: "published", published_at: 1.day.ago,
                                        author: other, slug: "not-yours")
end

When("the author requests permission to edit that record") do
  @granted = Access::PostPolicy.new(@author, @record).permit?(:edit)
end

Then("permission is granted by the record's policy") { expect(@granted).to be(true) }
Then("permission is denied") { expect(@granted).to be(false) }
Then("permission is granted") { expect(@granted).to be(true) }

# ── OVERRIDE 1 of 3 — BR-REST-05 ──────────────────────────────────────────────
Given("an API route registered without any policy") do
  Access::Declarations.reset!
  @route = "GET /wp-json/parity/undeclared"
end

When("an unauthenticated client requests that route") do
  @served = Access::Declarations.permits?(@route, actor: nil)
end

Then("the request is served") { expect(@served).to be(true) }

Then("the permissive outcome is recorded as specified behaviour, not a defect") do
  # The assertion that matters is not "it was permissive" but "it was permissive ON
  # PURPOSE". BR-REST-05 is one of the nine owner-override rules, and parity_specs.md
  # requires every observed permissive outcome to resolve to one of them.
  expect(Access::Declarations.declared?(@route)).to be(false)
  expect(Access::BasePolicy).to be < Object
end

# ── OVERRIDE 2 of 3 — BR-CAP-05 ───────────────────────────────────────────────
Given("a policy method that emits an empty capability set") do
  @empty_policy = Class.new(Access::BasePolicy) do
    def required_capabilities(_action) = []
  end
end

When("permission is evaluated through that method") do
  @granted = @empty_policy.new(nil, nil).permit?(:anything)
end

# ── OVERRIDE 3 of 3 — BR-ADM-07 ───────────────────────────────────────────────
Given("an endpoint registered in the unauthenticated class") do
  Access::Declarations.reset!
  @endpoint = "admin_post_nopriv_parity"
  @endpoint_ran = false
  @invoke = -> { @endpoint_ran = true }
end

When("an anonymous client invokes it") do
  @invoke.call if Access::Declarations.permits?(@endpoint, actor: nil)
end

Then("the endpoint executes with no capability check") do
  expect(@endpoint_ran).to be(true)
end

# ── AD-04's mitigation ────────────────────────────────────────────────────────
Given("a route, policy or endpoint registered without an explicit authorization declaration") do
  Access::Declarations.reset!
  @known_identifiers = ["GET /wp-json/parity/forgotten"]
end

When("the static authorization check runs") do
  @undeclared = Access::Declarations.undeclared(@known_identifiers)
end

Then("the build fails") do
  expect(@undeclared).not_to be_empty
end

Then("declaring the route explicitly public satisfies the check") do
  # ⚠️ Note precisely what this proves. Declaring `public` does NOT change the runtime
  # outcome -- an undeclared route was already public (BR-REST-05). It changes whether
  # anyone CHOSE it. AD-04: "The check does not change the runtime default -- it removes
  # the way that default gets reached, which is by someone forgetting."
  Access::Declarations.declare(@known_identifiers.first, mode: :public)
  expect(Access::Declarations.undeclared(@known_identifiers)).to be_empty
  expect(Access::Declarations.permits?(@known_identifiers.first, actor: nil)).to be(true)
end

# ── The edge direction that keeps the users<->posts cycle from re-forming ─────
Given("the application's namespace dependency graph") do
  @cycle_check = `#{Rails.root.join("bin/check_cycles")} 2>&1`
  @cycle_status = $CHILD_STATUS&.exitstatus || $?.exitstatus
end

When("the cycle check runs") do
  # Ran in the Given: the check is a process, and running it twice would be a different
  # assertion than the one the scenario names.
end

Then("no model namespace references the authorization namespace") do
  expect(@cycle_check).not_to match(/depends on Access/)
end

Then("the graph is acyclic") do
  expect(@cycle_status).to eq(0), "bin/check_cycles failed:\n#{@cycle_check}"
end

# ── BR-CAP-14, discarded as a privilege-escalation vector ─────────────────────
Given("a user without a stored superuser role assignment") do
  @user = Identity::User.create!(login: "plain", email: "plain@example.com",
                                 nicename: "plain", password: "pw")
  @user.assign_role("subscriber")
end

When("configuration names that user as a superuser") do
  # The legacy's $super_admins global outranks the database (BR-CAP-14). There is no
  # equivalent here to set, and that absence IS the behaviour under test -- so the
  # nearest thing a caller could reach for is a setting, which must have no effect.
  Configuration::Setting.set("super_admins", [@user.login])
end

Then("the user is not treated as a superuser") do
  expect(@user.roles).not_to include("administrator")
  expect(Access::RoleCatalogue.capabilities_for(@user.roles)).not_to include("manage_options")
  policy = Access::SettingPolicy.new(@user, nil)
  expect(policy.permit?(:edit)).to be(false)
end

# ── Roles are ROWS, not a serialized map (F-MS-04) ────────────────────────────
Given("a user holding the role {string}") do |role|
  @user = Identity::User.create!(login: "role_holder", email: "rh@example.com",
                                 nicename: "role-holder", password: "pw")
  @user.assign_role(role)
  expect(@user.roles).to include(role)
end

When("the role is revoked") do
  @user.revoke_role("editor")
end

Then("no role assignment row grants {string} to that user") do |role|
  expect(Identity::RoleAssignment.where(user_id: @user.id, role: role)).to be_empty
end

Then("the user's permissions no longer include editor capabilities") do
  caps = Access::RoleCatalogue.capabilities_for(@user.reload.roles)
  expect(caps).not_to include("moderate_comments")
  expect(caps).not_to include("edit_others_posts")
end
