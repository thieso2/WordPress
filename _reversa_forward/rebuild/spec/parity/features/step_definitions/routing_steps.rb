# frozen_string_literal: true

# PT-007 -- Permalinks, reserved segments and slug allocation.
# BR-MIGRATE-141..152 (AGG-Permalink), plus the coupling BR-MIGRATE-034 / BR-POST-07 /
# F-RW-06 that this feature exists to pin down.
#
# ⚠️ This is the ONE cycle edge that survives the paradigm change. topology_decision.md:
# most of the legacy's 23-module component dissolves with the hook system and the boot
# globals; rewrite <-> query does not, because the pagination base and the registered feed
# slugs decide WHICH POST SLUGS ARE LEGAL. The edge is kept pointing Routing -> Publishing
# by dependency inversion (Publishing owns the port, config/initializers/reserved_segments.rb
# fills it in), so every step below reaches for Routing and never asks Publishing to name it.
#
# Inspector contract (paradigm_decision.md): assert what an outside observer sees. Nothing
# below asserts a callback fired, a validation is named a particular thing, or a column
# carries a default.

# A distinctly-named helper: step files share one World, so a bare `author` would collide
# with another feature's helper.
def parity_routing_author
  @parity_routing_author ||= Identity::User.create!(
    login: "routing_author", email: "routing_author@example.com", nicename: "routing-author",
    password: "correct horse battery staple", display_name: "Routing Author"
  ).tap { |user| user.assign_role("author") }
end

def parity_routing_publish!(slug)
  record = Publishing::Article.new(title: slug.to_s.presence || "Routing record", content: "",
                                   excerpt: "", status: "published", published_at: 1.day.ago,
                                   author: parity_routing_author)
  Routing::SlugAllocator.new.allocate!(record, requested: slug)
  record
end

# ── The reserved set is DERIVED from the structure ────────────────────────────────
# BR-MIGRATE-143 (feed slugs are feed, rdf, rss, rss2, atom) and BR-MIGRATE-144
# (pagination_base is 'page'), both confirmed against the live oracle's $wp_rewrite.

Given("a permalink structure containing a pagination base and registered feed slugs") do
  @permalink_structure = Routing::PermalinkStructure.current
  expect(@permalink_structure.pagination_base).to be_present
  expect(@permalink_structure.feed_slugs).not_to be_empty
end

When("the reserved segment set is computed") do
  @reserved_set = @permalink_structure.reserved_segments
end

Then("it contains the pagination base") do
  expect(@reserved_set).to include(@permalink_structure.pagination_base)
end

Then("it contains every registered feed slug") do
  expect(@reserved_set).to include(*@permalink_structure.feed_slugs)
end

Then("it contains the embed segment") do
  expect(@reserved_set).to include("embed")
end

# ── BR-MIGRATE-034 / BR-POST-07 / F-RW-06: the coupling under test ────────────────
# ⚠️ DELIBERATE TIGHTENING, and it is worth stating plainly. The oracle refuses "feed"
# and "embed" for a post slug but ACCEPTS "page" (wp_unique_post_slug() only tests the
# pagination base as the prefix of a NUMBER, `^(page)?\d+$`). target_domain_model.md
# AGG-Permalink specifies the reserved set as "pagination base, registered feed slugs,
# `embed`, date-archive segments", so the target reserves the bare pagination base too.
# The feature demands it; the spec authorises it; the divergence from the legacy is
# recorded here rather than papered over.

Given("the reserved segment {string}") do |segment|
  expect(Routing::PermalinkStructure.current).to be_reserved(segment)
  @reserved_segment = segment
end

# BR-MIGRATE-144. Stated as a fact about the structure, not about a config file.
Given("the pagination base is {string}") do |base|
  expect(Routing::PermalinkStructure.current.pagination_base).to eq(base)
end

When("an author publishes a record requesting the slug {string}") do |requested|
  @requested_slug = requested
  @record = parity_routing_publish!(requested)
end

# The legacy's answer for "2" is "2-2" (oracle: wp_unique_post_slug('2', 0, 'publish',
# 'post', 0)). The scenario asks only that a suffix appears, so that is what is asserted.
Then("the allocated slug takes a numeric suffix") do
  expect(@record.reload.slug).to match(/-\d+\z/)
  expect(@record.slug).not_to eq(@requested_slug)
end

# ── AD-06: the compiled route table is derived state ──────────────────────────────

