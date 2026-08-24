# frozen_string_literal: true

# PT-012 -- Cross-context couplings. THE WAVE 3 INTEGRATION CHECKPOINT.
#
# migration_strategy.md: "an integration checkpoint is required at the end of Wave 3
# that exercises the entire former 23-module component together, because a wave that is
# individually parity-clean can still be jointly wrong (F-SIM-05, RISK-016)." Every other
# feature in this directory tests within one context; this one deliberately spans them,
# and every scenario below is taken from spec-impact-matrix.md section 6.
#
# Inspector contract (paradigm_decision.md): assert what an outside observer sees. Each
# step reaches into the contexts on BOTH ends of a coupling and watches the effect cross
# the boundary -- never how it crossed. Where a scenario asserts that a coupling has been
# DELETED (AD-06, the BR-CMT-10 deviation), the step tries the thing that used to cause
# the effect and watches nothing happen.
#
# Shared phrasings reused from the single-context step files, deliberately not redefined
# (Cucumber shares one glue namespace):
#   the term's content count is {int}                      -> classification_steps.rb
#   an author publishes a record requesting the slug {string} -> routing_steps.rb
#   a comment matching a disallowed keyword / the comment's status is {string}
#                                                           -> discussion_steps.rb
#   the user's session is destroyed                         -> identity_steps.rb

module IntegrationParityWorld
  SDD_ROOT = Rails.root.join("../../_reversa_sdd").cleanpath
  INTEGRATION_FEATURE = "12-cross-context-integration.feature"

  def integration_author
    @integration_author ||= Identity::User.create!(
      login: "integration_author", email: "integration_author@example.com",
      nicename: "integration-author", password: "correct horse battery staple",
      display_name: "Integration Author"
    ).tap { |user| user.assign_role("author") }
  end

  def integration_article(title:, status: "published", published_at: 1.day.ago, slug: nil)
    Publishing::Article.create!(
      title: title, slug: slug, content: "", excerpt: "", status: status,
      published_at: status == "draft" ? nil : published_at, author: integration_author
    )
  end

  # Which of the SQL statements the RUBY side issued during a block. The database's own
  # trigger work does not surface here -- which is exactly the distinction COUPLING 1
  # turns on.
  def ruby_side_sql
    statements = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql]
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end
end
World(IntegrationParityWorld)

# ── COUPLING 1: taxonomy-and-terms -> posts-and-post-types (BR-TAX-11) ───────────────

Given("a term with exactly one published record classified under it") do
  @term = classification_remember(
    Classification::Term.create!(taxonomy: classification_taxonomy, name: "Coupled", slug: "coupled")
  )
  @record = integration_article(title: "Coupled record")
  Classification::Assignment.create!(term: @term, classifiable: @record)
end

When("the record's status changes to {string}") do |status|
  # The caller is PUBLISHING's own command. It names no term, no count, no other
  # context; the statements it issues are captured so the next step can say so.
  @count_before = @term.reload.count
  @caller_statements = ruby_side_sql do
    status == "draft" ? @record.unpublish!(actor: integration_author) : @record.update!(status: status)
  end
  expect(@record.reload.status).to eq(status)
end

Then("no explicit recount was requested by the caller") do
  # Nothing the caller ran wrote to, or even read, the classification tables...
  classification_statements = @caller_statements.grep(/\b(terms|term_assignments|taxonomies)\b/i)
  expect(classification_statements).to be_empty,
                                       "the caller touched Classification: #{classification_statements.inspect}"
  expect(@caller_statements.grep(/recompute|classification_refresh/i)).to be_empty
  # ...yet the count moved, and moved to the recomputed truth.
  expect(@term.reload.count).to eq(@count_before - 1)
  recomputed = ActiveRecord::Base.connection.select_value("SELECT classification_term_count(#{@term.id})")
  expect(@term.count).to eq(recomputed)
  # And the command cannot have asked, because Publishing does not know Classification
  # exists -- the surviving one-directional edge (target_architecture.md BC-02).
  # (Code, not commentary: the model's comments are free to NAME the context whose
  # counter reacts; its code may not reference it. bin/check_cycles enforces the same.)
  command_code = File.readlines(Publishing::Post.instance_method(:unpublish!).source_location.first)
                     .reject { |line| line.strip.start_with?("#") }.join
  expect(command_code).not_to match(/\bClassification\b/)
end

# ── COUPLING 2: rewrite-and-permalinks -> posts-and-post-types (BR-POST-07, F-RW-06) ──

Given("a permalink structure whose pagination base is {string}") do |base|
  @permalink_structure = Routing::PermalinkStructure.current
  expect(@permalink_structure.pagination_base).to eq(base)
