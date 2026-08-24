# frozen_string_literal: true

require "rails_helper"
require_relative "oracle"

# Presentation::TemplateResolver / BodyClass / DocumentTitle, against the live oracle.
#
# ⚠️ DIFFERENTIAL. The three things asserted here — which template renders a URL, the body
# classes and the title — are each produced by a long chain of conditionals in the legacy
# (template-loader.php:67, post-template.php:639, general-template.php:1385), and the
# chains INTERACT: `is_front_page()` matching but yielding nothing is what sends `/` to
# `home`, and `is_privacy_policy()` matching but yielding nothing is what sends
# /privacy-policy/ to `page`. Nobody writes those expectations correctly from memory, so
# none are written here: the oracle is asked and the answers are compared.
RSpec.describe "Presentation screen resolution" do
  PRESENTATION_ORACLE = Presentation::SpecOracle
  PRESENTATION_CORPUS = PRESENTATION_ORACLE.available? ? PRESENTATION_ORACLE.corpus : nil
  PRESENTATION_SCREENS = PRESENTATION_ORACLE.available? ? PRESENTATION_ORACLE.screens : nil

  before do
    skip "the PHP oracle is not available" if PRESENTATION_CORPUS.nil?

    # ⚠️ Retried, and the reason is environmental rather than logical: several families
    # are working this wave in parallel and `bundle exec rspec` uses a SINGLE
    # `rebuild_test` database, so another suite's transaction can hold the very rows this
    # one replaces. PostgreSQL resolves that as a deadlock on one side. Retrying is the
    # standard remedy; the alternative — TRUNCATE — would take an ACCESS EXCLUSIVE lock
    # and break everyone else's examples instead of this one.
    attempts = 0
    begin
      # A SAVEPOINT, so a failed attempt rolls back to a usable transaction instead of
      # leaving an aborted one every later statement would bounce off.
      ActiveRecord::Base.transaction(requires_new: true) { seed! }
    rescue ActiveRecord::Deadlocked, ActiveRecord::RecordNotUnique
      attempts += 1
      sleep(0.2 * attempts)
      retry if attempts < 8
      raise
    end
  end

  # ── the comparison ────────────────────────────────────────────────────────────────

  # The oracle's answer is a FILE PATH plus `$_wp_current_template_id`; the target's is a
  # row. Both reduce to a slug, and `null` on the oracle side means "not a block template
  # at all", which is the embed screen.
  def oracle_template_slug(screen)
    id = PRESENTATION_SCREENS.dig(screen, "template_id")
    id&.split("//")&.last
  end

  # Ids are the one thing that cannot match: the target's sequences start fresh and T-06
  # keys terms on term_taxonomy_id, so `tag-6` here is `tag-3` there. The parity harness
  # makes exactly this allowance (spec/parity/harness/normalizer.rb:44); the seeded rows
  # below carry the oracle's ids so that even this is only a safety net.
  def strip_ids(tokens)
    tokens.map { |t| t.gsub(/(?<=-)\d+\z/, "<ID>") }
  end

  it "resolves the same template as the oracle for every corpus screen" do
    mismatches = screens.filter_map do |name, screen|
      expected = oracle_template_slug(name)
      actual = Presentation::TemplateResolver.new(theme_slug: "twentytwentyfive").resolve(screen).slug
      "#{name}: oracle=#{expected.inspect} target=#{actual.inspect}" if expected != actual
    end
    expect(mismatches).to eq([])
  end

  # The fall-through is the part of template-loader.php that a case statement would get
  # wrong, so it is asserted as a fact about the RESULT, not about the code.
  it "falls through a conditional that holds but yields no template" do
    resolver = Presentation::TemplateResolver.new(theme_slug: "twentytwentyfive")
    # `/` is both the front page and the blog home; `front-page` does not exist.
    expect(screens["web.index"].front_page?).to be(true)
    expect(resolver.resolve(screens["web.index"]).type).to eq(:home)
    # /privacy-policy/ is a privacy policy AND a page; `privacy-policy` does not exist.
    expect(screens["web.privacy_policy"].privacy_policy?).to be(true)
    expect(resolver.resolve(screens["web.privacy_policy"]).type).to eq(:page)
    # Every archive shape reaches `archive` only after its own type yields nothing.
    %w[web.category web.tag web.author web.date web.taxonomy].each do |name|
      expect(resolver.resolve(screens[name]).type).to eq(:archive), name
    end
  end

  it "builds the same candidate hierarchy as the oracle, type by type" do
    resolver = Presentation::TemplateResolver.new(theme_slug: "twentytwentyfive")
    mismatches = []
    screens.each do |name, screen|
      (PRESENTATION_SCREENS.dig(name, "hierarchy") || {}).each do |type, files|
        expected = files.map { |f| f.sub(/\.(php|html)\z/, "") }
        actual = resolver.hierarchy_for(type.to_sym, screen)
        mismatches << "#{name}/#{type}: oracle=#{expected.inspect} target=#{actual.inspect}" if expected != actual
      end
    end
    expect(mismatches).to eq([])
  end

  it "produces the same body classes as get_body_class()" do
    mismatches = screens.filter_map do |name, screen|
      next if name == "web.embed" # rendered by wp-includes/theme-compat/embed.php, not here

      expected = strip_ids(PRESENTATION_SCREENS.dig(name, "body_class")).sort
      actual = strip_ids(Presentation::BodyClass.new(screen, theme_slug: "twentytwentyfive").to_a).sort
      "#{name}:\n  oracle=#{expected.inspect}\n  target=#{actual.inspect}" if expected != actual
    end
    expect(mismatches).to eq([])
  end

  it "produces the same document title as wp_get_document_title()" do
    mismatches = screens.filter_map do |name, screen|
      expected = PRESENTATION_SCREENS.dig(name, "title")
      actual = Presentation::DocumentTitle.new(screen).to_s
      "#{name}:\n  oracle=#{expected.inspect}\n  target=#{actual.inspect}" if expected != actual
    end
    expect(mismatches).to eq([])
  end

  # ── the screens, stated the way the controllers state them ────────────────────────

  def screens
    @screens ||= begin
      s = Presentation::Screen
      article = Publishing::Article.find_by(slug: "hello-world")
      {
        "web.index" => s.new(kind: :home),
        "web.singular" => s.new(kind: :single, post: article),
        "web.page" => s.new(kind: :page, post: Publishing::Page.find_by(slug: "parent-page")),
        # The middle rung of the oracle's three-level page tree: parent 23, child 24,
        # grandchild 25. It is the only screen that reaches post-template.php:723.
        "web.page_child" => s.new(kind: :page, post: Publishing::Page.find_by(slug: "child-page")),
        "web.archive" => s.new(kind: :date, year: 2026),
        "web.category" => s.new(kind: :category, term: term("top-category")),
        "web.tag" => s.new(kind: :tag, term: term("flat-tag-one")),
        "web.taxonomy" => s.new(kind: :category, term: term("middle-category")),
        "web.author" => s.new(kind: :author, author: Identity::User.find_by(login: "oracle_author")),
        "web.date" => s.new(kind: :date, year: 2026, month: 3),
        "web.search" => s.new(kind: :search, search_query: "article", found_posts: 3),
        "web.not_found_404" => s.new(kind: :not_found),
        "web.embed" => s.new(kind: :single, post: article, embed: true),
        "web.privacy_policy" => s.new(kind: :page, post: Publishing::Page.find_by(slug: "privacy-policy")),
      }
    end
  end

  def term(slug) = Classification::Term.joins(:taxonomy).find_by(slug: slug)

  # ── seeding ───────────────────────────────────────────────────────────────────────

  def seed!
    clear_corpus_rows!
    # ⚠️ SORTED, and not for tidiness. Several suites run against one `rebuild_test`
    # concurrently this wave; two transactions that update the same `settings` rows in
    # DIFFERENT orders deadlock, while two that use the same order simply queue. Writing
    # in name order is the cheapest thing one side can do about it unilaterally.
    PRESENTATION_CORPUS["options"].sort.each do |name, value|
      next if value.nil? || value == false

      Configuration::Setting.find_or_initialize_by(name: name).update!(value: value.to_s)
    end
    Presentation::Theme.find_or_create_by!(slug: "twentytwentyfive") { |t| t.version = "1.5" }
                       .update!(active: true, theme_json: Presentation::Assets.theme_json)
    Composition::Template.where(theme_slug: "twentytwentyfive").delete_all
    JSON.parse(File.read(Rails.root.join("db/theme/templates.json"))).each do |row|
      Composition::Template.create!(theme_slug: "twentytwentyfive", kind: row["kind"],
                                    slug: row["slug"], area: row["area"],
                                    title: row["title"], content: row["content"])
    end
    PRESENTATION_CORPUS["users"].each do |u|
      insert_row!("users",
                  { "id" => u["id"], "login" => u["login"], "nicename" => u["login"],
                    "display_name" => u["display_name"], "email" => "#{u["login"]}@example.test",
                    "password_digest" => "x", "registered_at" => Time.current },
                  unique: %w[login email])
    end
    PRESENTATION_CORPUS["terms"].each do |t|
      taxonomy = Classification::Taxonomy.find_or_create_by!(name: t["taxonomy"]) do |tx|
        tx.hierarchical = t["taxonomy"] == "category"
      end
      insert_row!("terms", { "id" => t["id"], "taxonomy_id" => taxonomy.id, "name" => t["name"],
                             "slug" => t["slug"], "parent_id" => (t["parent"].zero? ? nil : t["parent"]),
                             "description" => "", "count" => 0 }, unique: %w[slug])
    end
    PRESENTATION_CORPUS["posts"].each do |p|
      insert_row!("posts",
                  { "id" => p["id"],
                    "type" => p["type"] == "page" ? "Publishing::Page" : "Publishing::Article",
                    "slug" => p["slug"], "title" => p["title"], "content" => "", "excerpt" => "",
                    "status" => "published", "published_at" => p["date"],
                    "parent_id" => (p["parent"].zero? ? nil : p["parent"]),
                    "template_slug" => p["template"], "comment_status" => p["comment_status"],
                    "comment_count" => p["comment_count"], "menu_order" => 0,
                    "guid" => SecureRandom.uuid, "author_id" => PRESENTATION_CORPUS["users"].first["id"] },
                  unique: %w[slug])
    end
  end

  # One DELETE per table, children first, before any INSERT. Interleaving deletes and
  # inserts across three tables is what turns a contended `rebuild_test` into a four-way
  # deadlock; doing all the removal up front, posts before users, keeps the FK's
  # `UPDATE posts SET author_id = NULL` from firing at all.
  def clear_corpus_rows!
    conn = ActiveRecord::Base.connection
    post_ids = PRESENTATION_CORPUS["posts"].map { |p| p["id"] }
    post_slugs = PRESENTATION_CORPUS["posts"].map { |p| conn.quote(p["slug"]) }
    conn.execute("DELETE FROM posts WHERE id IN (#{post_ids.join(",")}) OR slug IN (#{post_slugs.join(",")})")
    term_ids = PRESENTATION_CORPUS["terms"].map { |t| t["id"] }
    term_slugs = PRESENTATION_CORPUS["terms"].map { |t| conn.quote(t["slug"]) }
    conn.execute("DELETE FROM terms WHERE id IN (#{term_ids.join(",")}) OR slug IN (#{term_slugs.join(",")})")
    user_ids = PRESENTATION_CORPUS["users"].map { |u| u["id"] }
    logins = PRESENTATION_CORPUS["users"].map { |u| conn.quote(u["login"]) }
    conn.execute("DELETE FROM users WHERE id IN (#{user_ids.join(",")}) OR login IN (#{logins.join(",")})")
  end

  # `posts.id` is GENERATED ALWAYS AS IDENTITY, and the ids MATTER here — `page-23` is a
  # rung of the page template hierarchy. OVERRIDING SYSTEM VALUE is the only way to make
  # the target's inputs identical to the oracle's.
  #
  # ⚠️ `DELETE` first, and no TRUNCATE. The suite is run concurrently against a single
  # `rebuild_test` database while several families work in parallel, so a row with this id
  # may already be there from a run that was interrupted; a TRUNCATE would take an ACCESS
  # EXCLUSIVE lock across everyone else's examples.
  def insert_row!(table, attributes, unique: []) # rubocop:disable Lint/UnusedMethodArgument
    conn = ActiveRecord::Base.connection
    columns = attributes.keys
    conn.execute(<<~SQL)
      INSERT INTO #{conn.quote_table_name(table)}
        (#{columns.map { |c| conn.quote_column_name(c) }.join(", ")})
        OVERRIDING SYSTEM VALUE
        VALUES (#{columns.map { |c| conn.quote(attributes[c]) }.join(", ")})
    SQL
  end
end
