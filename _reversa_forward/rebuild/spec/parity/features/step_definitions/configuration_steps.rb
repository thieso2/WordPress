# frozen_string_literal: true

# PT-010 -- Settings and their load policy. BR-MIGRATE-008..014 (AGG-Setting), plus the
# AD-06 split that the whole context exists for.
#
# Inspector contract (paradigm_decision.md): assert what an outside observer sees, never
# how the model computes it. Nothing below reaches for a callback, a validation name or a
# column default. The one scenario the Inspector marked "asserted structurally" is
# nonetheless asserted by TRYING the forbidden thing and watching the store refuse it,
# not by reading the schema.
#
# Note: "Then the write is rejected by a uniqueness constraint" is already defined in
# publishing_steps.rb and is reused here rather than redefined.

# ── Scenario: Setting and reading a value ────────────────────────────────────────
Given("no setting named {string}") do |name|
  Configuration::Setting.unset(name)
  expect(Configuration::Setting[name]).to be(false)
end

When("the value {string} is stored under {string}") do |value, name|
  @result = Configuration::Setting.set(name, value)
end

Then("reading {string} returns {string}") do |name, value|
  expect(Configuration::Setting[name]).to eq(value)
end

# ── Scenario: Setting names are unique ───────────────────────────────────────────
Given("a setting named {string}") do |name|
  @setting_name = name
  Configuration::Setting.set(name, "Example")
end

When("a second row with the same name is written directly to the database") do
  # "written DIRECTLY to the database": AD-05. The guarantee that matters is the unique
  # index (settings_name_key -- the legacy's one genuine unique index, preserved), not a
  # model validation. Going through the model would prove only that the validation runs.
  @write_error = begin
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO settings (name, value) VALUES ('#{@setting_name}', '"Duplicate"'::jsonb)
    SQL
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid => e
    e
  end
end

# ── Scenario: An unchanged write is distinguishable from a failed write ──────────
# DEVIATION BR-OPT-04, approved. The legacy update_option() answers `false` both when
# the value was already what you asked for and when the write did not happen.
Given("a setting whose value is {string}") do |value|
  @setting_name = "site_title"
  @result = Configuration::Setting.set(@setting_name, value)
  expect(Configuration::Setting[@setting_name]).to eq(value)
end

When("the same value {string} is written again") do |value|
  @result = Configuration::Setting.set(@setting_name, value)
end

Then("the operation reports success with no change") do
  expect(@result.success?).to be(true)
  expect(@result.changed?).to be(false)
  # ...and the stored value is still the one that was already there.
  expect(Configuration::Setting[@setting_name]).to eq("Example")
end

Then("this is distinguishable from a write that failed") do
  # A genuinely failed write, for contrast: AD-06 bars the compiled routing table from
  # this store, so asking for it is a write that does not happen.
  failed = Configuration::Setting.set("rewrite_rules", { "^feed/?$" => "index.php?feed=1" })

  expect(failed.success?).to be(false)
  expect(failed.errors).to be_present
  expect(Configuration::Setting["rewrite_rules"]).to be(false)

  # The point of the deviation: the two answers are not the same answer.
  expect(@result.success?).not_to eq(failed.success?)
  expect(@result.outcome).not_to eq(failed.outcome)
end

# ── Scenario: The home URL falls back to the site URL when empty ─────────────────
# BR-MIGRATE-012 (BR-OPT-12). Confirmed against the live oracle: with home set to "",
# get_option('home') answers get_option('siteurl').
Given("the site URL is set and the home URL is empty") do
  Configuration::Setting.set("siteurl", "https://example.test")
  Configuration::Setting.set("home", "")
end

When("the home URL is read") do
  @read_value = Configuration::Setting["home"]
end

Then("it returns the site URL") do
  expect(@read_value).to eq(Configuration::Setting["siteurl"])
  expect(@read_value).to eq("https://example.test")
end

# ── Scenario: Load policy is explicit and never derived from value size ──────────
# BR-OPT-06 / F-RW-02 / F-CRON-03. The legacy de-autoloads an option over the threshold,
# which is how the routing table and the cron queue could silently stop being loaded.
#
# The threshold is 150000 BYTES, not 150 KiB: wp-includes/option.php:1362,
# `apply_filters( 'wp_max_autoloaded_option_size', 150000, $option )`, and the test is
# `$size > $max_option_size`. Confirmed against the live oracle -- an option left at the
# default autoload ('auto') stays 'auto' at 149995 bytes and flips to 'auto-off' at
# 150001. Using 150 * 1024 (=153600) would put every size this step walks ABOVE the real
# boundary, so the "walk it from both sides" below would never touch the under side.
LEGACY_AUTOLOAD_THRESHOLD_BYTES = 150_000

Given("a setting marked to load eagerly") do
  @setting_name = "eager_setting"
  Configuration::Setting.set(@setting_name, "small", autoload: true)
  expect(Configuration::Setting.autoloaded.pluck(:name)).to include(@setting_name)
end

When("its value grows beyond any historical size threshold") do
  @grown_value = "x" * (LEGACY_AUTOLOAD_THRESHOLD_BYTES * 2)
  Configuration::Setting.set(@setting_name, @grown_value)
  expect(Configuration::Setting[@setting_name].bytesize).to be > LEGACY_AUTOLOAD_THRESHOLD_BYTES
end

Then("it still loads eagerly") do
  # Observable as membership of the eagerly-loaded set, not as a column read.
  expect(Configuration::Setting.autoloaded.pluck(:name)).to include(@setting_name)