end

Then("Publishing refuses the requested slug") do
  # The allocator never hands the reserved segment out (routing_steps' When allocated
  # the record through Routing::SlugAllocator)...
  expect(@record.reload.slug).not_to eq(@requested_slug)
  expect(@record.slug).to match(/\A#{Regexp.escape(@requested_slug)}-\d+\z/)
  # ...and a record that tries to hold it directly is refused by Publishing itself.
  @refusal = Publishing::Article.new(
    title: @requested_slug, slug: @requested_slug, content: "", excerpt: "",
    status: "published", published_at: 1.day.ago, author: parity_routing_author
  )
  expect(@refusal.save).to be(false)
  expect(@refusal.errors[:slug]).to include("collides with a reserved route segment")
  expect(Publishing::Post.where(slug: @requested_slug)).not_to exist
end

Then("the refusal originates from the routing context's reserved segment set") do
  # The set Publishing consults IS Routing's derived set, not a copy of it.
  expect(Publishing.reserved_segments).to include(@requested_slug)
  expect(Publishing.reserved_segments).to eq(Routing::PermalinkStructure.current.reserved_segments)

  # Counterfactual: under a routing configuration whose pagination base is something
  # else, the very same record is acceptable. The refusal tracks Routing's
  # configuration, so Routing is where it comes from. Restored afterwards -- this is
  # configuration, not per-request state, and the suite shares the boot-time wiring.
  original = Publishing.reserved_segment_source
  begin
    other = Routing::PermalinkStructure.new(pagination_base: "p")
    expect(other.reserved_segments).not_to include(@requested_slug)
    Publishing.reserved_segment_source = -> { other.reserved_segments }
    expect(@refusal.valid?).to be(true), -> { @refusal.errors.full_messages.join("; ") }
  ensure
    Publishing.reserved_segment_source = original
  end
  expect(@refusal.valid?).to be(false)
end

# ── COUPLING 3: options-and-transients -> rewrite, cron (BR-OPT-06, F-RW-02, F-CRON-03)

Given("a settings store containing many large eagerly-loaded settings") do
  # One routable record and one piece of scheduled work, BEFORE the store grows, so the
  # later steps observe the same two things the legacy could lose.
  @routable = integration_article(title: "Routable record", slug: "routable-record")
  @scheduled = integration_article(title: "Scheduled record", slug: "scheduled-record",
                                   published_at: 2.hours.from_now)
  expect(@scheduled.status).to eq("scheduled")

  @eager_names = (1..12).map { |i| "bulky_setting_#{i}" }
  @eager_names.each do |name|
    Configuration::Setting.set(name, "x" * LEGACY_AUTOLOAD_THRESHOLD_BYTES, autoload: true)
  end
  @eager_count_before = Configuration::Setting.autoloaded.count
end

When("the total eagerly-loaded volume exceeds any historical threshold") do
  @eager_volume = Configuration::Setting.autoloaded.sum { |s| s.value.to_s.bytesize }
  # Every one of them is AT the legacy's per-option ceiling, and together they are an
  # order of magnitude over it.
  expect(@eager_volume).to be > LEGACY_AUTOLOAD_THRESHOLD_BYTES * 10
end

Then("route resolution continues to work") do
  structure = Routing::PermalinkStructure.current
  expect(structure.route_table).to be_present
  path = structure.path_for(@routable)

  # The compiled table still matches the record's path...
  expect(structure.route_table.any? { |rule| Regexp.new(rule.regex).match?(path.delete_prefix("/")) })
    .to be(true), "no compiled rule matched #{path}"
  # ...the application's router still resolves it to the singular screen...
  recognised = Rails.application.routes.recognize_path(path)
  expect(recognised[:controller]).to eq("web/singular")
  expect(recognised[:slug]).to eq(@routable.slug)
  # ...and the reserved set is still derived, not read from a setting that could have
  # been de-autoloaded.
  expect(structure.reserved_segments).to include(structure.pagination_base)
  expect(Configuration::Setting.where(name: "rewrite_rules")).to be_empty
end

Then("scheduled work continues to be discovered") do
  # Discovered two independent ways, neither of which reads the settings store.
  travel 3.hours
  expect(Publishing::Post.due_for_publication).to include(@scheduled)

  queued = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
    job[:job] == Publishing::PublishScheduledJob && job[:args] == [@scheduled.id]
  end
  expect(queued).not_to be_empty
  expect(queued.first[:at]).to be_present

  # And the work, when it runs, runs.
  Publishing::PublishScheduledJob.perform_now(@scheduled.id)
  expect(@scheduled.reload.status).to eq("published")
  expect(Publishing::Post.due_for_publication).not_to include(@scheduled)
  expect(Configuration::Setting.where(name: "cron")).to be_empty
end

Then("no setting was silently reclassified") do
  expect(Configuration::Setting.where(name: @eager_names).pluck(:autoload).uniq).to eq([true])
  expect(Configuration::Setting.autoloaded.count).to eq(@eager_count_before)
  # The only way a load policy moves is by someone moving it.
  Configuration::Setting.set_load_policy(@eager_names.first, false)
  expect(Configuration::Setting.autoloaded.count).to eq(@eager_count_before - 1)
end

# ── COUPLING 4: comments -> bootstrap-and-load (BR-CMT-10, deviation approved) ────────

When("trash retention is configured to {word} days") do |days|
  @retention_days = { "zero" => 0, "thirty" => 30 }.fetch(days) { Integer(days) }
  # Both spellings a caller might reach for. There is no constant to define: the
  # bootstrap coupling has no successor, and a setting is the only place left to try.
  Configuration::Setting.set("empty_trash_days", @retention_days.to_s)
  Configuration::Setting.set("EMPTY_TRASH_DAYS", @retention_days.to_s)
end

Then("the comment's status is still {string}") do |status|
  # The comment already moderated has not moved...
  expect(@comment.reload.status).to eq(status)
  # ...and a fresh submission of the same disallowed content, under the new retention
  # configuration, lands in the same place. A different author, so BR-MIGRATE-068's
  # interval rule stays out of it.
  probe = submit_comment(content: "Cheap #{@disallowed_keyword}, retention #{@retention_days}.",
                         author_name: "Retention Probe #{@retention_days}",
                         author_email: "retention-#{@retention_days}@example.com",
                         author_ip: "198.51.100.#{60 + @retention_days}")
  expect(probe.status).to eq(status)
  expect(Discussion::Comment.in_trashed.count).to eq(0)
end

# ── COUPLING 5: authentication-and-sessions -> all nonces (BR-AUTH-15) ───────────────

Given("an authenticated user holding an outstanding request token") do
  @user = identity_user("coupled_token_holder")
  @session_token = @user.start_session!
  @action = "publish-record"
  @nonce = Identity::Nonce.issue(@action, session_token: @session_token)
  expect(Identity::Nonce.verify(@nonce, @action, session_token: @session_token)).to be_truthy
end

Given("a pending action in another context authorised by that token") do
  # The action lives in Publishing; the authority lives in Identity. Nothing in
  # Publishing knows what a session is.
  @pending_record = Publishing::Article.create!(title: "Awaiting authority", content: "", excerpt: "",
                                                status: "draft", author: @user)
  @pending_action = lambda do
    Identity::Nonce.guard(@nonce, @action, session_token: @session_token) do
      @pending_record.publish!(actor: @user)
      :performed
    end
  end
  # The authority is real right now: the guard would let a no-op through.
  expect(Identity::Nonce.guard(@nonce, @action, session_token: @session_token) { :would_run }).to eq(:would_run)
end

Then("the pending action is refused") do
  expect(@pending_action.call).to be_nil
  expect(@pending_record.reload.status).to eq("draft")
  expect(@pending_record.status_transitions.where(to_status: "published")).to be_empty
end

# ── COUPLING 6: posts-and-post-types -> database-wpdb (BR-POST-04, BR-DB-10, RISK-007) ─

Given("a draft with no publication instant") do
  @draft = Publishing::Article.new(title: "Undated draft", content: "", excerpt: "",
                                   status: "draft", published_at: nil, author: integration_author)
end

When("the draft is stored") do
  @draft.save!
end

Then("its publication instant is null") do
  expect(@draft.reload.published_at).to be_nil
  expect(ActiveRecord::Base.connection.select_value("SELECT published_at IS NULL FROM posts WHERE id = #{@draft.id}"))
    .to be(true)
end

Then("the database requires no permissive date mode to accept it") do
  connection = ActiveRecord::Base.connection
  # The representation that needed NO_ZERO_DATE stripped is not merely avoided -- the
  # database refuses it outright, under the same session that just accepted the draft.
  expect { connection.select_value("SELECT '0000-00-00 00:00:00'::timestamptz") }
    .to raise_error(ActiveRecord::StatementInvalid, /out of range/i)
  expect do
    connection.execute("UPDATE posts SET published_at = '0000-00-00 00:00:00' WHERE id = #{@draft.id}")
  end.to raise_error(ActiveRecord::StatementInvalid, /out of range/i)
  # A second draft goes in the same way, with nothing relaxed in between.
  second = integration_article(title: "Second undated draft", status: "draft")
  expect(second.reload.published_at).to be_nil
  expect(Publishing::Post.columns_hash["published_at"].sql_type).to eq("timestamp with time zone")
end

Given("a mix of published records and drafts with no publication instant") do
  # Interleaved, so that insertion order cannot stand in for the ordering under test.
  @mixed = []
  3.times do |i|
    @mixed << integration_article(title: "Published #{i}", published_at: (i + 1).days.ago)
    @mixed << integration_article(title: "Draft #{i}", status: "draft")
  end
  expect(@mixed.count { |r| r.published_at.nil? }).to eq(3)
end

When("records are listed in descending publication order") do
  @listings = Array.new(5) { Publishing::Post.newest_first.pluck(:id, :published_at) }
end

Then("records with no publication instant appear last") do
  listing = @listings.first
  instants = listing.map(&:last)
  dated = instants.compact
  expect(dated.size).to eq(3)
  expect(instants.first(dated.size)).to eq(dated.sort.reverse)
  expect(instants.drop(dated.size).uniq).to eq([nil])
end

Then("the ordering is stable across repeated queries") do
  expect(@listings.uniq.size).to eq(1)
  # Stable for a reason, not by luck: the undated tail has a deterministic tiebreak.
  undated_ids = @listings.first.select { |_, at| at.nil? }.map(&:first)
  expect(undated_ids).to eq(undated_ids.sort.reverse)
end

# ── COUPLING 7: block-supports -> registration order (F-BSUP-01) ─────────────────────

Given("a block with several supports contributing classes") do
  # align, custom classname, generated classname, colors and typography each add a
  # class to the wrapper of core/post-title.
  @block_markup = '<!-- wp:post-title {"align":"wide","className":"coupled","fontSize":"large",' \
                  '"style":{"color":{"text":"#123456","background":"#abcdef"}}} /-->'
  @block_post = integration_article(title: "Coupled title", slug: "coupled-title")
end

When("the block is rendered twice with supports declared in different orders") do
  supports = Composition::Renderers::PostBlocks::Supports
  parsed = Composition::Parser.parse(@block_markup).first
  block = { "blockName" => parsed.block_name, "attrs" => parsed.attrs }
  registry = supports.registry

  # The legacy's WP_Block_Supports iterates its registry in registration order and
  # space-concatenates whatever each support writes (BR-MIGRATE-201). The same eleven
  # supports, the same block, two registration orders.
  @wrappers = [supports::REGISTRATION_ORDER, supports::REGISTRATION_ORDER.reverse].map do |order|
    engine = Styling::BlockSupports.new
    order.each do |name|
      applier = supports::APPLIERS.fetch(name)
      engine.register(name, apply: ->(type, attrs) { supports.public_send(applier, type, attrs) })
    end
    attributes = engine.apply_block_supports(block, registry)
    %(<h2 class="#{attributes["class"]}" style="#{attributes["style"]}">)
  end

  # And the production render, which declares its order once, at boot.
  @rendered = Composition::Renderer.render(@block_markup, Composition::RenderContext.new(post: @block_post))
end

Then("the rendered output is equivalent under class-token normalisation") do
  require Rails.root.join("spec/parity/harness/normalizer")
  normalizer = Parity::Normalizer.new

  first, second = @wrappers
  # The coupling is real: declared in a different order, the raw markup differs...
  expect(first).not_to eq(second)
  expect(first[/class="([^"]*)"/, 1].split.size).to be >= 5
  # ...and under the harness's own class-token normalisation it does not.
  expect(normalizer.call(first)).to eq(normalizer.call(second))

  # The production render carries exactly that class set, whichever order it declared.
  rendered_classes = @rendered[/class="([^"]*)"/, 1].to_s.split
  expect(rendered_classes.sort).to eq(first[/class="([^"]*)"/, 1].split.sort)
