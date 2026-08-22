---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: target_screens
producedBy: screen-translator
mode: hybrid
sourcePlatform: php-server-rendered
targetPlatform: rails-hotwire
adapter: adapters/php__spa
screenCount: 144
hash: "sha256:480843b87ed97086fc6a1e0e4464325419e42cd014958f0efad6624c9955fcd6"
---

# Target Screens

> An executable specification of each screen of the new system, derived from the legacy one
> according to the mode approved in `screen_modernization_decision.md`. **Textual content is
> preserved literally — no copy editing was approved.**
> Primary reading for the coder. Every section is a contract.

## Summary

- **Mode applied**: **hybrid** — 18 `web.*` screens literal, 126 console/auth/tenancy screens
  modernized (123 in scope; 3 excluded).
- **Screens generated**: **144**
- **Adapter**: `php__spa`, spec kind `route-component` (`spec.route` + `spec.layout` map onto Rails
  routes and layouts directly).
- **Tokens consumed**: `_reversa_sdd/design-system.md` §2 (front end, `theme.json`) —
  ⚠️ the expected path `_reversa_sdd/design-system/tokens.md` does not exist; the artifact lives at
  the root. Derived tokens are appended to `_reversa_sdd/design-system/tokens-derived.md`.
- **Golden files**: **0 present**, 18 declared in `_reversa_sdd/screens/golden/manifest.yaml`.
  ⚠️ All 18 literal screens are **blocked pending capture** (FR-13).
- **Deviations recorded**: **12** in `screen_deviation_log.md` — **0 pending**, 10 approved,
  1 rejected (DEV-007, superseded by DEV-012). Nothing blocks the Inspector.

### How this document is organized, and why it is not 144 sections

A one-section-per-screen document would be **144 sections of which roughly 105 are the same two
sections repeated**. The legacy admin is a front controller per URL, and the great majority of those
URLs are one of exactly two shapes: a filtered, paginated, bulk-actionable **list**, or a **form**
over one record. `wp-admin/edit.php`, `upload.php`, `users.php`, `edit-comments.php`,
`plugins.php`, `themes.php` and their network equivalents differ in their columns and their row
actions, not in their structure.

So this document defines **two patterns** (`P-LIST`, `P-EDIT`) as full contracts, then instantiates
the routine screens against them in tables that specify exactly what differs. Screens that are *not*
an instance of either pattern — the editor shells, the auth flows, the settings pages, the literal
front-end templates — get their own full section.

This is a specification decision, not a shortcut: a coder implementing `P-LIST` once and
instantiating it 40 times produces a more consistent console than one reading 40 near-identical
specs. **Every screen is still individually accounted for**, in a section or in an instantiation
table row.

| Part | Content | Screens |
|---|---|---|
| 1 | The two reusable patterns | *(contracts, not screens)* |
| 2 | Literal front-end templates — full specs | 18 |
| 3 | Auth flows — full specs | 8 |
| 4 | Non-pattern console screens — full specs | 21 |
| 5 | Pattern instantiations — tables | 92 |
| 6 | Multisite tenancy flows | 5 |
| **Total** | | **144** |

---

# Part 1 — The two reusable patterns

## Pattern P-LIST — filtered, paginated, bulk-actionable list

**Legacy shape**: `WP_List_Table` subclasses rendered by a `wp-admin/*.php` front controller.
**Mode**: modernized. **Spec kind**: `route-component`.

```yaml
spec.kind: route-component
spec.pattern: P-LIST
spec.layout: ConsoleLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: ResourceListPage
  props:
    resource: "{{resource}}"          # instantiated per screen
    columns: "{{columns}}"
    row_actions: "{{row_actions}}"
    bulk_actions: "{{bulk_actions}}"
    filters: "{{filters}}"
    per_page_setting: "{{per_page_setting}}"
  children:
    - component: PageTitle
      content: "{{title}}"            # LITERAL from the legacy, never rewritten
    - component: PrimaryAction
      label: "{{primary_action_label}}"
      route: "{{primary_action_route}}"
    - component: StatusTabs            # legacy "All | Published | Draft | Trash" links
      source: counts_by_status
    - component: FilterBar
      children: "{{filters}}"
    - component: BulkActionBar
      actions: "{{bulk_actions}}"
      confirm_destructive: true        # DEV-004
    - component: DataTable
      columns: "{{columns}}"
      sortable: "{{sortable_columns}}"
      row_actions: "{{row_actions}}"
      turbo_frame: "{{resource}}_list" # Hotwire: filter/sort/paginate without a full reload
    - component: Pagination
      strategy: "{{pagination_strategy}}"   # see DEV-003
spec.state_messages:
  loading: "Loading&hellip;"
  error: "{{error_message}}"
  success: "{{success_message}}"
  empty: "{{empty_message}}"           # LITERAL from the legacy's "No items found." family
```

