# frozen_string_literal: true

require_relative "console_spec_helper"

# console.index, console.tools, console.site-health(+info), the GDPR data-request
# screens, the informational pages and the privacy guide. Modernized mode: the auth
# gate, the capability, and the LITERAL strings are what is asserted.
RSpec.describe "console dashboard / tools / health / GDPR / info", type: :request do
  before do
    host! "127.0.0.1"
    seed_console_accounts!
  end

  describe "console.index (dashboard)" do
    it "redirects an anonymous visitor to /login" do
      get "/console"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login?redirect_to=")
    end

    it "renders the At a Glance widget for a logged-in user" do
      login_as("con_admin")
      Publishing::Article.create!(author: actor("con_admin"), title: "P", status: :published,
                                  published_at: Time.current)
      get "/console"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dashboard")
      expect(response.body).to include("At a Glance")
    end
  end

  describe "console.tools + console.export" do
    before { login_as("con_admin") }

    it "renders the tools index" do
      get "/console/tools"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tools")
    end

    it "renders the export form with the LITERAL strings" do
      get "/console/tools/export"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Export")
      expect(response.body).to include("Download Export File")
    end

    it "downloads a WXR file on POST" do
      Publishing::Article.create!(author: actor("con_admin"), title: "Exported", status: :published,
                                  published_at: Time.current)
      post "/console/tools/export", params: { content: "all" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/xml")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.body).to include("<rss")
      expect(response.body).to include("Exported")
    end

    it "refuses export to a user without the capability" do
      login_as("con_subscriber")
      get "/console/tools/export"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Sorry, you are not allowed to export the content of this site.")
    end
  end

  describe "console.site-health + info" do
    it "renders the status report for an admin (install_plugins)" do
      login_as("con_admin")
      get "/console/tools/site-health"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Site Health")
      expect(response.body).to include("Passed tests")

      get "/console/tools/site-health/info"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Site Health Info")
    end

    it "refuses a non-admin" do
      login_as("con_editor")
      get "/console/tools/site-health"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GDPR — export/erase personal data" do
    before { login_as("con_admin") }

    it "lists export requests with the LITERAL columns" do
      get "/console/tools/export-personal-data"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Export Personal Data")
      expect(response.body).to include("Add Data Export Request")
      expect(response.body).to include("Requester")
      expect(response.body).to include("Next steps")
    end

    it "creates a request and issues a confirmation key" do
      expect {
        post "/console/tools/export-personal-data", params: { kind: "export", username_or_email: "subject@example.com" }
      }.to change(Identity::DataRequest, :count).by(1)
      expect(response).to have_http_status(:see_other)
      request = Identity::DataRequest.order(:created_at).last
      expect(request.kind).to eq("export")
      expect(request.email).to eq("subject@example.com")
      expect(request.confirm_key_digest).to be_present
    end

    it "renders the erasure screen's own LITERAL heading" do
      get "/console/tools/erase-personal-data"
      expect(response.body).to include("Add Data Erasure Request")
    end
  end

  describe "console.privacy-policy-guide" do
    it "renders for an admin" do
      login_as("con_admin")
      get "/console/tools/privacy-guide"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Privacy Policy Guide")
    end
  end

  describe "informational pages (DEV-009: the rebuild's own content)" do
    before { login_as("con_subscriber") } # read-only pages: any logged-in reader

    %w[about credits freedoms contribute privacy].each do |page|
      it "renders console.#{page}" do
        get "/console/#{page}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "does not migrate WordPress-the-project text" do
      get "/console/about"
      expect(response.body).not_to include("WordPress.org")
    end
  end
end