Given("a published record with slug {string}") do |slug|
  @record = Publishing::Article.create!(
    title: slug.titleize, slug: slug, content: "", excerpt: "", status: "published",
    published_at: 1.day.ago, author: parity_routing_author
  )
  expect(@record.slug).to eq(slug)
end

When("the permalink structure is changed so that {string} would shadow a route") do |slug|
  before = Routing::PermalinkStructure.current
  @pattern_before = before.pattern
  @route_table_before = before.route_table
  # A front literal is the ordinary way a WordPress structure eats a segment
  # (/blog/%postname%/ makes "blog" unreachable as a post slug); here the front literal
  # is chosen to be exactly the slug the record already holds.
  @change = Routing::PermalinkStructure.change_to("/#{slug}/%postname%/")
end

Then("the route table is recomputed") do
  expect(@change.route_table).to be_present
  expect(@change.route_table).not_to eq(@route_table_before)
  # Recomputed FROM THE NEW STRUCTURE: the new front literal appears in every rule, and
  # the reserved set derived alongside it now contains that literal.
  compiled = @change.route_table.map(&:regex).join(" ")
  expect(compiled).to include(Regexp.escape(@record.slug))
  expect(@change.reserved_segments).to include(@record.slug)
  # AD-06: rebuilding it was a method call. Nothing was read from or written to a setting.
  expect(Configuration::Setting.where(name: "rewrite_rules")).to be_empty
end

Then("the conflict is surfaced rather than silently resolved") do
  expect(@change).to be_conflict
  expect(@change.conflicts.map(&:id)).to include(@record.id)
  # "Silently resolved" is exactly what the legacy would do on the write path: suffix the
  # slug and say nothing. The published record is untouched here...
  expect(@record.reload.slug).to eq("page-2")
  # ...and the shadowing structure was not adopted behind anyone's back either.
  expect(@change).not_to be_applied
  expect(Routing::PermalinkStructure.current.pattern).to eq(@pattern_before)
end

# ── AD-06 again, as a structural invariant of the settings store ──────────────────
# The legacy keeps the whole rule set in one autoloaded option (BR-MIGRATE-145) and the
# cron queue in another; the 150 KB autoload heuristic can then silently de-autoload
# either one (BR-OPT-06, F-RW-02, F-CRON-03). The failure mode exists only because
# unrelated things share a table, so the assertion is that they no longer can.

# `Given("the settings store")` is NOT defined here. PT-010 already defines it in
# configuration_steps.rb and Cucumber shares one glue namespace, so a second definition is
# ambiguity, not reinforcement.

Then("it contains no compiled route table") do
  expect(Configuration::Setting.where(name: "rewrite_rules")).to be_empty
  expect(Configuration::Setting["rewrite_rules"]).to be(false)
  # Not merely absent today: it cannot be put there.
  expect(Configuration::Setting.new(name: "rewrite_rules", value: ["x"]).save).to be(false)
  expect(Configuration::Setting.where(name: "rewrite_rules")).to be_empty
  # And the routing still has its table, because the table is derived.
  expect(Routing::PermalinkStructure.current.route_table).to be_present
end

Then("it contains no scheduled-work queue") do
  expect(Configuration::Setting.where(name: "cron")).to be_empty
  expect(Configuration::Setting["cron"]).to be(false)
  expect(Configuration::Setting.new(name: "cron", value: { "1" => {} }).save).to be(false)
  expect(Configuration::Setting.where(name: "cron")).to be_empty
end

# ── AD-03: the redirect replaces _wp_old_slug / _wp_old_date ──────────────────────

When("the slug is changed to {string}") do |slug|
  @old_path = Routing::PermalinkStructure.current.path_for(@record)
  Routing::SlugAllocator.new.rename!(@record, requested: slug)
  expect(@record.reload.slug).to eq(slug)
end

Then("a redirect exists from the old path to the record") do
  redirect = Routing::Redirect.find_by(from_path: @old_path)
  expect(redirect).to be_present
  expect(redirect.post_id).to eq(@record.id)
end

Then("requesting the old path resolves to the record") do
  expect(Routing::Redirect.resolve(@old_path)&.id).to eq(@record.id)
  # The same path with the trailing slash rubbed off is the same path.
  expect(Routing::Redirect.resolve(@old_path.chomp("/"))&.id).to eq(@record.id)
end