**Contract notes**:
- ⚠️ **Pagination strategy is a per-screen decision, not a default.** The legacy runs
  `SQL_CALC_FOUND_ROWS` on every list to render an exact total (TD-06, F-QUERY-03). RISK-013 records
  that exact totals are entangled with observable behaviour. Each instantiation below declares
  `exact` or `estimated`; `Retrieval::Page` implements both. See DEV-003.
- Row actions are rendered from `Access::*Policy`, not from a capability string embedded in the
  view. ⚠️ Per owner override, a policy emitting no capabilities **allows** (`BR-CAP-05`), so a
  missing policy renders every action. AD-04's build check is what prevents that being reached by
  omission.
- `per_page` is a per-user preference in the legacy (`wp_user_settings` / screen options). Preserved
  as a `Configuration` value scoped to the user.

## Pattern P-EDIT — form over a single record

**Legacy shape**: `wp-admin/*.php` with an embedded `edit-form-*.php` include.
**Mode**: modernized. **Spec kind**: `route-component`.

```yaml
spec.kind: route-component
spec.pattern: P-EDIT
spec.layout: ConsoleLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: ResourceFormPage
  props:
    resource: "{{resource}}"
    mode: "{{new | edit}}"
  children:
    - component: PageTitle
      content: "{{title}}"
    - component: Form
      submit_event: "{{resource}}.{{create | update}}"
      children: "{{fields}}"
    - component: SidebarPanels          # legacy metaboxes, collapsed to declared panels
      panels: "{{panels}}"
    - component: ButtonRow
      children:
        - component: Button
          variant: primary
          label: "{{submit_label}}"
          action: form.submit
        - component: Button
          variant: ghost
          label: "{{cancel_label}}"
          action: navigate.back
spec.state_messages:
  loading: "Saving&hellip;"
  error: "{{error_message}}"
  success: "{{success_message}}"
```

**Contract notes**:
- ⚠️ **Metaboxes do not survive as a mechanism.** The legacy metabox system is registered through
  hooks, which AD-01 removes. Panels are **declared per screen**, not registered at runtime. This is
  a structural consequence of the paradigm decision, recorded as DEV-002.
- Validation messages come from the model (`Publishing::Post` and friends), so a field's error text
  is the model's, not the view's — and the legacy's message strings are preserved verbatim.
- ⚠️ **`P-EDIT` does not cover the block editor.** `console.post`, `console.post-new` and
  `console.site-editor` are editor shells with an opaque canvas; see Part 4.

---

# Part 2 — Literal front-end templates (18)

**Mode**: literal. **All 18 are BLOCKED pending golden capture** — FR-13 forbids generating a
literal spec against a graphical target with no legacy capture. What follows is the *frame* of each
spec; the byte-level content arrives with the golden file.

**Shared contract for every screen in this part**:

```yaml
spec.kind: route-component
spec.mode: literal
spec.layout: WebLayout                 # legacy header.php + footer.php equivalent
spec.golden_required: true
spec.golden_dir: _reversa_sdd/screens/golden/
spec.states: preserved-from-legacy      # principle 6: NO invented states
spec.tokens_source: theme.json          # design-system.md §2 — 12 colours, gradients,
                                        # duotones, formula-generated spacing, 4 font sizes
spec.token_binding:
  css_custom_properties: "--wp--preset--{category}--{slug}"   # BR-GS-07
  utility_classes: ".has-{slug}-color, .has-{slug}-background-color"
  root_custom_property_selector: ":root"                      # BR-GS-06
  root_block_selector: "body"
spec.comparison:
  kind: html-css-snapshot
  normalize: [line_endings, whitespace_between_tags, nonce_values, timestamps, autoincrement_ids]
  deviations: [DEV-001, DEV-005, DEV-008]
```

