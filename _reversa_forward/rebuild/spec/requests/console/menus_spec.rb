# frozen_string_literal: true

require "rails_helper"
require_relative "console_spec_helper"

# console.nav-menus — nav-menus.php in modernized mode over AGG-Menu. Menu items are rows
# with columns (BR-MENU-02); the menu_items_one_target CHECK / MenuItem#exactly_one_target
# enforce exactly one target arm. LITERAL strings verbatim.
RSpec.describe "console.nav-menus", type: :request do
  before { seed_console_accounts! }

  it "redirects an unauthenticated request to /login" do
    get "/console/menus"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login")
  end

  it "forbids an actor without edit_theme_options (subscriber)" do
    login_as("con_subscriber")
    get "/console/menus"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the Edit Menus tab with LITERAL strings" do
    login_as("con_admin")
    get "/console/menus"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Menus")
    expect(response.body).to include("Edit Menus")
    expect(response.body).to include("Manage Locations")
    expect(response.body).to include("Create Menu")
  end

  describe "the menu lifecycle" do
    it "creates a menu (%s has been updated.)" do
      login_as("con_admin")
      post "/console/menus", params: { menu_name: "Primary" }
      expect(response).to have_http_status(:see_other)
      menu = Presentation::Menu.find_by!(name: "Primary")
      follow_redirect!
      expect(response.body).to include("Primary has been updated.")
      expect(menu.slug).to be_present
    end

    it "adds a custom-URL item (one target arm)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      post "/console/menus/#{menu.id}/items",
           params: { kind: "custom", url: "https://example.com", label: "Home" }
      expect(response).to have_http_status(:see_other)
      item = menu.reload.menu_items.first
      expect(item.url).to eq("https://example.com")
      expect(item.target_type).to be_nil
      expect(item.label).to eq("Home")
    end

    it "refuses an item with NEITHER a target NOR a URL (menu_items_one_target)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      post "/console/menus/#{menu.id}/items", params: { kind: "custom", url: "", label: "Nowhere" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(menu.reload.menu_items).to be_empty
    end

    it "moves an item to a new parent" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      parent = menu.menu_items.create!(url: "https://a", label: "A", position: 0)
      child = menu.menu_items.create!(url: "https://b", label: "B", position: 1)
      patch "/console/menus/#{menu.id}/items/#{child.id}", params: { parent_id: parent.id, position: 0 }
      expect(response).to have_http_status(:see_other)
      expect(child.reload.parent_id).to eq(parent.id)
    end

    it "removes an item" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      item = menu.menu_items.create!(url: "https://a", label: "A", position: 0)
      delete "/console/menus/#{menu.id}/items/#{item.id}"
      expect(response).to have_http_status(:see_other)
      expect(menu.reload.menu_items).to be_empty
    end

    it "deletes the menu (The menu has been successfully deleted.)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      menu.menu_items.create!(url: "https://a", label: "A", position: 0)
      delete "/console/menus/#{menu.id}"
      expect(response).to have_http_status(:see_other)
      expect(Presentation::Menu.where(id: menu.id)).not_to exist
      # FK cascade removed the items too (AGG-Menu, the FK the legacy lacked).
      expect(Presentation::MenuItem.where(menu_id: menu.id)).not_to exist
      follow_redirect!
      expect(response.body).to include("The menu has been successfully deleted.")
    end
  end
end
