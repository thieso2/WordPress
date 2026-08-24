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

    it "rejects a blank menu name with the VERBATIM string (Please enter a valid menu name.)" do
      login_as("con_admin")
      post "/console/menus", params: { menu_name: "" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please enter a valid menu name.")
      expect(response.body).not_to include("Name can&#39;t be blank")
      expect(Presentation::Menu.count).to eq(0)
    end

    it "rejects a rename to a blank name with the VERBATIM string" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      patch "/console/menus/#{menu.id}", params: { menu_name: "" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please enter a valid menu name.")
      expect(menu.reload.name).to eq("Main")
    end

    it "adds a PAGE item through the Pages panel (kind=post)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      page = Publishing::Page.create!(author: actor("con_editor"), title: "About",
                                      status: :published, published_at: Time.current)
      post "/console/menus/#{menu.id}/items", params: { kind: "post", target_id: page.id }
      expect(response).to have_http_status(:see_other)
      item = menu.reload.menu_items.first
      expect(item.target_type).to eq("Publishing::Post")
      expect(item.target_id).to eq(page.id)
      expect(item.label).to eq("About") # nav label defaults to the object title
    end

    it "adds a POST item through the Posts panel (kind=post)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      article = create_article!(title: "Hello World")
      post "/console/menus/#{menu.id}/items", params: { kind: "post", target_id: article.id }
      expect(response).to have_http_status(:see_other)
      item = menu.reload.menu_items.first
      expect(item.target_id).to eq(article.id)
      expect(item.label).to eq("Hello World")
    end

    it "adds a CATEGORY item through the Categories panel (kind=term)" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      term = create_term!(name: "News", slug: "news")
      post "/console/menus/#{menu.id}/items", params: { kind: "term", target_id: term.id }
      expect(response).to have_http_status(:see_other)
      item = menu.reload.menu_items.first
      expect(item.target_type).to eq("Classification::Term")
      expect(item.target_id).to eq(term.id)
      expect(item.label).to eq("News")
    end

    it "renders the Pages / Posts / Categories add panels on a persisted menu" do
      login_as("con_admin")
      menu = Presentation::Menu.create!(name: "Main", slug: "main")
      create_article!(title: "Hello World")
      get "/console/menus/#{menu.id}"
      expect(response.body).to include("Pages")
      expect(response.body).to include("Posts")
      expect(response.body).to include("Categories")
      expect(response.body).to include("Custom Links")
      expect(response.body).to include("Add to Menu")
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

  # nav-menus.php:513 `case 'locations'` — the Manage Locations sub-screen.
  describe "the Manage Locations tab" do
    it "redirects to Edit Menus when no theme locations are registered (!num_locations)" do
      login_as("con_admin")
      get "/console/menus?tab=locations"
      expect(response).to have_http_status(:see_other)
      expect(response.headers["Location"]).to end_with("/console/menus")
    end

    context "when the active theme registers menu locations (DEV-002 declared UI)" do
      before { stub_const("Console::MenusController::NAV_MENU_LOCATIONS", { "primary" => "Primary Menu" }) }

      it "renders the assignment table with VERBATIM strings and marks the tab active" do
        login_as("con_admin")
        Presentation::Menu.create!(name: "Main", slug: "main")
        get "/console/menus?tab=locations"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Menu Location")
        expect(response.body).to include("Assigned Menu")
        expect(response.body).to include("Select a Menu")
        expect(response.body).to include("Save Changes")
        expect(response.body).to include("Primary Menu")
        expect(response.body).to include('class="nav-tab nav-tab-active">Manage Locations')
      end

      it "saves an assignment and shows the VERBATIM notice (Menu locations updated.)" do
        login_as("con_admin")
        menu = Presentation::Menu.create!(name: "Main", slug: "main")
        post "/console/menus", params: { save_nav_menu_locations: "1",
                                         menu_locations: { "primary" => menu.id.to_s } }
        expect(response).to have_http_status(:see_other)
        expect(Configuration::Setting["nav_menu_locations"]).to eq("primary" => menu.id)
        follow_redirect!
        expect(response.body).to include("Menu locations updated.")
      end
    end
  end
end
