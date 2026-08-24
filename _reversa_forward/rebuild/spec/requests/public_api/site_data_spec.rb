# frozen_string_literal: true

require_relative "../console/console_spec_helper"

# TRACK 2 — the SITE DATA half of the REST surface: /wp/v2/settings, /wp/v2/themes,
# /wp/v2/global-styles (three shapes), /wp/v2/templates + /template-parts + lookup,
# /wp/v2/block-patterns/categories, /wp/v2/blocks and the `_fields` projection on `/`.
#
# This is the block editor's BOOT CONTRACT: twenty-four preloaded paths, of which these
# are the site-data ones. Every shape below was read off the live oracle and diffed
# field-by-field before it was written down (the handoff records the diffs); what these
# specs pin is the part of that contract which does not depend on the oracle's exact
# fixture rows — the field SET, the field ORDER where it is observable, the LITERAL error
# codes/messages, and the 401/403 split of rest_authorization_required_code().
#
# ⚠️ `bin/rspec_worker` runs `rake theme:load` before the suite, so the active theme, its
# eight templates, seven parts and 99 patterns are present. A spec that needs them says so
# through `skip_without_theme!` rather than failing for a fixture reason.
RSpec.describe "REST API — site data (/wp-json/wp/v2)", type: :request do
  before { host! "127.0.0.1" }

  def json = JSON.parse(response.body)
  def bearer(user) = { "Authorization" => "Bearer #{Identity::Session.issue!(user, ip: "127.0.0.1")}" }
  def json_headers(user) = bearer(user).merge("CONTENT_TYPE" => "application/json")

  def admin = actor("con_admin")
  def subscriber = actor("con_subscriber")

  def active_theme = Presentation::Theme.active.first

  def skip_without_theme!
    return if active_theme && Composition::Template.where(kind: "template",
                                                          theme_slug: active_theme.slug).exists?

    skip "no theme loaded — run `bin/rails theme:load` (bin/rspec_worker does)"
  end

  before { seed_console_accounts! }

  # ── /wp/v2/settings ───────────────────────────────────────────────────────────────
  describe "GET /wp/v2/settings" do
    it "denies an anonymous caller with the GENERIC rest_forbidden envelope at 401" do
      get "/wp-json/wp/v2/settings"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_forbidden",
                         "message" => "Sorry, you are not allowed to do that.",
                         "data" => { "status" => 401 })
    end

    it "denies a non-privileged identity with the same envelope at 403 (BR-REST-06)" do
      get "/wp-json/wp/v2/settings", headers: bearer(subscriber)
      expect(response).to have_http_status(:forbidden)
      expect(json["data"]).to eq("status" => 403)
    end

    # The key ORDER is register_initial_settings()' registration order, and it is
    # observable — the oracle emits exactly this sequence.
    it "serves the registered set, in registration order, to manage_options" do
      get "/wp-json/wp/v2/settings", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq("application/json; charset=UTF-8")
      expect(json.keys).to eq(%w[
                                title description url email timezone date_format time_format
                                start_of_week language use_smilies default_category
                                default_post_format posts_per_page show_on_front page_on_front
                                page_for_posts default_ping_status default_comment_status
                                site_logo site_icon
                              ])
    end

    it "prepares each value as its schema type, not as the stored string" do
      Configuration::Setting.set("start_of_week", "1")
      Configuration::Setting.set("posts_per_page", "10")
      Configuration::Setting.set("use_smilies", "1")
      get "/wp-json/wp/v2/settings", headers: bearer(admin)
      expect(json["start_of_week"]).to eq(1)
      expect(json["posts_per_page"]).to eq(10)
      expect(json["use_smilies"]).to be(true)
    end

    it "falls back to the registered default for an absent option, and site_logo is null" do
      Configuration::Setting.where(name: %w[WPLANG site_logo]).delete_all
      get "/wp-json/wp/v2/settings", headers: bearer(admin)
      expect(json["language"]).to eq("en_US")
      expect(json["site_logo"]).to be_nil
    end
  end

  describe "PUT /wp/v2/settings" do
    it "denies an anonymous writer" do
      put "/wp-json/wp/v2/settings", params: { title: "x" }.to_json,
                                     headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("rest_forbidden")
    end

    it "writes the named settings and answers with the whole document" do
      put "/wp-json/wp/v2/settings",
          params: { date_format: "Y-m-d", posts_per_page: 7 }.to_json,
          headers: json_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["date_format"]).to eq("Y-m-d")
      expect(json["posts_per_page"]).to eq(7)
      expect(Configuration::Setting["date_format"]).to eq("Y-m-d")
    end

    it "leaves an unnamed setting alone and ignores an unregistered one" do
      Configuration::Setting.set("time_format", "g:i a")
      put "/wp-json/wp/v2/settings", params: { date_format: "Y-m-d", not_a_setting: "boom" }.to_json,
                                     headers: json_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(Configuration::Setting["time_format"]).to eq("g:i a")
      expect(Configuration::Setting.find_by(name: "not_a_setting")).to be_nil
    end

    # BR-MIGRATE-014 (BR-OPT-15): update_option() -> sanitize_option() -> esc_html for
    # these two, which is why they are stored escaped (SANITIZED_ON_WRITE).
    it "esc_html's blogname on write, and does not double-encode an escaped value" do
      put "/wp-json/wp/v2/settings", params: { title: %(a "quoted" & <b>x</b>) }.to_json,
                                     headers: json_headers(admin)
      expect(json["title"]).to eq("a &quot;quoted&quot; &amp; &lt;b&gt;x&lt;/b&gt;")

      put "/wp-json/wp/v2/settings", params: { title: "a &quot;quoted&quot;" }.to_json,
                                     headers: json_headers(admin)
      expect(json["title"]).to eq("a &quot;quoted&quot;")
    end

    it "rejects a wrong type with rest_invalid_param and writes NOTHING" do
      Configuration::Setting.set("date_format", "F j, Y")
      put "/wp-json/wp/v2/settings",
          params: { start_of_week: "nope", date_format: "Y-m-d" }.to_json,
          headers: json_headers(admin)
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        "code" => "rest_invalid_param",
        "message" => "Invalid parameter(s): start_of_week",
        "data" => {
          "status" => 400,
          "params" => { "start_of_week" => "start_of_week is not of type integer." },
          "details" => { "start_of_week" => {
            "code" => "rest_invalid_type",
            "message" => "start_of_week is not of type integer.",
            "data" => { "param" => "start_of_week" }
          } }
        }
      )
      expect(Configuration::Setting["date_format"]).to eq("F j, Y")
    end

    it "deletes the option when the value is null (:174)" do
      Configuration::Setting.set("default_post_format", "0")
      put "/wp-json/wp/v2/settings", params: { default_post_format: nil }.to_json,
                                     headers: json_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(Configuration::Setting.find_by(name: "default_post_format")).to be_nil
    end
  end

  # ── /wp/v2/themes ─────────────────────────────────────────────────────────────────
  describe "GET /wp/v2/themes?context=edit&status=active" do
    it "refuses anonymously with the theme-specific code" do
      get "/wp-json/wp/v2/themes", params: { context: "edit", status: "active" }
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_view_active_theme",
                         "message" => "Sorry, you are not allowed to view the active theme.",
                         "data" => { "status" => 401 })
    end

    it "serves the active theme with its theme_supports block" do
      skip_without_theme!
      get "/wp-json/wp/v2/themes", params: { context: "edit", status: "active" },
                                   headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(1)
      theme = json.first
      expect(theme["stylesheet"]).to eq(active_theme.slug)
      expect(theme["status"]).to eq("active")
      expect(theme["is_block_theme"]).to be(true)
      expect(theme["name"]).to eq("raw" => active_theme.name, "rendered" => active_theme.name)
      expect(theme["theme_supports"]).to include("editor-styles" => true, "post-thumbnails" => true)
      expect(theme["theme_supports"]["html5"]).to include("comment-form", "caption")
      # The two tables the site editor reads off this response.
      expect(theme["default_template_types"].map { |t| t["slug"] }).to include("index", "single", "404")
      expect(theme["default_template_part_areas"].map { |a| a["area"] })
        .to include("header", "footer", "uncategorized")
    end

    it "links the theme to its (auto-created) user global styles record" do
      skip_without_theme!
      get "/wp-json/wp/v2/themes", params: { status: "active" }, headers: bearer(admin)
      href = json.first["_links"]["wp:user-global-styles"].first["href"]
      expect(href).to eq(PublicApi::Url.rest("/wp/v2/global-styles/#{active_theme.id}"))
      # BR-MIGRATE-209: reading the link is what CREATES the record, so it resolves.
      # Followed as a PATH: `home` is unset in the spec database, so Url.rest builds a
      # relative href there and rack-test cannot parse it as a URI.
      get "/wp-json/wp/v2/global-styles/#{active_theme.id}", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  # ── /wp/v2/global-styles ──────────────────────────────────────────────────────────
  describe "global styles" do
    it "refuses the theme endpoints anonymously with rest_cannot_read_global_styles" do
      skip_without_theme!
      get "/wp-json/wp/v2/global-styles/themes/#{active_theme.slug}"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_read_global_styles",
                         "message" => "Sorry, you are not allowed to access the global styles on this site.",
                         "data" => { "status" => 401 })
    end

    it "serves the THEME layer as settings + styles off the four-origin cascade" do
      skip_without_theme!
      get "/wp-json/wp/v2/global-styles/themes/#{active_theme.slug}", params: { context: "view" },
                                                                      headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json.keys).to eq(%w[settings styles _links])
      # `appearanceTools` is the theme's; `border`/`dimensions`/`position` only exist
      # because core's own theme.json (the 'default' origin) merged in first.
      expect(json["settings"]).to include("appearanceTools", "color", "typography", "border",
                                          "dimensions", "position")
      # The theme's block style-variation partials (styles/blocks/*, styles/sections/*),
      # which WP_Theme_JSON_Resolver::get_theme_data() injects before the merge.
      expect(json["styles"]["blocks"]["core/group"]["variations"].keys).to include("section-1")
      expect(json["styles"]["blocks"]["core/heading"]["variations"].keys).to include("text-display")
      expect(json["_links"]["self"].first["targetHints"]).to eq("allow" => ["GET"])
    end

    it "serves the theme's style VARIATIONS as whole theme.json documents" do
      skip_without_theme!
      get "/wp-json/wp/v2/global-styles/themes/#{active_theme.slug}/variations",
          params: { context: "view" }, headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to be_an(Array)
      expect(json).not_to be_empty
      expect(json.first.keys).to include("version", "title", "settings", "styles")
      expect(json.map { |v| v["title"] }).to include("Evening", "Midnight")
    end

    it "answers rest_theme_not_found for any theme but the active one (:565)" do
      get "/wp-json/wp/v2/global-styles/themes/not-a-theme", headers: bearer(admin)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_theme_not_found", "message" => "Theme not found.",
                         "data" => { "status" => 404 })
    end

    it "answers rest_global_styles_not_found for an unknown record id" do
      get "/wp-json/wp/v2/global-styles/999999", headers: bearer(admin)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_global_styles_not_found",
                         "message" => "No global styles config exists with that ID.",
                         "data" => { "status" => 404 })
    end

    it "serves the USER layer, empty until it is written (:345-350)" do
      skip_without_theme!
      active_theme.update!(user_styles: nil)
      get "/wp-json/wp/v2/global-styles/#{active_theme.id}", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(active_theme.id)
      expect(json["title"]).to eq("raw" => "Custom Styles", "rendered" => "Custom Styles")
      expect(json["settings"]).to eq({})
      expect(json["styles"]).to eq({})
      expect(json["_links"]["about"].first["href"])
        .to eq(PublicApi::Url.rest("/wp/v2/types/wp_global_styles"))
    end

    it "refuses the user layer anonymously with rest_cannot_view" do
      skip_without_theme!
      get "/wp-json/wp/v2/global-styles/#{active_theme.id}"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_view",
                         "message" => "Sorry, you are not allowed to view this global style.",
                         "data" => { "status" => 401 })
    end

    it "PUT gates on edit_theme_options with rest_cannot_edit" do
      skip_without_theme!
      put "/wp-json/wp/v2/global-styles/#{active_theme.id}",
          params: { styles: {} }.to_json, headers: json_headers(subscriber)
      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("code" => "rest_cannot_edit",
                         "message" => "Sorry, you are not allowed to edit this global style.",
                         "data" => { "status" => 403 })
    end

    it "PUT writes the user layer and keeps the isGlobalStylesUserThemeJSON flag" do
      skip_without_theme!
      put "/wp-json/wp/v2/global-styles/#{active_theme.id}",
          params: { styles: { "color" => { "background" => "#111111" } },
                    settings: { "color" => { "custom" => true } } }.to_json,
          headers: json_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json["styles"]).to eq("color" => { "background" => "#111111" })
      expect(json["settings"]).to eq("color" => { "custom" => true })
      # BR-MIGRATE-210: without the flag the document is not trusted at read time, so a
      # write that dropped it would silently empty the user layer.
      stored = active_theme.reload.user_styles
      expect(stored["isGlobalStylesUserThemeJSON"]).to be(true)

      get "/wp-json/wp/v2/global-styles/#{active_theme.id}", headers: bearer(admin)
      expect(json["styles"]).to eq("color" => { "background" => "#111111" })
    end
  end

  # ── /wp/v2/templates + /template-parts ────────────────────────────────────────────
  describe "templates" do
    it "refuses anonymously with rest_cannot_manage_templates" do
      get "/wp-json/wp/v2/templates"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("code" => "rest_cannot_manage_templates",
                         "message" => "Sorry, you are not allowed to access the templates on this site.",
                         "data" => { "status" => 401 })
    end

    it "serves the ACTIVE theme's templates only, in the legacy's field shape" do
      skip_without_theme!
      Composition::Template.create!(theme_slug: "some-other-theme", kind: "template",
                                    slug: "index", title: "Other", content: "x")
      get "/wp-json/wp/v2/templates", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json.map { |t| t["theme"] }.uniq).to eq([active_theme.slug])

      page = json.detect { |t| t["slug"] == "page" }
      expect(page["id"]).to eq("#{active_theme.slug}//page")
      expect(page["type"]).to eq("wp_template")
      expect(page["source"]).to eq("theme")
      expect(page["origin"]).to be_nil
      expect(page["status"]).to eq("publish")
      expect(page["wp_id"]).to eq(0)
      expect(page["has_theme_file"]).to be(true)
      expect(page["author"]).to eq(0)
      expect(page["modified"]).to be_nil
      expect(page["date"]).to be_nil
      expect(page["original_source"]).to eq("theme")
      expect(page["author_text"]).to eq(active_theme.name)
      expect(page["description"]).to include("Displays a static page")
    end

    # `is_custom` is "this slug is not one of get_default_block_template_types()".
    it "marks a theme's customTemplates entry is_custom, and a default type not" do
      skip_without_theme!
      get "/wp-json/wp/v2/templates", headers: bearer(admin)
      by_slug = json.index_by { |t| t["slug"] }
      expect(by_slug["index"]["is_custom"]).to be(false)
      expect(by_slug["page-no-title"]["is_custom"]).to be(true) if by_slug.key?("page-no-title")
    end

    # :684-690 — the whole reason the editor can render a template it just fetched.
    it "RESOLVES core/pattern references in content.raw" do
      skip_without_theme!
      pattern = Composition::Pattern.where("slug LIKE ?", "%/%").first
      skip "no theme patterns loaded" if pattern.nil?
      template = Composition::Template.create!(
        theme_slug: active_theme.slug, kind: "template", slug: "pattern-probe",
        title: "Probe", content: %(<!-- wp:pattern {"slug":"#{pattern.slug}"} /-->\n)
      )
      get "/wp-json/wp/v2/templates/#{template.theme_slug}//#{template.slug}", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json["content"]["raw"]).not_to include("wp:pattern")
      expect(json["content"]["raw"]).not_to be_empty
    end

    it "answers rest_template_not_found for an unknown id" do
      skip_without_theme!
      get "/wp-json/wp/v2/templates/#{active_theme.slug}//nope", headers: bearer(admin)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_template_not_found",
                         "message" => "No templates exist with that id.",
                         "data" => { "status" => 404 })
    end

    it "serves template PARTS with `area` and without `is_custom`" do
      skip_without_theme!
      get "/wp-json/wp/v2/template-parts", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      part = json.detect { |t| t["slug"] == "footer" }
      skip "theme ships no footer part" if part.nil?
      expect(part["type"]).to eq("wp_template_part")
      expect(part["area"]).to eq("footer")
      expect(part).not_to have_key("is_custom")
      expect(part["_links"]["collection"].first["href"])
        .to eq(PublicApi::Url.rest("/wp/v2/template-parts"))
    end
  end

  # ── /wp/v2/templates/lookup ───────────────────────────────────────────────────────
  describe "GET /wp/v2/templates/lookup" do
    it "requires the slug argument (rest_missing_callback_param)" do
      get "/wp-json/wp/v2/templates/lookup", headers: bearer(admin)
      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("code" => "rest_missing_callback_param",
                         "message" => "Missing parameter(s): slug",
                         "data" => { "status" => 400, "params" => ["slug"] })
    end

    it "resolves a slug through the hierarchy to the single best match" do
      skip_without_theme!
      {
        "index" => "index", "404" => "404", "search" => "search", "home" => "home",
        # No `category-*` / `author-*` / `date` template ships, so each falls to `archive`.
        "category-news" => "archive", "author-jane" => "archive", "date" => "archive",
        "taxonomy-category" => "archive",
        # `single-post` -> single-post -> single; `page-about` -> page-about -> page.
        "single-post" => "single", "page-about" => "page",
        # `attachment` -> attachment -> single -> singular -> index; only `single` exists.
        "attachment" => "single",
        # A slug nothing matches falls all the way to `index` (template-loader.php:103).
        "not-a-template" => "index"
      }.each do |slug, expected|
        get "/wp-json/wp/v2/templates/lookup", params: { slug: slug }, headers: bearer(admin)
        expect(response).to have_http_status(:ok)
        expect(json["id"]).to eq("#{active_theme.slug}//#{expected}"),
                                 "lookup(#{slug.inspect}) resolved to #{json["id"].inspect}"
      end
    end

    it "`is_custom` short-circuits the hierarchy to page -> singular -> index" do
      skip_without_theme!
      get "/wp-json/wp/v2/templates/lookup", params: { slug: "my-custom", is_custom: "1" },
                                             headers: bearer(admin)
      expect(json["id"]).to eq("#{active_theme.slug}//page")
    end

    # :168 — "return an empty object rather than a 404 error when no template is found".
    it "answers an EMPTY OBJECT, not a 404, when the theme has nothing at all" do
      Composition::Template.delete_all
      get "/wp-json/wp/v2/templates/lookup", params: { slug: "page" }, headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to eq({})
    end
  end

  # ── /wp/v2/block-patterns/categories ──────────────────────────────────────────────
  describe "GET /wp/v2/block-patterns/categories" do
    it "refuses anonymously with the pattern-category code" do
      get "/wp-json/wp/v2/block-patterns/categories"
      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq(
        "code" => "rest_cannot_view",
        "message" => "Sorry, you are not allowed to view the registered block pattern categories.",
        "data" => { "status" => 401 }
      )
    end

    it "serves {name, label, description} for every registered category" do
      get "/wp-json/wp/v2/block-patterns/categories", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(json).to be_an(Array)
      expect(json).not_to be_empty
      expect(json.first.keys).to eq(%w[name label description])
      expect(json.map { |c| c["name"] }).to include("header", "footer", "text")
    end
  end

  # ── /wp/v2/blocks ─────────────────────────────────────────────────────────────────
  describe "GET /wp/v2/blocks" do
    let!(:reusable) do
      Composition::Pattern.create!(slug: "a-reusable-block", title: "A Reusable Block",
                                   content: "<!-- wp:paragraph --><p>Hello</p><!-- /wp:paragraph -->")
    end

    # `wp_block` is not a public post type: the collection is served with no route gate and
    # the per-record read check empties it. 200 + [] + the headers, never a 404.
    it "answers 200 with an EMPTY collection and the pagination headers for an anonymous caller" do
      get "/wp-json/wp/v2/blocks"
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
      expect(response.headers["X-WP-Total"]).to eq("0")
      expect(response.headers["X-WP-TotalPages"]).to eq("0")
    end

    it "serves the reusable blocks to an editor, in the legacy's field shape" do
      get "/wp-json/wp/v2/blocks", headers: bearer(admin)
      expect(response).to have_http_status(:ok)
      expect(response.headers["X-WP-Total"]).to eq(json.length.to_s)
      block = json.detect { |b| b["slug"] == "a-reusable-block" }
      expect(block["type"]).to eq("wp_block")
      expect(block["status"]).to eq("publish")
      expect(block["title"]).to eq("raw" => "A Reusable Block")
      expect(block["content"]["raw"]).to include("<p>Hello</p>")
      expect(block["content"]["protected"]).to be(false)
      expect(block["meta"]).to eq("footnotes" => "")
      expect(block["wp_pattern_category"]).to eq([])
      expect(block["wp_pattern_sync_status"]).to eq("")
      expect(block["_links"]["about"].first["href"])
        .to eq(PublicApi::Url.rest("/wp/v2/types/wp_block"))
    end

    # AD-02 put the theme's registered patterns in the SAME table; they are not reusable
    # blocks and `/wp/v2/blocks` must never show them.
    it "never returns a theme's registered pattern (its slug is namespaced)" do
      Composition::Pattern.create!(slug: "sometheme/hero", title: "Hero", content: "x")
      get "/wp-json/wp/v2/blocks", headers: bearer(admin)
      expect(json.map { |b| b["slug"] }).not_to include("sometheme/hero")
    end

    it "answers rest_post_invalid_id for an unknown id" do
      get "/wp-json/wp/v2/blocks/999999", headers: bearer(admin)
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("code" => "rest_post_invalid_id", "message" => "Invalid post ID.",
                         "data" => { "status" => 404 })
    end
  end

  # ── GET / (the root document's `_fields` projection) ──────────────────────────────
  describe "GET /wp-json/ with the editor's _fields projection" do
    it "carries the front-page wiring in the un-projected document, in position" do
      get "/wp-json/"
      expect(response).to have_http_status(:ok)
      keys = json.keys
      expect(keys).to include("page_for_posts", "page_on_front", "show_on_front")
      expect(keys.index("show_on_front")).to be < keys.index("namespaces")
      expect(keys.index("timezone_string")).to be < keys.index("page_for_posts")
    end

    it "projects to the INTERSECTION of the request's names, in the document's own order" do
      fields = "description,gmt_offset,home,image_max_bit_depth,image_sizes," \
               "image_size_threshold,image_strip_meta,name,site_icon,site_icon_url," \
               "site_logo,timezone_string,url,page_for_posts,page_on_front,show_on_front"
      get "/wp-json/", params: { _fields: fields }
      expect(response).to have_http_status(:ok)
      # The names the header has no field for are OMITTED, not emitted as null.
      expect(json.keys).to eq(%w[name description url home gmt_offset timezone_string
                                 page_for_posts page_on_front show_on_front
                                 site_logo site_icon site_icon_url])
      # `routes` and `_links` were not asked for, so they are gone.
      expect(json).not_to have_key("routes")
      expect(json).not_to have_key("_links")
    end

    it "leaves the document untouched when no _fields is given" do
      get "/wp-json/"
      expect(json).to have_key("routes")
      expect(json).to have_key("_links")
    end
  end
end
