# frozen_string_literal: true

require_relative "console_spec_helper"

# The nine settings screens (target_screens.md § Settings screens). Modernized mode:
# no golden files. What is asserted is (1) the single auth gate (auth_redirect →
# /login), (2) the capability wp_die() with its LITERAL string, (3) the LITERAL titles
# and labels, and (4) the SAVE RESULT against the settings row, including the special
# rules — home fallback (BR-OPT-12), esc_html at rest (BR-MIGRATE-014), and the
# permalink recompute/refusal (BR-POST-07).
RSpec.describe "console.settings", type: :request do
  before do
    host! "127.0.0.1"
    seed_console_accounts!
  end

  describe "the single auth gate (auth_redirect, admin.php:104)" do
    it "redirects an anonymous request to /login carrying redirect_to" do
      get "/console/settings"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login?redirect_to=")
      expect(response.headers["Location"]).to include(CGI.escape("/console/settings"))
    end
  end

  describe "the capability gate (options-general.php:15)" do
    it "answers a logged-in non-admin with the LITERAL wp_die string at 403" do
      login_as("con_subscriber")
      get "/console/settings"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Sorry, you are not allowed to manage options for this site.")
    end
  end

  describe "GET /console/settings (general)" do
    before { login_as("con_admin") }

    it "renders the LITERAL title and field labels" do
      get "/console/settings"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("General Settings")
      expect(response.body).to include("Site Title")
      expect(response.body).to include("Tagline")
      expect(response.body).to include("WordPress Address (URL)")
      expect(response.body).to include("New User Default Role")
    end

    it "renders each sibling section with its LITERAL title" do
      { "/console/settings/writing" => "Writing Settings",
        "/console/settings/reading" => "Reading Settings",
        "/console/settings/discussion" => "Discussion Settings",
        "/console/settings/media" => "Media Settings",
        "/console/settings/permalinks" => "Permalink Settings",
        "/console/settings/privacy" => "Privacy",
        "/console/settings/connectors" => "Connectors" }.each do |path, title|
        get path
        expect(response).to have_http_status(:ok), "#{path} did not render"
        expect(response.body).to include(title), "#{path} missing #{title.inspect}"
      end
    end
  end

  describe "POST /console/settings — a save writes through Configuration::Setting" do
    before { login_as("con_admin") }

    it "persists declared fields and shows the LITERAL 'Settings saved.' notice" do
      post "/console/settings", params: {
        blogname: "My Site", blogdescription: "A tagline", siteurl: "http://example.test",
        home: "http://example.test", timezone_string: "UTC", date_format: "F j, Y",
        time_format: "g:i a", users_can_register: "1", default_role: "author"
      }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("Settings saved.")

      expect(Configuration::Setting["blogname"]).to eq("My Site")
      expect(Configuration::Setting["users_can_register"]).to eq("1")
      expect(Configuration::Setting["default_role"]).to eq("author")
    end

    it "stores an unchecked checkbox as '0' (options.php whitelist behaviour)" do
      Configuration::Setting.set("users_can_register", "1")
      post "/console/settings", params: { blogname: "x" } # no users_can_register param
      expect(Configuration::Setting["users_can_register"]).to eq("0")
    end

    # BR-MIGRATE-014 (BR-OPT-15): sanitize_option esc_html's blogname on write, so it is
    # HTML-escaped at rest — the same value the legacy stores.
    it "HTML-escapes blogname on write (esc_html, ENT_QUOTES, no double-encode)" do
      post "/console/settings", params: { blogname: %(He said "hi" & <b>bold</b>) }
      expect(Configuration::Setting["blogname"]).to eq("He said &quot;hi&quot; &amp; &lt;b&gt;bold&lt;/b&gt;")
    end

    # BR-MIGRATE-012 (BR-OPT-12): get_option('home') empty falls back to siteurl.
    it "falls back home → siteurl when home is saved empty" do
      post "/console/settings", params: { blogname: "x", siteurl: "http://siteurl.test", home: "" }
      expect(Configuration::Setting["home"]).to eq("http://siteurl.test")
    end
  end

  describe "POST /console/settings/discussion — the moderation policy options" do
    before { login_as("con_admin") }

    it "writes the moderation keys and flags Discussion::ModerationPolicy reads" do
      post "/console/settings/discussion", params: {
        comment_moderation: "1", comment_max_links: "5",
        moderation_keys: "spammy\nbadword", disallowed_keys: "slur"
      }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["comment_moderation"]).to eq("1")
      expect(Configuration::Setting["comment_max_links"]).to eq(5)
      expect(Configuration::Setting["moderation_keys"]).to eq("spammy\nbadword")
      expect(Configuration::Setting["disallowed_keys"]).to eq("slur")
    end
  end

  describe "POST /console/settings/permalinks — BR-POST-07 recompute + refusal" do
    before { login_as("con_admin") }

    it "applies a valid structure and stores it" do
      post "/console/settings/permalinks", params: { selection: "/%postname%/" }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("Permalink structure updated.")
      expect(Configuration::Setting["permalink_structure"]).to eq("/%postname%/")
    end

    it "REFUSES a structure that would shadow an already-published slug and names it" do
      # 'blog' is a legal slug under the default structure (no literal segments), but a
      # structure with a literal /blog/ prefix reserves it — the collision the legacy
      # resolves silently by leaving the post unreachable.
      Publishing::Article.create!(author: actor("con_admin"), title: "Blog post",
                                  slug: "blog", status: :published, published_at: Time.current)
      post "/console/settings/permalinks", params: { selection: "custom", permalink_structure: "/blog/%postname%/" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("blog")
      expect(response.body).to include("was not changed")
      # unchanged: the structure in force before is still in force.
      expect(Configuration::Setting["permalink_structure"]).not_to eq("/blog/%postname%/")
    end
  end

  describe "POST /console/settings/privacy" do
    before { login_as("con_admin") }

    it "selects a page and stores its id" do
      page = Publishing::Page.create!(author: actor("con_admin"), title: "Policy", slug: "policy",
                                      status: :published, published_at: Time.current)
      post "/console/settings/privacy", params: { page_for_privacy_policy: page.id.to_s }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["wp_page_for_privacy_policy"]).to eq(page.id)
    end

    it "requires manage_privacy_options with its OWN LITERAL refusal" do
      login_as("con_subscriber")
      get "/console/settings/privacy"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Sorry, you are not allowed to manage privacy options on this site.")
    end
  end

  # ── General: Administration Email Address + Week Starts On (options-general.php:265,577)
  describe "GET /console/settings (general) — admin email and week start" do
    before { login_as("con_admin") }

    it "renders the Administration Email Address field bound to admin_email" do
      Configuration::Setting.set("admin_email", "boss@example.test")
      get "/console/settings"
      expect(response.body).to include("Administration Email Address")
      expect(response.body).to include(%(name="new_admin_email"))
      expect(response.body).to include("boss@example.test")
      expect(response.body).to include("an email will be sent to your new address to confirm it")
    end

    it "renders the Week Starts On weekday select" do
      get "/console/settings"
      expect(response.body).to include("Week Starts On")
      expect(response.body).to include(%(name="start_of_week"))
      %w[Sunday Monday Saturday].each { |d| expect(response.body).to include(d) }
    end

    it "persists new_admin_email and start_of_week on save" do
      post "/console/settings", params: {
        blogname: "x", new_admin_email: "new@example.test", start_of_week: "6"
      }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["new_admin_email"]).to eq("new@example.test")
      expect(Configuration::Setting["start_of_week"]).to eq(6)
    end
  end

  # ── Writing: the Formatting fieldset (options-writing.php:70-77)
  describe "GET/POST /console/settings/writing — Formatting" do
    before { login_as("con_admin") }

    it "renders the Formatting flags with their LITERAL labels" do
      get "/console/settings/writing"
      expect(response.body).to include("Formatting")
      expect(response.body).to include("Convert emoticons like")
      expect(response.body).to include("to graphics on display")
      expect(response.body).to include("WordPress should correct invalidly nested XHTML automatically")
    end

    it "persists use_smilies and use_balanceTags (unchecked stores '0')" do
      Configuration::Setting.set("use_smilies", "1")
      post "/console/settings/writing", params: { use_balanceTags: "1" } # no use_smilies
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["use_balanceTags"]).to eq("1")
      expect(Configuration::Setting["use_smilies"]).to eq("0")
    end
  end

  # ── Reading: feed content length (options-reading.php:190-195)
  describe "GET/POST /console/settings/reading — rss_use_excerpt" do
    before { login_as("con_admin") }

    it "renders the Full text / Excerpt control" do
      get "/console/settings/reading"
      expect(response.body).to include("For each post in a feed, include")
      expect(response.body).to include("Full text")
      expect(response.body).to include("Excerpt")
      expect(response.body).to include(%(name="rss_use_excerpt"))
    end

    it "persists rss_use_excerpt" do
      post "/console/settings/reading", params: { show_on_front: "posts", rss_use_excerpt: "1" }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["rss_use_excerpt"]).to eq(1)
    end
  end

  # ── Discussion: the full comment-behaviour set (options-discussion.php:48-193)
  describe "GET/POST /console/settings/discussion — the full option set" do
    before { login_as("con_admin") }

    it "renders every functional comment-behaviour label VERBATIM" do
      get "/console/settings/discussion"
      [
        "Default post settings",
        "Attempt to notify any blogs linked to from the post",
        "Allow link notifications from other blogs (pingbacks and trackbacks) on new posts",
        "Allow people to submit comments on new posts",
        "Comment author must fill out name and email",
        "Users must be registered and logged in to comment",
        "Show comments cookies opt-in checkbox, allowing comment author cookies to be set",
        "Enable threaded (nested) comments",
        "Number of levels for threaded (nested) comments",
        "Comment Pagination",
        "Break comments into pages",
        "Top level comments per page",
        "Comments page to display by default",
        "Comments to display at the top of each page",
        "Email me whenever",
        "Anyone posts a comment",
        "A comment is held for moderation",
      ].each { |s| expect(response.body).to include(s), "missing #{s.inspect}" }
    end

    it "persists the default-post, threading, pagination and notify options" do
      post "/console/settings/discussion", params: {
        default_pingback_flag: "1", default_ping_status: "open", default_comment_status: "open",
        require_name_email: "1", comment_registration: "1",
        show_comments_cookies_opt_in: "1", thread_comments: "1", thread_comments_depth: "7",
        page_comments: "1", comments_per_page: "25", default_comments_page: "oldest", comment_order: "desc",
        comments_notify: "1", moderation_notify: "1"
      }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["default_pingback_flag"]).to eq("1")
      expect(Configuration::Setting["default_ping_status"]).to eq("open")
      expect(Configuration::Setting["default_comment_status"]).to eq("open")
      expect(Configuration::Setting["comment_registration"]).to eq("1")
      expect(Configuration::Setting["thread_comments_depth"]).to eq(7)
      expect(Configuration::Setting["comments_per_page"]).to eq(25)
      expect(Configuration::Setting["default_comments_page"]).to eq("oldest")
      expect(Configuration::Setting["comment_order"]).to eq("desc")
      expect(Configuration::Setting["moderation_notify"]).to eq("1")
    end

    it "stores an unchecked open/closed status as '' (closed)" do
      Configuration::Setting.set("default_comment_status", "open")
      post "/console/settings/discussion", params: { comment_moderation: "1" } # no status
      expect(Configuration::Setting["default_comment_status"]).to eq("")
    end
  end

  # ── Permalinks: the Optional category/tag base section (options-permalink.php:408-453)
  describe "GET/POST /console/settings/permalinks — Optional bases" do
    before { login_as("con_admin") }

    it "renders the Optional category/tag base inputs" do
      get "/console/settings/permalinks"
      expect(response.body).to include("Optional")
      expect(response.body).to include("Category base")
      expect(response.body).to include("Tag base")
      expect(response.body).to include(%(name="category_base"))
      expect(response.body).to include(%(name="tag_base"))
    end

    it "persists a slash-normalized category_base and tag_base alongside a valid structure" do
      post "/console/settings/permalinks", params: {
        selection: "/%postname%/", category_base: "topics", tag_base: "labels"
      }
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["category_base"]).to eq("/topics")
      expect(Configuration::Setting["tag_base"]).to eq("/labels")
    end

    it "stores an empty base as '' (defaults used)" do
      post "/console/settings/permalinks", params: {
        selection: "/%postname%/", category_base: "", tag_base: ""
      }
      expect(Configuration::Setting["category_base"]).to eq("")
      expect(Configuration::Setting["tag_base"]).to eq("")
    end
  end
end