| Screen | Legacy origin (hierarchy branch) | Route | Critical | Golden file | Status |
|---|---|---|---|:--:|---|
| `web.index` | `index.php` — the hierarchy's terminal fallback | `/` | no | `web-index.html` | ⚠️ blocked |
| `web.front_page` | `front-page.php` | `/` | no | `web-front-page.html` | ⚠️ blocked |
| `web.home` | `home.php` — the posts index | `/` or `/{posts_page}` | **yes** | `web-home.html` | ⚠️ blocked |
| `web.singular` | `singular.php` | — (fallback) | no | `web-singular.html` | ⚠️ blocked |
| `web.single` | `single.php`, `single-{type}.php` | `/{permalink_structure}` | **yes** | `web-single.html` | ⚠️ blocked |
| `web.page` | `page.php`, `page-{slug}.php` | `/{slug}` | **yes** | `web-page.html` | ⚠️ blocked |
| `web.archive` | `archive.php` | `/{type}` | **yes** | `web-archive.html` | ⚠️ blocked |
| `web.category` | `category.php`, `category-{slug}.php` | `/category/{slug}` | no | `web-category.html` | ⚠️ blocked |
| `web.tag` | `tag.php`, `tag-{slug}.php` | `/tag/{slug}` | no | `web-tag.html` | ⚠️ blocked |
| `web.taxonomy` | `taxonomy.php`, `taxonomy-{tax}.php` | `/{taxonomy}/{slug}` | no | `web-taxonomy.html` | ⚠️ blocked |
| `web.author` | `author.php` | `/author/{nicename}` | no | `web-author.html` | ⚠️ blocked |
| `web.date` | `date.php` | `/{year}/{month}/` | no | `web-date.html` | ⚠️ blocked |
| `web.search` | `search.php` | `/?s={query}` | no | `web-search.html` | ⚠️ blocked |
| `web.not_found_404` | `404.php` | *(any unmatched)* | **yes** | `web-404.html` | ⚠️ blocked |
| `web.attachment` | `attachment.php` | `/{parent}/{slug}` | no | `web-attachment.html` | ⚠️ blocked |
| `web.embed` | `embed.php` + `embed-content.php` | `/{permalink}/embed/` | no | `web-embed.html` | ⚠️ blocked |
| `web.privacy_policy` | `privacy-policy.php` | `/{privacy_page_slug}` | no | `web-privacy-policy.html` | ⚠️ blocked |
| `web.comments` | `comments.php` *(a partial, not a route)* | — | no | `web-comments.html` | ⚠️ blocked |

**Interpolation points shared across the branch**: `{{site_title}}`, `{{site_description}}`,
`{{post_title}}`, `{{post_content}}`, `{{post_excerpt}}`, `{{author_display_name}}`,
`{{published_at}}`, `{{term_name}}`, `{{search_query}}`, `{{pagination}}`.

**Exit transitions**: `web.single` ← from any archive branch · `web.comments` embedded within
`web.single` / `web.page` · `web.search` ← from the search form in `WebLayout`.

⚠️ **Two things this part deliberately does not do:**
1. **It does not enumerate block output.** 115 core blocks render inside `{{post_content}}`
   (`blocks-library`, `block-supports`). Their markup is a `Composition::Renderer` concern with its
   own 6 + 6 migrated rules, not a screen concern.
2. **It does not invent states.** Principle 6: literal mode preserves only the states the legacy has.
   These templates have no loading state — they are server-rendered in one pass.

---

# Part 3 — Auth flows (8)

**Mode**: modernized. All strings below are **verbatim** from `wp-login.php`.

## Screen: `auth.login`

**Origin**: `wp-login.php` — `$action = 'login'` (the default)
**Mode applied**: modernized · **Critical**: yes
**Exit transitions**: `console.index` (success) · `auth.lostpassword` · `auth.register`

```yaml
spec.kind: route-component
spec.route: /login
spec.layout: AuthLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: LoginPage
  legacy_origin: "wp-login.php:login_form"
  children:
    - component: BrandMark
      content: "{{product_name}}"            # DEV-009 RESOLVED: WordPress branding dropped
    - component: Form
      submit_event: session.create
      children:
        - component: FormField
          name: log
          label: "Username or Email Address"  # LITERAL
          validation: { required: true }
        - component: PasswordField
          name: pwd
          label: "Password"                   # LITERAL
          toggle_labels: ["Show password", "Hide password"]   # LITERAL
          validation: { required: true }
        - component: Checkbox
          name: rememberme
          label: "Remember Me"                # LITERAL
        - component: Button
          variant: primary
          label: "Log In"                     # LITERAL
          action: form.submit
    - component: LinkRow
      children:
        - { label: "Lost your password?", route: /login/lost-password }   # LITERAL
        - { label: "Register",            route: /register }              # LITERAL
spec.api_changes:
  - legacy: "POST /wp-login.php (form-urlencoded, redirect_to param)"
    target: "POST /login (form-urlencoded, Turbo-aware redirect)"
    deviation: DEV-006
```

| State | Description | Content / message |
|---|---|---|
| Idle | The form, unsubmitted | as above |
| Loading | Credentials being verified | `"Log In"` button disabled, Turbo submitting |
| Error | Authentication failed | `{{error_message}}` — ⚠️ legacy error strings preserved verbatim, including whether they disclose that a username exists |
| Success | Session created | redirect to `{{redirect_to}}` or `console.index`; the legacy's `"You have logged in successfully."` is used only on the interstitial path |

