# frozen_string_literal: true

require_relative "console_spec_helper"

# console.users — the Users list (users.php, WP_Users_List_Table). P-LIST over
# Identity::User, EXACT pagination. list_users is administrator-only. LITERAL columns
# "Username / Name / Email / Role / Posts", role filter tabs, "No users found."
RSpec.describe "console.users (Users list)", type: :request do
  before { seed_console_accounts!; host! "127.0.0.1" }

  it "redirects an unauthenticated request to /login" do
    get "/console/users"
    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("/login?")
  end

  it "forbids an actor without list_users (editor)" do
    login_as("con_editor")
    get "/console/users"
    expect(response).to have_http_status(:forbidden)
  end

  it "renders the LITERAL title, column headers and the seeded accounts as rows" do
    login_as("con_admin")
    get "/console/users"
    expect(response).to have_http_status(:ok)
    expect(doc.at_css("h1").text).to include("Users")
    headers = doc.css("thead th, thead td").map(&:text).map(&:strip)
    expect(headers).to include("Username", "Name", "Email", "Role", "Posts")
    expect(body_text).to include("con_admin").and include("con_editor").and include("con_subscriber")
  end

  it "filters to a role tab (Subscriber) showing only that role's members" do
    login_as("con_admin")
    get "/console/users?role=subscriber"
    expect(response).to have_http_status(:ok)
    expect(body_text).to include("con_subscriber")
    expect(body_text).not_to include("con_editor@example.com")
  end

  # ── Defect 5: Posts column is a LINK to the author's posts ────────────────────────
  it "renders the Posts count as a link to the author's posts with accessible text" do
    create_article!(author: actor("con_editor"), title: "By the editor")
    login_as("con_admin")
    get "/console/users"
    row = doc.at_css("tr#console\\.users-#{actor('con_editor').id}")
    link = row.at_css("td.column-posts a")
    expect(link).not_to be_nil
    expect(link["href"]).to eq("/console/posts?author=#{actor('con_editor').id}")
    expect(row.text).to include("post by this author").or include("posts by this author")
  end

  # ── Defect 4: the "No role" filter tab + role=none query ──────────────────────────
  context "with a user that has no role for the site" do
    let!(:norole) do
      Identity::User.create!(login: "con_norole", email: "con_norole@example.com",
                             nicename: "con-norole", display_name: "con_norole", password: "pw-norole-123")
    end

    it "renders a 'No role' tab when unassigned users exist" do
      login_as("con_admin")
      get "/console/users"
      tab = doc.css("ul.subsubsub a").find { |a| a.text.include?("No role") }
      expect(tab).not_to be_nil
      expect(tab["href"]).to include("role=none")
    end

    it "role=none returns the unassigned users only" do
      login_as("con_admin")
      get "/console/users?role=none"
      expect(response).to have_http_status(:ok)
      expect(body_text).to include("con_norole")
      expect(body_text).not_to include("con_editor@example.com")
    end
  end

  # ── Defect 3: per-row 'Send password reset' action ───────────────────────────────
  it "adds a per-row 'Send password reset' action for other users but not for oneself" do
    login_as("con_admin")
    get "/console/users"
    expect(body_text).to include("Send password reset")
    own_row = doc.at_css("tr#console\\.users-#{actor('con_admin').id}")
    expect(own_row.text).not_to include("Send password reset")
    other_row = doc.at_css("tr#console\\.users-#{actor('con_editor').id}")
    expect(other_row.text).to include("Send password reset")
  end

  # ── Defect 1: bulk 'Change role to…' (the promote action) ─────────────────────────
  it "renders the 'Change role to…' control gated on promote_users" do
    login_as("con_admin")
    get "/console/users"
    expect(response.body).to include("Change role to")
    expect(response.body).to include("No role for this site")
    expect(doc.at_css("#changeit")).not_to be_nil
  end

  it "changes the role of the selected users (set_role) and shows 'Changed roles.'" do
    login_as("con_admin")
    post "/console/users/bulk", params: { changeit: "Change", new_role: "editor",
                                          ids: [actor("con_subscriber").id] }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(body_text).to include("Changed roles.")
    expect(actor("con_subscriber").roles).to eq(["editor"])
  end

  it "'No role' (new_role=none) removes the site role from the selected users" do
    login_as("con_admin")
    post "/console/users/bulk", params: { changeit: "Change", new_role: "none",
                                          ids: [actor("con_subscriber").id] }
    expect(response).to have_http_status(:see_other)
    expect(actor("con_subscriber").roles).to eq([])
  end

  it "refuses removing one's OWN role with the LITERAL wp_die message (403)" do
    login_as("con_admin")
    post "/console/users/bulk", params: { changeit: "Change", new_role: "none",
                                          ids: [actor("con_admin").id] }
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you cannot remove your own role.")
    expect(actor("con_admin").roles).to eq(["administrator"])
  end

  it "refuses an ineligible target role with the LITERAL wp_die message (403)" do
    login_as("con_admin")
    post "/console/users/bulk", params: { changeit: "Change", new_role: "wizard",
                                          ids: [actor("con_subscriber").id] }
    expect(response).to have_http_status(:forbidden)
    expect(body_text).to include("Sorry, you are not allowed to give users that role.")
    expect(actor("con_subscriber").roles).to eq(["subscriber"])
  end

  # ── Defect 2: Delete Users screen with per-user content reassignment ──────────────
  describe "Delete Users (content reassignment)" do
    it "renders the per-user content choice for a content-owning user" do
      create_article!(author: actor("con_subscriber"), title: "Subscriber post")
      login_as("con_admin")
      post "/console/users/bulk", params: { bulk_action: "delete", ids: [actor("con_subscriber").id] }
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("Delete Users")
      expect(body_text).to include("What should be done with the content owned by this user?")
      expect(body_text).to include("Delete all content.")
      expect(body_text).to include("Attribute all content to another user.")
    end

    it "reports a content-free user rather than a radio choice" do
      login_as("con_admin")
      post "/console/users/bulk", params: { bulk_action: "delete", ids: [actor("con_subscriber").id] }
      expect(response).to have_http_status(:ok)
      expect(body_text).to include("This user does not have any content.")
    end

    it "reassigns the departing user's content to another user, then deletes them" do
      article = create_article!(author: actor("con_subscriber"), title: "Subscriber post")
      editor_id = actor("con_editor").id
      login_as("con_admin")
      expect {
        post "/console/users/bulk", params: {
          bulk_action: "delete", confirmed: "1", ids: [actor("con_subscriber").id],
          delete_option: { actor("con_subscriber").id.to_s => "reassign" },
          reassign_user: { actor("con_subscriber").id.to_s => editor_id }
        }
      }.to change(Identity::User, :count).by(-1)
      expect(response).to have_http_status(:see_other)
      expect(article.reload.author_id).to eq(editor_id)
      follow_redirect!
      expect(body_text).to include("User deleted.")
    end

    it "deletes the departing user's content when 'Delete all content.' is chosen" do
      create_article!(author: actor("con_subscriber"), title: "Subscriber post")
      login_as("con_admin")
      expect {
        post "/console/users/bulk", params: {
          bulk_action: "delete", confirmed: "1", ids: [actor("con_subscriber").id],
          delete_option: { actor("con_subscriber").id.to_s => "delete" }
        }
      }.to change(Publishing::Post, :count).by(-1)
      expect(Identity::User.exists?(login: "con_subscriber")).to be(false)
    end

    it "rejects a submit with no content option chosen ('Please select an option.')" do
      create_article!(author: actor("con_subscriber"), title: "Subscriber post")
      login_as("con_admin")
      expect {
        post "/console/users/bulk", params: {
          bulk_action: "delete", confirmed: "1", ids: [actor("con_subscriber").id]
        }
      }.not_to change(Identity::User, :count)
      expect(response).to have_http_status(:ok)
      expect(body_text).to include("Please select an option.")
    end
  end
end