end

Then("no size heuristic changes its load policy") do
  # Walk the legacy threshold from both sides, in both directions, and watch nothing
  # happen. An eager setting stays eager however large it gets...
  [LEGACY_AUTOLOAD_THRESHOLD_BYTES - 1,
   LEGACY_AUTOLOAD_THRESHOLD_BYTES,
   LEGACY_AUTOLOAD_THRESHOLD_BYTES + 1,
   LEGACY_AUTOLOAD_THRESHOLD_BYTES * 8].each do |size|
    Configuration::Setting.set(@setting_name, "x" * size)
    expect(Configuration::Setting.autoloaded.pluck(:name))
      .to include(@setting_name), "size #{size} changed the load policy"
  end

  # ...and a lazily-loaded setting is not promoted by shrinking, either. The policy
  # moves only when someone moves it.
  Configuration::Setting.set("lazy_setting", "x" * (LEGACY_AUTOLOAD_THRESHOLD_BYTES * 2),
                             autoload: false)
  Configuration::Setting.set("lazy_setting", "tiny")
  expect(Configuration::Setting.autoloaded.pluck(:name)).not_to include("lazy_setting")

  Configuration::Setting.set_load_policy("lazy_setting", true)
  expect(Configuration::Setting.autoloaded.pluck(:name)).to include("lazy_setting")
end

# ── Scenario: The settings store cannot hold derived or queued state ─────────────
# AD-06 / F-DD-03. The legacy options table holds site config PLUS the compiled routing
# table PLUS the cron queue PLUS the transient cache, behind one unique index.
Given("the settings store") do
  Configuration::Setting.set("site_title", "Example")
  Configuration::Setting.set("permalink_structure", "/%year%/%monthnum%/%postname%/")
  @settings_before = Configuration::Setting.count
  ActiveJob::Base.queue_adapter.enqueued_jobs.clear
end

Then("no setting holds a compiled routing table") do
  # It cannot be put there...
  attempt = Configuration::Setting.set(
    "rewrite_rules", { "^feed/?$" => "index.php?feed=1", "^page/([0-9]{1,})/?$" => "index.php?paged=$1" }
  )
  expect(attempt.success?).to be(false)
  expect(Configuration::Setting["rewrite_rules"]).to be(false)

  # ...and it does not need to be, because the compiled table is derived on demand from
  # the permalink structure (AGG-Permalink: "derived state, cached and rebuildable --
  # never a stored setting"). Computing it adds no row to the store.
  compiled = Routing::PermalinkStructure.current.reserved_segments
  expect(compiled).to be_present
  expect(Configuration::Setting.count).to eq(@settings_before)
end

Then("no setting holds a scheduled-work queue") do
  attempt = Configuration::Setting.set("cron", { Time.current.to_i => { "hook" => "wp_version_check" } })
  expect(attempt.success?).to be(false)
  expect(Configuration::Setting["cron"]).to be(false)

  # Scheduling work is a job-queue operation, and it leaves the settings store alone.
  ApplicationJob.set(wait: 1.hour).perform_later("parity")
  expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(1)
  expect(Configuration::Setting.count).to eq(@settings_before)
end

Then("no setting holds a cached value with an expiry") do
  # BR-OPT-08: the legacy stored the value and its timeout as two option rows.
  %w[_transient_feed_abc _transient_timeout_feed_abc
     _site_transient_update_core _site_transient_timeout_update_core].each do |legacy_name|
    attempt = Configuration::Setting.set(legacy_name, "cached")
    expect(attempt.success?).to be(false), "#{legacy_name} was accepted into the settings store"
  end

  # And there is no other way to say it either: a setting takes a name, a value and a
  # load policy. An expiry is not something this store can express.
  expect { Configuration::Setting.set("feed_abc", "cached", expires_in: 60) }
    .to raise_error(ArgumentError)
  expect(Configuration::Setting.count).to eq(@settings_before)
end

# ── Scenario: Cached values with expiry live in the cache, not in settings ───────
Given("a value cached with a {int} second expiry") do |seconds|
  @cache_name  = "feed_response"
  @cache_value = "<rss version=\"2.0\"/>"
  @cache_ttl   = seconds.seconds
end

When("the value is stored") do
  Configuration::Transient.write(@cache_name, @cache_value, expires_in: @cache_ttl)
end

Then("it is not present in the settings store") do
  expect(Configuration::Setting[@cache_name]).to be(false)
  expect(Configuration::Setting.where("name LIKE ?", "%#{@cache_name}%")).to be_empty
  expect(Configuration::Setting.count).to eq(0)
end

Then("it is retrievable from the cache before expiry") do
  travel(@cache_ttl - 1.second)
  expect(Configuration::Transient.read(@cache_name)).to eq(@cache_value)
end

# ── Scenario: A deprecated setting alias resolves to its current name ────────────
# BR-MIGRATE-009 (BR-OPT-02). Verified against the live oracle: with disallowed_keys
# populated, get_option('blacklist_keys') returns the same value.
Given("a setting stored under its current name") do
  @setting_name  = "disallowed_keys"
  @setting_value = "press\nbadword"
  Configuration::Setting.set(@setting_name, @setting_value)
end

When("it is read through its deprecated alias") do
  @read_value = Configuration::Setting["blacklist_keys"]
end

Then("the current value is returned") do
  expect(@read_value).to eq(@setting_value)
  # The alias is a name for the same setting, not a second row.
  expect(Configuration::Setting.where(name: "blacklist_keys")).to be_empty
end