**Accepted divergences**: DEV-006 (redirect mechanics), DEV-009 (branding dropped — the only place
principle 2 is overridden, and scoped to **branding and project-identity strings only**; every
functional label, prompt, validation message and error string above is still verbatim).

## Screen: `auth.lostpassword`

**Origin**: `wp-login.php` — `$action = 'lostpassword'` · **Mode**: modernized · Critical: no

```yaml
spec.kind: route-component
spec.route: /login/lost-password
spec.layout: AuthLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: LostPasswordPage
  children:
    - component: PageTitle
      content: "Lost Password"                # LITERAL
    - component: HelpText
      content: "Please enter your username or email address. You will receive an email message with instructions on how to reset your password."   # LITERAL, unmodified
    - component: Form
      submit_event: password_reset.request
      children:
        - component: FormField
          name: user_login
          label: "Username or Email Address"  # LITERAL
          validation: { required: true }
        - component: Button
          variant: primary
          label: "Get New Password"           # LITERAL
          action: form.submit
```

| State | Content / message |
|---|---|
| Success | routes to `auth.checkemail`, whose title is `"Check your email"` (LITERAL) |
| Error | `{{error_message}}` — ⚠️ preserved verbatim including its account-existence disclosure behaviour |

## Screen: `auth.resetpass`

**Origin**: `wp-login.php` — `$action = 'resetpass'` / `'rp'` · **Mode**: modernized · **Critical**: yes

```yaml
spec.kind: route-component
spec.route: /login/reset-password
spec.layout: AuthLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: ResetPasswordPage
  children:
    - component: PageTitle
      content: "Reset Password"               # LITERAL
    - component: Form
      submit_event: password.reset
      children:
        - component: PasswordField
          name: pass1
          label: "New password"               # LITERAL
          generator_label: "Generate Password" # LITERAL
          strength_indicator: true
          strength_label: "Strength indicator" # LITERAL
        - component: PasswordField
          name: pass2
          label: "Confirm new password"       # LITERAL
        - component: Checkbox
          name: pw_weak
          label: "Confirm use of weak password"  # LITERAL
          visible_when: strength == 'weak'
        - component: Button
          variant: primary
          label: "Save Password"              # LITERAL
          action: form.submit
      validation:
        - rule: not_all_whitespace
          message: "The password cannot be a space or all spaces."   # LITERAL
```

| State | Content / message |
|---|---|
| Success | `"Your password has been reset."` (LITERAL), then routes to `auth.login` |

## Screens: `auth.register`, `auth.checkemail`, `auth.confirmaction`, `auth.logout`, `auth.retrievepassword`

| Screen | Route | Legacy action | Title (LITERAL) | Shape | States |
|---|---|---|---|---|---|
| `auth.register` | `/register` | `register` | `"Registration Form"` / `"Register For This Site"` | form: `user_login`, `user_email`, button `"Register"` | idle, loading, error, success |
| `auth.checkemail` | `/login/check-email` | `checkemail` | `"Check your email"` | message only | idle |
| `auth.confirmaction` | `/login/confirm` | `confirmaction` | `"User action confirmed."` · errors `"Missing confirm key."`, `"Missing request ID."` | message only | idle, error |
| `auth.logout` | `DELETE /session` | `logout` | `"You are now logged out."` | message + redirect | success |
| `auth.retrievepassword` | `/login/lost-password` | `retrievepassword` | *(alias of `lostpassword`)* | — | — |

⚠️ `auth.retrievepassword` is a **legacy action alias**, not a distinct screen. It is counted in the
inventory because the legacy dispatches on it, and specified here as an alias so the coder does not
build it twice. Recorded as DEV-010.

---

# Part 4 — Non-pattern console screens (21)

## The editor — specified by observation (DEV-012)

### Screens: `console.post-new`, `console.post`, `console.site-editor`

**Origin**: `wp-admin/post-new.php`, `wp-admin/post.php` (both including `edit-form-blocks.php`),
`wp-admin/site-editor.php`
**Mode applied**: modernized, **at behavioural parity** · **Critical**: yes

> ⚠️ **Regenerated 2026-08-21.** An earlier version of this section specified only the shell and
> marked the canvas `raw-prose`, under deviation DEV-007. **DEV-007 was rejected** — the owner ruled
> the editor must be on par — so this section is regenerated in conformant mode, per the deviation
> log's convention.

