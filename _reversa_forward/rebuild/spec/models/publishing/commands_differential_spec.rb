# frozen_string_literal: true

require "rails_helper"
require "open3"
require "json"

# AGG-Post's accepted commands against the live PHP oracle.
#
# DIFFERENTIAL, for the reason parser_spec.rb and layout_blocks_spec.rb give: a spec that
# asserted what this author believes wp_update_post() does would reproduce exactly the
# weakness the oracle exists to remove (handoff.md: the rules "were verified by READING,
# never by executing"). So support/commands_probe.php runs every command through
# WordPress 7.2-alpha-63330's own write API and prints the ROW STATE that results; the
# same commands are then run here and the two states compared.
#
# ⚠️ RISK-002: the probe WRITES to the oracle -- through wp_insert_post and friends, never
# the database directly -- and force-deletes everything it created. The seeded corpus is
# left as found; `bin/oracle reseed` restores it if a run is interrupted.
#
# Two divergences are asserted AS divergences rather than hidden, because the
# specification chose them (see the parity report):
#   * restore returns the PRIOR status (target_domain_model.md AGG-Post, PT-001); the
#     unfiltered legacy default since 5.6 is 'draft' (post.php:4210);
#   * a trashed record KEEPS its slug; the legacy renames it `<slug>__trashed`
#     (post.php:8613) to free the slug for a new record, a rule the Curator did not
#     migrate and the seeding pipeline does not carry (`_wp_desired_post_slug` is
#     dropped).
RSpec.describe "Publishing commands against the oracle", type: :model do
  include ActiveSupport::Testing::TimeHelpers
  after { travel_back }

  PROBE = File.expand_path("support/commands_probe.php", __dir__)
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  before(:all) do
    skip "no PHP oracle on PATH" unless system("php -v > /dev/null 2>&1")
    skip "oracle not installed" unless File.exist?(BOOTSTRAP)
    out, err, status = Open3.capture3("php", PROBE)
    raise "oracle probe failed: #{err}" unless status.success?

    @oracle = JSON.parse(out)
  end

  let(:oracle) { @oracle }

  # The legacy's status vocabulary, as data_migration_plan.md maps it.
  LEGACY_STATUS = { "publish" => "published", "future" => "scheduled", "trash" => "trashed",
                    "draft" => "draft", "pending" => "pending", "private" => "private" }.freeze

  def legacy_revisions(key)
    oracle.fetch(key).map { |r| [r["post_title"], r["post_content"], r["post_name"].include?("autosave")] }
  end

  def ours_revisions(post)
    post.revisions.reload.oldest_first.map { |r| [r.title, r.content, r.autosave] }
  end

  def purge!
    %w[comments term_assignments terms taxonomies assets posts users settings redirects]
      .each { |table| ActiveRecord::Base.connection.execute("DELETE FROM #{table}") }
  end

  let(:actor) do
    Identity::User.create!(login: "probe_admin", email: "probe@example.com", nicename: "probe-admin",
                           password: "correct horse battery staple", display_name: "Probe")
  end
  let(:taxonomy) { Classification::Taxonomy.create!(name: "category", hierarchical: true, object_types: ["Publishing::Post"]) }
  let(:term) { Classification::Term.create!(taxonomy: taxonomy, name: "Reversa probe category", slug: "reversa-probe-category") }

  before do
    purge!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    @post = Publishing::Article.create!(title: "Reversa probe", content: "v1", excerpt: "",
                                        status: "draft", author: actor)
    Classification::Assignment.create!(term: term, classifiable: @post)
  end

  it "create: a draft has no slug, no publication instant and no revision" do
    expect(oracle["create_draft"]).to include("post_status" => "draft", "post_name" => "",
                                              "post_date_gmt" => "0000-00-00 00:00:00")
    expect(@post.status).to eq("draft")
    expect(@post.slug).to be_nil                        # '' in the legacy; NULL here (BR-MIGRATE-032)
    expect(@post.published_at).to be_nil                # '0000-00-00 00:00:00' there; NULL here (RISK-007)
    expect(@post.revisions.count).to eq(oracle["create_draft_revisions"])
    expect(term.reload.count).to eq(oracle["count_after_assign_to_draft"])
  end

  it "publish: allocates the slug, stamps the instant, records the first revision, counts" do
    @post.publish!(actor: actor)
    expect(LEGACY_STATUS.fetch(oracle["publish"]["post_status"])).to eq(@post.status)
    expect(@post.slug).to eq(oracle["publish"]["post_name"])
    expect(@post.published_at).to be_present
    expect(ours_revisions(@post)).to eq(legacy_revisions("publish_revisions"))
    expect(term.reload.count).to eq(oracle["count_after_publish"])
  end

  it "unpublish: back to draft, slug and instant retained, the count falls" do
    @post.publish!(actor: actor)
    @post.unpublish!(actor: actor)
    expect(LEGACY_STATUS.fetch(oracle["unpublish"]["post_status"])).to eq(@post.status)
    expect(@post.slug).to eq(oracle["unpublish"]["post_name"])
    expect(oracle["unpublish"]["post_date_gmt"]).not_to eq("0000-00-00 00:00:00")
    expect(@post.published_at).to be_present
    expect(term.reload.count).to eq(oracle["count_after_unpublish"])
  end

  it "republish: a formerly published draft keeps its original instant (post.php:4748)" do
    @post.publish!(actor: actor)
    first_instant = @post.published_at
    travel 90.seconds
    @post.unpublish!(actor: actor)
    @post.publish!(actor: actor)
    expect(oracle["republish"]["post_date_gmt"]).to eq(oracle["publish"]["post_date_gmt"])
    expect(@post.published_at).to eq(first_instant)
    expect(LEGACY_STATUS.fetch(oracle["republish"]["post_status"])).to eq(@post.status)
    expect(@post.slug).to eq(oracle["republish"]["post_name"])
  end

  it "normalize_whitespace: byte-for-byte with formatting.php:5590, including what trim() leaves alone" do
    expect(oracle["normalize_whitespace"].size).to eq(8)
    oracle["normalize_whitespace"].each do |input_hex, expected_hex|
      input = [input_hex].pack("H*").force_encoding(Encoding::UTF_8)
      expect(Publishing::Revision.normalize_whitespace(input).b.unpack1("H*")).to eq(expected_hex),
        "normalize_whitespace(#{input.inspect}) diverges from the oracle"
    end
  end

  it "update with a slug change: the old slug becomes a redirect, and renaming back retires it" do
    @post.publish!(actor: actor)
    structure = Routing::PermalinkStructure.current
    @post.update!(slug: "reversa-probe-renamed")
    expect(@post.slug).to eq(oracle["rename"]["post_name"])
    old_paths = Routing::Redirect.where(post_id: @post.id).pluck(:from_path)
    expect(old_paths).to eq(oracle["rename_old_slugs"].map { |s| structure.path_for(@post, slug: s) })

    @post.update!(slug: "reversa-probe")
    old_paths = Routing::Redirect.where(post_id: @post.id).pluck(:from_path)
    expect(old_paths).to eq(oracle["rename_back_old_slugs"].map { |s| structure.path_for(@post, slug: s) })
  end

  it "revise: a revision per changed update, none for an unchanged or whitespace-only one" do
    expect(Publishing::Post::REVISIONS_TO_KEEP).to eq(oracle["revisions_to_keep"])
    @post.publish!(actor: actor)
    @post.update!(slug: "reversa-probe-renamed")
    @post.update!(slug: "reversa-probe")
    @post.update!(content: "v2")
    expect(ours_revisions(@post)).to eq(legacy_revisions("revise_after_content_change"))
    @post.update!(content: "v2")
    expect(ours_revisions(@post)).to eq(legacy_revisions("revise_after_no_change"))
    @post.update!(content: "v2  \n")
    expect(ours_revisions(@post)).to eq(legacy_revisions("revise_after_whitespace_change"))
    @post.update!(title: "Reversa probe v3")
    expect(ours_revisions(@post)).to eq(legacy_revisions("revise_after_title_change"))
  end

  it "autosave: one per author, overwritten in place, deleted when identical to the record" do
    # The probe's own sequence, in the probe's own order: the whitespace-only edit lands
    # BEFORE the title change, so the title revision carries "v2  \n".
    @post.publish!(actor: actor)
    @post.update!(content: "v2")
    @post.update!(content: "v2  \n")
    @post.update!(title: "Reversa probe v3")
    a1 = @post.autosave!(title: "Reversa probe v3", content: "autosaved A", actor: actor)
    expect(ours_revisions(@post)).to eq(legacy_revisions("autosave_first"))
    a2 = @post.autosave!(title: "Reversa probe v3", content: "autosaved B", actor: actor)
    expect(ours_revisions(@post)).to eq(legacy_revisions("autosave_second_same_author"))
    expect(a1.id == a2.id).to eq(oracle["autosave_ids_equal"])
    a3 = @post.autosave!(title: "Reversa probe v3", content: "v2", actor: actor)
    expect(ours_revisions(@post)).to eq(legacy_revisions("autosave_identical_to_post"))
    expect(a3).to be_nil                                 # the legacy answers 0
    expect(oracle["autosave_identical_return"]).to eq(0)
  end

  it "schedule: a future instant schedules, arms the publication and counts nothing until due" do
    @post.publish!(actor: actor)
    @post.schedule!(at: 2.days.from_now, actor: actor)
    expect(LEGACY_STATUS.fetch(oracle["schedule"]["post_status"])).to eq(@post.status)
    expect(@post.slug).to eq(oracle["schedule"]["post_name"])
    armed = ActiveJob::Base.queue_adapter.enqueued_jobs.any? do |job|
      job[:job] == Publishing::PublishScheduledJob && job[:args] == [@post.id]
    end
    expect(armed).to eq(oracle["schedule_cron_event"])
    expect(term.reload.count).to eq(oracle["count_while_scheduled"])

    # The moment arrives (the probe moves the date into the past the same way).
    @post.update_columns(published_at: 2.minutes.ago)
    expect(@post.reload.publish_due!).to be(true)
    expect(LEGACY_STATUS.fetch(oracle["publish_due"]["post_status"])).to eq(@post.status)
    expect(@post.published_at).to be < Time.current   # the date is not rewritten by publication
    expect(term.reload.count).to eq(oracle["count_after_due"])
  end

  it "trash and restore: the prior status is kept in a column; two recorded divergences" do
    @post.publish!(actor: actor)
    @post.trash!(actor: actor)
    expect(LEGACY_STATUS.fetch(oracle["trash"]["post_status"])).to eq(@post.status)
    expect(@post.status_before_trash).to eq(LEGACY_STATUS.fetch(oracle["trash_meta_status"].first))
    expect(@post.trashed_at).to be_present
    expect(term.reload.count).to eq(oracle["count_after_trash"])

    # DIVERGENCE 1 (recorded): the legacy frees the slug by renaming it; this keeps it.
    expect(oracle["trash"]["post_name"]).to eq("reversa-probe__trashed")
    expect(oracle["trash_desired_slug"]).to eq(["reversa-probe"])
    expect(@post.slug).to eq("reversa-probe")

    @post.restore!(actor: actor)
    # DIVERGENCE 2 (specified): prior status here, 'draft' there (post.php:4210).
    expect(oracle["restore"]["post_status"]).to eq("draft")
    expect(@post.status).to eq("published")
    expect(@post.status_before_trash).to be_nil
    expect(@post.trashed_at).to be_nil
    expect(oracle["restore_meta_status"]).to eq([])
    expect(@post.slug).to eq(oracle["restore"]["post_name"])
  end

  it "delete: revisions, comments, attributes and assignments go; children move up a level" do
    parent = Publishing::Page.create!(title: "Reversa probe parent", slug: "reversa-probe-parent", content: "",
                                      excerpt: "", status: "published", published_at: 1.day.ago)
    victim = Publishing::Page.create!(title: "Reversa probe victim", slug: "reversa-probe-victim", parent: parent,
                                      content: "", excerpt: "", status: "published", published_at: 1.day.ago)
    child = Publishing::Page.create!(title: "Reversa probe child", slug: "reversa-probe-child", parent: victim,
                                     content: "", excerpt: "", status: "published", published_at: 1.day.ago)
    Publishing::Attribute.create!(post: victim, key: "reversa_probe_key", value: "value")
    victim.update!(content: "revised")
    Discussion::Comment.create!(post: victim, status: "approved", content: "probe", submitted_at: Time.current,
                                author_name: "probe", author_email: "probe@example.com",
                                author_ip: "203.0.113.1", user_agent: "probe")
    before = { "revisions" => victim.revisions.count,
               "comments" => Discussion::Comment.where(post_id: victim.id).count,
               "meta" => Publishing::Attribute.where(post_id: victim.id).count,
               "child_parent" => child.reload.parent_id == victim.id }
    expect(before).to eq(oracle["delete_before"])

    victim_id = victim.id
    victim.delete!(actor: actor)
    after = { "row" => Publishing::Post.find_by(id: victim_id),
              "revisions" => Publishing::Revision.where(post_id: victim_id).count,
              "comments" => Discussion::Comment.where(post_id: victim_id).count,
              "meta" => Publishing::Attribute.where(post_id: victim_id).count,
              "child_reparented_to" => child.reload.parent_id == parent.id ? "grandparent" : child.parent_id.to_s,
              "term_relationships" => Classification::Assignment.where(classifiable_type: "Publishing::Post",
                                                                       classifiable_id: victim_id).count }
    expect(after).to eq(oracle["delete_after"])

    # And the classified record: its assignments and its contribution to the count go too.
    @post.publish!(actor: actor)
    expect(term.reload.count).to eq(1)
    post_id = @post.id
    @post.delete!(actor: actor)
    expect(term.reload.count).to eq(oracle["count_after_delete"])
    expect(Classification::Assignment.where(classifiable_type: "Publishing::Post", classifiable_id: post_id).count)
      .to eq(oracle["delete_classified_relationships"])
  end
end