end

# ── The gate ─────────────────────────────────────────────────────────────────────────

Given("the set of cross-context couplings recorded in the spec impact matrix") do
  matrix = File.read(IntegrationParityWorld::SDD_ROOT.join("traceability/spec-impact-matrix.md"))
  section = matrix[/^## 6\..*?(?=^## 7\.)/m]
  expect(section).to be_present
  @couplings = section.scan(/^\| `([^`]+)` → (.+?) \| (.+) \|$/).map do |source, targets, mechanism|
    { source: source, targets: targets.scan(/`([^`]+)`/).flatten, mechanism: mechanism,
      rules: mechanism.scan(/\b(?:BR|F|ADR)-[A-Z]+-\d+\b/).uniq }
  end
  expect(@couplings.size).to eq(8)
end

When("the integration checkpoint runs") do
  # Every scenario in the parity suite, with the comment block that introduces it --
  # the Inspector cites the coupling and its rule ids there.
  @scenarios = Dir[Rails.root.join("spec/parity/features/*.feature").to_s].sort.flat_map do |file|
    comment = []
    tags = []
    File.readlines(file).filter_map do |line|
      stripped = line.strip
      if stripped.start_with?("#")
        comment << stripped.delete_prefix("#").strip
        nil
      elsif stripped.start_with?("@")
        tags = stripped.split
        nil
      elsif stripped.match?(/\AScenario( Outline)?:/)
        record = { file: File.basename(file), name: stripped.sub(/\AScenario( Outline)?:\s*/, ""),
                   tags: tags, comment: comment.join(" ") }
        comment = []
        tags = []
        record
      elsif stripped.empty?
        nil
      else
        # A step or a table row ends the comment block for this scenario.
        comment = [] unless stripped.start_with?("Feature:", "As ", "I want", "So that")
        nil
      end
    end
  end
  expect(@scenarios.size).to be > 9

  mentions = lambda do |scenario, coupling|
    scenario[:comment].include?("#{coupling[:source]} ->") ||
      coupling[:rules].any? { |rule| scenario[:comment].include?(rule) }
  end
  @coverage = @couplings.to_h do |coupling|
    [coupling, @scenarios.select { |s| mentions.call(s, coupling) }]
  end