**The method changes here, and only here.** Every other screen in this document is specified from
Reversa's extraction. The editor cannot be: `wp-includes/js/dist/` ships compiled bundles, so
component names, variants and props are unreadable from this checkout (TD-19, Q6, F-DS-07), and
**none of the 363 migrated rules describes client-side editing** — the 12 `block-editor` rules are
all server-side. But unreadable *here* is not unspecifiable. The behaviour is fully observable from
the reference WordPress instance that AD-08 already commits to building.

```yaml
spec.kind: route-component
spec.route: [/console/posts/new, /console/posts/:id/edit, /console/site-editor]
spec.layout: EditorLayout                # full-bleed; ConsoleLayout chrome suppressed
spec.states: [idle, loading, error, success]
spec.parity_target: behavioural-and-interaction
spec.specification_source: oracle-observation   # NOT rule extraction — the only screen where this is true
spec.component:
  component: EditorShell
  server_side:                           # fully specified from the extraction
    - autosave and revision behaviour        # Publishing::Revision
    - post locking                            # legacy _edit_lock / _edit_last, now columns (AD-03)
    - the publish / schedule state machine    # BR-MIGRATE-029/030, the 60-second threshold
    - slug allocation on first publish        # BR-MIGRATE-032/033/034, via Routing::SlugAllocator
    - block parsing and serialization         # Composition::Block, markup 📦
    - server-side block rendering             # Composition::Renderer, 6 rules
    - block supports attribute emission       # styling 📦, 6 rules
  client_side:                           # specified by observation against the oracle
    canvas:
      - block insertion, selection, multi-selection, drag reorder
      - inline formatting and rich-text editing
      - block transforms and variations
      - nested blocks and inner-block containers
      - copy / paste round-trip through block markup
      - undo / redo across the whole document
    inspector:
      - per-block settings panels driven by block.json schemas
      - block supports controls (23 supports — see block-supports/requirements.md)
    chrome:
      - the block inserter, patterns browser, list view
      - document settings, template selection
      - preview modes and device widths
    site_editor_additional:
      - template and template-part browsing and editing
      - global styles editing across the four-origin cascade   # BR-GS-01, styling 📦
spec.specifiable_from_extraction:
  - "115 core block schemas"          # blocks-library/requirements.md — block.json is READABLE
  - "23 block supports"               # block-supports/requirements.md
  - "the theme.json four-origin cascade"  # design-system.md §2, BR-GS-01/05/06/07
spec.deviations: [DEV-002, DEV-012]
```

### What is actually readable, and what has to be observed

This distinction is the whole content of DEV-012, so it is stated explicitly rather than left to be
rediscovered:

| Layer | Readable from this checkout? | Source |
|---|---|---|
| Block **schemas** — 115 core blocks | ✅ **yes** | `wp-includes/blocks/*/block.json`, `blocks-json.php` (206 KB) |
| Block **supports** — 23 decorators | ✅ **yes** | `wp-includes/block-supports/`, 6 migrated rules |
| **Server-side** block rendering | ✅ yes | `wp-includes/blocks/*.php` |
| The `theme.json` **token cascade** | ✅ yes | `wp-includes/theme.json`, 🟢 CONFIRMED |
| Block **markup** serialization format | ✅ yes | `class-wp-block-parser.php` |
| The editing **canvas** behaviour | ❌ **no** | `wp-includes/js/dist/` — compiled |
| The **inspector controls** | ❌ no | `@wordpress/components` — compiled (F-DS-07) |
| Editor **chrome and interactions** | ❌ no | compiled |

**The readable half is substantial and should be used first.** 115 block schemas plus 23 supports
plus the cascade is a real specification of *what a block is and what it can be configured to do*.
What is missing is *how a person manipulates it*, which is exactly the part that must be observed.

### How to reach parity — the method, in order

1. **Build the oracle first** (Wave 0, AD-08). It is required for the other 141 screens anyway; here
   it is the *only* specification source for the client half.
2. **Specify from the readable half.** Generate the inspector's control surface from the 115
   `block.json` schemas and the 23 supports. This is mechanical and covers most of the panel content.
3. **Observe the interaction layer** against the oracle and author interaction-level parity specs by
   observation. ⚠️ These are the **only** parity specs in this project with no `BR-MIGRATE-*` behind
   them; the Inspector must keep them in a distinct category.
4. **Consult upstream where observation is ambiguous.** The `gutenberg` and `wordpress-develop`
   repositories carry the source this checkout does not. They are outside Reversa's scope and outside
   this analysis, but they are not outside the world, and DEV-012 records them as a legitimate input.

### ⚠️ Two consequences recorded, not assumed

