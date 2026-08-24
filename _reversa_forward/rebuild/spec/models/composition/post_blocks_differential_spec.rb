# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# BR-MIGRATE-199 — the post + site block family against the PHP oracle.
#
# DIFFERENTIAL, in the strong sense the parser spec established: the oracle supplies BOTH
# halves of every example. `support/post_blocks_oracle.php` dumps the running corpus
# projected onto the target schema AND the HTML `render_block()` produced for each
# case, in one call. Nothing here is a transcription of someone's reading of the legacy —
# handoff.md's whole objection to the 431 rules is that they were "verified by READING,
# never by executing" (AD-08).
#
# ⚠️ TWO NORMALIZATIONS, and both name a real, reported divergence rather than hiding one.
# They are applied to BOTH sides so the rest of the byte comparison stays exact.
# ⚠️ Namespaced deliberately. Constants written inside an RSpec.describe block land on
# Object, and three spec files in this directory already race for the name `BOOTSTRAP`.
module PostBlocksOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE = File.expand_path("support/post_blocks_oracle.php", __dir__)
  CASES = File.expand_path("support/post_blocks_cases.json", __dir__)

  module_function

  def available?
    File.exist?(BOOTSTRAP) && system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  # One PHP process for the whole file: the corpus and the expectations arrive together.
  def payload
    @payload ||= begin
      cases = JSON.parse(File.read(CASES))
      stdout, stderr, status = Open3.capture3(
        { "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP }, "php", BRIDGE, stdin_data: JSON.generate(cases)
      )
      raise "oracle bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout).merge("cases" => cases)
    end
  end
end

RSpec.describe "Composition::Renderers::PostBlocks vs the PHP oracle" do

  # ── The two known divergences ────────────────────────────────────────────────
  #
  # 1. `datetime` / any time-bearing date format. AD-07 + data_migration_plan.md T-01
  #    keep ONE timestamptz and derive the local wall clock from `timezone_string`. The
  #    oracle's corpus was seeded with post_date == post_date_gmt while gmt_offset is +2,
  #    so its own local column disagrees with its own GMT column. The rebuild renders the
  #    GMT instant in the site zone, which is what the plan specifies — one hour later
  #    than the oracle prints. The golden files normalize the ISO datetime to <TIME> and
  #    no golden screen uses a time-bearing format, so no golden byte moves.
  #
  # There is no second entry any more. srcset candidate FILENAMES used to be normalized
  # here, because `asset_variants` has no filename column (target_data_model.md:361) and
  # the port fell back to WordPress's canonical `<base>-<w>x<h>.<ext>` — wrong for this
  # corpus's `med-…` / `large-…` files, on 10 of the 18 golden screens. The filename now
  # survives in `assets.metadata['sizes']`, which the spec's DDL already allows, so the
  # srcset is compared BYTE FOR BYTE like everything else.
  DIVERGENCES = [
    [/datetime="[^"]*"/, 'datetime="<TIME>"'],
    [/\d{2}:\d{2}(?=<\/time>)/, "<CLOCK>"]
  ].freeze

  # `loading`, `fetchpriority` and the `auto, ` prefix on `sizes` are decided by
  # `wp_increase_content_media_count()`, a PHP function-static — page-scoped mutable
  # state. A CLI `render_block()` and a full page render disagree about them for the SAME
  # block, so a block-level differential cannot assert them. They ARE asserted, in the
  # golden form, by post_blocks_spec.rb — "matches the golden files' featured-image
  # loading attributes, not the CLI's" and "core/site-logo against the PHP oracle", the
  # latter running one PHP process PER CASE so the counter is never warm.
  PAGE_SCOPED = [
    [/ loading=['"]lazy['"]/, ""],
    [/ fetchpriority=['"]high['"]/, ""],
    [/sizes=(['"])auto, /, 'sizes=\1']
  ].freeze

  def normalize(html)
    (DIVERGENCES + PAGE_SCOPED).inject(html.to_s) { |acc, (pattern, with)| acc.gsub(pattern, with) }
  end

  # ⚠️ before(:each), never before(:all). `use_transactional_fixtures` wraps each EXAMPLE
  # in a transaction; a before(:all) fixture load happens outside it and LEAKS into every
  # other spec file in the run. The oracle call itself is memoized on the module, so the
  # PHP process still runs only once.
  before do
    skip "PHP oracle not available" unless PostBlocksOracle.available?

    @cases = PostBlocksOracle.payload.fetch("cases")
    @rendered = PostBlocksOracle.payload.fetch("rendered")
    Fixtures.load!(PostBlocksOracle.payload.fetch("fixtures"))
  end

  # Projects the oracle's own rows onto the target schema. Ids are NOT forced — the
  # target's sequences are GENERATED ALWAYS (AD-05) — so every cross-reference is
  # translated through a map, which is also what the real seeding pipeline does.
  module Fixtures
    STATUSES = { "publish" => "published", "future" => "scheduled", "draft" => "draft",
                 "pending" => "pending", "private" => "private", "trash" => "trashed",
                 "auto-draft" => "auto_draft" }.freeze

    class << self
      attr_reader :posts, :terms, :assets, :users, :comments

      def load!(data)
        purge!
        load_settings(data["settings"])
        load_users(data["users"])
        load_terms(data["taxonomies"], data["terms"])
        load_assets(data["assets"])
        load_posts(data["posts"])
        load_assignments(data["assignments"])
        load_comments(data["comments"])
      end

      private

      # ⚠️ Other spec files in this directory seed their own corpora from `before(:all)`,
      # which `use_transactional_fixtures` does NOT roll back — so rows survive across
      # files and across concurrent runs against the shared test database (README §
      # "Run the parity suite through bin/parity_worker"). This purge happens INSIDE the
      # example's transaction, so it is undone when the example ends and it cannot damage
      # anything: it only guarantees this file starts from the corpus it was handed.
      def purge!
        %w[comments term_assignments terms taxonomies asset_variants assets posts users
           settings].each do |table|
          ActiveRecord::Base.connection.execute("DELETE FROM #{table}")
        end
      end

      def load_settings(settings)
        settings.each { |name, value| Configuration::Setting.set(name, value) }
      end

      def load_users(rows)
        @users = {}
        rows.each do |row|
          user = Identity::User.new(
            login: row["login"], nicename: row["nicename"], email: row["email"],
            display_name: row["display_name"], registered_at: row["registered_at"]
          )
          user.password_digest = "$2a$12$#{"x" * 53}"
          user.save!(validate: false)
          @users[row["id"]] = user
        end
      end

      def load_terms(taxonomy_names, rows)
        taxonomies = taxonomy_names.index_with do |name|
          Classification::Taxonomy.create!(name: name, hierarchical: name == "category",
                                           object_types: ["post"])
        end
        @terms = {}
        # Parents before children: the FK and the acyclicity validation both need it.
        remaining = rows.dup
        until remaining.empty?
          progressed = false
          remaining.reject! do |row|
            next false if row["parent"].positive? && !@terms.key?(row["parent"])

            @terms[row["id"]] = Classification::Term.create!(
              taxonomy: taxonomies.fetch(row["taxonomy"]), name: row["name"], slug: row["slug"],
              description: row["description"], count: row["count"],
              parent: row["parent"].positive? ? @terms[row["parent"]] : nil
            )
            progressed = true
          end
          raise "unresolvable term hierarchy" unless progressed
        end
      end

      def load_assets(rows)
        @assets = {}
        rows.each do |row|
          @assets[row["id"]] = Library::Asset.create!(
            title: row["title"], slug: row["name"], mime_type: row["mime_type"],
            alt_text: row["alt"], caption: row["caption"], byte_size: 0,
            uploader: @users[row["uploader"]],
            width: row.dig("metadata", "width"), height: row.dig("metadata", "height"),
            # `sizes` is KEPT, mirroring lib/seeding/pipeline.rb: the per-size DIMENSIONS
            # become Variant rows (AD-03), but the per-size FILENAME has nowhere else to
            # live and `wp_calculate_image_srcset()` needs it.
            metadata: row["metadata"]
          )
          # AD-03: `_wp_attachment_metadata['sizes']` becomes Library::Variant rows.
          (row.dig("metadata", "sizes") || {}).each do |size_name, size|
            @assets[row["id"]].variants.create!(size_name: size_name, width: size["width"],
                                                height: size["height"], mime_type: size["mime-type"])
          end
        end
      end

      # ⚠️ Parents BEFORE children, not a second pass. `posts_slug_hierarchical` is unique
      # on (type, COALESCE(parent_id, 0), slug) — BR-MIGRATE-033 — so inserting the two
      # `child-page` rows with a null parent and fixing them up afterwards collides.
      def load_posts(rows)
        @posts = {}
        remaining = rows.dup
        until remaining.empty?
          progressed = false
          remaining.reject! do |row|
            next false if row["parent"].positive? && !@posts.key?(row["parent"])

            @posts[row["id"]] = build_post(row)
            progressed = true
          end
          raise "unresolvable post hierarchy" unless progressed
        end
      end

      def build_post(row)
        klass = row["type"] == "page" ? Publishing::Page : Publishing::Article
        post = klass.new(
          title: row["title"], slug: row["name"].presence, content: row["content"],
          excerpt: row["excerpt"], status: STATUSES.fetch(row["status"]),
          author: @users[row["author"]], menu_order: row["menu_order"],
          parent_id: row["parent"].positive? ? @posts[row["parent"]].id : nil,
          featured_asset: @assets[row["thumbnail"]],
          password_digest: row["password"].to_s.empty? ? nil : "$2a$12$#{"y" * 53}"
        )
        post.published_at = Time.find_zone("UTC").parse(row["date_gmt"]) if datetime?(row["date_gmt"])
        post.save!(validate: false)
        post.update_column(:modified_at, Time.find_zone("UTC").parse(row["modified_gmt"])) if datetime?(row["modified_gmt"])
        post
      end

      # T-01: the legacy's zero date becomes NULL, and every draft carries one.
      def datetime?(value) = !value.to_s.empty? && !value.to_s.start_with?("0000")

      def load_assignments(rows)
        rows.each_with_index do |row, index|
          Classification::Assignment.create!(term: @terms.fetch(row["term"]),
                                             classifiable: @posts.fetch(row["post"]),
                                             position: index)
        end
      end

      def load_comments(rows)
        @comments = {}
        rows.each do |row|
          @comments[row["id"]] = Discussion::Comment.create!(
            post: @posts.fetch(row["post"]), author_name: row["author_name"],
            author_email: row["author_email"], author_url: row["author_url"],
            content: row["content"], status: "approved",
            submitted_at: Time.find_zone("UTC").parse(row["date_gmt"])
          )
        end
      end
    end
  end

  def resolve_queried(spec)
    return nil if spec.nil?

    case spec["kind"]
    when "term"
      Classification::Term.joins(:taxonomy).find_by(slug: spec["slug"], taxonomies: { name: spec["taxonomy"] })
    when "user" then Identity::User.find_by(login: spec["login"])
    when "date" then spec.slice("year", "monthnum", "day")
    end
  end

  # The target's ids are GENERATED ALWAYS (AD-05), so a fixture load cannot reuse the
  # oracle's. `core/avatar`'s `userId` attribute is the one case that names an id inside
  # the block markup, so it is translated the same way every other cross-reference is.
  def translate_markup(markup)
    markup.gsub(/"userId":(\d+)/) do
      user = Fixtures.users[Regexp.last_match(1).to_i]
      %("userId":#{user ? user.id : Regexp.last_match(1)})
    end
  end

  # `styles` is the one `StyleCollector` shared by EVERY case of a run. The bridge renders
  # all 178 cases in ONE PHP process, so its function-static counters — wp_unique_id()
  # (functions.php:8177, the `is-style-<variation>--<n>` instance) and
  # wp_unique_prefixed_id() (:8196, `wp-elements-<n>`) — keep counting from case to case.
  # The rebuild keys the same counters on the collector (paradigm_decision.md implication
  # 1: no function-statics), so one collector per run is the faithful equivalent of one
  # process per run; a fresh one per case would read `--1` where the oracle reads `--3`.
  def render_case(kase, styles)
    post = kase["post_slug"] ? Publishing::Post.find_by(slug: kase["post_slug"]) : nil
    screen = (kase["screen"] || {}).dup
    screen["queriedObject"] = resolve_queried(screen["queriedObject"]) if screen["queriedObject"]
    context = (kase["context"] || {}).dup
    if kase["context_term"]
      term = Classification::Term.joins(:taxonomy).find_by(
        slug: kase["context_term"]["slug"], taxonomies: { name: kase["context_term"]["taxonomy"] }
      )
      context["termId"] = term&.id
      context["taxonomy"] = kase["context_term"]["taxonomy"]
    end
    # Same id translation as `userId`, for the schema's own `usesContext: [commentId]`.
    if context["commentId"]
      comment = Fixtures.comments[context["commentId"]]
      context["commentId"] = comment.id if comment
    end
    ctx = Composition::RenderContext.new(post: post, styles: styles, context: context.merge(screen))
    Composition::Renderer.render(Composition::Parser.parse(translate_markup(kase["markup"])), ctx)
  end

  # ⚠️ Namespaced for the same reason BOOTSTRAP is: a constant assigned inside an
  # RSpec.describe block lands on Object, and packs/sanitizing already owns the name
  # KNOWN_DIVERGENCES.
  #
  # ⚠️ Named, not silenced. Each entry is a case this family CANNOT reproduce and the
  # reason why; the second example below fails if the set ever grows OR shrinks, so a
  # fix cannot land without deleting its entry here.
  PostBlocksOracle::KNOWN_DIVERGENCES = {
    # Empty, and kept as a table rather than deleted because the two examples below are
    # the contract: the first fails on any divergence not recorded here, the second on
    # any entry that no longer diverges.
    #
    # What used to be listed — the layout support's `wp-container-core-post-content-
    # is-layout-<hash>` class and rule, the child-layout `wp-container-content-<hash>`
    # for `style.layout.selfStretch`, and `wp_get_typography_font_size_value()`'s fluid
    # clamp() for a custom font size — was never a property of these callbacks. It is
    # the `render_block` filter chain (layout.php:984, typography.php), applied to every
    # block by render_block(); `PostBlocks::SupportChain` now delegates the chain to the
    # shared port in `Renderers::LayoutBlocks`, and the bridge applies the root block's
    # `render_block_data` pass exactly as render_block() does.
  }.freeze

  def diverging_cases
    Composition::Renderers::PostBlocks # loading this file is what registers the fifteen names

    styles = Composition::StyleCollector.new
    @cases.each_with_index.filter_map do |kase, index|
      want = @rendered[index]
      got = render_case(kase, styles)
      next if normalize(got) == normalize(want)

      [kase["name"], "want: #{want.inspect}\n    got:  #{got.inspect}"]
    end.to_h
  end

  it "renders every case byte-identically to render_block()" do
    unexpected = diverging_cases.reject { |name, _| PostBlocksOracle::KNOWN_DIVERGENCES.key?(name) }

    expect(unexpected.keys).to eq([]), lambda {
      "#{unexpected.length}/#{@cases.length} diverged:\n  " +
        unexpected.map { |name, detail| "#{name}\n    #{detail}" }.join("\n  ")
    }
  end

  it "diverges on exactly the cases recorded as unreproducible, and no others" do
    actual = diverging_cases
    recorded = PostBlocksOracle::KNOWN_DIVERGENCES.keys.sort
    expect(actual.keys.sort).to eq(recorded), lambda {
      fixed = recorded - actual.keys
      fresh = actual.keys - recorded
      "fixed — delete their entries from KNOWN_DIVERGENCES:\n  #{fixed.join("\n  ")}\n" \
        "new — fix them or record them with a cause:\n  " +
        fresh.map { |name| "#{name}\n    #{actual[name]}" }.join("\n  ")
    }
  end

  it "registers a renderer for all fifteen names in the family" do
    Composition::Renderers::PostBlocks
    names = %w[core/site-title core/site-tagline core/site-logo core/post-title core/post-date
               core/post-author-name core/post-author core/post-terms core/post-content
               core/post-excerpt core/post-featured-image core/post-navigation-link
               core/query-title core/term-description core/avatar]
    expect(names.reject { |name| Composition::Renderers.for(name) }).to eq([])
  end
end
