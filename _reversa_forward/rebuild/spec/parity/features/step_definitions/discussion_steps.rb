# frozen_string_literal: true

# PT-003 -- Moderating discussion. BR-MIGRATE-065..078 (BR-CMT-01..14).
#
# Inspector contract (paradigm_decision.md): assert BEHAVIOUR, never mechanism. Nothing
# below asks whether a callback fired, what a validation is called or what a column
# defaults to; every assertion is something a caller submitting a comment could see.
#
# ⚠️ BR-MIGRATE-078 (BR-CMT-14) is asserted by ABSENCE and is worth stating plainly: in
# the legacy the pipeline's answer always passes through `pre_comment_approved`, so a
# plugin can overrule the whole thing. Under AD-01 there is no filter and no override
# API to reach for -- the verdict these steps observe IS the verdict, permanently. The
# proof of that rule is that no step here (and no seam in Discussion) can change it.
#
# Shared phrasings: `Given a comment matching a disallowed keyword` and
# `Then the comment's status is "..."` are also used by 12-cross-context-integration
# (COUPLING 4). They are defined here, in the AGG-Comment step file. The Given only
# PREPARES a submission; `the comment's status is` submits it if no When did, so the
# integration feature can use both without knowing how this file stores state.

module DiscussionParityWorld
  # _reversa_sdd/ sits two levels above the Rails app.
  MIGRATION_SPECS = Rails.root.join("../../_reversa_sdd/migration").cleanpath

  DEFAULT_AUTHOR = { author_name: "Parity Commenter",
                     author_email: "parity.commenter@example.com",
                     author_ip: "203.0.113.10",
                     user_agent: "ParityHarness/1.0" }.freeze

  # One published record for every comment in a scenario to hang off. Created lazily so
  # a scenario that never mentions a record never makes one.
  def commentable_record
    @commentable_record ||= begin
      author = Identity::User.create!(
        login: "discussion_author", email: "discussion_author@example.com",
        nicename: "discussion-author", password: "pw", display_name: "Discussion Author"
      )
      Publishing::Article.create!(
        title: "A record that takes comments", slug: "a-record-that-takes-comments",
        content: "", excerpt: "", status: "published", published_at: 2.days.ago, author: author
      )
    end
  end

  def author_identity = @author_identity || DEFAULT_AUTHOR

  # The one entry point a submitter has. Comment.moderate runs the whole pipeline and
  # either records a verdict against a saved row or raises Comment::Rejected.
  def submit_comment(attrs = {})
    Discussion::Comment.moderate(
      { post: commentable_record, submitted_at: Time.current }
        .merge(author_identity).merge(attrs)
    )
  end

  def submit_comment_rescuing_rejection(attrs = {})
    @rejection = nil
    @comment = submit_comment(attrs)
  rescue Discussion::Comment::Rejected => e
    @rejection = e
    @comment = nil
  end

  # An already-admitted comment, admitted the way any other comment is: through the
  # model's own approve! command, so it carries a verdict like every real one does.
  def admitted_comment(content:, at: Time.current, **identity)
    comment = Discussion::Comment.create!(
      { post: commentable_record, status: "pending", content: content, submitted_at: at }
        .merge(author_identity).merge(identity)
    )
    comment.approve!
    comment
  end

  def latest_verdict = @comment.moderation_verdicts.order(:decided_at, :id).last

  # The deviation register. "Recorded as an accepted divergence" is a claim about the
  # written record, so it is checked against the written record.
  def recorded_deviation(rule_id)
    row = File.readlines(MIGRATION_SPECS.join("parity_specs.md"))
              .find { |line| line.start_with?("| `#{rule_id}`") }
    raise "parity_specs.md records no accepted deviation for #{rule_id}" if row.nil?

    row
  end

  def rule_row(rule_id)
    row = File.readlines(MIGRATION_SPECS.join("target_business_rules.md"))
              .find { |line| line.include?("`#{rule_id}`") }
    raise "target_business_rules.md has no row for #{rule_id}" if row.nil?

    row
  end
end
World(DiscussionParityWorld)