**The target platform is carved out for these three screens.** The confirmed target is
`rails-hotwire`. A canvas with live block manipulation, multi-block selection and undo across a
document is not a Turbo-frame problem — reaching parity almost certainly requires a **React island**
inside the Hotwire console. That is the third option presented at the Phase 1 pause and not taken
("Hotwire for console, React for the editor"). It does not overturn the platform choice for the
other 141 screens; it carves out three. Flagged in `ambiguity_log.md` rather than decided here.

**Wave 4's parity gate is now maximally scoped.** `migration_strategy.md` places editing and API
surfaces in Wave 4 and notes its scope is "set by the Screen Translator, not by the rule set". That
is now settled in the direction of most work. Wave 4 already had the least specification behind it;
it now also has the most to build. RISK-010 changes character accordingly — from *unspecified scope*
to *specified-by-observation scope*, which is larger and slower to pin down, not smaller.

## Settings screens (9) — a family, not a pattern

**Origin**: `wp-admin/options-*.php` · **Mode**: modernized · Critical: `options-general`,
`options-permalink`, `options-discussion`

```yaml
spec.kind: route-component
spec.pattern: none                       # deliberately NOT P-EDIT: no record, only settings
spec.layout: ConsoleLayout
spec.states: [idle, loading, error, success]
spec.component:
  component: SettingsPage
  props:
    section: "{{section}}"
    fields: "{{declared_fields}}"        # DECLARED, not hook-registered — AD-01, DEV-002
  children:
    - component: PageTitle
      content: "{{title}}"               # LITERAL
    - component: SettingsForm
      submit_event: settings.update
      binds_to: Configuration::Setting
```

| Screen | Route | Settings owned | Note |
|---|---|---|---|
| `console.options-general` | `/console/settings` | `siteurl`, `home`, `blogname`, `blogdescription`, `timezone_string`, `date_format`, `time_format`, `users_can_register`, `default_role` | `home` falls back to `siteurl` when empty (BR-OPT-12) |
| `console.options-writing` | `/console/settings/writing` | `default_category`, `mailserver_*` | ⚠️ `mailserver_*` drives post-by-email (`wp-mail.php`), which has no MIGRATE rules — DEV-011 |
| `console.options-reading` | `/console/settings/reading` | `show_on_front`, `page_on_front`, `page_for_posts`, `posts_per_page`, `posts_per_rss`, `blog_public` | `blog_public` gates sitemaps and robots |
| `console.options-discussion` | `/console/settings/discussion` | `comment_moderation`, `comment_previously_approved`, `comment_max_links`, `moderation_keys`, `disallowed_keys`, `close_comments_*` | ⚠️ **the entire comment moderation policy**; three deviations apply (BR-CMT-04/08/10) |
| `console.options-media` | `/console/settings/media` | `thumbnail_size_*`, `medium_size_*`, `large_size_*`, `uploads_use_yearmonth_folders` | binds to `Library::Variant` size names |
| `console.options-permalink` | `/console/settings/permalinks` | `permalink_structure` | ⚠️ **changing this changes which slugs are legal** (BR-POST-07, F-RW-06). The form must warn; `Routing::ReservedSegment` recomputes. |
| `console.options-privacy` | `/console/settings/privacy` | privacy page selection | — |
| `console.options-connectors` | `/console/settings/connectors` | AI provider configuration | `Assistance` context, Wave 5 |
| `console.options` | `/console/settings/all` | the generic settings writer | ⚠️ legacy catch-all POST target; **not reproduced** as a screen — DEV-002 |

## Dashboard, tools and informational screens (9)

| Screen | Route | Shape | Note |
|---|---|---|---|
| `console.index` | `/console` | dashboard widget grid | ⚠️ widgets were hook-registered; now **declared** (AD-01, DEV-002) |
| `console.tools` | `/console/tools` | link index | — |
| `console.export` | `/console/tools/export` | form → file download | — |
| `console.import` | `/console/tools/import` | importer index | ⚠️ importers were plugins; scope is a product decision |
| `console.site-health` | `/console/tools/site-health` | status report | `Platform::Health` |
| `console.site-health-info` | `/console/tools/site-health/info` | expandable report | `Platform::Health` |
| `console.export-personal-data` | `/console/tools/export-personal-data` | P-LIST over `Identity::DataRequest` | GDPR |
| `console.erase-personal-data` | `/console/tools/erase-personal-data` | P-LIST over `Identity::DataRequest` | GDPR |
| `console.privacy-policy-guide` | `/console/tools/privacy-guide` | static guidance | — |

✅ **`console.about`, `console.credits`, `console.freedoms`, `console.contribute`, `console.privacy`**
(each appearing three times — root, `network/`, `user/`) described *WordPress the project*, not this
system. **DEV-009 resolved**: they are retained as routes carrying the rebuild's own content. The
WordPress-project text is not migrated.

