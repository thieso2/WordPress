# frozen_string_literal: true

require "rails_helper"
require_relative "console_spec_helper"

# console.themes — themes.php in modernized mode. Semantic contract: LITERAL strings
# verbatim, the DATA (which themes, which is active) correct; the markup is not compared.
# The suite's before(:suite) leaves twentytwentyfive active with its templates loaded.
RSpec.describe "console.themes", type: :request do
  before { seed_console_accounts! }

  let!(:other) do
    Presentation::Theme.create!(slug: "twentytwentyfour", version: "1.3", active: false,
                                theme_json: { "name" => "Twenty Twenty-Four" })
  end

  describe "the auth gate (auth_redirect, admin.php:104)" do
    it "redirects an unauthenticated request to /login with redirect_to" do
      get "/console/themes"
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/login")
      expect(response.headers["Location"]).to include("redirect_to")
    end
  end

  describe "authorization (switch_themes, administrator-only)" do
    it "forbids a subscriber" do
      login_as("con_subscriber")
      get "/console/themes"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /console/themes" do
    it "lists themes with the LITERAL title and the active one marked" do
      login_as("con_admin")
      get "/console/themes"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Themes")
      expect(response.body).to include("Add Theme")
      expect(response.body).to include("Twenty Twenty-Four")
      expect(response.body).to include("Twenty Twenty-Five") # the seeded active theme's name
    end
  end

  describe "POST /console/themes/:slug/activate" do
    it "swaps the active row and shows the LITERAL notice" do
      login_as("con_admin")
      post "/console/themes/twentytwentyfour/activate"
      expect(response).to have_http_status(:see_other)
      expect(other.reload.active?).to be(true)
      expect(Presentation::Theme.where(active: true).count).to eq(1)
      follow_redirect!
      expect(response.body).to include("New theme activated.")
    end
  end

  describe "DELETE /console/themes/:slug" do
    it "deletes an inactive theme (Theme deleted.)" do
      login_as("con_admin")
      delete "/console/themes/twentytwentyfour"
      expect(response).to have_http_status(:see_other)
      expect(Presentation::Theme.where(slug: "twentytwentyfour")).not_to exist
      follow_redirect!
      expect(response.body).to include("Theme deleted.")
    end

    it "refuses to delete the ACTIVE theme (delete_theme guard)" do
      active = Presentation::Theme.find_by!(active: true)
      login_as("con_admin")
      delete "/console/themes/#{active.slug}"
      expect(Presentation::Theme.where(slug: active.slug)).to exist
      follow_redirect!
      # themes.php:304, the delete-active-child branch the guard emulates — VERBATIM.
      expect(response.body).to include("You cannot delete a theme while it has an active child theme.")
    end

    it "answers a missing theme with the LITERAL not-found string" do
      login_as("con_admin")
      delete "/console/themes/does-not-exist"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("The requested theme does not exist.")
    end
  end

  # themes.php:83-124 — per-theme auto-update opt-in stored in the `auto_update_themes`
  # site option. The screen's behaviour is the preference write plus its verbatim notice;
  # WP-Cron's executor is out of scope (AD-01), the recorded preference is not.
  describe "the auto-update toggle" do
    it "enables auto-updates (Theme will be auto-updated.)" do
      login_as("con_admin")
      post "/console/themes/twentytwentyfour/enable-auto-update"
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["auto_update_themes"]).to include("twentytwentyfour")
      follow_redirect!
      expect(response.body).to include("Theme will be auto-updated.")
    end

    it "disables auto-updates (Theme will no longer be auto-updated.)" do
      login_as("con_admin")
      Configuration::Setting.set("auto_update_themes", ["twentytwentyfour"])
      post "/console/themes/twentytwentyfour/disable-auto-update"
      expect(response).to have_http_status(:see_other)
      expect(Configuration::Setting["auto_update_themes"]).not_to include("twentytwentyfour")
      follow_redirect!
      expect(response.body).to include("Theme will no longer be auto-updated.")
    end

    it "forbids a subscriber from toggling auto-updates" do
      login_as("con_subscriber")
      post "/console/themes/twentytwentyfour/enable-auto-update"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