# support/env.rb truncates the tables that existed when it was written. TRUNCATE ...
# CASCADE reaches moderation_verdicts through its FK to comments, but comment_rate_limits
# has no foreign key by design, so it survives. A counter row left over from one scenario
# would throttle an author in the next. Cleared here because this file owns the namespace
# that owns the table.
Before { Discussion::RateLimit.delete_all }

# ── Scenario: a previously approved author is admitted ───────────────────────────
# BR-MIGRATE-073 (BR-CMT-09)
Given("moderation requires previous approval") do
  Configuration::Setting.set("comment_previously_approved", "1")
end

Given("an author with a previously approved comment") do
  @author_identity = { author_name: "Returning Commenter",
                       author_email: "returning@example.com",
                       author_ip: "203.0.113.11",
                       user_agent: "ParityHarness/1.0" }
  # Two days back, not two seconds: BR-MIGRATE-067's flood window looks back one hour,
  # and the point of this scenario is the previous-approval rule, not the interval one.
  admitted_comment(content: "An earlier remark, already admitted.", at: 2.days.ago)
end

When("that author submits a comment") do
  submit_comment_rescuing_rejection(content: "A new remark from the same author.")
end

# ── Scenario: the link limit ─────────────────────────────────────────────────────
# BR-MIGRATE-071 (BR-CMT-07)
Given("the maximum link count is {int}") do |max|
  Configuration::Setting.set("comment_max_links", max)
  @max_links = max
end