---

# Part 5 — Pattern instantiations (92)

## P-LIST instantiations

| Screen | Route | Resource | Key columns | Bulk actions | Pagination | Note |
|---|---|---|---|---|---|---|
| `console.edit` | `/console/posts` | `Publishing::Post` | title, author, categories, tags, comments, date | edit, trash | **exact** | status tabs from `counts_by_status` |
| `console.upload` | `/console/media` | `Library::Asset` | file, author, attached-to, date | delete | estimated | grid + list views |
| `console.edit-comments` | `/console/comments` | `Discussion::Comment` | author, comment, in-response-to, submitted | approve, unapprove, spam, trash | **exact** | ⚠️ moderation deviations apply |
| `console.moderation` | `/console/comments?status=pending` | `Discussion::Comment` | *(as above)* | *(as above)* | exact | legacy alias route |
| `console.users` | `/console/users` | `Identity::User` | username, name, email, role, posts | delete, change-role | exact | roles are rows now |
| `console.edit-tags` | `/console/terms/:taxonomy` | `Classification::Term` | name, description, slug, count | delete | exact | ⚠️ `count` = **published only** |
| `console.themes` | `/console/themes` | `Presentation::Theme` | screenshot, name, version, active | activate, delete | estimated | ✅ **built** — DEV-011 resolved: themes yes |
| `console.theme-install` | `/console/themes/new` | remote directory | — | install | estimated | ✅ built · `Egress` — ⚠️ SSRF validation is default-on (`BR-HTTP-01`) |
| ~~`console.plugins`~~ | — | — | — | — | — | ❌ **not built** — DEV-011: no hook system, nothing for a plugin to attach to |
| ~~`console.plugin-install`~~ | — | — | — | — | — | ❌ not built — DEV-011 |
| `console.update-core` | `/console/updates` | `Platform::SchemaVersion` | — | update | n/a | ⚠️ see P-4 in `ambiguity_log.md` |
| `console.nav-menus` | `/console/menus` | `Presentation::Menu` | menu items tree | delete | n/a | 🔑 items are **rows with columns** now, not 9 postmeta keys |
| `console.widgets` | `/console/widgets` | — | — | — | n/a | ⚠️ consolidated into `console.site-editor` by BC-11 — DEV-002 |
| `console.widgets-form` / `-blocks` | — | — | — | — | n/a | ⚠️ same consolidation |
| `console.my-sites` | `/console/my-sites` | tenancy | site, role | — | estimated | Wave 5 |
| `console.ms-sites` | `/console/network/sites` | tenancy | — | — | — | legacy alias of `network.sites` |
| `console.ms-users` | `/console/network/users` | `Identity::User` | — | — | — | legacy alias |
| `console.ms-themes` | `/console/network/themes` | `Presentation::Theme` | — | — | — | legacy alias |
| `console.network.sites` | `/console/network/sites` | tenancy | path, last updated, registered, users | delete, archive, spam | exact | Wave 5 |
| `console.network.users` | `/console/network/users` | `Identity::User` | username, name, email, registered, sites | delete, spam | exact | Wave 5 |
| `console.network.themes` | `/console/network/themes` | `Presentation::Theme` | theme, enabled | enable, disable | estimated | Wave 5 |
| ~~`console.network.plugins`~~ | — | — | — | — | — | ❌ not built — DEV-011 |
| `console.network.site-users` | `/console/network/sites/:id/users` | `Identity::RoleAssignment` | — | remove | exact | Wave 5 |
| `console.network.site-themes` | `/console/network/sites/:id/themes` | `Presentation::Theme` | — | enable | estimated | Wave 5 |
| `console.network.sites` *(index)* | — | — | — | — | — | — |

*(The remaining `console.network.*` and `console.user.*` entries below are P-LIST or P-EDIT
instantiations of the same resources, re-scoped to the network or to the current user. They are
listed in Part 5's traceability appendix rather than repeated here, because the only difference is
the scope filter.)*

## P-EDIT instantiations

