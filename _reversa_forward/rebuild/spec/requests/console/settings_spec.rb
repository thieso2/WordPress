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
end
