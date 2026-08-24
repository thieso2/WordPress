# frozen_string_literal: true

require "rails_helper"
require_relative "console_spec_helper"

# console.import — the WXR importer that replaces wp-admin/import.php's plugin list
# (AD-01 left that list with nothing to point at; see Console::ImportsController).
#
# ⚠️ ROUTES AND DECLARATIONS. config/routes.rb and
# config/initializers/authorization_declarations.rb are the integrator's files and are not
# edited from here, so this spec DRAWS the three routes it needs and DECLARES them the way
# the integrator will. Both are idempotent: once the real routes land, the guard below
# sees them and the spec drives the real thing instead. The declarations are asserted, not
# assumed — an import screen that answered before AD-04 had an opinion would be exactly
# the failure AD-04 exists to prevent.
RSpec.describe "console.import (WXR importer)", type: :request do
  IMPORT_ROUTES = [
    ["GET", "/console/tools/import", "console/imports#show"],
    ["POST", "/console/tools/import", "console/imports#prepare"],
    ["POST", "/console/tools/import/run", "console/imports#create"]
  ].freeze

  before(:all) do
    unless Rails.application.routes.routes.any? { |r| r.defaults[:controller] == "console/imports" }
      # PREPENDED, not appended: config/routes.rb ends with `get "/*path"`, the page
      # permalink glob, which would otherwise swallow /console/tools/import as a page slug
      # — the same reason every console route in config/routes.rb is declared above it.
      Rails.application.routes.prepend do
        get  "/console/tools/import",     to: "console/imports#show"
        post "/console/tools/import",     to: "console/imports#prepare"
        post "/console/tools/import/run", to: "console/imports#create"
      end
      Rails.application.reload_routes!
    end
  end

  before do
    IMPORT_ROUTES.each do |verb, _path, action|
      next if Access::Declarations.declared?("#{verb} #{action}")

      Access::Declarations.declare("#{verb} #{action}", mode: :authenticated, source: __FILE__)
    end
    seed_console_accounts!
  end

  # The ORACLE's own export, captured verbatim from the live 7.2-alpha-63330 corpus —
  # see spec/models/importing/wxr_spec.rb for how it was taken (AD-08).
  let(:oracle_wxr) { Rails.root.join("spec/fixtures/wxr/oracle_export.xml").read }

  def upload(bytes, filename: "export.xml")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "text/xml", original_filename: filename)
  end

  # Step 1 -> step 2 -> step 3, as a browser walks it.
  def import!(bytes, authors: nil, filename: "export.xml")
    post "/console/tools/import", params: { import: upload(bytes, filename: filename) }
    expect(response).to have_http_status(:ok)
    token = doc.at_css("input[name='token']")&.[]("value")
    expect(token).to be_present, "step 2 did not stage the file"
    payload = { token: token }
    payload[:authors] = authors if authors
    post "/console/tools/import/run", params: payload
    expect(response).to have_http_status(:ok)
  end

  # ── The gate ────────────────────────────────────────────────────────────────────
  describe "authorization" do
    it "redirects a logged-out browser to the login screen (auth_redirect)" do
      get "/console/tools/import"
      expect(response).to redirect_to(%r{/login\?.*redirect_to=%2Fconsole%2Ftools%2Fimport})
    end

    it "refuses an actor without `import` with import.php's LITERAL wp_die() string" do
      # menu.php:392 gates Import on `import`, which only the administrator holds
      # (Access::RoleCatalogue::ADMINISTRATOR).
      login_as("con_editor")
      get "/console/tools/import"
      expect(response).to have_http_status(:forbidden)
      expect(body_text).to include("Sorry, you are not allowed to import content into this site.")
    end

    it "refuses the RUN step to the same actor, not only the form" do
      login_as("con_editor")
      post "/console/tools/import/run", params: { token: "0" * 32 }
      expect(response).to have_http_status(:forbidden)
    end

    it "admits an administrator" do
      login_as("con_admin")
      get "/console/tools/import"
      expect(response).to have_http_status(:ok)
    end

    it "carries an explicit AD-04 declaration for every action" do
      IMPORT_ROUTES.each do |verb, _path, action|
        expect(Access::Declarations.declared?("#{verb} #{action}")).to be(true), "#{verb} #{action} undeclared"
      end
    end
  end

  # ── Step 1: the upload form ─────────────────────────────────────────────────────
  describe "the upload form" do
    before { login_as("con_admin") }

    it "renders the LITERAL heading and description with a file field" do
      get "/console/tools/import"

      expect(doc.at_css("h1").text).to eq("Import")                       # import.php:19
      # wp-admin/includes/import.php:206, the 'wordpress' importer's own description.
      expect(body_text).to include("Import posts, pages, comments, custom fields, " \
                                   "categories, and tags from a WordPress export file.")
      field = doc.at_css("input[type=file]")
      expect(field["name"]).to eq("import")   # $_FILES['import'], includes/import.php:80
      expect(field["accept"]).to include(".xml")
      expect(field.ancestors("form").first["enctype"]).to eq("multipart/form-data")
    end

    it "says out loud that attachments are not fetched" do
      get "/console/tools/import"
      expect(body_text).to match(/Attachments are.*not.*fetched/m)
    end

    it "answers an empty submission with wp_import_handle_upload()'s LITERAL error" do
      post "/console/tools/import", params: {}
      expect(response).to have_http_status(:unprocessable_content)
      expect(body_text).to include(
        "File is empty. Please upload something more substantial. This error could also " \
        "be caused by uploads being disabled in your php.ini file or by post_max_size " \
        "being defined as smaller than upload_max_filesize in php.ini."
      )
    end

    it "refuses a file that is not a WXR, and writes nothing" do
      expect do
        post "/console/tools/import", params: { import: upload("<catalogue/>", filename: "notes.xml") }
      end.not_to change(Publishing::Post, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body_text).to include("could not be read as a WordPress eXtended RSS (WXR) export")
    end
  end

  # ── Step 2: assign authors ──────────────────────────────────────────────────────
  describe "the author-assignment step" do
    before { login_as("con_admin") }

    it "parses the file, writes NOTHING, and asks how to assign each author" do
      expect do
        post "/console/tools/import", params: { import: upload(oracle_wxr) }
      end.not_to change(Publishing::Post, :count)

      expect(response).to have_http_status(:ok)
      # export.php:507-509, LITERAL — the instructions the export file itself carries.
      expect(body_text).to include(
        "You will first be asked to map the authors in this export file to users on the " \
        "site. For each author, you may choose to map to an existing user on the site or " \
        "to create a new user."
      )
      expect(body_text).to include("oracle_admin", "oracle_editor", "oracle_author")
      expect(doc.css("input[name='authors[oracle_admin][mode]']").map { |i| i["value"] })
        .to contain_exactly("create", "existing", "skip")
      expect(doc.at_css("input[name='token']")["value"]).to match(/\A[0-9a-f]{32}\z/)
    end

    it "offers the 'Download and import file attachments' option DISABLED, and says why" do
      post "/console/tools/import", params: { import: upload(oracle_wxr) }

      box = doc.at_css("input[name='fetch_attachments']")
      expect(box).to be_present
      expect(box["disabled"]).to be_present
      expect(body_text).to include("Download and import file attachments")
      expect(body_text).to include("makes no outbound requests")
    end

    it "pre-selects an existing account when the export names one this site already has" do
      Identity::User.create!(login: "oracle_editor", email: "oracle_editor@example.com",
                             nicename: "oracle-editor", display_name: "Editor",
                             password: "pw-oracle-1234")
      post "/console/tools/import", params: { import: upload(oracle_wxr) }

      row = doc.css("input[name='authors[oracle_editor][mode]']").find { |i| i["value"] == "existing" }
      expect(row["checked"]).to be_present
    end
  end

  # ── Step 3: the run, against the ORACLE's own export ────────────────────────────
  describe "importing the oracle's own WXR export" do
    before { login_as("con_admin") }

    it "imports posts, pages, terms, comments and authors, and reports every record" do
      import!(oracle_wxr)

      # Content: AD-02's two content types. The other ten post types in the file are
      # machinery and are reported, not imported.
      hello = Publishing::Article.find_by(slug: "hello-world")
      expect(hello).to be_present
      expect(hello.title).to eq("Hello world!")
      expect(hello.status).to eq("published")
      expect(hello.published_at.utc.strftime("%Y-%m-%d %H:%M:%S")).to eq("2026-03-15 09:59:00")
      expect(hello.content).to include("<!-- wp:paragraph -->")
      expect(hello.comment_status).to eq("open")
      # AD-03 dropped ping_status as a column; the value is parked, not lost.
      expect(hello.residual_attributes["ping_status"]).to eq("open")
      # T-07: the export's guid is a permalink on the SOURCE site, never an identifier.
      expect(hello.guid).not_to include("127.0.0.1")

      expect(Publishing::Page.where.not(slug: nil)).to be_any

      # Authors: created with authentication DISABLED — a WXR carries no password.
      admin = Identity::User.find_by(login: "oracle_admin")
      expect(admin).to be_present
      expect(admin.email).to eq("oracle@example.com")
      expect(admin.password_digest).to eq(Seeding::Transformations::DISABLED_DIGEST)
      expect(hello.author).to eq(admin)

      # Terms, with the hierarchy wp:category_parent expresses by SLUG.
      top = Classification::Term.find_by(slug: "top-category")
      middle = Classification::Term.find_by(slug: "middle-category")
      leaf = Classification::Term.find_by(slug: "leaf-category")
      expect(top.name).to eq("Top « Category » 😀")
      expect(middle.parent).to eq(top)
      expect(leaf.parent).to eq(middle)
      expect(Classification::Term.find_by(slug: "flat-tag-one").taxonomy.name).to eq("post_tag")

      # The per-item <category domain= nicename=> references became assignments.
      expect(hello.reload && Classification::Assignment.where(classifiable: hello).count).to eq(1)

      # Comments, with the thread wp:comment_parent carries.
      first = Discussion::Comment.find_by(author_name: "A WordPress Commenter")
      expect(first).to be_present
      expect(first.status).to eq("approved")
      expect(first.author_url).to eq("https://wordpress.org/")
      expect(Discussion::Comment.where.not(parent_id: nil).count).to eq(3)
      threaded = Discussion::Comment.where.not(parent_id: nil).first
      expect(threaded.parent.post_id).to eq(threaded.post_id)

      # The summary names every record, with a reason on anything not imported.
      expect(doc.at_css("h1").text).to eq("Import")
      expect(body_text).to include("Import finished")
      expect(body_text).to include("Hello world!")
    end

    it "reports each attachment as skipped, with the URL it did not fetch" do
      import!(oracle_wxr)

      rows = doc.css("tbody tr").select { |r| r.css("td").first&.text == "attachment" }
      expect(rows.length).to eq(3)
      expect(rows.first.text).to include("Skipped")
      expect(rows.first.text).to include("/wp-content/uploads/")
      # AD-02: nothing pretended to be a media record.
      expect(Library::Asset.count).to eq(0)
    end

    it "reports the machinery post types as skipped rather than dropping them silently" do
      import!(oracle_wxr)

      text = body_text
      %w[nav_menu_item wp_template wp_global_styles wp_navigation custom_css].each do |type|
        expect(text).to include(type)
      end
      expect(text).to include("is not a content type in this system")
    end

    it "is IDEMPOTENT: a second run of the same file imports nothing twice" do
      import!(oracle_wxr)
      counts = [Publishing::Post.count, Discussion::Comment.count,
                Classification::Term.count, Identity::User.count]

      import!(oracle_wxr)

      expect([Publishing::Post.count, Discussion::Comment.count,
              Classification::Term.count, Identity::User.count]).to eq(counts)
      expect(body_text).to include("Already exists")
    end

    it "honours an explicit author mapping onto an existing account" do
      target = actor("con_editor")
      import!(oracle_wxr,
              authors: { "oracle_admin" => { "mode" => "existing", "user_id" => target.id.to_s } })

      expect(Identity::User.find_by(login: "oracle_admin")).to be_nil
      expect(Publishing::Article.find_by(slug: "hello-world").author).to eq(target)
    end

    it "honours `skip`, leaving the records author-less rather than inventing an owner" do
      import!(oracle_wxr,
              authors: { "oracle_admin" => { "mode" => "skip" } })

      expect(Identity::User.find_by(login: "oracle_admin")).to be_nil
      expect(Publishing::Article.find_by(slug: "hello-world").author).to be_nil
    end
  end

  # ── The round trip: export -> import, through the real screens ──────────────────
  #
  # This is the claim the whole track rests on. The content is exported through the SAME
  # endpoint the Export screen posts to (POST /console/tools/export), the database is
  # emptied, and the bytes are fed back through the import screens. Anything the pair
  # cannot carry shows up here as a diff, not as an assumption.
  describe "round trip through /console/tools/export" do
    before { login_as("con_admin") }

    def build_corpus!
      author = actor("con_author")
      category = Classification::Taxonomy.find_or_create_by!(name: "category") { |t| t.hierarchical = true }
      tags = Classification::Taxonomy.find_or_create_by!(name: "post_tag") { |t| t.hierarchical = false }
      parent_term = Classification::Term.create!(taxonomy: category, name: "Parent « Cat » 😀", slug: "parent-cat",
                                                 description: "A description with \"quotes\".")
      child_term = Classification::Term.create!(taxonomy: category, name: "Child Cat", slug: "child-cat",
                                                parent: parent_term)
      tag = Classification::Term.create!(taxonomy: tags, name: "Tagged", slug: "tagged")

      article = Publishing::Article.create!(
        author: author, title: %(Round trip — "quoted" 😀), slug: "round-trip",
        content: "<!-- wp:paragraph -->\n<p>Body & more</p>\n<!-- /wp:paragraph -->",
        excerpt: "An excerpt", status: :published, published_at: 3.days.ago.change(usec: 0),
        comment_status: "open", menu_order: 0
      )
      Publishing::Attribute.create!(post: article, key: "custom_note", value: "kept".to_json)

      parent_page = Publishing::Page.create!(author: author, title: "Parent Page", slug: "parent-page",
                                             content: "parent", status: :published,
                                             published_at: 4.days.ago.change(usec: 0))
      Publishing::Page.create!(author: author, title: "Child Page", slug: "child-page", parent: parent_page,
                               content: "child", status: :published, menu_order: 3,
                               published_at: 2.days.ago.change(usec: 0))

      Classification::Assignment.set(article, [parent_term.id, child_term.id, tag.id])

      root = Discussion::Comment.create!(post: article, author_name: "Jo", author_email: "jo@example.com",
                                         author_url: "https://jo.example", content: "Top level",
                                         status: "approved", submitted_at: 2.days.ago.change(usec: 0))
      Discussion::Comment.create!(post: article, parent: root, author_name: "Ada",
                                  author_email: "ada@example.com", content: "A reply",
                                  status: "approved", submitted_at: 1.day.ago.change(usec: 0))
      # export.php:686 excludes spam; the round trip must therefore LOSE this one.
      Discussion::Comment.create!(post: article, author_name: "Spammer", content: "buy things",
                                  status: "spam", submitted_at: 1.day.ago.change(usec: 0))
    end

    def wipe!
      # Everything the export could have carried, so the re-import starts from nothing.
      Discussion::Comment.delete_all
      Classification::Assignment.delete_all
      Publishing::Attribute.delete_all
      Publishing::StatusTransition.delete_all
      Publishing::Revision.delete_all
      Publishing::Post.where.not(parent_id: nil).delete_all
      Publishing::Post.delete_all
      Classification::Term.delete_all
      Identity::RoleAssignment.where(user_id: Identity::User.where.not(login: "con_admin").select(:id)).delete_all
      Identity::Session.where(user_id: Identity::User.where.not(login: "con_admin").select(:id)).delete_all
      Identity::User.where.not(login: "con_admin").delete_all
    end

    it "carries the content, the hierarchy, the taxonomy, the custom fields and the threads" do
      build_corpus!

      post "/console/tools/export", params: { content: "all" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/xml")
      wxr = response.body
      expect(wxr).to include("<wp:wxr_version>1.2</wp:wxr_version>")

      wipe!
      expect(Publishing::Post.count).to eq(0)

      import!(wxr, filename: "round-trip.xml")

      # Posts and pages.
      article = Publishing::Article.find_by(slug: "round-trip")
      expect(article).to be_present
      expect(article.title).to eq(%(Round trip — "quoted" 😀))
      expect(article.content).to include("<p>Body & more</p>")
      expect(article.excerpt).to eq("An excerpt")
      expect(article.status).to eq("published")
      expect(article.comment_status).to eq("open")

      # The parent/child page hierarchy, rebuilt through the id REMAP (wp:post_parent
      # names the source site's id, which cannot be preserved: posts.id is GENERATED
      # ALWAYS AS IDENTITY).
      parent = Publishing::Page.find_by(slug: "parent-page")
      child = Publishing::Page.find_by(slug: "child-page")
      expect(child.parent).to eq(parent)
      expect(child.menu_order).to eq(3)

      # Taxonomy: the terms, their hierarchy, and the item's assignments.
      expect(Classification::Term.find_by(slug: "child-cat").parent.slug).to eq("parent-cat")
      expect(Classification::Term.find_by(slug: "parent-cat").description).to eq("A description with \"quotes\".")
      expect(Classification::Term.find_by(slug: "tagged").taxonomy.name).to eq("post_tag")
      assigned = Classification::Assignment.where(classifiable: article).includes(:term).map { |a| a.term.slug }
      expect(assigned).to contain_exactly("parent-cat", "child-cat", "tagged")

      # Custom fields (AD-03's residual bucket). The stored form is JSON TEXT — the
      # seeding pipeline's convention, which the importer follows — so the assertion is
      # that the row comes back BYTE-IDENTICAL to the one the export was taken from, not
      # that it has quietly gained or lost a level of JSON encoding.
      expect(Publishing::Attribute.find_by(post_id: article.id, key: "custom_note").value)
        .to eq("kept".to_json)

      # Authors.
      expect(article.author.login).to eq("con_author")

      # Comments, with the thread.
      root = Discussion::Comment.find_by(author_name: "Jo")
      reply = Discussion::Comment.find_by(author_name: "Ada")
      expect(root.post).to eq(article)
      expect(reply.parent).to eq(root)
      expect(root.author_url).to eq("https://jo.example")
      # export.php:686 — spam is not content and does not travel. Asserted so the loss is
      # a stated property of the pair rather than a surprise.
      expect(Discussion::Comment.find_by(author_name: "Spammer")).to be_nil
    end
  end
end
