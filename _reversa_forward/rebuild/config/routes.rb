Rails.application.routes.draw do
  # Wave 1 (syndication) + Wave 2 (front-end read path). migration_strategy.md:
  # both are READ-ONLY -- "no write path", "the whole public site renders from
  # PostgreSQL". Nothing here writes, which is why these waves are reversible.
  #
  # ⚠️ AD-04: every route must carry an EXPLICIT authorization declaration, including a
  # declaration of `public`. config/initializers/authorization_declarations.rb registers
  # them and fails the boot if any route is missing one. That does not change the runtime
  # default -- BR-REST-05 keeps an undeclared route public -- it removes the way that
  # default gets reached, which is by someone forgetting.

  root "web/archives#index"

  # Wave 3 -- the content write path, Library. POST /console/media is the upload endpoint
  # (wp-admin/async-upload.php, API-shaped); GET /wp-content/uploads/* is
  # wp_get_attachment_url()'s URL space, declared before the page glob below would
  # swallow it. Both carry explicit AD-04 declarations.
  post "/console/media", to: "web/uploads#create", as: :console_media_uploads
  get "/wp-content/uploads/*path", to: "web/uploads#show", as: :uploaded_file, format: false

  # ── Wave 4: the editor SHELL — console.post-new / console.post / console.site-editor ──
  # target_screens.md § The editor (DEV-012). ⚠️ SERVER-SIDE HALF ONLY this pass (owner
  # ruling): the Gutenberg canvas/inspector is the deferred React island. Full-bleed
  # EditorLayout. Declared BEFORE the /*path page glob, which would otherwise swallow
  # `console/...` as a page slug. Every route carries an AD-04 declaration
  # (config/initializers/authorization_declarations.rb).
  get    "/console/posts/new",           to: "console/posts#new",        as: :new_console_post
  get    "/console/posts/:id/edit",      to: "console/posts#edit",       as: :edit_console_post
  match  "/console/posts/:id",           to: "console/posts#update",     as: :console_post, via: %i[patch put]
  get    "/console/posts/:id/blocks",    to: "console/posts#blocks",     as: :blocks_console_post # editor React island (DEV-012, D-3) initial load
  post   "/console/posts/:id/autosave",  to: "console/posts#autosave",   as: :autosave_console_post
  post   "/console/posts/:id/lock",      to: "console/posts#lock",       as: :lock_console_post
  delete "/console/posts/:id/lock",      to: "console/posts#unlock",     as: :unlock_console_post
  post   "/console/posts/:id/steal",     to: "console/posts#steal",      as: :steal_console_post
  get    "/console/site-editor",         to: "console/site_editor#show", as: :console_site_editor
  # Site Editor React island (DEV-012, D-3): template browser, template block editing, and
  # Global Styles over the theme.json cascade.
  get   "/console/site-editor/templates",           to: "console/site_editor#templates_index", as: :console_site_editor_templates
  get   "/console/site-editor/templates/:id/blocks", to: "console/site_editor#template_blocks", as: :console_site_editor_template_blocks
  match "/console/site-editor/templates/:id",       to: "console/site_editor#update_template", as: :console_site_editor_template, via: %i[patch put]
  get   "/console/site-editor/styles",              to: "console/site_editor#styles",          as: :console_site_editor_styles
  match "/console/site-editor/styles",              to: "console/site_editor#update_styles",   via: %i[patch put]

  # ── Wave 4: the P-EDIT single-record console edit screens (target_screens.md § P-EDIT
  # instantiations). Modernized mode: LITERAL strings, model-backed saves, Access object
  # policies. Declared BEFORE the /*path glob. `new` before `:id/edit` so it is not read as
  # an id. `/console/posts/:id/revisions` is more specific than the editor's `:id` routes.
  # List index routes (GET /console/users, /console/comments, …) belong to the P-LIST track;
  # these claim only the single-record paths so the two tracks do not collide on route names.
  get   "/console/comments/:id/edit",        to: "console/comments#edit",   as: :edit_console_comment
  match "/console/comments/:id",             to: "console/comments#update", as: :console_comment, via: %i[patch put]
  get   "/console/terms/:taxonomy/:id/edit", to: "console/terms#edit",      as: :edit_console_term
  match "/console/terms/:taxonomy/:id",      to: "console/terms#update",    as: :console_term, via: %i[patch put]
  get   "/console/media/:id/edit",           to: "console/media#edit",      as: :edit_console_medium
  match "/console/media/:id",                to: "console/media#update",    as: :console_medium, via: %i[patch put]
  get   "/console/users/new",                to: "console/users#new",       as: :new_console_user
  post  "/console/users",                    to: "console/users#create", as: :console_user_create # explicit: an UNNAMED post would auto-derive `console_users`, colliding with the P-LIST index route of that name
  get   "/console/users/:id/edit",           to: "console/users#edit",      as: :edit_console_user
  match "/console/users/:id",                to: "console/users#update",    as: :console_user, via: %i[patch put]
  get   "/console/profile",                  to: "console/profiles#show",   as: :console_profile
  match "/console/profile",                  to: "console/profiles#update", via: %i[patch put]
  get   "/console/posts/:id/revisions",      to: "console/revisions#index", as: :console_post_revisions

  # ── Wave 4: the P-LIST console list screens (target_screens.md § Part 5) ────────────
  # console.edit (posts + pages variant), console.upload, console.edit-comments,
  # console.users, console.edit-tags. Each is a filtered, paginated, bulk-actionable list.
  # Distinct controllers from the editor/P-EDIT ones above: WordPress separates edit.php
  # (list) from post.php (single), and the tracks are separate here too. Declared BEFORE
  # the /*path page glob. The /bulk paths are the checkbox-column POST target (DEV-004
  # confirms destructive actions). GET /console/media coexists with the Wave 3 upload
  # endpoint (POST /console/media) — same path, different verb.
  get  "/console/posts",               to: "console/posts_list#index",    as: :console_posts
  post "/console/posts/bulk",          to: "console/posts_list#bulk",     as: :console_posts_bulk
  get  "/console/pages",               to: "console/pages_list#index",    as: :console_pages
  post "/console/pages/bulk",          to: "console/pages_list#bulk",     as: :console_pages_bulk
  get  "/console/media",               to: "console/media_list#index",    as: :console_media
  post "/console/media/bulk",          to: "console/media_list#bulk",     as: :console_media_bulk
  get  "/console/comments",            to: "console/comments_list#index", as: :console_comments
  post "/console/comments/bulk",       to: "console/comments_list#bulk",  as: :console_comments_bulk
  get  "/console/users",               to: "console/users_list#index",    as: :console_users
  post "/console/users/bulk",          to: "console/users_list#bulk",     as: :console_users_bulk
  get  "/console/terms/:taxonomy",      to: "console/terms_list#index",   as: :console_terms
  post "/console/terms/:taxonomy/bulk", to: "console/terms_list#bulk",    as: :console_terms_bulk

  # ── Wave 4: appearance — console.themes / console.theme-install / console.nav-menus ──
  # target_screens.md § Part 5 + DEV-011 (themes yes, plugins no). Declared BEFORE the
  # /*path page glob, which would otherwise swallow `console/...`. Each carries an AD-04
  # declaration. `themes/new` is declared before `themes/:slug` so `new` is not read as a
  # slug.
  get    "/console/themes",                to: "console/themes#index",          as: :console_themes
  get    "/console/themes/new",            to: "console/theme_install#new",     as: :new_console_theme
  post   "/console/themes",                to: "console/theme_install#create"
  post   "/console/themes/:slug/activate", to: "console/themes#activate",       as: :activate_console_theme
  delete "/console/themes/:slug",          to: "console/themes#destroy",        as: :console_theme

  get    "/console/menus",                 to: "console/menus#index",           as: :console_menus
  post   "/console/menus",                 to: "console/menus#create"
  get    "/console/menus/:id",             to: "console/menus#show",            as: :console_menu
  match  "/console/menus/:id",             to: "console/menus#update",          via: %i[patch put]
  delete "/console/menus/:id",             to: "console/menus#destroy"
  post   "/console/menus/:id/items",       to: "console/menus#add_item",        as: :console_menu_items
  match  "/console/menus/:id/items/:item_id", to: "console/menus#move_item",    via: %i[patch put], as: :console_menu_item
  delete "/console/menus/:id/items/:item_id", to: "console/menus#remove_item"

  # ── Wave 4: the bespoke console — dashboard, 9 settings screens, tools, site health,
  # GDPR data requests, informational pages (target_screens.md § Settings screens :510,
  # § Dashboard, tools :545). Modernized mode: LITERAL strings, DECLARED fields (DEV-002).
  # Declared BEFORE the /*path page glob. The single-record and list routes above belong
  # to the P-EDIT / P-LIST tracks; this block claims only the settings/tools/info paths.
  get  "/console",                      to: "console/dashboard#index",  as: :console_dashboard

  # The 9 settings screens (console.options is NOT reproduced — DEV-002). `settings`
  # (general) is the exact path; every other section is `settings/:section`.
  get  "/console/settings",             to: "console/settings#show",    as: :console_settings, defaults: { section: "general" }
  post "/console/settings",             to: "console/settings#update",  defaults: { section: "general" }
  get  "/console/settings/:section",    to: "console/settings#show",    as: :console_settings_section
  post "/console/settings/:section",    to: "console/settings#update"

  # Tools + Site Health.
  get  "/console/tools",                to: "console/tools#index",      as: :console_tools
  get  "/console/tools/export",         to: "console/tools#export",     as: :console_export
  post "/console/tools/export",         to: "console/tools#export_download"
  get  "/console/tools/site-health",    to: "console/site_health#show", as: :console_site_health
  get  "/console/tools/site-health/info", to: "console/site_health#info", as: :console_site_health_info
  get  "/console/tools/privacy-guide",  to: "console/privacy_guide#show", as: :console_privacy_guide

  # GDPR — P-LIST over Identity::DataRequest, one screen per kind (console.export/erase).
  get  "/console/tools/export-personal-data", to: "console/data_requests#export", as: :console_export_personal_data
  post "/console/tools/export-personal-data", to: "console/data_requests#create"
  get  "/console/tools/erase-personal-data",  to: "console/data_requests#erase",  as: :console_erase_personal_data
  post "/console/tools/erase-personal-data",  to: "console/data_requests#create",  as: :console_create_data_request

  # Informational pages (console.about/.credits/.freedoms/.contribute/.privacy) — DEV-009:
  # the rebuild's own content. Constrained so the glob below never reads a page slug here.
  # console.contribute is titled "Get Involved"; only the legacy FILE name says "contribute".
  # Place ABOVE the existing `get "/console/:page"` info glob (its constraint does not match
  # this slug) and well above the `get "/*path"` page permalink glob. Needs NO new AD-04
  # declaration: it dispatches to console/info#show, already declared :authenticated.
  # The existing /console/contribute route stays as-is; Console::InfoController#info_tab_path
  # switches the tab to this path automatically as soon as the named helper exists.
  get  "/console/get-involved", to: "console/info#show", as: :console_get_involved, defaults: { page: "contribute" }
  # ── Wave 5: the NETWORK ADMIN (wp-admin/ms-*.php → wp-admin/network/*.php) ──────────
  # target_screens.md Part 6's neighbour: 7 screens + 2 Add screens, MODERNIZED mode.
  # ⚠️ STRICTLY ADDITIVE — every one of these 404s while `Tenancy.enabled?` is false
  # (Console::Network::BaseController prepends the gate ahead of auth_redirect and AD-04),
  # so a single site behaves exactly as it did in Waves 0–4. Declared BEFORE the /*path
  # page glob, which would otherwise swallow `console/network/...` as a page slug. Every
  # route carries an AD-04 declaration.
  get  "/console/network",                    to: "console/network/dashboard#index", as: :console_network

  # console.ms-sites. `new` BEFORE `:id`, so it is not read as a site id.
  get  "/console/network/sites",              to: "console/network/sites#index",     as: :console_network_sites
  post "/console/network/sites/bulk",         to: "console/network/sites#bulk",      as: :console_network_sites_bulk
  get  "/console/network/sites/new",          to: "console/network/sites#new",       as: :new_console_network_site
  post "/console/network/sites",              to: "console/network/sites#create",    as: :create_console_network_site

  # console.ms-site-edit — the four network_edit_site_nav tabs (Info/Users/Themes/Settings).
  get  "/console/network/sites/:id",          to: "console/network/site_edit#info",            as: :console_network_site
  post "/console/network/sites/:id",          to: "console/network/site_edit#update_info"
  get  "/console/network/sites/:id/users",    to: "console/network/site_edit#users",           as: :console_network_site_users
  get  "/console/network/sites/:id/themes",   to: "console/network/site_edit#themes",          as: :console_network_site_themes
  post "/console/network/sites/:id/themes",   to: "console/network/site_edit#update_themes"
  get  "/console/network/sites/:id/settings", to: "console/network/site_edit#settings",        as: :console_network_site_settings
  post "/console/network/sites/:id/settings", to: "console/network/site_edit#update_settings"

  # console.ms-users
  get  "/console/network/users",              to: "console/network/users#index",     as: :console_network_users
  post "/console/network/users/bulk",         to: "console/network/users#bulk",      as: :console_network_users_bulk
  get  "/console/network/users/new",          to: "console/network/users#new",       as: :new_console_network_user
  post "/console/network/users",              to: "console/network/users#create",    as: :create_console_network_user

  # console.ms-themes
  get  "/console/network/themes",             to: "console/network/themes#index",    as: :console_network_themes
  post "/console/network/themes/bulk",        to: "console/network/themes#bulk",     as: :console_network_themes_bulk

  # console.ms-options
  get  "/console/network/settings",           to: "console/network/settings#show",   as: :console_network_settings
  post "/console/network/settings",           to: "console/network/settings#update"

  # console.my-sites — NOT network admin: my-sites.php:19 gates on `read`, so an ordinary
  # member reaches it. It carries its own multisite gate all the same.
  get  "/console/my-sites",                   to: "console/my_sites#show",           as: :console_my_sites
  post "/console/my-sites",                   to: "console/my_sites#update"
  # console.import — wp-admin/import.php. Place with the other Tools routes (BEFORE the
  # `get "/*path"` page glob, which would otherwise swallow `console/...` as a page slug),
  # and ABOVE the export routes so the file reads in menu.php's own submenu order
  # (Available Tools 5, Import 10, Export 15 — menu.php:391-393).
  get  "/console/tools/import",     to: "console/imports#show",    as: :console_import
  post "/console/tools/import",     to: "console/imports#prepare"
  post "/console/tools/import/run", to: "console/imports#create",  as: :console_import_run

  # ── Admin parity pass (2026-08-24): actions the audited screens were missing ────────
  # Each has a matching AD-04 declaration in config/initializers/authorization_declarations.rb.
  get   "/console/media/new",                        to: "console/media#new",           as: :new_console_medium
  post  "/console/media/new",                        to: "console/media#create",        as: :create_console_medium
  match "/console/terms/:taxonomy",                  to: "console/terms_list#create",   via: %i[post]
  post  "/console/terms/:taxonomy/:id/inline",       to: "console/terms_list#inline_save", as: :console_term_inline
  get   "/console/comments/:id/reply",               to: "console/comments#reply",      as: :reply_console_comment
  post  "/console/comments/:id/reply",               to: "console/comments#create_reply"
  post  "/console/quick-draft",                      to: "console/dashboard#quick_draft", as: :console_quick_draft
  post  "/console/posts/:id/revisions/restore",      to: "console/revisions#restore",   as: :restore_console_post_revision
  post  "/console/themes/:slug/enable-auto-update",  to: "console/themes#enable_auto_update"
  post  "/console/themes/:slug/disable-auto-update", to: "console/themes#disable_auto_update"
  post  "/console/tools/export-personal-data/bulk",  to: "console/data_requests#bulk",  as: :console_export_personal_data_bulk
  post  "/console/tools/erase-personal-data/bulk",   to: "console/data_requests#bulk",       as: :console_erase_personal_data_bulk

  get  "/console/:page", to: "console/info#show", as: :console_info,
       constraints: { page: /about|credits|freedoms|contribute|privacy/ }

  # Syndication -- Wave 1. Terminal modules, zero dependents (F-SIM-06).
  get "/robots.txt", to: "syndication/robots#show", as: :robots, defaults: { format: "text" }
  get "/wp-sitemap.xml", to: "syndication/sitemaps#index", as: :sitemap_index, defaults: { format: "xml" }
  get "/wp-sitemap-posts-:type-:page.xml", to: "syndication/sitemaps#posts", as: :sitemap_posts, defaults: { format: "xml" }
  get "/wp-sitemap-users-:page.xml", to: "syndication/sitemaps#users", as: :sitemap_users, defaults: { format: "xml" }
  get "/feed(/:variant)", to: "syndication/feeds#show", as: :feed, defaults: { format: "xml" }
  get "/comments/feed", to: "syndication/feeds#comments", as: :comments_feed, defaults: { format: "xml" }

  # Front-end read path -- Wave 2.
  get "/author/:login", to: "web/archives#author", as: :author_archive
  get "/category/*path", to: "web/archives#category", as: :category_archive
  get "/tag/:slug", to: "web/archives#tag", as: :tag_archive

  # The permalink structure is /%year%/%monthnum%/%postname%/ -- Routing::PermalinkStructure.
  # Date archives are the same prefix with the trailing segments absent.
  get "/:year/:monthnum/:slug", to: "web/singular#show", as: :permalink,
      constraints: { year: /\d{4}/, monthnum: /\d{2}/ }
  # The `/embed/` endpoint on a post permalink (EP_PERMALINK, wp-includes/embed.php via
  # rewrite.php:24) — declared BEFORE the attachment route because WordPress's rewrite
  # rules give the literal `embed` segment precedence over an attachment slug.
  get "/:year/:monthnum/:slug/embed", to: "web/embeds#show", as: :post_embed,
      constraints: { year: /\d{4}/, monthnum: /\d{2}/ }, format: false
  # An attachment's permalink nests under its parent post's (get_attachment_link,
  # link-template.php). It never renders: web/attachments#show 301-redirects to the file
  # (canonical.php:553, `wp_attachment_pages_enabled` = '0').
  get "/:year/:monthnum/:slug/:attachment_slug", to: "web/attachments#show", as: :attachment_permalink,
      constraints: { year: /\d{4}/, monthnum: /\d{2}/ }, format: false
  # `<attachment permalink>/embed/` — class-wp-rewrite.php:1145 generates the `embed=true`
  # rule for attachments too (`$sub1embed`, :1213). It never reaches the embed template:
  # redirect_canonical() runs on `template_redirect` (default-filters.php), BEFORE
  # template-loader.php, and canonical.php:553 fires on is_attachment() regardless of the
  # endpoint. Verified against the oracle: 301 to the file, same as without `/embed/`.
  get "/:year/:monthnum/:slug/:attachment_slug/embed", to: "web/attachments#show", as: :attachment_embed,
      constraints: { year: /\d{4}/, monthnum: /\d{2}/ }, format: false
  get "/:year/:monthnum", to: "web/archives#month", as: :month_archive,
      constraints: { year: /\d{4}/, monthnum: /\d{2}/ }
  get "/:year", to: "web/archives#year", as: :year_archive, constraints: { year: /\d{4}/ }

  # ── Wave 3: the content WRITE path ─────────────────────────────────────────────
  # `wp-comments-post.php` — the comment form's `action` is `site_url('/wp-comments-post.php')`
  # (comment-template.php:2516), which every golden records, so the route is the literal
  # legacy path. :8-18 of the script answers anything but POST with 405 `Allow: POST`.
  post "/wp-comments-post.php", to: "web/comments#create", as: :comments_post, format: false
  get "/wp-comments-post.php", to: "web/comments#method_not_allowed", format: false

  # ── Wave 3: the authentication surface (target_screens.md § Part 3, 8 screens) ──
  # wp-login.php dispatched every screen from ONE URL on `$action`; DEV-006 gives each
  # its own route under /login, /register and /session. Declared BEFORE the page glob,
  # which would otherwise resolve `login` as a page slug. DEV-010: `retrievepassword`
  # is an alias of `lostpassword` and has no route of its own.
  get    "/login",                to: "auth/sessions#new",          as: :login
  post   "/login",                to: "auth/sessions#create"
  delete "/session",              to: "auth/sessions#destroy",      as: :session
  get    "/login/lost-password",  to: "auth/lost_passwords#new",    as: :lost_password
  post   "/login/lost-password",  to: "auth/lost_passwords#create"
  get    "/login/reset-password", to: "auth/reset_passwords#show",  as: :reset_password
  post   "/login/reset-password", to: "auth/reset_passwords#create"
  get    "/login/check-email",    to: "auth/check_emails#show",     as: :check_email
  get    "/login/confirm",        to: "auth/confirmations#show",    as: :confirm_action
  get    "/register",             to: "auth/registrations#new",     as: :register
  post   "/register",             to: "auth/registrations#create"

  # ── Wave 5: the multisite signup/activation surface (target_screens.md Part 6, 5 screens)
  # wp-signup.php + wp-activate.php, one screen per state. MODERNIZED mode; these are NOT
  # among the 25 byte-parity screens. Declared BEFORE the /*path page glob, which would
  # otherwise swallow `signup`/`activate` as page slugs. Every route carries an AD-04
  # declaration (config/initializers/authorization_declarations.rb) — all `public`, because
  # a browser reaches them before it has any identity, exactly like the auth surface. With
  # multisite disabled (the single-site default) they answer the legacy "disabled" state.
  get  "/signup",         to: "tenancy/signups#user_signup", as: :signup
  post "/signup",         to: "tenancy/signups#create"
  get  "/signup/site",    to: "tenancy/signups#blog_signup", as: :signup_site
  get  "/signup/confirm", to: "tenancy/signups#confirm",     as: :signup_confirm
  get  "/activate",       to: "tenancy/activations#form",    as: :activate
  post "/activate",       to: "tenancy/activations#create"
  get  "/activate/done",  to: "tenancy/activations#done",    as: :activate_done

  # ── Wave 4: the REST API surface (public_api, BR-MIGRATE-234..244) ──────────────
  # `/wp-json/*` — the routes the corpus already references (front-end goldens link to
  # `/wp-json/`, `/wp-json/oembed/1.0/embed` and `/wp-json/wp/v2/{posts,pages,categories,
  # tags,users}/<id>`). Declared BEFORE the page glob, which would otherwise swallow
  # `wp-json` as a page slug. This pass is the READ surface + the permission model; write
  # routes (POST/PUT/DELETE) are deferred (see the controller headers and the report).
  scope "/wp-json", defaults: { format: :json } do
    get "/",             to: "public_api/root#index",      as: :rest_index
    get "/wp/v2",        to: "public_api/root#namespace",  as: :rest_namespace_wp_v2

    get "/wp/v2/posts",      to: "public_api/posts#index",  as: :rest_posts
    get "/wp/v2/posts/:id",  to: "public_api/posts#show",   constraints: { id: /\d+/ }
    get "/wp/v2/pages",      to: "public_api/pages#index",  as: :rest_pages
    get "/wp/v2/pages/:id",  to: "public_api/pages#show",   constraints: { id: /\d+/ }
    get "/wp/v2/media",      to: "public_api/media#index",  as: :rest_media
    get "/wp/v2/media/:id",  to: "public_api/media#show",   constraints: { id: /\d+/ }

    get "/wp/v2/categories",     to: "public_api/categories#index", as: :rest_categories
    get "/wp/v2/categories/:id", to: "public_api/categories#show",  constraints: { id: /\d+/ }
    get "/wp/v2/tags",           to: "public_api/tags#index",       as: :rest_tags
    get "/wp/v2/tags/:id",       to: "public_api/tags#show",        constraints: { id: /\d+/ }

    get "/wp/v2/users",     to: "public_api/users#index",  as: :rest_users
    get "/wp/v2/users/me",  to: "public_api/users#me"
    get "/wp/v2/users/:id", to: "public_api/users#show",   constraints: { id: /\d+/ }

    get "/wp/v2/comments",     to: "public_api/comments#index", as: :rest_comments
    get "/wp/v2/comments/:id", to: "public_api/comments#show",  constraints: { id: /\d+/ }

    get "/wp/v2/types",        to: "public_api/types#index", as: :rest_types
    get "/wp/v2/types/:type",  to: "public_api/types#show"
    get "/wp/v2/taxonomies",             to: "public_api/taxonomies#index", as: :rest_taxonomies
    get "/wp/v2/taxonomies/:taxonomy",   to: "public_api/taxonomies#show"
    get "/wp/v2/statuses",          to: "public_api/statuses#index", as: :rest_statuses
    get "/wp/v2/statuses/:status",  to: "public_api/statuses#show"

    get "/oembed/1.0/embed", to: "public_api/oembed#embed", as: :rest_oembed

    # BR-MIGRATE-356 (BR-SH-05): the site-health async tests, exposed over REST. Only the
    # loopback test has an analogue here (BR-MIGRATE-355 → the job queue); the rest of the
    # legacy's wp-site-health/v1 battery polls wordpress.org (VOID) or probes shared-hosting
    # transports (absorbed). PublicApi::SiteHealthController explains why one route, not a
    # namespace of stubs.
    get "/wp-site-health/v1/tests/loopback-requests",
        to: "public_api/site_health#loopback_requests", as: :rest_site_health_loopback

    # rest_no_route (class-wp-rest-server.php:1096): anything under /wp-json that no route
    # matched is a REST 404 with the WP_Error envelope, NOT the HTML 404 the page glob
    # below would render. via :all so a POST to an unknown route answers the same.
    # ── The REST WRITE surface (Track 1). Inside the existing `scope "/wp-json"` block,
    # ABOVE the `match "/*path" ... via: :all` rest_no_route catch-all. Placing them next
    # to the existing GET /wp/v2/posts lines keeps the file readable; nothing here shadows
    # anything, because every path is either a new verb on an existing path or a new
    # `/autosaves` segment.
    post   "/wp/v2/posts",      to: "public_api/posts#create"
    match  "/wp/v2/posts/:id",  to: "public_api/posts#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/posts/:id",  to: "public_api/posts#destroy", constraints: { id: /\d+/ }
    get    "/wp/v2/posts/:id/autosaves", to: "public_api/autosaves#index",  constraints: { id: /\d+/ }, defaults: { parent_type: "posts" }, as: :rest_post_autosaves
    post   "/wp/v2/posts/:id/autosaves", to: "public_api/autosaves#create", constraints: { id: /\d+/ }, defaults: { parent_type: "posts" }

    post   "/wp/v2/pages",      to: "public_api/pages#create"
    match  "/wp/v2/pages/:id",  to: "public_api/pages#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/pages/:id",  to: "public_api/pages#destroy", constraints: { id: /\d+/ }
    get    "/wp/v2/pages/:id/autosaves", to: "public_api/autosaves#index",  constraints: { id: /\d+/ }, defaults: { parent_type: "pages" }, as: :rest_page_autosaves
    post   "/wp/v2/pages/:id/autosaves", to: "public_api/autosaves#create", constraints: { id: /\d+/ }, defaults: { parent_type: "pages" }
    # ── Track 3: the media / taxonomy / comment WRITE surface ──────────────────────
    # `match … via: %i[post put patch]` because the legacy registers EDITABLE for an item
    # route, which is all three verbs (class-wp-rest-server.php:1035).
    post   "/wp/v2/media",     to: "public_api/media#create"
    match  "/wp/v2/media/:id", to: "public_api/media#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/media/:id", to: "public_api/media#destroy", constraints: { id: /\d+/ }

    post   "/wp/v2/categories",     to: "public_api/categories#create"
    match  "/wp/v2/categories/:id", to: "public_api/categories#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/categories/:id", to: "public_api/categories#destroy", constraints: { id: /\d+/ }

    post   "/wp/v2/tags",     to: "public_api/tags#create"
    match  "/wp/v2/tags/:id", to: "public_api/tags#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/tags/:id", to: "public_api/tags#destroy", constraints: { id: /\d+/ }

    post   "/wp/v2/comments",     to: "public_api/comments#create"
    match  "/wp/v2/comments/:id", to: "public_api/comments#update",  via: %i[post put patch], constraints: { id: /\d+/ }
    delete "/wp/v2/comments/:id", to: "public_api/comments#destroy", constraints: { id: /\d+/ }

    # ↑ ALL of the above go inside the existing `scope "/wp-json"` block and BEFORE the
    #   `match "/*path", to: "public_api/root#no_route", via: :all` catch-all.
    # ── TRACK 2: SITE DATA (settings, themes, global styles, templates, patterns, blocks)
    # The block editor's boot preload. Declared BEFORE the `match "/*path"` rest_no_route
    # catch-all at the end of this scope, and each `lookup`/`themes` literal BEFORE the
    # glob or `:id` route that would otherwise swallow it.
    get   "/wp/v2/settings", to: "public_api/settings#show", as: :rest_settings
    match "/wp/v2/settings", to: "public_api/settings#update", via: %i[post put patch]

    get "/wp/v2/themes", to: "public_api/themes#index", as: :rest_themes

    # `themes/…` before `:id`, and `/variations` before the bare stylesheet, so neither is
    # read as the other. `format: false` because a stylesheet slug may contain a dot.
    get   "/wp/v2/global-styles/themes/:stylesheet/variations", to: "public_api/global_styles#variations",
          as: :rest_global_styles_theme_variations, format: false
    get   "/wp/v2/global-styles/themes/:stylesheet", to: "public_api/global_styles#theme",
          as: :rest_global_styles_theme, format: false
    get   "/wp/v2/global-styles/:id", to: "public_api/global_styles#show", as: :rest_global_styles,
          constraints: { id: /\d+/ }
    match "/wp/v2/global-styles/:id", to: "public_api/global_styles#update", via: %i[post put patch],
          constraints: { id: /\d+/ }

    # A template id is `<theme>//<slug>` — two slashes, so `show` takes a glob. `lookup`
    # and the collection are literals declared ahead of it.
    get "/wp/v2/templates/lookup", to: "public_api/templates#lookup", as: :rest_templates_lookup
    get "/wp/v2/templates",        to: "public_api/templates#index",  as: :rest_templates
    get "/wp/v2/templates/*id",    to: "public_api/templates#show",   format: false
    get "/wp/v2/template-parts",     to: "public_api/template_parts#index", as: :rest_template_parts
    get "/wp/v2/template-parts/*id", to: "public_api/template_parts#show",  format: false

    get "/wp/v2/block-patterns/categories", to: "public_api/block_pattern_categories#index",
        as: :rest_block_pattern_categories

    get "/wp/v2/blocks",     to: "public_api/blocks#index", as: :rest_blocks
    get "/wp/v2/blocks/:id", to: "public_api/blocks#show",  constraints: { id: /\d+/ }

    # OPTIONS on any REST path — the route descriptor + `Allow` header core-data reads to
    # decide which controls the editor may offer. Declared before the catch-all so it is not
    # swallowed by it, and matched as a glob because every REST path answers OPTIONS.
    match "/*rest_path", to: "public_api/options#show", via: :options, format: false

    match "/*path", to: "public_api/root#no_route", via: :all, format: false
  end

  # `<page path>/embed/` — the `embed` endpoint is registered with EP_PAGES as well as
  # EP_PERMALINK (class-wp-rewrite.php:892 `$embedregex`, :1099 for the page permastruct),
  # so every page URL has an embed variant. Declared BEFORE the page glob, which would
  # otherwise swallow `embed` as a (non-existent) child-page slug.
  get "/*path/embed", to: "web/embeds#page", as: :page_embed, format: false
  # Hierarchical pages: /parent-page/child-page/ -- BR-MIGRATE-033's (type, parent) scope.
  get "/*path", to: "web/pages#show", as: :page_permalink, format: false


end
