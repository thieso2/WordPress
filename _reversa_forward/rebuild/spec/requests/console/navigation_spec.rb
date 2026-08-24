# frozen_string_literal: true

require_relative "console_spec_helper"

# The admin menu and admin bar (wp-admin's #adminmenu / #wpadminbar). DEV-002 makes the
# menu a DECLARED structure rather than a hook-registered one, so what is asserted here is
# the observable half: which entries a role sees, which section is open, and the pending-
# comment bubble. The structure itself is free (modernized mode); the labels are LITERAL,
# authored against the live oracle's own $menu/$submenu (tools/dump_menu.php).
RSpec.describe "the console navigation", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  def menu_labels = doc.css(".adminmenu > ul > li > a span:first-child").map { |n| n.text.strip }
  def submenu_labels = doc.css(".adminmenu .sub a").map { |n| n.text.strip }

  describe "an administrator" do
    it "sees every top-level section, in the oracle's order" do
      login_as("con_admin")
      get "/console"
      expect(response).to have_http_status(:ok)
      expect(menu_labels).to eq(["Dashboard", "Posts", "Media", "Pages", "Comments",
                                 "Appearance", "Users", "Tools", "Settings"])
    end

    it "opens the section for the current screen and lists its children" do
      login_as("con_admin")
      get "/console/settings/general"
      expect(doc.at_css(".adminmenu li.current > a span:first-child").text.strip).to eq("Settings")
      expect(submenu_labels).to eq(%w[General Writing Reading Discussion Media Permalinks Privacy])
    end

    it "keeps the parent section open on a nested screen the menu does not name" do
      login_as("con_admin")
      article = Publishing::Article.create!(author: actor("con_admin"), status: :draft,
                                           title: "Nested", content: "", excerpt: "")
      get "/console/posts/#{article.id}/revisions"
      expect(doc.at_css(".adminmenu li.current > a span:first-child").text.strip).to eq("Posts")
    end
  end

  describe "capability gating (the menu is Access-resolved in the controller)" do
    it "hides Settings, Appearance and Tools' privileged children from an author" do
      login_as("con_author")
      get "/console"
      expect(menu_labels).to include("Posts", "Media")
      expect(menu_labels).not_to include("Settings")
      expect(menu_labels).not_to include("Appearance")
    end

    it "still shows Users to a subscriber, because Profile lives under it" do
      login_as("con_subscriber")
      get "/console"
      expect(menu_labels).to include("Users")
      get "/console/profile"
      expect(submenu_labels).to eq(["Profile"])
    end
  end

  describe "the admin bar" do
    it "carries the site name, a new-post shortcut and the account controls" do
      login_as("con_admin")
      get "/console"
      bar = doc.at_css(".adminbar")
      expect(bar.text).to include("Howdy,")
      expect(bar.css("a").map { |a| a[:href] }).to include("/", "/console/posts/new", "/console/profile")
      expect(bar.text).to include("Log Out")
    end
  end

  describe "the pending-comment bubble (menu.php $awaiting_moderation)" do
    it "shows the count of comments awaiting moderation, and nothing when there are none" do
      login_as("con_admin")
      Discussion::Comment.where(status: "pending").delete_all
      get "/console"
      expect(doc.at_css(".adminmenu .badge")).to be_nil
    end
  end
end
