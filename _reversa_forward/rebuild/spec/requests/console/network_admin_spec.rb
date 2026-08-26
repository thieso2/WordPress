# frozen_string_literal: true

require_relative "console_spec_helper"
require_relative "../../tenancy/tenancy_helper"

# The NETWORK ADMIN screens — wp-admin/network/*.php (ms-*.php are the 3.0 shims that
# forward there) plus my-sites.php. MODERNIZED mode: no goldens, so what is asserted is
#   (1) THE ACCEPTANCE GATE — multisite is off by default and every one of these URLs must
#       be absent, not merely refused, while it is;
#   (2) the capability gate, which is the super-admin bypass and nothing else;
#   (3) the LITERAL strings, verbatim from the cited legacy file;
#   (4) the WRITE RESULT against the model rows.
RSpec.describe "Console network admin", type: :request do
  include TenancyHelper

  # Every network URL this track added. Used whole by the acceptance-gate examples.
  NETWORK_PATHS = [
    "/console/network",
    "/console/network/sites",
    "/console/network/sites/new",
    "/console/network/users",
    "/console/network/users/new",
    "/console/network/themes",
    "/console/network/settings",
    "/console/my-sites"
  ].freeze

  before { host! "127.0.0.1" }

  # ───────────────────────────────────────────────────────────────────────────────────
  # (1) THE ACCEPTANCE GATE. Multisite is OFF by default; nothing here may exist.
  # ───────────────────────────────────────────────────────────────────────────────────
  describe "with multisite disabled (the default)" do
    before { seed_console_accounts! }

    it "is off by default" do
      expect(Tenancy.enabled?).to be(false)
    end

    it "404s every network URL for a signed-in administrator, with my-sites.php's own message" do
      login_as("con_admin")
      NETWORK_PATHS.each do |path|
        get path
        expect(response).to have_http_status(:not_found), "expected 404 for #{path}, got #{response.status}"
        expect(response.body).to include("Multisite support is not enabled.")
      end
    end

    it "404s for an anonymous request too — the screen does not exist, it is not merely refused" do
      NETWORK_PATHS.each do |path|
        get path
        expect(response).to have_http_status(:not_found), "expected 404 for #{path}, got #{response.status}"
        expect(response.headers["Location"]).to be_nil
      end
    end

    it "404s the write endpoints as well" do
      login_as("con_admin")
      post "/console/network/settings", params: { site_name: "Nope" }
      expect(response).to have_http_status(:not_found)
      post "/console/network/sites/bulk", params: { bulk_action: "delete", ids: [1] }
      expect(response).to have_http_status(:not_found)
    end

    it "leaves the single-site console menu untouched — no Network entry anywhere" do
      login_as("con_admin")
      get "/console"
      expect(response).to have_http_status(:ok)
      labels = doc.css("nav.adminmenu > ul > li > a span").map(&:text)
      expect(labels).not_to include("Network")
      expect(response.body).not_to include("/console/network")
    end

    it "leaves the single-site screens themselves untouched" do
      login_as("con_admin")
      get "/console/users"
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("Users")
    end
  end

  # ───────────────────────────────────────────────────────────────────────────────────
  # With multisite ON.
  # ───────────────────────────────────────────────────────────────────────────────────
  describe "with multisite enabled" do
    around { |example| with_multisite { example.run } }

    before do
      seed_console_accounts!
      @main = Tenancy::Site.create!(domain: "main.example", path: "/", name: "Main Site",
                                    schema_name: "site_main", registered_at: 3.days.ago)
      @other = Tenancy::Site.create!(domain: "other.example", path: "/", name: "Other Site",
                                     schema_name: "site_other", registered_at: 2.days.ago)
    end

    def make_super_admin!(login = "con_admin")
      Tenancy::NetworkSetting["site_admins"] = [actor(login).id]
    end

    # ── (2) the capability gate ─────────────────────────────────────────────────────
    describe "authorization" do
      it "redirects an unauthenticated request to /login (auth_redirect runs once the network exists)" do
        get "/console/network"
        expect(response).to have_http_status(:found)
        expect(response.headers["Location"]).to include("/login?")
      end

      it "refuses an ordinary administrator who is not a super admin, with the verbatim wp_die string" do
        login_as("con_admin")
        get "/console/network"
        expect(response).to have_http_status(:forbidden)
        # network/index.php:16
        expect(body_text).to include("Sorry, you are not allowed to access this page.")
      end

      it "refuses every network screen to a non-super-admin" do
        login_as("con_admin")
        %w[/console/network /console/network/sites /console/network/users
           /console/network/themes /console/network/settings].each do |path|
          get path
          expect(response).to have_http_status(:forbidden), "expected 403 for #{path}"
        end
      end

      it "uses network/themes.php's own more specific refusal on the Themes screen" do
        login_as("con_editor")
        get "/console/network/themes"
        expect(response).to have_http_status(:forbidden)
        # network/themes.php:14
        expect(body_text).to include("Sorry, you are not allowed to manage network themes.")
      end

      it "admits a SUPER ADMIN — the `site_admins` network option is the only source (BR-CAP-14)" do
        make_super_admin!
        login_as("con_admin")
        get "/console/network"
        expect(response).to have_http_status(:ok)
      end

      it "admits a super admin who holds NO role capabilities at all — the bypass is not a role" do
        subscriber = actor("con_subscriber")
        Tenancy::NetworkSetting["site_admins"] = [subscriber.id]
        login_as("con_subscriber")
        get "/console/network/settings"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to eq("Network Settings")
      end
    end

    # ── console.ms-admin ────────────────────────────────────────────────────────────
    describe "console.ms-admin (/console/network)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders the Right Now widget with both quick links and the counts sentence" do
        get "/console/network"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to eq("Dashboard")
        expect(body_text).to include("Right Now")
        # dashboard.php:458, :461
        expect(body_text).to include("Create a New Site").and include("Create a New User")
        # dashboard.php:468-473 — 'You have %1$s and %2$s.'
        expect(body_text).to include("You have 2 sites and #{Identity::User.count} users.")
      end

      it "renders both search forms, pointing at the Users and Sites screens" do
        get "/console/network"
        actions = doc.css("form").map { |f| f["action"] }
        expect(actions).to include("/console/network/users", "/console/network/sites")
        expect(body_text).to include("Search Users").and include("Search Sites")
      end

      it "uses the singular 'site' when the network has exactly one" do
        @other.destroy!
        get "/console/network"
        expect(body_text).to include("You have 1 site and")
      end
    end

    # ── console.ms-sites ────────────────────────────────────────────────────────────
    describe "console.ms-sites (/console/network/sites)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders the LITERAL title, columns and both sites as rows" do
        get "/console/network/sites"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("Sites")
        expect(column_headers).to include("URL", "Last Updated", "Registered", "Users")
        expect(body_text).to include("main.example").and include("other.example")
      end

      it "marks the first site 'Main' and gives it only Edit / Dashboard / Visit" do
        row = doc_for("/console/network/sites").at_css("tr#console\\.ms-sites-#{@main.id}")
        expect(row.text).to include("Main")
        labels = action_labels(row)
        expect(labels).to include("Edit", "Dashboard", "Visit")
        expect(labels).not_to include("Delete Permanently", "Archive")
        expect(row.at_css("input[name='ids[]']")).to be_nil
      end

      it "gives a non-main site the seven row actions, verbatim" do
        row = doc_for("/console/network/sites").at_css("tr#console\\.ms-sites-#{@other.id}")
        labels = action_labels(row)
        # :740-868
        expect(labels).to include("Edit", "Dashboard", "Flag for Deletion", "Archive",
                                  "Spam", "Delete Permanently", "Visit")
      end

      it "offers the three bulk actions" do
        get "/console/network/sites"
        options = doc.css("select[name=bulk_action] option").map(&:text)
        # :302-309
        expect(options).to include("Delete", "Mark as spam", "Not spam")
      end

      it "renders the status views only for statuses with a positive count" do
        @other.update!(archived: true)
        get "/console/network/sites"
        tabs = doc.css("ul.subsubsub a").map { |a| a.text.strip }
        expect(tabs.join(" ")).to include("All").and include("Archived")
        expect(tabs.join(" ")).not_to include("Flagged for Deletion")
      end

      it "filters to a status view" do
        @other.update!(spam: true)
        get "/console/network/sites?status=spam"
        expect(body_text).to include("other.example")
        expect(body_text).not_to include("main.example")
      end

      it "searches by site address" do
        get "/console/network/sites?s=other"
        expect(body_text).to include("other.example")
        expect(body_text).not_to include("main.example")
      end

      it "counts the users of each site from the per-site role rows (BR-MS-04)" do
        actor("con_editor").assign_role("administrator", site_id: @other.id)
        actor("con_author").assign_role("author", site_id: @other.id)
        row = doc_for("/console/network/sites").at_css("tr#console\\.ms-sites-#{@other.id}")
        expect(row.at_css("td.column-users").text.strip).to eq("2")
      end

      it "says 'No sites found.' when the filter matches nothing" do
        get "/console/network/sites?s=nothing-matches-this"
        expect(body_text).to include("No sites found.")
      end
    end

    describe "console.ms-sites write arms" do
      before { make_super_admin!; login_as("con_admin") }

      it "archives a site and reports it with sites.php's verbatim notice" do
        post "/console/network/sites/bulk", params: { bulk_action: "archiveblog", ids: [@other.id] }
        expect(response).to have_http_status(:see_other)
        expect(@other.reload.archived).to be(true)
        follow_redirect!
        expect(body_text).to include("Site archived.")
      end

      it "unarchives, flags for deletion, removes the flag, spams and unspams" do
        {
          "unarchiveblog"  => [:archived, false, "Site unarchived."],
          "deactivateblog" => [:deleted, true, "Site flagged for deletion."],
          "activateblog"   => [:deleted, false, "Site deletion flag removed."],
          "spamblog"       => [:spam, true, "Site marked as spam."],
          "unspamblog"     => [:spam, false, "Site removed from spam."]
        }.each do |action, (attribute, value, notice)|
          post "/console/network/sites/bulk", params: { bulk_action: action, ids: [@other.id] }
          expect(@other.reload.public_send(attribute)).to be(value), "#{action} did not set #{attribute}"
          follow_redirect!
          expect(body_text).to include(notice)
        end
      end

      it "marks sites as spam in bulk" do
        post "/console/network/sites/bulk", params: { bulk_action: "spam", ids: [@other.id] }
        follow_redirect!
        expect(body_text).to include("Sites marked as spam.")
      end

      it "refuses to act on the network's main site with the verbatim wp_die string" do
        post "/console/network/sites/bulk", params: { bulk_action: "archiveblog", ids: [@main.id] }
        expect(response).to have_http_status(:forbidden)
        # sites.php:257
        expect(body_text).to include("Sorry, you are not allowed to change the current site.")
        expect(@main.reload.archived).to be(false)
      end

      it "confirms before deleting (DEV-004) and does not delete on the first post" do
        post "/console/network/sites/bulk", params: { bulk_action: "deleteblog", ids: [@other.id] }
        expect(response).to have_http_status(:ok)
        expect(body_text).to include("Confirm your action")
        # sites.php:123
        expect(body_text).to include("Deleting a site is a permanent action that cannot be undone.")
        expect(body_text).to include("You are about to delete the site other.example.")
        expect(Tenancy::Site.exists?(@other.id)).to be(true)
      end

      it "deletes the site AND its schema once confirmed" do
        Tenancy::Provisioner.provision!(@other)
        expect(@other.provisioned?).to be(true)
        post "/console/network/sites/bulk",
             params: { bulk_action: "deleteblog", confirmed: "1", ids: [@other.id] }
        expect(response).to have_http_status(:see_other)
        expect(Tenancy::Site.exists?(@other.id)).to be(false)
        expect(Tenancy::Provisioner.schema_exists?("site_other")).to be(false)
        follow_redirect!
        expect(body_text).to include("Site permanently deleted.")
      end
    end

    describe "console.ms-site-new (/console/network/sites/new)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders the Add Site form with the legacy's labels" do
        get "/console/network/sites/new"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to eq("Add Site")
        expect(body_text).to include("Site Address (URL)").and include("Site Title").and include("Admin Email")
        expect(body_text).to include("Only lowercase letters (a-z), numbers, and hyphens are allowed.")
      end

      it "creates the site, provisions its schema and makes the admin email its administrator" do
        expect do
          post "/console/network/sites", params: { blog: { domain: "fresh.example", title: "Fresh",
                                                           email: "fresh@example.com" } }
        end.to change(Tenancy::Site, :count).by(1)
        site = Tenancy::Site.find_by(domain: "fresh.example")
        expect(site.provisioned?).to be(true)
        owner = Identity::User.find_by(email: "fresh@example.com")
        expect(owner.roles(site_id: site.id)).to include("administrator")
        expect(response).to have_http_status(:see_other)
      ensure
        Tenancy::Provisioner.deprovision!(site) if site
      end

      it "surfaces the wp_die validations verbatim" do
        post "/console/network/sites", params: { blog: { domain: "", title: "", email: "" } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(body_text).to include("Missing site title.")
        expect(body_text).to include("Missing or invalid site address.")
        expect(body_text).to include("Missing email address.")
      end

      it "refuses a site address that already exists" do
        post "/console/network/sites", params: { blog: { domain: "other.example", title: "Dup",
                                                         email: "dup@example.com" } }
        expect(body_text).to include("Sorry, that site already exists!")
      end
    end

    # ── console.ms-site-edit ────────────────────────────────────────────────────────
    describe "console.ms-site-edit (/console/network/sites/:id)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders the heading, the actions line and all four tabs in wp-admin's order" do
        get "/console/network/sites/#{@other.id}"
        expect(response).to have_http_status(:ok)
        # site-info.php:134
        expect(doc.at_css("h1#edit-site").text).to eq("Edit Site: Other Site")
        expect(doc.at_css("p.edit-site-actions").text).to include("Visit").and include("Dashboard")
        tabs = doc.css("nav.nav-tab-wrapper a").map { |a| a.text.strip }
        # wp-admin/includes/ms.php:1112-1129
        expect(tabs).to eq(%w[Info Users Themes Settings])
      end

      it "renders the Info fields and every attribute checkbox for a non-main site" do
        get "/console/network/sites/#{@other.id}"
        expect(body_text).to include("Site Address (URL)").and include("Registered").and include("Last Updated")
        expect(body_text).to include("Attributes")
        labels = doc.css("fieldset label").map { |l| l.text.strip }
        expect(labels).to include("Public", "Archived", "Spam", "Flagged for Deletion")
      end

      it "prints the main site's address read-only and offers only Public" do
        get "/console/network/sites/#{@main.id}"
        expect(doc.at_css("code")).not_to be_nil
        expect(doc.at_css("input#url")).to be_nil
        labels = doc.css("fieldset label").map { |l| l.text.strip }
        expect(labels).to eq(["Public"])
      end

      it "saves the Info tab and reports it verbatim" do
        post "/console/network/sites/#{@other.id}",
             params: { blog: { url: "http://renamed.example/", public: "1", archived: "1" } }
        expect(response).to have_http_status(:see_other)
        @other.reload
        expect(@other.domain).to eq("renamed.example")
        expect(@other.archived).to be(true)
        expect(@other.public).to be(true)
        follow_redirect!
        expect(body_text).to include("Site info updated.") # site-info.php:126
      end

      it "clears an unchecked attribute" do
        @other.update!(spam: true)
        post "/console/network/sites/#{@other.id}", params: { blog: { url: "http://other.example/" } }
        expect(@other.reload.spam).to be(false)
      end

      it "404s an id that names no site, with the legacy's message" do
        get "/console/network/sites/999999"
        expect(response).to have_http_status(:not_found)
        expect(body_text).to include("The requested site does not exist.")
      end

      it "lists the site's members on the Users tab, with their per-site role" do
        actor("con_editor").assign_role("editor", site_id: @other.id)
        get "/console/network/sites/#{@other.id}/users"
        expect(response).to have_http_status(:ok)
        expect(body_text).to include("con_editor").and include("Editor")
        headers = doc.css("thead th").map(&:text)
        expect(headers).to include("Username", "Name", "Email", "Role")
      end

      it "renders the Themes tab with the legacy's own scoping rule" do
        Presentation::Theme.find_or_create_by!(slug: "spec-theme") { |t| t.version = "1.0" }
        get "/console/network/sites/#{@other.id}/themes"
        expect(response).to have_http_status(:ok)
        # site-themes.php:237
        expect(body_text).to include("Network enabled themes are not shown on this screen.")
        expect(body_text).to include("spec-theme")
      end

      it "reads and writes the site's OWN options on the Settings tab, inside its schema" do
        Tenancy::Provisioner.provision!(@other)
        @other.switch { Configuration::Setting.set("blogname", "Tenant Title") }

        get "/console/network/sites/#{@other.id}/settings"
        expect(response).to have_http_status(:ok)
        expect(body_text).to include("blogname")
        expect(doc.at_css("input#blogname")["value"]).to eq("Tenant Title")

        post "/console/network/sites/#{@other.id}/settings",
             params: { option: { "blogname" => "Renamed Tenant" } }
        expect(response).to have_http_status(:see_other)
        @other.switch { expect(Configuration::Setting["blogname"]).to eq("Renamed Tenant") }
        # and the GLOBAL setting of that name is untouched — the schema boundary held
        expect(Configuration::Setting["blogname"]).not_to eq("Renamed Tenant")
        follow_redirect!
        expect(body_text).to include("Site options updated.")
      ensure
        Tenancy::Provisioner.deprovision!(@other)
      end

      # ── RISK-023 V7 ──────────────────────────────────────────────────────────────
      # site-settings.php:60 writes through update_option(), and update_option() runs
      # sanitize_option(), whose blogname/blogdescription arm is `esc_html( $value )`
      # (formatting.php:5006). That is what makes those two options HTML-ESCAPED AT REST,
      # and it is the premise Configuration::Setting.display relies on when it hands them to
      # a view as `html_safe`. This screen wrote them RAW, so a title submitted here became
      # trusted markup on every surface that prints the site name.
      it "HTML-escapes blogname and blogdescription on write, as sanitize_option does" do
        Tenancy::Provisioner.provision!(@other)
        @other.switch do
          Configuration::Setting.set("blogname", "Tenant Title")
          Configuration::Setting.set("blogdescription", "A tenant")
        end

        post "/console/network/sites/#{@other.id}/settings",
             params: { option: { "blogname" => "<script>alert(1)</script>",
                                 "blogdescription" => %(a "quoted" & <b>bold</b>) } }

        @other.switch do
          expect(Configuration::Setting["blogname"]).to eq("&lt;script&gt;alert(1)&lt;/script&gt;")
          expect(Configuration::Setting["blogname"]).not_to include("<script")
          expect(Configuration::Setting["blogdescription"])
            .to eq("a &quot;quoted&quot; &amp; &lt;b&gt;bold&lt;/b&gt;")
        end
      ensure
        Tenancy::Provisioner.deprovision!(@other)
      end

      # ...and ONLY those two. sanitize_option dispatches per option name; every other
      # option is raw at rest and gets ordinary escaping at the point of display, so
      # escaping it here would corrupt the stored value.
      it "leaves options WordPress does not sanitize exactly as submitted" do
        Tenancy::Provisioner.provision!(@other)
        @other.switch { Configuration::Setting.set("date_format", "F j, Y") }

        post "/console/network/sites/#{@other.id}/settings",
             params: { option: { "date_format" => "a < b & c" } }

        @other.switch { expect(Configuration::Setting["date_format"]).to eq("a < b & c") }
      ensure
        Tenancy::Provisioner.deprovision!(@other)
      end

      it "refuses to edit options for a site whose schema was never provisioned" do
        # The footgun this guard closes: search_path is `<tenant>, public`, so an
        # unprovisioned tenant would resolve `settings` to the GLOBAL table.
        Configuration::Setting.set("blogname", "Global Title")
        get "/console/network/sites/#{@other.id}/settings"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("input#blogname")).to be_nil
        post "/console/network/sites/#{@other.id}/settings",
             params: { option: { "blogname" => "Hijacked" } }
        expect(Configuration::Setting["blogname"]).to eq("Global Title")
      end
    end

    # ── console.ms-users ────────────────────────────────────────────────────────────
    describe "console.ms-users (/console/network/users)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders the LITERAL columns and every network account" do
        get "/console/network/users"
        expect(response).to have_http_status(:ok)
        # class-wp-ms-users-list-table.php:192-198
        expect(column_headers).to include("Username", "Name", "Email", "Registered", "Sites")
        expect(body_text).to include("con_admin").and include("con_subscriber")
      end

      it "marks a super admin in the Username cell" do
        row = doc_for("/console/network/users").at_css("tr#console\\.ms-users-#{actor('con_admin').id}")
        # :286-288 — ' &mdash; Super Admin'
        expect(row.at_css("td.column-username").text).to include("Super Admin")
      end

      it "offers the All and Super Admin views and filters on ?role=super" do
        get "/console/network/users"
        tabs = doc.css("ul.subsubsub a").map { |a| a.text.strip }.join(" ")
        expect(tabs).to include("All").and include("Super Admin")
        get "/console/network/users?role=super"
        expect(body_text).to include("con_admin")
        expect(body_text).not_to include("con_subscriber@example.com")
      end

      it "lists the sites a user belongs to, each with its Edit link" do
        actor("con_editor").assign_role("editor", site_id: @other.id)
        row = doc_for("/console/network/users").at_css("tr#console\\.ms-users-#{actor('con_editor').id}")
        expect(row.at_css("td.column-blogs").text).to include("other.example")
        expect(row.at_css("td.column-blogs a")["href"]).to eq("/console/network/sites/#{@other.id}")
      end

      it "gives a super admin no Delete action and no checkbox" do
        row = doc_for("/console/network/users").at_css("tr#console\\.ms-users-#{actor('con_admin').id}")
        expect(action_labels(row)).not_to include("Delete")
        expect(row.at_css("input[name='ids[]']")).to be_nil
      end

      it "marks users as spam and back, with the verbatim notices" do
        target = actor("con_author")
        post "/console/network/users/bulk", params: { bulk_action: "spam", ids: [target.id] }
        expect(target.reload.status).to eq("spam")
        follow_redirect!
        expect(body_text).to include("Users marked as spam.")

        post "/console/network/users/bulk", params: { bulk_action: "notspam", ids: [target.id] }
        expect(target.reload.status).to eq("active")
        follow_redirect!
        expect(body_text).to include("Users removed from spam.")
      end

      it "refuses to bulk-modify a network administrator, verbatim" do
        post "/console/network/users/bulk", params: { bulk_action: "spam", ids: [actor("con_admin").id] }
        follow_redirect!
        # users.php:88
        expect(body_text).to include("Warning! User cannot be modified. The user con_admin is a network administrator.")
      end

      it "confirms a delete before running it, then deletes" do
        target = actor("con_subscriber")
        post "/console/network/users/bulk", params: { bulk_action: "delete", ids: [target.id] }
        expect(response).to have_http_status(:ok)
        expect(body_text).to include("Confirm your action")
        expect(Identity::User.exists?(target.id)).to be(true)

        post "/console/network/users/bulk",
             params: { bulk_action: "delete", confirmed: "1", ids: [target.id] }
        expect(Identity::User.exists?(target.id)).to be(false)
        follow_redirect!
        expect(body_text).to include("User deleted.")
      end

      it "adds a network user from the Add User screen" do
        get "/console/network/users/new"
        expect(doc.at_css("h1").text).to eq("Add User")
        expect(body_text).to include("A password reset link will be sent to the user via email.")

        expect do
          post "/console/network/users", params: { user: { username: "netnew", email: "netnew@example.com" } }
        end.to change(Identity::User, :count).by(1)
        follow_redirect!
        expect(body_text).to include("User added.")
      end

      it "refuses an empty or duplicated new user, verbatim" do
        post "/console/network/users", params: { user: { username: "", email: "" } }
        expect(body_text).to include("Cannot create an empty user.")
        post "/console/network/users", params: { user: { username: "con_admin", email: "x@example.com" } }
        expect(body_text).to include("Duplicated username or email address.")
      end
    end

    # ── console.ms-themes ───────────────────────────────────────────────────────────
    describe "console.ms-themes (/console/network/themes)" do
      before do
        make_super_admin!
        login_as("con_admin")
        @theme = Presentation::Theme.find_or_create_by!(slug: "spec-theme") { |t| t.version = "1.0" }
      end

      it "renders the LITERAL columns and bulk actions" do
        get "/console/network/themes"
        expect(response).to have_http_status(:ok)
        # class-wp-ms-themes-list-table.php:337-342
        expect(column_headers).to include("Theme", "Description")
        options = doc.css("select[name=bulk_action] option").map(&:text)
        # :479-489
        expect(options).to include("Network Enable", "Network Disable")
      end

      it "network-enables a theme and reports it verbatim" do
        post "/console/network/themes/bulk",
             params: { bulk_action: "enable-selected", ids: [@theme.id] }
        expect(response).to have_http_status(:see_other)
        expect(Tenancy::NetworkSetting["allowedthemes"]).to include("spec-theme")
        follow_redirect!
        expect(body_text).to include("Theme enabled.")
      end

      it "network-disables it again" do
        Tenancy::NetworkSetting["allowedthemes"] = ["spec-theme"]
        post "/console/network/themes/bulk",
             params: { bulk_action: "disable-selected", ids: [@theme.id] }
        expect(Tenancy::NetworkSetting["allowedthemes"]).not_to include("spec-theme")
        follow_redirect!
        expect(body_text).to include("Theme disabled.")
      end

      it "offers the Enabled and Disabled views and filters on them" do
        Tenancy::NetworkSetting["allowedthemes"] = ["spec-theme"]
        get "/console/network/themes"
        tabs = doc.css("ul.subsubsub a").map { |a| a.text.strip }.join(" ")
        expect(tabs).to include("All").and include("Enabled")
        get "/console/network/themes?status=disabled"
        expect(response).to have_http_status(:ok)
        expect(body_text).not_to include(">spec-theme<")
      end
    end

    # ── console.ms-options ──────────────────────────────────────────────────────────
    describe "console.ms-options (/console/network/settings)" do
      before { make_super_admin!; login_as("con_admin") }

      it "renders every section heading in wp-admin's order, with the LITERAL labels" do
        get "/console/network/settings"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to eq("Network Settings")
        headings = doc.css("h2").map(&:text)
        expect(headings).to eq(["Operational Settings", "Registration Settings",
                                "New Site Settings", "Upload Settings"])
        expect(body_text).to include("Network Title").and include("Network Admin Email")
        expect(body_text).to include("Registration is disabled")
        expect(body_text).to include("User accounts may be registered")
        expect(body_text).to include("Logged in users may register new sites")
        expect(body_text).to include("Both sites and user accounts can be registered")
        expect(body_text).to include("Welcome Email").and include("First Post")
      end

      it "saves the network settings into Tenancy::NetworkSetting and reports 'Settings saved.'" do
        post "/console/network/settings",
             params: { site_name: "The Network", admin_email: "net@example.com",
                       registration: "all", registrationnotification: "yes",
                       illegal_names: "root admin", blog_upload_space: "250",
                       upload_filetypes: "jpg png", fileupload_maxk: "1500" }
        expect(response).to have_http_status(:see_other)
        expect(Tenancy::NetworkSetting["site_name"]).to eq("The Network")
        expect(Tenancy::NetworkSetting["admin_email"]).to eq("net@example.com")
        expect(Tenancy::NetworkSetting["registration"]).to eq("all")
        expect(Tenancy::NetworkSetting["registrationnotification"]).to be(true)
        expect(Tenancy::NetworkSetting["blog_upload_space"]).to eq(250)
        follow_redirect!
        expect(body_text).to include("Settings saved.")
      end

      it "ignores a registration value that is not one of the four modes" do
        Tenancy::NetworkSetting["registration"] = "none"
        post "/console/network/settings", params: { registration: "anything-else" }
        expect(Tenancy::NetworkSetting["registration"]).to eq("none")
      end

      it "reproduces the INVERTED upload-space checkbox (settings.php:404)" do
        # Ticked means "limit total size" is ON, i.e. the check is NOT disabled.
        post "/console/network/settings", params: { upload_space_check_disabled: "1" }
        expect(Tenancy::NetworkSetting["upload_space_check_disabled"]).to be(false)
        post "/console/network/settings", params: {}
        expect(Tenancy::NetworkSetting["upload_space_check_disabled"]).to be(true)
      end
    end

    # ── console.my-sites ────────────────────────────────────────────────────────────
    describe "console.my-sites (/console/my-sites)" do
      it "is reachable by an ORDINARY user — my-sites.php gates on `read`, not on the network" do
        actor("con_subscriber").assign_role("subscriber", site_id: @other.id)
        login_as("con_subscriber")
        get "/console/my-sites"
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to eq("My Sites")
        expect(body_text).to include("Other Site")
        expect(body_text).to include("Visit").and include("Dashboard")
      end

      it "shows the empty-state notice for a user who belongs to no site" do
        login_as("con_author")
        get "/console/my-sites"
        expect(response).to have_http_status(:ok)
        # my-sites.php:92
        expect(body_text).to include("You must be a member of at least one site to use this page.")
      end

      it "offers 'Add New Site' only when the network's registration option admits it" do
        actor("con_subscriber").assign_role("subscriber", site_id: @other.id)
        login_as("con_subscriber")
        get "/console/my-sites"
        expect(body_text).not_to include("Add New Site")

        Tenancy::NetworkSetting["registration"] = "blog"
        get "/console/my-sites"
        expect(body_text).to include("Add New Site")
      end

      it "renders the Primary Site chooser as a select once the user belongs to two sites" do
        subscriber = actor("con_subscriber")
        subscriber.assign_role("subscriber", site_id: @other.id)
        subscriber.assign_role("subscriber", site_id: @main.id)
        login_as("con_subscriber")
        get "/console/my-sites"
        # wp-admin/includes/ms.php:767
        expect(body_text).to include("Primary Site")
        expect(doc.css("select#primary_blog option").length).to eq(2)
      end

      it "stores the chosen primary site and reports 'Settings saved.'" do
        subscriber = actor("con_subscriber")
        subscriber.assign_role("subscriber", site_id: @other.id)
        login_as("con_subscriber")
        post "/console/my-sites", params: { primary_blog: @other.id }
        expect(response).to have_http_status(:see_other)
        expect(Tenancy::NetworkSetting["primary_blog"]).to eq({ subscriber.id.to_s => @other.id })
        follow_redirect!
        expect(body_text).to include("Settings saved.")
      end

      it "refuses a primary site the user does not belong to, verbatim" do
        actor("con_subscriber").assign_role("subscriber", site_id: @other.id)
        login_as("con_subscriber")
        post "/console/my-sites", params: { primary_blog: @main.id }
        expect(response).to have_http_status(:forbidden)
        # my-sites.php:32
        expect(body_text).to include("The primary site you chose does not exist.")
      end
    end
  end

  # A second GET whose document is what the example inspects; keeps the row lookups short.
  def doc_for(path)
    get path
    doc
  end

  # The shared P-LIST partial appends the accessible sort hint ("Sort ascending.") to a
  # sortable header and a " |" separator to every row action but the last. Neither is part
  # of the LITERAL label, so both are stripped before comparing.
  def column_headers
    doc.css("thead th, thead td").map { |th| th.text.strip.sub(/\s*Sort (ascending|descending)\.\z/, "") }
  end

  def action_labels(row)
    row.css(".row-actions span").map { |span| span.text.strip.sub(/\s*\|\z/, "").strip }
  end
end
