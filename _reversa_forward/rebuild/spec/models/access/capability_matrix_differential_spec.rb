# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# BR-MIGRATE-097..110 -- the capability matrix against the PHP oracle.
#
# DIFFERENTIAL in the strong sense: `support/capabilities_oracle.php` dumps the running
# corpus projected onto the target schema AND what `user_can()` answered for every
# corpus user (plus anonymous) x every ported arm x every object, in one call. The
# rebuild loads that corpus, asks its policies the same questions, and the two answer
# sheets are compared line by line. Nothing here is a transcription of someone's reading
# of capabilities.php -- handoff.md's objection to the 431 rules is that they were
# "verified by READING, never by executing" (AD-08).
#
# ⚠️ Namespaced deliberately: constants written inside an RSpec.describe block land on
# Object, and several spec files in this tree already race for the name `BOOTSTRAP`.
module CapabilitiesOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE = File.expand_path("support/capabilities_oracle.php", __dir__)

  module_function

  def available?
    File.exist?(BOOTSTRAP) && system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  # One PHP process for the whole file.
  def payload
    @payload ||= begin
      stdout, stderr, status = Open3.capture3({ "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP }, "php", BRIDGE)
      raise "oracle bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end
  end

  # Projects the oracle's rows onto the target schema. Ids are NOT forced -- the target's
  # sequences are GENERATED ALWAYS (AD-05) -- so every cross-reference is translated
  # through a map, which is also what lib/seeding/pipeline.rb does.
  class Fixtures
    STATUSES = { "publish" => "published", "future" => "scheduled", "draft" => "draft",
                 "pending" => "pending", "private" => "private", "trash" => "trashed",
                 "auto-draft" => "auto_draft" }.freeze
    COMMENT_STATUSES = { "1" => "approved", "0" => "pending", "spam" => "spam",
                         "trash" => "trashed", "post-trashed" => "trashed" }.freeze

    attr_reader :users, :posts, :assets, :comments, :terms

    def initialize(data)
      @data = data
      @users = {}
      @posts = {}
      @assets = {}
      @comments = {}
      @terms = {}
    end

    def load!
      purge!
      load_users
      load_posts
      load_assets
      load_comments
      load_terms
      load_settings
      self
    end

    # Anonymous is user 0 in the legacy; nil actor here.
    def actor(oracle_id) = oracle_id.zero? ? nil : users.fetch(oracle_id)

    def object(kind, oracle_id)
      case kind
      when "post"    then posts.fetch(oracle_id)
      when "asset"   then assets.fetch(oracle_id)
      when "comment" then comments.fetch(oracle_id)
      when "term"    then terms.fetch(oracle_id)
      when "user"    then users.fetch(oracle_id)
      end
    end

    private

    # Inside the example's transaction, so it is undone when the example ends.
    def purge!
      %w[comments term_assignments terms taxonomies asset_variants assets posts
         role_assignments users settings].each do |table|
        ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
      end
    end

    def load_users
      @data["users"].each do |row|
        user = Identity::User.new(login: row["login"], nicename: row["nicename"], email: row["email"],
                                  display_name: row["display_name"])
        user.password_digest = "$2a$12$#{"x" * 53}"
        user.save!(validate: false)
        row["roles"].each { |role| user.assign_role(role) }
        @users[row["id"]] = user
      end
    end

    # Parents BEFORE children: posts_slug_hierarchical is unique on (type, parent, slug).
    def load_posts
      remaining = @data["posts"].dup
      until remaining.empty?
        progressed = false
        remaining.reject! do |row|
          next false if row["parent"].positive? && !@posts.key?(row["parent"])

          @posts[row["id"]] = build_post(row)
          progressed = true
        end
        raise "unresolvable page hierarchy" unless progressed
      end
    end

    def build_post(row)
      status = STATUSES.fetch(row["status"])
      klass = row["type"] == "page" ? Publishing::Page : Publishing::Article
      post = klass.new(
        title: row["title"], content: "", excerpt: "", status: status,
        slug: row["name"].presence, author: @users[row["author"]],
        parent: row["parent"].positive? ? @posts[row["parent"]] : nil
      )
      # The corpus's scheduled post must stay scheduled relative to THIS clock, and
      # BR-MIGRATE-029 resolves status from the date -- so the date is stated here.
      post.published_at =
        if status == "scheduled"
          1.year.from_now
        elsif %w[published private].include?(status)
          Time.zone.parse("#{row['date_gmt']} UTC")
        end
      if status == "trashed"
        # AD-03: `_wp_trash_meta_status` becomes a column; an absent meta reads as
        # `draft`, the same default lib/seeding/pipeline.rb applies.
        post.status_before_trash = STATUSES.fetch(row["trash_status"].presence || "draft")
        post.trashed_at = Time.current
      end
      post.save!
      post
    end

    def load_assets
      @data["assets"].each do |row|
        @assets[row["id"]] = Library::Asset.create!(
          title: row["title"], slug: row["name"], mime_type: row["mime_type"], byte_size: 0,
          uploader: @users[row["uploader"]]
        )
      end
    end

    def load_comments
      @data["comments"].each do |row|
        @comments[row["id"]] = Discussion::Comment.create!(
          post: @posts.fetch(row["post"]), user: row["user"].positive? ? @users[row["user"]] : nil,
          content: row["content"].presence || "(empty)", author_name: row["author_name"].to_s,
          status: COMMENT_STATUSES.fetch(row["approved"])
        )
      end
    end

    def load_terms
      taxonomies = %w[category post_tag].index_with do |name|
        Classification::Taxonomy.create!(name: name, hierarchical: name == "category", object_types: ["post"])
      end
      remaining = @data["terms"].dup
      until remaining.empty?
        progressed = false
        remaining.reject! do |row|
          next false if row["parent"].positive? && !@terms.key?(row["parent"])

          @terms[row["id"]] = Classification::Term.create!(
            taxonomy: taxonomies.fetch(row["taxonomy"]), name: row["name"], slug: row["slug"],
            parent: row["parent"].positive? ? @terms[row["parent"]] : nil
          )
          progressed = true
        end
        raise "unresolvable term hierarchy" unless progressed
      end
    end

    # The post-id settings are translated through the maps, as POST_ID_SETTINGS does in
    # the seeding pipeline; `default_category` through the term map.
    def load_settings
      @data["settings"].each do |name, value|
        next if value == false

        translated =
          case name
          when "page_on_front", "page_for_posts", "wp_page_for_privacy_policy"
            value.to_i.positive? ? @posts.fetch(value.to_i).id : 0
          when "default_category", "default_term_category", "default_post_tag", "default_term_post_tag"
            value.to_i.positive? ? @terms.fetch(value.to_i).id : 0
          else value
          end
        Configuration::Setting.set(name, translated)
      end
    end
  end
end

RSpec.describe "Access policies vs the PHP oracle (map_meta_cap + has_cap)" do
  # The legacy asks `user_can( $id, $cap, $object )`; the rebuild asks a policy for an
  # action. This is the whole translation table between the two vocabularies.
  def evaluate(fixtures, expectation)
    actor = fixtures.actor(expectation["user"])
    cap = expectation["cap"]
    record = expectation["kind"] == "none" ? nil : fixtures.object(expectation["kind"], expectation["object"])

    case expectation["kind"]
    when "none"    then Access::SitePolicy.new(actor, nil).permit?(cap)
    when "post"    then Access::PostPolicy.for(actor, record).permit?(cap.sub(/_post\z/, ""))
    when "asset"   then Access::AssetPolicy.new(actor, record).permit?(cap.sub(/_post\z/, ""))
    when "comment" then Access::CommentPolicy.new(actor, record).permit?(:edit)
    when "term"    then Access::TermPolicy.new(actor, record).permit?(cap.sub(/_term\z/, ""))
    when "user"    then Access::UserPolicy.new(actor, record).permit?(cap.sub(/_user\z/, ""))
    end
  end

  before do
    skip "PHP oracle not available" unless CapabilitiesOracle.available?
  end

  let(:payload) { CapabilitiesOracle.payload }
  let(:fixtures) { CapabilitiesOracle::Fixtures.new(payload["fixtures"]).load! }

  it "asks the oracle a matrix large enough to mean something" do
    kinds = payload["expectations"].map { |e| e["kind"] }.tally
    expect(payload["fixtures"]["users"].map { |u| u["roles"] }.flatten.uniq.sort)
      .to eq(%w[administrator author contributor editor subscriber])
    expect(kinds.keys).to match_array(%w[none post asset comment term user])
    expect(payload["expectations"].length).to be > 1000
  end

  it "answers every user_can() question exactly as the oracle does" do
    divergences = payload["expectations"].filter_map do |e|
      got = evaluate(fixtures, e)
      next if got == e["allowed"]

      format("user %-2d %-28s %-7s %-3s oracle=%-5s rebuild=%s", e["user"], e["cap"], e["kind"],
             e["object"].to_s, e["allowed"], got)
    end

    expect(divergences).to be_empty, <<~MSG
      #{divergences.length} of #{payload['expectations'].length} capability answers diverge from the oracle:

      #{divergences.first(80).join("\n")}
      #{divergences.length > 80 ? "… (#{divergences.length - 80} more)" : ''}
    MSG
  end

  # The arms the matrix exercises, named so a regression in the file is visible as a
  # regression in a rule rather than a count.
  describe "the distinctions the matrix covers" do
    let(:by) do
      payload["expectations"].group_by { |e| [e["user"], e["cap"], e["kind"], e["object"]] }
                             .transform_values { |v| v.first["allowed"] }
    end
    let(:users) { payload["fixtures"]["users"].to_h { |u| [u["roles"].first, u["id"]] } }
    let(:posts) { payload["fixtures"]["posts"] }

    def post_where(status:, author_role:)
      posts.find { |p| p["type"] == "post" && p["status"] == status && p["author"] == users.fetch(author_role) }
    end

    it "BR-CAP-01: the non-owner `_others_` branch ANDs the `_published_` capability" do
      published = post_where(status: "publish", author_role: "author")
      expect(by[[users["editor"], "edit_post", "post", published["id"]]]).to be(true)
      expect(by[[users["contributor"], "edit_post", "post", published["id"]]]).to be(false)
    end

    it "the owner of a draft needs edit_posts; of a published post edit_published_posts" do
      draft = post_where(status: "draft", author_role: "author")
      published = post_where(status: "publish", author_role: "author")
      expect(by[[users["author"], "edit_post", "post", draft["id"]]]).to be(true)
      expect(by[[users["author"], "edit_post", "post", published["id"]]]).to be(true)
      expect(by[[users["contributor"], "edit_post", "post", draft["id"]]]).to be(false)
    end

    it "a private post of someone else requires `_private_`" do
      private_post = post_where(status: "private", author_role: "author")
      expect(by[[users["editor"], "read_post", "post", private_post["id"]]]).to be(true)
      expect(by[[users["contributor"], "read_post", "post", private_post["id"]]]).to be(false)
      expect(by[[users["author"], "read_post", "post", private_post["id"]]]).to be(true)
    end

    it "the privacy policy page additionally requires manage_options" do
      policy_page = payload["fixtures"]["settings"]["wp_page_for_privacy_policy"].to_i
      skip "corpus has no privacy policy page" unless policy_page.positive?

      expect(by[[users["editor"], "edit_post", "post", policy_page]]).to be(false)
      expect(by[[users["administrator"], "edit_post", "post", policy_page]]).to be(true)
    end

    it "BR-CAP-06/07: nobody can edit user 0, and anyone may edit themselves" do
      expect(by[[0, "edit_user", "user", users["subscriber"]]]).to be(false)
      expect(by[[users["subscriber"], "edit_user", "user", users["subscriber"]]]).to be(true)
      expect(by[[users["subscriber"], "edit_user", "user", users["editor"]]]).to be(false)
    end

    it "BR-CAP-10: an object arm asked without an object fails closed" do
      expect(by[[users["administrator"], "edit_post", "none", nil]]).to be(false)
      expect(by[[users["administrator"], "delete_page", "none", nil]]).to be(false)
    end

    it "BR-CAP-02/04: do_not_allow is never held and exist always is" do
      expect(by[[users["administrator"], "do_not_allow", "none", nil]]).to be(false)
      expect(by[[0, "exist", "none", nil]]).to be(true)
    end

    it "BR-CAP-15: contributors can neither publish posts nor upload files" do
      expect(by[[users["contributor"], "publish_posts", "none", nil]]).to be(false)
      expect(by[[users["contributor"], "upload_files", "none", nil]]).to be(false)
      expect(by[[users["author"], "upload_files", "none", nil]]).to be(true)
    end
  end
end
