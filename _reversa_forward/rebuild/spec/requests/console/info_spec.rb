# frozen_string_literal: true

require_relative "console_spec_helper"

# console.about / console.credits / console.freedoms / console.contribute —
# wp-admin/about.php, credits.php, freedoms.php, contribute.php.
#
# These four screens are ALMOST ENTIRELY WordPress project identity, which DEV-009 drops,
# so they are the one place in the rebuild where "verbatim" is a scalpel. What this spec
# pins is therefore three things at once:
#
#   1. the GATE — `read`, i.e. any signed-in user; logged out is bounced to /login;
#   2. the IA — wp-admin's own: the shared secondary nav-tab bar (What's New / Credits /
#      Freedoms / Privacy / Get Involved, in that order, current tab marked), each screen's
#      heading, and the return-to-dashboard link;
#   3. HONESTY — the strings that MUST survive (the four freedoms, the tab labels, the
#      return link) are present verbatim, and the project-identity text that must NOT be
#      reproduced, and the fabricated contributor/version claims that must never appear,
#      are absent.
RSpec.describe "console.about / .credits / .freedoms / .contribute", type: :request do
  # /console/get-involved is wired by the integrator (returned in routes_to_add). Until it
  # exists the tab falls back to the slug route already in config/routes.rb, and the
  # examples that assert the canonical path skip, so the suite is green either way.
  def get_involved_wired?
    Rails.application.routes.url_helpers.respond_to?(:console_get_involved_path)
  end

  SCREENS = {
    "/console/about"      => "About",
    "/console/credits"    => "Credits",
    "/console/freedoms"   => "The Four Freedoms",
    "/console/contribute" => "Get Involved"
  }.freeze

  before do
    host! "127.0.0.1"
    seed_console_accounts!
  end

  # ── the gate: `read`, held by every role ──────────────────────────────────────────
  describe "authorization" do
    SCREENS.each_key do |path|
      it "bounces an anonymous visitor from #{path} to /login" do
        get path
        expect(response).to have_http_status(:found)
        expect(response.headers["Location"]).to include("/login?redirect_to=")
      end
    end

    SCREENS.each do |path, heading|
      it "renders #{path} for a subscriber (the `read` capability)" do
        login_as("con_subscriber")
        get path
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text.strip).to eq(heading)
      end
    end
  end

  # ── the shared secondary nav-tab bar (about.php:52-58 and its three twins) ────────
  describe "the secondary nav-tab bar" do
    before { login_as("con_subscriber") }

    let(:expected_labels) { ["What’s New", "Credits", "Freedoms", "Privacy", "Get Involved"] }

    SCREENS.each_key do |path|
      it "renders every tab, in wp-admin's order, on #{path}" do
        get path
        tabs = doc.css("nav.about-tabs a")
        expect(tabs.map { |a| a.text.strip }).to eq(expected_labels)
      end
    end

    it "uses the LITERAL 'What&#8217;s New' label and the 'Secondary menu' aria-label" do
      get "/console/about"
      expect(response.body).to include("What&#8217;s New")
      expect(doc.at_css("nav.about-tabs")["aria-label"]).to eq("Secondary menu")
    end

    {
      "/console/about"      => "What’s New",
      "/console/credits"    => "Credits",
      "/console/freedoms"   => "Freedoms",
      "/console/contribute" => "Get Involved"
    }.each do |path, current_label|
      it "marks #{current_label.inspect} as the current tab on #{path}" do
        get path
        current = doc.css("nav.about-tabs a[aria-current='page']")
        expect(current.size).to eq(1)
        expect(current.first.text.strip).to eq(current_label)
      end
    end

    it "links the tabs to this build's own routes, never to wordpress.org" do
      get "/console/freedoms"
      hrefs = doc.css("nav.about-tabs a").map { |a| a["href"] }
      expect(hrefs[0, 4]).to eq(%w[/console/about /console/credits /console/freedoms /console/privacy])
      expect(hrefs.last).to eq(get_involved_wired? ? "/console/get-involved" : "/console/contribute")
    end
  end

  # ── console.about ────────────────────────────────────────────────────────────────
  describe "console.about" do
    before { login_as("con_admin") }

    it "reports the runtime it is ACTUALLY running, not a written-down version" do
      get "/console/about"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(RUBY_VERSION)
      expect(response.body).to include(Rails.version)
      # …and the row labels that carry them.
      expect(body_text).to include("Ruby")
      expect(body_text).to include("Rails")
      expect(body_text).to include("Database")
    end

    it "names the decisions that actually changed against the legacy" do
      get "/console/about"
      expect(body_text).to include("No plugins, no hooks")
      expect(body_text).to include("Authorization is declared at the route")
      expect(body_text).to include("The menu is declared, not registered")
      expect(body_text).to include("Destructive bulk actions confirm first")
    end

    it "carries about.php's LITERAL return-to-dashboard link" do
      get "/console/about"
      expect(response.body).to include("Go to Dashboard &rarr; Home")
      expect(doc.at_css(".about-return a")["href"]).to eq("/console")
    end

    it "does NOT migrate about.php's release announcement (DEV-009)" do
      get "/console/about"
      expect(response.body).not_to include("Welcome to WordPress")
      expect(response.body).not_to include("WordPress 7.1")
      expect(response.body).not_to include("Field Guide")
      expect(response.body).not_to include("See everything new")
      expect(response.body).not_to include("Learn WordPress")
    end

    it "offers the site-health pointer only to a user who may follow it (BR-CAP-05)" do
      get "/console/about"
      expect(response.body).to include("/console/tools/site-health/info")

      login_as("con_subscriber")
      get "/console/about"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("/console/tools/site-health/info")
    end
  end

  # ── console.credits ──────────────────────────────────────────────────────────────
  describe "console.credits" do
    before { login_as("con_subscriber") }

    it "states the build's provenance instead of a contributor list" do
      get "/console/credits"
      expect(response).to have_http_status(:ok)
      expect(body_text).to include("Provenance")
      expect(body_text.squish).to include("This build has no contributor roster")
      expect(body_text).to include("_reversa_sdd/")
    end

    it "NEVER fabricates a contributor, a team or a sponsor" do
      get "/console/credits"
      # every group title credits.php keeps translatable for the API response
      ["Project Leaders", "Noteworthy Contributors", "Cofounder, Project Lead",
       "Lead Developer", "Release Lead", "Core Developer", "Core Contributors",
       "Want to see your name in lights on this page?",
       "Created by a worldwide team of passionate individuals"].each do |fabrication|
        expect(response.body).not_to include(fabrication)
      end
    end

    it "makes no external request and shows no wordpress.org link" do
      get "/console/credits"
      expect(response.body).not_to include("wordpress.org")
      expect(response.body).not_to match(%r{https?://})
    end

    it "lists the External Libraries actually loaded, with their real versions" do
      get "/console/credits"
      expect(body_text).to include("External Libraries") # credits.php:135, LITERAL
      row = doc.css("table.about-facts tr").find { |tr| tr.at_css("th")&.text&.strip == "rails" }
      expect(row).to be_present
      expect(row.at_css("td").text.strip).to eq(Gem.loaded_specs["rails"].version.to_s)
      expect(row.at_css("td").text.strip).to eq(Rails.version)
    end
  end

  # ── console.freedoms ─────────────────────────────────────────────────────────────
  describe "console.freedoms" do
    before { login_as("con_subscriber") }

    # freedoms.php:62-83 — the ONE block of text on these four screens that is a genuine
    # license statement rather than project identity. Verbatim, in order.
    FOUR_FREEDOMS = [
      ["The 1st Freedom", "To run the program for any purpose."],
      ["The 2nd Freedom", "To study how the program works and change it to make it do what you wish."],
      ["The 3rd Freedom", "To redistribute."],
      ["The 4th Freedom", "To distribute copies of your modified versions to others."]
    ].freeze

    it "keeps the four freedom statements VERBATIM and in order" do
      get "/console/freedoms"
      expect(response).to have_http_status(:ok)
      panels = doc.css(".about-columns.is-4 .panel")
      expect(panels.size).to eq(4)
      FOUR_FREEDOMS.each_with_index do |(heading, statement), i|
        expect(panels[i].at_css("h3").text.strip).to eq(heading)
        expect(panels[i].at_css("p").text.strip).to eq(statement)
      end
    end

    it "keeps freedoms.php's LITERAL heading" do
      get "/console/freedoms"
      expect(doc.at_css("h1").text.strip).to eq("The Four Freedoms")
    end

    it "drops the WordPress-specific framing around them (DEV-009)" do
      get "/console/freedoms"
      ["WordPress is free and open source software",
       "worldview-changing",
       "WordPress Foundation",
       "trademark",
       "wordpress.org"].each do |dropped|
        expect(response.body).not_to include(dropped)
      end
      expect(response.body).not_to match(%r{https?://})
    end

    it "claims no licence for this build that it cannot show" do
      get "/console/freedoms"
      expect(body_text.squish).to include("this build ships no license file of its own")
    end
  end

  # ── console.contribute ───────────────────────────────────────────────────────────
  describe "console.contribute" do
    before { login_as("con_subscriber") }

    it "keeps contribute.php's LITERAL title and its two lanes" do
      get "/console/contribute"
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text.strip).to eq("Get Involved")
      expect(body_text).to include("No-code contribution")   # contribute.php:58, LITERAL
      expect(body_text).to include("Code-based contribution") # contribute.php:87, LITERAL
    end

    it "describes THIS build's languages, not the legacy project's" do
      get "/console/contribute"
      expect(body_text).to include("Ruby on Rails")
      expect(body_text).to include("PostgreSQL")
      expect(body_text).to include("Hotwire")
      expect(response.body).not_to include("Kotlin")
      expect(response.body).not_to include("Objective-C")
      expect(response.body).not_to include("Block Editor: HTML, CSS, PHP")
    end

    it "drops every wordpress.org destination (DEV-009)" do
      get "/console/contribute"
      ["make.wordpress.org", "WordCamps", "WordPress.tv", "Photo Directory",
       "Be the future of WordPress", "Find your team",
       "Shape the future of the web with WordPress"].each do |dropped|
        expect(response.body).not_to include(dropped)
      end
      expect(response.body).not_to match(%r{https?://})
    end

    it "is also reachable at /console/get-involved once the route is wired" do
      skip "GET /console/get-involved not yet wired by the integrator" unless get_involved_wired?
      get "/console/get-involved"
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text.strip).to eq("Get Involved")
      current = doc.css("nav.about-tabs a[aria-current='page']")
      expect(current.first.text.strip).to eq("Get Involved")
    end
  end
end
