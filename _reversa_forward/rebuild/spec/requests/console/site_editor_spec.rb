# frozen_string_literal: true

require_relative "editor_spec_helper"

# console.site-editor — the Site Editor React island's server half (DEV-012, D-3). Verifies
# the template browser, template block-tree round-trip through Composition::Serializer, and
# the Global Styles user layer (themes.user_styles). Interaction/UI parity is covered by the
# live-browser test editor_e2e/site_editor.mjs (DEV-012: verify by observation, no goldens).
RSpec.describe "the site editor", type: :request do
  before { seed_editor_users!; host! "127.0.0.1" }

  def a_template
    Composition::Template.where(kind: "template").order(:slug).first ||
      Composition::Template.create!(kind: "template", theme_slug: "twentytwentyfive", slug: "spec-tpl",
                                    title: "Spec Template", content: "<!-- wp:paragraph --><p>t</p><!-- /wp:paragraph -->")
  end

  describe "authorization (edit_theme_options)" do
    it "bounces an unauthenticated request to login" do
      get "/console/site-editor"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login?redirect_to=")
    end

    it "forbids a subscriber from the templates API" do
      sign_in_as("subscriber")
      get "/console/site-editor/templates", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /console/site-editor/templates" do
    it "lists templates and parts for the active theme" do
      sign_in_as("administrator")
      get "/console/site-editor/templates", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("templates").and have_key("parts")
      expect(body["active_theme"]).to be_present
    end
  end

  describe "template block round-trip" do
    it "hands over the parsed tree and saves an edited tree serialized server-side" do
      sign_in_as("administrator")
      tpl = a_template
      get "/console/site-editor/templates/#{tpl.id}/blocks", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["blocks"]).to be_an(Array)

      blocks = [{ "name" => "core/paragraph", "attrs" => {}, "innerHTML" => "<p>Edited</p>", "innerContent" => ["<p>Edited</p>"], "innerBlocks" => [] }]
      patch "/console/site-editor/templates/#{tpl.id}",
            params: { title: tpl.title, blocks: blocks }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be(true)
      expect(tpl.reload.content).to eq("<!-- wp:paragraph --><p>Edited</p><!-- /wp:paragraph -->")
    end
  end

  describe "Global Styles" do
    it "returns the user layer + the theme palette, and persists an edit" do
      sign_in_as("administrator")
      get "/console/site-editor/styles", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key("user_styles").and have_key("settings")

      styles = { "version" => 3, "styles" => { "color" => { "background" => "var(--wp--preset--color--base)" } } }
      patch "/console/site-editor/styles",
            params: { user_styles: styles }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to be(true)
      theme = Presentation::Theme.active.first
      expect(theme.reload.user_styles.dig("styles", "color", "background")).to eq("var(--wp--preset--color--base)")
    end
  end
end
