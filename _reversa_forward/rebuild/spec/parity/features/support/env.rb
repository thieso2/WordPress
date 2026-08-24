# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

# cucumber-rails derives RAILS_ROOT from the support directory's grandparent, which
# assumes the conventional <root>/features layout. target_architecture.md puts the parity
# suite at spec/parity/features instead, so the root is stated rather than guessed.
# (cucumber-rails uses ||=, so setting it first wins.)
ENV["RAILS_ROOT"] ||= File.expand_path("../../../..", __dir__)

# ── Per-worker test database ──────────────────────────────────────────────────
# The Before hook below runs a global TRUNCATE ... RESTART IDENTITY CASCADE. With two
# cucumber processes against one database that is not isolation, it is a race: a row can
# vanish between a Given and its When, surfacing as PG::ForeignKeyViolation or
# ActiveRecord::Deadlocked on a scenario that is perfectly correct.
#
# ⚠️ This matters more here than in an ordinary suite. parity_specs.md makes any
# unexplained divergence on a write path DISQUALIFYING -- "we do not know why it differs"
# blocks the wave. A harness that manufactures its own divergences under concurrency
# would spend that budget on itself.
#
# Set PARITY_WORKER (any token) to get a private database. Nothing to remember for a
# single run; CI and concurrent agents set it per worker.
# Plain Ruby, not ActiveSupport: this block runs BEFORE cucumber/rails boots Rails.
worker = ENV["PARITY_WORKER"].to_s
if !worker.empty? && ENV["DATABASE_URL"].to_s.empty?
  suffix = worker.gsub(/[^a-zA-Z0-9_]/, "_")
  ENV["DATABASE_URL"] = "postgres:///rebuild_test_#{suffix}"
end

require "cucumber/rails"

# parity_specs.md: "any unexplained divergence on a content write path blocks the wave.
# On a write path, 'we do not know why it differs' is disqualifying."
# So the suite fails on an undefined step rather than reporting it as pending.
ActionController::Base.allow_rescue = false

Cucumber::Rails::Database.autorun_database_cleaner = false

Before do
  # Truncation rather than transactions: several scenarios assert that the DATABASE
  # rejects a write (AD-05), and a failed statement poisons an open transaction.
  ActiveRecord::Base.connection.execute(
    "TRUNCATE posts, assets, users, comments, terms, taxonomies, settings, " \
    "term_assignments, post_status_transitions, post_attributes, revisions, " \
    "redirects, menus, menu_items RESTART IDENTITY CASCADE"
  )
  # TRUNCATE bypasses Active Record, so Setting's after_save/after_destroy invalidation
  # cannot see it. Reset the per-request setting memo explicitly or the first scenario to
  # read a setting after a truncation gets the PREVIOUS scenario's value — a divergence the
  # harness would have manufactured itself. See Configuration::Current.
  Configuration::Current.reset
end

# The 60-second publication threshold (BR-MIGRATE-029/030) is an EXACT boundary, and the
# Inspector wrote a Scenario Outline that walks it at 59, 60 and 61 seconds. With a live
# clock the few milliseconds between the Given and the When push the 60-second case below
# the threshold, and the suite reports a defect that is really a test-harness artefact.
#
# golden/manifest.yaml already names the answer for the screen captures:
#   determinismStrategy: "fake-clock + fixed-seed + seeded corpus"
# The same strategy is applied here. Freezing is not a workaround for a flaky test; it is
# what makes an exact-boundary assertion mean anything at all.
World(ActiveSupport::Testing::TimeHelpers)

Before { freeze_time }
After  { travel_back }
