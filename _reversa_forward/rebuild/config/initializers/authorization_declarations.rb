# frozen_string_literal: true

# AD-04, made operational.
#
#   "A static check fails the build when a route, policy or endpoint is registered without
#    an explicit authorization declaration -- INCLUDING A DECLARATION OF `public`. The
#    check does not change the runtime default -- it removes the way that default gets
#    reached, which is by someone forgetting."
#
# Every Wave 1/2 action is `public`, because these are the public read surfaces and
# BR-REST-05 would have made them public anyway. The difference is that somebody chose it,
# and a new action that nobody chose for fails the boot instead of silently serving.
Rails.application.config.to_prepare do
  Access::Declarations.reset!

  %w[
    web/archives#index web/archives#year web/archives#month web/archives#category
    web/archives#tag web/archives#author
    web/singular#show web/pages#show web/embeds#show web/embeds#page web/attachments#show
    syndication/feeds#show syndication/feeds#comments
    syndication/sitemaps#index syndication/sitemaps#posts syndication/sitemaps#users
    syndication/robots#show
  ].each { |action| Access::Declarations.declare("GET #{action}", mode: :public, source: __FILE__) }

  # Wave 3 -- Library write path. The upload needs an actor (wp_ajax_upload_attachment()
  # runs behind a login); the capability checks the legacy performs inside the action
  # (`upload_files`, `edit_post`) are performed inside the action, through Access
  # policies, answering with the legacy's JSON refusals. The file URL space is public:
  # wp-content/uploads is served by the web server in the legacy, with no gate at all.
  Access::Declarations.declare("POST web/uploads#create", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("GET web/uploads#show", mode: :public, source: __FILE__)

  # Wave 3 — the comment submission endpoint. PUBLIC, deliberately: wp-comments-post.php
  # admits anonymous submitters (the `comment_registration` gate is a rule inside
  # Discussion::Submission, answered with the legacy's 403, not an authorization
  # declaration), and the 405 answer to a GET is public by the same token.
  Access::Declarations.declare("POST web/comments#create", mode: :public, source: __FILE__)
  Access::Declarations.declare("GET web/comments#method_not_allowed", mode: :public, source: __FILE__)

  # Wave 3 — the authentication surface (auth.*, target_screens.md § Part 3). Every one
  # PUBLIC, deliberately: these are the screens a browser reaches BEFORE it has an
  # identity. `DELETE auth/sessions#destroy` is public too -- wp-login.php:804 runs
  # `logout` for a logged-out browser as well and lands it on the same "You are now
  # logged out." screen; what guards it is the request-forgery token (the legacy's
  # check_admin_referer('log-out'), Rails' authenticity token here, DEV-006). The
  # reset and confirm screens are guarded by their keys (Identity::PasswordReset,
  # Identity::DataRequest), which are credentials, not capabilities.
  %w[
    GET\ auth/sessions#new POST\ auth/sessions#create DELETE\ auth/sessions#destroy
    GET\ auth/lost_passwords#new POST\ auth/lost_passwords#create
    GET\ auth/reset_passwords#show POST\ auth/reset_passwords#create
    GET\ auth/check_emails#show GET\ auth/confirmations#show
    GET\ auth/registrations#new POST\ auth/registrations#create
  ].each { |identifier| Access::Declarations.declare(identifier, mode: :public, source: __FILE__) }

  # ── Policy mode, for the write surfaces that follow (console.*, Wave 4) ──────────
  #
  # A write route declares the POLICY CLASS and the ACTION the policy is asked; the
  # controller supplies the actor (and, for object policies, the record). Two shapes:
  #
  #   # A site-wide primitive (`current_user_can( 'manage_options' )`) — no record.
  #   # Access::SitePolicy is map_meta_cap()'s record-less arms plus its `default:` arm:
  #   Access::Declarations.declare("GET console/settings#show", mode: :policy,
  #                                policy: Access::SitePolicy, action: :manage_options)
  #
  #   # An object arm (`current_user_can( 'edit_post', $id )`) — the declaration cannot
  #   # know which row the request names, so it gates the surface on identity and the
  #   # controller evaluates `Access::PostPolicy.for(actor, post).permit?(:edit)` (or
  #   # CommentPolicy / TermPolicy / AssetPolicy / UserPolicy) on the loaded record:
  #   Access::Declarations.declare("POST console/posts#update", mode: :authenticated)
  #
  # ⚠️ Owner override 1 applies to BOTH shapes (BR-CAP-05): a policy whose arm emits no
  # capabilities ALLOWS. Access::UserPolicy#edit on oneself does exactly that, by the
  # legacy's own rule (BR-MIGRATE-103). Declare deliberately; read the policy you name.

  # ── Wave 4: the editor SHELL (console.post-new / console.post / console.site-editor) ──
  #
  # The post editor is the OBJECT-ARM shape (`current_user_can( 'edit_post', $id )`): the
  # declaration cannot know which row the request names, so it gates the surface on
  # identity (:authenticated) and Console::PostsController evaluates
  # `Access::PostPolicy.for(actor, post).permit?(:edit)` on the loaded record — including
  # `new`, where the arm is asked on the freshly built auto_draft (create_posts → edit_posts).
  # `match via: [:patch, :put]` registers BOTH verbs, so both are declared.
  Access::Declarations.declare("GET console/posts#new", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("GET console/posts#edit", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("GET console/posts#blocks", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("PATCH console/posts#update", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("PUT console/posts#update", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/posts#autosave", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/posts#lock", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("DELETE console/posts#unlock", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/posts#steal", mode: :authenticated, source: __FILE__)

  # The site editor is the SITE-PRIMITIVE shape (`current_user_can( 'edit_theme_options' )`,
  # wp-admin/site-editor.php) — a record-less capability, so it declares the policy and the
  # action directly. Access::SitePolicy maps edit_theme_options to itself (the :864 default
  # arm), which only the editor and administrator roles hold.
  Access::Declarations.declare("GET console/site_editor#show", mode: :policy,
                               policy: Access::SitePolicy, action: :edit_theme_options, source: __FILE__)
  # The Site Editor island's API actions share the edit_theme_options gate (site-editor.php).
  ["GET console/site_editor#templates_index", "GET console/site_editor#template_blocks",
   "PATCH console/site_editor#update_template", "PUT console/site_editor#update_template",
   "GET console/site_editor#styles", "PATCH console/site_editor#update_styles",
   "PUT console/site_editor#update_styles"].each do |route|
    Access::Declarations.declare(route, mode: :policy, policy: Access::SitePolicy,
                                 action: :edit_theme_options, source: __FILE__)
  end

  # ── Wave 4: appearance — console.themes / console.theme-install / console.nav-menus ──
  # themes.php:12 gates on `switch_themes` OR `edit_theme_options`; theme-install.php:15 on
  # `install_themes`; the delete arm on `delete_themes` (themes.php:60); nav-menus.php:23 on
  # `edit_theme_options`. All four are ADMINISTRATOR-only in the RoleCatalogue, so declaring
  # the single primary of the OR yields the legacy outcome for every seeded role. These are
  # real capability names through Access::SitePolicy (:864 default arm), so owner override 1
  # (BR-CAP-05) does NOT soften them — an actor without the cap is refused.
  Access::Declarations.declare("GET console/themes#index", mode: :policy,
                               policy: Access::SitePolicy, action: :switch_themes, source: __FILE__)
  Access::Declarations.declare("POST console/themes#activate", mode: :policy,
                               policy: Access::SitePolicy, action: :switch_themes, source: __FILE__)
  Access::Declarations.declare("DELETE console/themes#destroy", mode: :policy,
                               policy: Access::SitePolicy, action: :delete_themes, source: __FILE__)
  Access::Declarations.declare("GET console/theme_install#new", mode: :policy,
                               policy: Access::SitePolicy, action: :install_themes, source: __FILE__)
  Access::Declarations.declare("POST console/theme_install#create", mode: :policy,
                               policy: Access::SitePolicy, action: :install_themes, source: __FILE__)

  %w[index show create update destroy add_item remove_item move_item].each do |action|
    verb = case action
           when "index", "show" then "GET"
           when "create", "add_item" then "POST"
           when "update", "move_item" then "PATCH"
           when "destroy", "remove_item" then "DELETE"
           end
    Access::Declarations.declare("#{verb} console/menus##{action}", mode: :policy,
                                 policy: Access::SitePolicy, action: :edit_theme_options, source: __FILE__)
  end
  # PUT shares the update action (routes.rb `via: %i[patch put]`).
  Access::Declarations.declare("PUT console/menus#update", mode: :policy,
                               policy: Access::SitePolicy, action: :edit_theme_options, source: __FILE__)
  Access::Declarations.declare("PUT console/menus#move_item", mode: :policy,
                               policy: Access::SitePolicy, action: :edit_theme_options, source: __FILE__)

  # ── Wave 4: the P-LIST console list screens (console.edit/upload/edit-comments/users/
  # edit-tags, target_screens.md § Part 5). The INDEX is the SITE-PRIMITIVE shape: the
  # legacy gates each list on the menu capability its screen opens with (edit.php →
  # edit_posts / edit_pages, upload.php → upload_files, edit-comments.php → edit_posts,
  # users.php → list_users, edit-tags.php → manage_categories), a record-less
  # `current_user_can`, so the route declares Access::SitePolicy + that primitive. A
  # logged-in actor lacking it gets a 403; a logged-out one is redirected to /login by the
  # auth gate first. Those are all real capability names, so Owner override 1's permissive
  # arm (BR-CAP-05) does not loosen them — SitePolicy's `default:` arm requires the cap
  # itself.
  #
  # The BULK target is the OBJECT-ARM shape (`current_user_can( $meta_cap, $id )` per
  # selected row): the declaration cannot know which rows the request names, so it gates on
  # identity (:authenticated) and the controller evaluates each record's Access policy
  # (PostPolicy/CommentPolicy/UserPolicy/TermPolicy/AssetPolicy) before acting, skipping any
  # row the actor may not touch. DEV-004 inserts a confirmation step before destructive runs.
  {
    "GET console/posts_list#index"    => :edit_posts,
    "GET console/pages_list#index"    => :edit_pages,
    "GET console/media_list#index"    => :upload_files,
    "GET console/comments_list#index" => :edit_posts,
    "GET console/users_list#index"    => :list_users,
    "GET console/terms_list#index"    => :manage_categories
  }.each do |identifier, capability|
    Access::Declarations.declare(identifier, mode: :policy, policy: Access::SitePolicy,
                                 action: capability, source: __FILE__)
  end
  %w[
    POST\ console/posts_list#bulk POST\ console/pages_list#bulk POST\ console/media_list#bulk
    POST\ console/comments_list#bulk POST\ console/users_list#bulk POST\ console/terms_list#bulk
  ].each { |identifier| Access::Declarations.declare(identifier, mode: :authenticated, source: __FILE__) }

  # ── Wave 4: the P-EDIT single-record edit screens (console.comment/term/media/user-edit/
  # user-new/profile/revision). ALL the OBJECT-ARM shape: the declaration cannot know which
  # row the URL names, so it gates the surface on identity (:authenticated) and each
  # controller evaluates the record's Access policy — CommentPolicy(:edit), TermPolicy(:edit),
  # AssetPolicy(:edit), UserPolicy(:edit|:create), PostPolicy(:edit for a revision's parent) —
  # answering a refusal with the legacy's verbatim wp_die message and a 403. The single auth
  # gate (Console::BaseController#auth_redirect) redirects a LOGGED-OUT request to /login
  # before any of this runs. `match via: %i[patch put]` registers both verbs, so both are
  # declared. Owner override 1 (BR-CAP-05) is in force in the policies — read them.
  %w[
    GET\ console/comments#edit PATCH\ console/comments#update PUT\ console/comments#update
    GET\ console/terms#edit PATCH\ console/terms#update PUT\ console/terms#update
    GET\ console/media#edit PATCH\ console/media#update PUT\ console/media#update
    GET\ console/users#new POST\ console/users#create
    GET\ console/users#edit PATCH\ console/users#update PUT\ console/users#update
    GET\ console/profiles#show PATCH\ console/profiles#update PUT\ console/profiles#update
    GET\ console/revisions#index
  ].each { |identifier| Access::Declarations.declare(identifier, mode: :authenticated, source: __FILE__) }

  # ── Wave 4: the bespoke console — settings, dashboard, tools, site health, GDPR,
  # informational pages (target_screens.md § Settings screens / § Dashboard, tools).
  #
  # These are declared `:authenticated`, not `:policy`, on purpose. Two reasons:
  #   1. The site capability each options screen opens with (`manage_options`,
  #      `manage_privacy_options`, `export`, `view_site_health_checks`->`install_plugins`)
  #      is refused with a LITERAL wp_die() string the modernized contract must render
  #      verbatim (options-general.php:15 etc.). A `:policy` denial is a bare 403 with no
  #      message, so the capability is enforced INSIDE the controller
  #      (Console::Chrome#require_capability!, via Access::SitePolicy) where the right
  #      string is reachable — the same shape the P-EDIT object screens use.
  #   2. Dashboard and the informational pages require only a logged-in reader (the
  #      legacy's `read`, held by every role); `:authenticated` is exactly that gate, and
  #      auth_redirect (Console::BaseController) has already bounced the logged-out.
  # The capability is still enforced; it is simply enforced where its message lives.
  %w[
    GET\ console/dashboard#index
    GET\ console/settings#show POST\ console/settings#update
    GET\ console/tools#index
    GET\ console/tools#export POST\ console/tools#export_download
    GET\ console/site_health#show GET\ console/site_health#info
    GET\ console/privacy_guide#show
    GET\ console/data_requests#export GET\ console/data_requests#erase
    POST\ console/data_requests#create
    GET\ console/info#show
  ].each { |identifier| Access::Declarations.declare(identifier, mode: :authenticated, source: __FILE__) }

  # ── Wave 4: the REST API surface (public_api, BR-MIGRATE-234..244) ──────────────
  #
  # Every read route is `mode: :public`, DELIBERATELY. This is BR-REST-05 made a choice
  # instead of an accident: the WP route has a permission callback that, for `view`
  # context on published content, returns true — i.e. public. AD-04 will not let that be
  # reached by omission, so it is declared. The per-record read checks a `view` request
  # can still fail (a draft, an `edit`-context field) run INSIDE the controller through
  # the endpoint's own permission callback (PublicApi::BaseController) and answer with the
  # legacy's WP_Error envelope + 401/403 (BR-REST-04/06) — exactly the async-upload.php
  # pattern, one layer down from the route gate.
  #
  # `users#me` is NOT an exception at the route gate: it is declared `:public` like every
  # other read route, DELIBERATELY (BR-REST-05 reachable only on purpose). Its
  # `require_login` permission callback (PublicApi::UsersController) is what denies an
  # anonymous caller — and it must, because the denial has to be the legacy's
  # `rest_not_logged_in` WP_Error envelope with status 401 (BR-REST-06). The `:authenticated`
  # route gate would instead short-circuit with an empty-bodied 403 BEFORE the callback
  # runs, which is neither the right status nor the right body — so the gate is `:public`
  # and the controller owns the 401/403, exactly as class-wp-rest-server.php:1252 does.
  %w[
    public_api/root#index public_api/root#namespace public_api/root#no_route
    public_api/posts#index public_api/posts#show
    public_api/pages#index public_api/pages#show
    public_api/media#index public_api/media#show
    public_api/categories#index public_api/categories#show
    public_api/tags#index public_api/tags#show
    public_api/users#index public_api/users#show
    public_api/comments#index public_api/comments#show
    public_api/types#index public_api/types#show
    public_api/taxonomies#index public_api/taxonomies#show
    public_api/statuses#index public_api/statuses#show
    public_api/oembed#embed
    public_api/site_health#loopback_requests
  ].each do |action|
    %w[GET HEAD].each { |verb| Access::Declarations.declare("#{verb} #{action}", mode: :public, source: __FILE__) }
  end
  # rest_no_route answers every verb (routes.rb `via: :all`), so declare the non-GET ones.
  %w[POST PUT PATCH DELETE OPTIONS].each do |verb|
    Access::Declarations.declare("#{verb} public_api/root#no_route", mode: :public, source: __FILE__)
  end
  Access::Declarations.declare("GET public_api/users#me", mode: :public, source: __FILE__)
  Access::Declarations.declare("HEAD public_api/users#me", mode: :public, source: __FILE__)

  # ── Wave 5: the multisite signup/activation surface (tenancy.*, target_screens.md Part 6) ──
  # Every one PUBLIC, deliberately: like the auth screens, a browser reaches these BEFORE it
  # has an identity — wp-signup.php / wp-activate.php gate on the SIGNUP settings and the
  # activation KEY (a credential, Tenancy::Signup#activation_key), not on a capability. The
  # `require_multisite` before_action answers the single-site "disabled" state; that is a
  # product rule inside the surface, not an authorization decision.
  %w[
    GET\ tenancy/signups#user_signup POST\ tenancy/signups#create
    GET\ tenancy/signups#blog_signup GET\ tenancy/signups#confirm
    GET\ tenancy/activations#form POST\ tenancy/activations#create
    GET\ tenancy/activations#done
  ].each { |identifier| Access::Declarations.declare(identifier, mode: :public, source: __FILE__) }
end

# The build check. Walks the real routing table and refuses to boot on an omission.
Rails.application.config.after_initialize do
  # ── Admin parity pass (2026-08-24): declarations for the newly built actions ────────
  # Every route added in the same pass; AD-04 fails boot if any is left undeclared.
  Access::Declarations.declare("GET console/media#new", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/media#create", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/terms_list#create", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/terms_list#inline_save", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("GET console/comments#reply", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/comments#create_reply", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/dashboard#quick_draft", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/revisions#restore", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/data_requests#bulk", mode: :authenticated, source: __FILE__)
  Access::Declarations.declare("POST console/themes#enable_auto_update", mode: :policy,
                               policy: Access::SitePolicy, action: :update_themes, source: __FILE__)
  Access::Declarations.declare("POST console/themes#disable_auto_update", mode: :policy,
                               policy: Access::SitePolicy, action: :update_themes, source: __FILE__)

  next if Rails.env.test?


  identifiers = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    action = route.defaults[:action]
    next if controller.nil? || action.nil?
    next if controller.start_with?("rails/", "active_storage/", "action_mailbox/")

    verb = route.verb.presence || "GET"
    "#{verb} #{controller}##{action}"
  end.uniq

  undeclared = Access::Declarations.undeclared(identifiers)
  next if undeclared.empty?

  raise Access::Declarations::Undeclared, <<~MSG
    #{undeclared.length} route(s) have no authorization declaration (AD-04):

    #{undeclared.map { |i| "  · #{i}" }.join("\n")}

    Declare each in config/initializers/authorization_declarations.rb. `mode: :public` is
    a valid answer -- the point is that it is an answer. Under BR-REST-05 an undeclared
    route is public at runtime, and AD-01 means there is no filter to correct it later.
  MSG


end