end

Then("every coupling has at least one end-to-end scenario") do
  end_to_end = @coverage.transform_values { |scenarios| scenarios.select { |s| s[:tags].include?("@integration") } }
  uncovered = end_to_end.select { |_, scenarios| scenarios.empty? }.keys

  # ⚠️ A coupling can only be exercised end to end if both of its ends exist. For one
  # row of section 6 the SOURCE module was removed wholesale -- topology_decision.md
  # lists it under "(absorbed by the framework) … removed" and target_business_rules.md
  # records its mechanism as discarded -- so there is no context in the target for the
  # coupling to span. That removal has to be ON THE RECORD, or the coupling is simply
  # untested; the check below demands the record, and the parity report names the row.
  topology = File.read(IntegrationParityWorld::SDD_ROOT.join("migration/topology_decision.md"))
  removed_row = topology.lines.find { |l| l.include?("absorbed by the framework") && l.include?("| removed |") }
  removed_modules = removed_row.to_s.scan(/`([^`]+)`/).flatten
  rules = File.read(IntegrationParityWorld::SDD_ROOT.join("migration/target_business_rules.md"))

  @exempt = uncovered.select do |coupling|
    removed_modules.include?(coupling[:source]) &&
      rules.lines.any? { |l| l.start_with?("| `BR-DISCARD-") && coupling[:rules].any? { |r| l.include?("`#{r}`") } }
  end
  (uncovered - @exempt).each do |coupling|
    raise "coupling #{coupling[:source]} -> #{coupling[:targets].join(", ")} has no @integration scenario"
  end
  @exempt.each do |coupling|
    warn "  [PT-012] coupling #{coupling[:source]} -> #{coupling[:targets].join(", ")}: " \
         "source module removed from the target (topology_decision.md); no end-to-end scenario exists"
  end
  expect(@couplings.size - @exempt.size).to eq(7)
  expect(end_to_end.values.flatten.map { |s| s[:file] }.uniq).to eq([IntegrationParityWorld::INTEGRATION_FEATURE])
end

Then("no coupling is covered only by a single-context test") do
  @coverage.each do |coupling, scenarios|
    next if @exempt.include?(coupling)

    integration = scenarios.select { |s| s[:file] == IntegrationParityWorld::INTEGRATION_FEATURE }
    expect(integration).not_to be_empty,
                               "#{coupling[:source]} is covered only by #{scenarios.map { |s| s[:file] }.uniq.inspect}"
    # And the covering scenario genuinely spans two modules: its header names both ends.
    integration.each do |s|
      expect(s[:comment]).to include(" -> "), "#{s[:name]} names no second context"
      expect(s[:tags]).to include("@integration")
    end
  end
  # The @integration tag is carried by this feature and by nothing else -- a
  # single-context feature cannot claim the checkpoint's coverage by tagging itself.
  tagged_files = @scenarios.select { |s| s[:tags].include?("@integration") }.map { |s| s[:file] }.uniq
  expect(tagged_files).to eq([IntegrationParityWorld::INTEGRATION_FEATURE])
end