| Screen | Route | Resource | Panels | Note |
|---|---|---|---|---|
| `console.comment` | `/console/comments/:id/edit` | `Discussion::Comment` | status, author | — |
| `console.term` | `/console/terms/:taxonomy/:id/edit` | `Classification::Term` | parent, description | unique on `(taxonomy, parent, slug)` |
| `console.media` | `/console/media/:id/edit` | `Library::Asset` | alt text, caption, variants | 🔑 alt text is a column now |
| `console.media-new` | `/console/media/new` | `Library::Asset` | upload | Active Storage |
| `console.profile` | `/console/profile` | `Identity::User` | account, contact, preferences | ⚠️ `admin_color` **not reproduced** — DEV-008 |
| `console.user-edit` | `/console/users/:id/edit` | `Identity::User` | *(as above)* + roles | roles are rows |
| `console.user-new` | `/console/users/new` | `Identity::User` | account, role | — |
| `console.revision` | `/console/posts/:id/revisions` | `Publishing::Revision` | diff view | own table now |
| `console.authorize-application` | `/console/application-passwords/authorize` | `Identity::ApplicationPassword` | — | ⚠️ `Access` gate required |
| `console.customize` | `/console/site-editor` | — | — | ⚠️ **consolidated** into `console.site-editor` (BC-11) — DEV-002 |
| `console.custom-header` / `custom-background` | `/console/site-editor` | — | — | ⚠️ same consolidation |
| `console.font-library` | `/console/site-editor/fonts` | `styling` 📦 data | — | was a post type (AD-02) |
| `console.network.site-info` / `site-new` / `site-settings` | `/console/network/sites/*` | tenancy | — | Wave 5 |
| `console.network.settings` / `setup` | `/console/network/settings` | `Configuration::Setting` | — | Wave 5 |
| `console.network.user-edit` / `user-new` | `/console/network/users/*` | `Identity::User` | — | Wave 5 |

## Screens specified as NOT built (14)

| Screen | Reason |
|---|---|
| `console.link-manager`, `console.link-add`, `console.link` | ⚠️ **excluded from scope.** The target drops `wp_links` (F-DD-07, `target_data_model.md`). |
| `console.plugins`, `console.plugin-install`, `console.network.plugins` | ⚠️ **DEV-011 resolved: plugins no.** With no hook system (AD-01) there is nothing for a plugin to attach to, and no replacement mechanism was designed. |
| `console.plugin-editor`, `console.theme-editor`, `console.network.plugin-editor`, `console.network.theme-editor` | Editing source files from a web UI. No target concept, independent of the DEV-011 ruling. |
| `console.press-this`, `console.media-upload`, `console.options-head`, `console.upgrade-functions` | Legacy internals, aliases or bookmarklet endpoints, not user-facing screens. |
| `console.install`, `console.setup-config`, `console.upgrade`, `console.ms-upgrade-network` | Installation and upgrade flows. `Platform::SchemaVersion` + Rails migrations replace them. ⚠️ See P-4 in `ambiguity_log.md`. |

---

# Part 6 — Multisite tenancy flows (5)

**Mode**: modernized · **Wave 5, post-launch** · All bind to the `Tenancy` cross-cutting concern.

| Screen | Route | Legacy origin | Shape |
|---|---|---|---|
| `tenancy.user_signup` | `/signup` | `wp-signup.php` | form: username, email |
| `tenancy.blog_signup` | `/signup/site` | `wp-signup.php` | form: site address, title, privacy |
| `tenancy.signup_confirm` | `/signup/confirm` | `wp-signup.php` | message |
| `tenancy.activate_form` | `/activate` | `wp-activate.php` | form: activation key |
| `tenancy.activate_result` | `/activate/done` | `wp-activate.php` | message + credentials |

⚠️ Each new site provisions a **PostgreSQL schema**, not a set of prefixed tables (`BR-MS-01`). The
signup flow therefore triggers a schema creation and migration run — which is why `Tenancy` is
sequenced last (RISK-009), and why these five screens are specified now but built after launch.

---

## Appendix: traceability to the inventory

`_reversa_sdd/ui/inventory.md` **does not exist** (EC-18), so the middle column of the template's
traceability table cannot be filled. Traceability runs to
`_reversa_sdd/screens/inventory.json` only.

| Group | Screens | Inventory ids | Where specified |
|---|---:|---|---|
| `console.*` (root) | 78 | `SCR-0001` … `SCR-0078` | Parts 4, 5 |
| `console.network.*` | 28 | `SCR-0079` … `SCR-0106` | Part 5 |
| `console.user.*` | 8 | `SCR-0107` … `SCR-0114` | Part 5 |
| `auth.*` | 8 | `SCR-0115` … `SCR-0122` | Part 3 |
| `tenancy.*` | 5 | `SCR-0123` … `SCR-0127` | Part 6 |
| `web.*` | 18 | `SCR-0128` … `SCR-0144` +1 | Part 2 |
| **Total** | **144** | | |

> ⚠️ **The inventory is one reading, not two.** `reversa-visor` never ran, so the FR-05 rule — stop
> if two inventories diverge by more than 10% — could not be applied. The screen count is derived
> from the file tree by this agent alone: one screen per admin route, one per template-hierarchy
> branch, one per `wp-login.php` action. It is defensible, and it is unverified.
