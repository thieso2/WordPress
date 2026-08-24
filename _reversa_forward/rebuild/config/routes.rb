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
  post   "/console/posts/:id/autosave",  to: "console/posts#autosave",   as: :autosave_console_post
  post   "/console/posts/:id/lock",      to: "console/posts#lock",       as: :lock_console_post
  delete "/console/posts/:id/lock",      to: "console/posts#unlock",     as: :unlock_console_post
  post   "/console/posts/:id/steal",     to: "console/posts#steal",      as: :steal_console_post
  get    "/console/site-editor",         to: "console/site_editor#show", as: :console_site_editor

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