When("a comment containing {int} links is submitted") do |count|
  links = Array.new(count) { |i| %(<a href="https://example.com/#{i}" rel="nofollow">link #{i}</a>) }
  submit_comment_rescuing_rejection(content: "Have a look at #{links.join(" and ")}.")
end

Then("the moderation verdict's reason identifies the link limit") do
  # The reason is the audit trail a moderator reads, so it has to name WHICH rule held
  # the comment -- not merely that something did.
  expect(latest_verdict.reason).to include("comment_max_links")
end

# ── DEVIATION BR-CMT-04 / BR-MIGRATE-068: rate limiting ──────────────────────────
Given("an author who submitted a comment {int} seconds ago") do |seconds|
  @author_identity = { author_name: "Rapid Fire", author_email: "rapid@example.com",
                       author_ip: "203.0.113.44", user_agent: "ParityHarness/1.0" }
  @interval_seconds = seconds
  admitted_comment(content: "The first of two.", at: seconds.seconds.ago)
end

When("that author submits another comment") do
  submit_comment_rescuing_rejection(content: "The second of two, moments later.")
end

Then("the submission is rejected as too frequent") do
  # Rejected, not held: in the legacy this is a WP_Error return from wp_allow_comment(),
  # which means no comment row came into existence at all. The code, message and status
  # are the legacy's own and are preserved verbatim.
  expect(@rejection).to be_a(Discussion::Comment::Rejected)
  expect(@rejection.code).to eq("comment_flood")
  expect(@rejection.http_status).to eq(429)
  expect(@rejection.message).to eq("You are posting comments too quickly. Slow down.")
  # Nothing was persisted -- the first comment is still the only one that author has.
  expect(Discussion::Comment.where(author_email: "rapid@example.com").count).to eq(1)
end

Then("the legacy behaviour of accepting it is recorded as an accepted divergence") do
  # The divergence IS on the record, in both registers.
  expect(recorded_deviation("BR-CMT-04")).to match(/rate limit/i)
  expect(rule_row("BR-MIGRATE-068")).to include("DEVIATION")

  # ⚠️ FINDING, raised rather than asserted. Both registers describe the legacy as
  # enforcing NO rate limit. Probed against the running oracle, two comments from one
  # author 2 seconds apart returned WP_Error('comment_flood', 'You are posting comments
  # too quickly. Slow down.', 429) -- core DOES throttle, via
  #   default-filters.php:310 -> check_comment_flood_db() -> add_filter(
  #     'wp_is_comment_flood', 'wp_check_comment_flood') -> comment_flood_filter ->
  #   wp_throttle_comment_flood()  ( gap < 15s )
  # which a static read of comment.php:938 cannot see. The DIRECTION of the divergence
  # therefore holds (the target enforces a limit and does so unconditionally), but the
  # recorded justification does not. See Discussion::RateLimit.
end

# ── DEVIATION BR-CMT-08 / BR-MIGRATE-072: word-boundary keywords ─────────────────
Given("{string} is a disallowed keyword") do |word|
  Configuration::Setting.set("disallowed_keys", word)
  @disallowed_keyword = word
end

When("a comment containing the word {string} is submitted") do |word|
  submit_comment_rescuing_rejection(content: "I have been using #{word} for years.")
end

Then("the comment is not marked as spam for that reason") do
  expect(@comment.reload.status).not_to eq("spam")
  expect(latest_verdict.reason).not_to match(/disallowed/i)
end

Then("the divergence from the legacy substring match is recorded") do
  expect(recorded_deviation("BR-CMT-08")).to match(/word.boundary/i)
  expect(rule_row("BR-MIGRATE-072")).to include("DEVIATION")

  # And the deviation is word-boundary matching, NOT a broken keyword list: the same
  # keyword standing alone still marks the comment. Without this the scenario above
  # would pass just as well against a matcher that never matches anything.
  standalone = submit_comment(content: "One word: #{@disallowed_keyword}.",
                              author_name: "Boundary Probe",
                              author_email: "boundary.probe@example.com",
                              author_ip: "198.51.100.200")
  expect(standalone.status).to eq("spam")
end

# ── DEVIATION BR-CMT-10 / BR-MIGRATE-074: spam, never trash ──────────────────────
# Also used by 12-cross-context-integration (COUPLING 4).
Given("a comment matching a disallowed keyword") do
  @disallowed_keyword = "buymeds"
  Configuration::Setting.set("disallowed_keys", @disallowed_keyword)
  @prepared_comment = { content: "Cheap #{@disallowed_keyword} available now." }
end

When("the comment is submitted") do
  submit_comment_rescuing_rejection(@prepared_comment)
end

Then("the outcome does not depend on any trash-retention setting") do
  # The legacy computes `EMPTY_TRASH_DAYS ? 'trash' : 'spam'` -- the outcome of a
  # moderation decision read off a bootstrap constant. On the oracle EMPTY_TRASH_DAYS is
  # 30, so the same comment lands in TRASH there. Here the setting is walked across its
  # whole meaningful range, under both spellings a caller might reach for, and the answer
  # does not move. Each probe is a different author so the interval rule stays out of it.
  %w[0 1 30 365].each_with_index do |days, i|
    Configuration::Setting.set("empty_trash_days", days)
    Configuration::Setting.set("EMPTY_TRASH_DAYS", days)
    probe = submit_comment(content: "Cheap #{@disallowed_keyword}, offer #{i}.",
                           author_name: "Retention Probe #{i}",
                           author_email: "retention#{i}@example.com",
                           author_ip: "198.51.100.#{i + 1}")
    expect(probe.status).to eq("spam"), "retention #{days} produced #{probe.status}"
    expect(Discussion::Comment.in_trashed.count).to eq(0)
  end
end

# ── BR-MIGRATE-076 (BR-CMT-12): the status set is a type, not a convention ───────
Given("a comment in status {string}") do |status|
  @comment = Discussion::Comment.create!(
    { post: commentable_record, status: status, content: "A comment awaiting a decision.",
      submitted_at: Time.current }.merge(author_identity)
  )
end

When("a status outside the declared set is written directly to the database") do
  # "DIRECTLY": the guarantee under test is the column's type, not a model validation.
  # 'post-trashed' is one of the five values the legacy varchar(20) accepted, so this is
  # a value real legacy data contains -- T-05 maps it during migration, and after that
  # the database will not take it back.
  @write_error = begin
    ActiveRecord::Base.connection.execute(
      "UPDATE comments SET status = 'post-trashed' WHERE id = #{@comment.id}"
    )
    nil
  rescue ActiveRecord::StatementInvalid => e
    e
  end
end

Then("the write is rejected by the column's type constraint") do
  expect(@write_error).to be_present
  expect(@write_error.message).to match(/invalid input value for enum/i)
  expect(@comment.reload.status).to eq("pending")
end

# ── Deleting a record deletes its discussion ─────────────────────────────────────
Given("a published record with {int} approved comments") do |count|
  @record = commentable_record
  count.times do |i|
    admitted_comment(content: "Approved remark #{i}.",
                     author_email: "commenter#{i}@example.com",
                     author_ip: "198.51.100.#{100 + i}")
  end
  expect(Discussion::Comment.where(post_id: @record.id).in_approved.count).to eq(count)
end

When("the record is deleted") do
  @deleted_record_id = @record.id
  @record.destroy!
end

Then("no comments reference that record") do
  expect(Discussion::Comment.where(post_id: @deleted_record_id)).to be_empty
  # The verdicts go with them: an orphaned moderation trail pointing at a record that no
  # longer exists is the same leak in a different table.
  expect(Discussion::ModerationVerdict.count).to eq(0)
end

# ── Threading depth is bounded ───────────────────────────────────────────────────
Given("the maximum threading depth is {int}") do |max|
  Configuration::Setting.set("thread_comments_depth", max)
  @max_depth = max
end

When("a reply is submitted at depth {int}") do |depth|
  parent = nil
  (depth - 1).times do |i|
    parent = Discussion::Comment.create!(
      { post: commentable_record, parent: parent, status: "approved",
        content: "Level #{i + 1}.", submitted_at: Time.current }.merge(author_identity)
    )
  end
  @reply = Discussion::Comment.new(
    { post: commentable_record, parent: parent, status: "pending",
      content: "Level #{depth}.", submitted_at: Time.current }.merge(author_identity)
  )
  @reply_saved = @reply.save
end

Then("the reply is rejected or attached at the maximum permitted depth") do
  # The scenario permits either resolution, so the assertion permits either -- but not
  # a third: a reply that is neither rejected nor within the bound.
  if @reply_saved
    expect(@reply.reload.depth).to be <= @max_depth
  else
    expect(@reply.errors[:parent_id].join(" ")).to include("thread depth")
    expect(@reply).not_to be_persisted
  end
end

# ── Shared with 12-cross-context-integration ─────────────────────────────────────
Then("the comment's status is {string}") do |status|
  # If no When submitted it, the prepared submission is made here: the observable claim
  # is "a comment like this ends up in status X", and submitting is how you find out.
  submit_comment_rescuing_rejection(@prepared_comment) if @comment.nil? && @prepared_comment
  expect(@rejection).to be_nil, "submission was rejected: #{@rejection&.message}"
  expect(@comment.reload.status).to eq(status)
end

Then("a moderation verdict is recorded with its reason") do
  # target_domain_model.md § AGG-Comment: "A comment is admitted only after a
  # ModerationVerdict; the verdict, not the comment, carries the reason."
  verdict = latest_verdict
  expect(verdict).to be_present
  expect(verdict.outcome).to eq(@comment.status)
  expect(verdict.reason).to be_present

  # And the admission is the PREVIOUS-APPROVAL rule doing the work, not the pipeline
  # falling through to its default. Verified by mutation: with BR-MIGRATE-073's branch
  # deleted from ModerationPolicy the scenario above still went green, because the
  # default verdict is "approved" too. Same hole, and same remedy, as the standalone
  # probe in "the divergence from the legacy substring match is recorded".
  #
  # The control is an author the rule cannot admit -- no prior approved comment -- under
  # exactly the settings the scenario established. A different name, email and IP so the
  # interval rule (BR-MIGRATE-068) stays out of it. Confirmed against the running oracle:
  # with comment_previously_approved = '1', check_comment() answers false for an author
  # with no approved history and true for one with it.
  newcomer = submit_comment(content: "A first remark from a stranger.",
                            author_name: "First Timer",
                            author_email: "first.timer@example.com",
                            author_ip: "198.51.100.240")
  expect(newcomer.status).to eq("pending")
end
