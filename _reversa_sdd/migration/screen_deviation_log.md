---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: screen_deviation_log
producedBy: screen-translator
mode: append-only
hash: "sha256:ebbd27476bcc021f034fae17cf02241e4cd925d97e93c00d92af6de8e6870c37"
---

# Screen Deviation Log

> Record of every divergence between the legacy system and the spec generated in
> `target_screens.md`. Append-only. **Pending deviations block the handoff to the Inspector.**
> Approved deviations are propagated to `parity_specs.md § Exceptions` when the Inspector runs.

## Conventions

- **ID**: `DEV-NNN`.
- **Type**: `technical` · `modernization` · `platform` · `fix`.
- **Approval**: `pending` | `approved` | `rejected`.

## Summary

- **Total**: 12
- **Pending**: **0** — all resolved at the post-Screen-Translator pause on 2026-08-21
- **Approved**: 10
- **Rejected**: 1 — **DEV-007**, superseded by DEV-012
- **Blocking the Inspector**: none

> **Resolved 2026-08-21.** DEV-001 approved with a commitment to capture. DEV-009 resolved as a
> `fix` — the WordPress branding is dropped. DEV-011 resolved as **themes yes, plugins no**.
> ⚠️ **DEV-007 was REJECTED**: the owner ruled that the editor must reach parity, so the deviation
> that would have excused it from parity does not stand. See **DEV-012**, which replaces it and
> carries a materially larger scope.

## Entries

### DEV-001 — the 18 literal screens have no golden files

| Field | Value |
|---|---|
| Affected screen | all 18 `web.*` |
| Type | `technical` |
| Description | Literal mode was chosen for the front-end templates, but no legacy capture exists. FR-13 forbids generating a literal spec against a graphical target with no golden file, so Part 2 specifies the *frame* of each screen and leaves the byte-level content unspecified. |
| Reason | `_reversa_sdd/ui/screens/` does not exist and `reversa-visor` never ran (EC-18). The capture is possible — AD-08 commits to a running reference WordPress instance in Wave 0 — but has not happened. v1 does not automate capture (OQ-02). |
| Legacy origin | `wp-includes/template-loader.php` and the theme template hierarchy |
| Implication for parity tests | Observable HTML/CSS parity is **unavailable** until capture runs. |
| Approval | `approved` — ⚠️ **conditionally.** The owner committed to running the capture against the Wave 0 oracle. The approval covers the *interim* state, not a permanent exemption: once `manifest.yaml` is executed and `present: true`, these 18 screens move into full observable parity and this deviation closes. |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes — as a **temporary** exception the Inspector must mark for removal after capture |

### DEV-002 — hook-registered UI becomes declared UI

| Field | Value |
|---|---|
| Affected screen | `console.index` (dashboard widgets), all `P-EDIT` screens (metaboxes), all settings screens, `console.options` |
| Type | `modernization` |
| Description | Dashboard widgets, metaboxes and settings sections are registered through hooks in the legacy. AD-01 removes the hook system, so all three become **declared** structures in the target. `console.options`, the legacy's generic settings POST target, is not reproduced as a screen at all. |
| Reason | A direct consequence of `paradigm_decision.md` implication 2 and AD-01: behaviour is final, so a runtime registration mechanism has nothing to register into. Also absorbs BC-11's consolidation of the four overlapping settings surfaces (TD-10, F-CUST-04): `console.customize`, `console.widgets`, `console.custom-header` and `console.custom-background` fold into `console.site-editor`. |
| Legacy origin | `wp-admin/includes/dashboard.php`, `wp-admin/includes/meta-boxes.php`, `wp-admin/options.php` |
| Implication for parity tests | Screen composition is not comparable. Compare the **resulting fields and their values**, never the panel registry. |
| Approval | `approved` — implied by the architecture approval on 2026-08-21 |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-003 — pagination totals may be estimated

| Field | Value |
|---|---|
| Affected screen | all `P-LIST` instantiations |
| Type | `modernization` |
| Description | The legacy runs `SQL_CALC_FOUND_ROWS` on every list to render an exact total. `P-LIST` declares `exact` or `estimated` per screen; six declare `estimated`. |
| Reason | TD-06 / F-QUERY-03: every archive page counts the full matching set to render a pager. RISK-013 records that fixing this is *observably different* at the pager, so it is a deviation and not a silent optimization. |
| Legacy origin | `wp-includes/class-wp-query.php` |
| Implication for parity tests | On screens declaring `estimated`, the total row count is **out of parity scope**; page contents remain in scope. |
| Approval | `approved` — RISK-013's mitigation, decided in the architecture |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-004 — destructive bulk actions require confirmation

| Field | Value |
|---|---|
| Affected screen | all `P-LIST` instantiations with a destructive bulk action |
| Type | `fix` |
| Description | `P-LIST` sets `confirm_destructive: true`. Several legacy bulk actions delete without an interstitial confirmation. |
| Reason | A small, contained safety improvement, consistent with the six deliberate deviations already approved at the Curator pause. |
| Legacy origin | `wp-admin/includes/class-wp-list-table.php` |
| Implication for parity tests | One extra interaction step before the destructive action. Compare the **outcome**, not the click count. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-005 — two token systems, only one carried forward

| Field | Value |
|---|---|
| Affected screen | all `console.*` |
| Type | `modernization` |
| Description | The legacy has **two design systems that share no tokens** (F-DS-01): `theme.json` for the front end, and eight SCSS colour schemes for `/wp-admin/`. The target carries the first and **does not reproduce the second**. |
| Reason | The admin colour schemes are a per-user preference stored in the `admin_color` user meta, delivered as eight compiled SCSS files. Reproducing them means shipping eight admin themes for a console that BC-11 is already consolidating. `theme.json` is the token system with 🟢 CONFIRMED values and a documented delivery contract (BR-GS-06/07). |
| Legacy origin | `wp-admin/css/colors/*/colors.scss` |
| Implication for parity tests | Console colours are out of visual parity scope entirely — which they already are, since all console screens are modernized. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-006 — auth POST targets and redirect mechanics change

| Field | Value |
|---|---|
| Affected screen | all 8 `auth.*` |
| Type | `platform` |
| Description | `wp-login.php` dispatches every auth screen from one URL on an `$action` parameter, and redirects via a `redirect_to` query parameter. The target uses distinct routes under `/login/*` with Turbo-aware responses. |
| Reason | One URL serving eight screens is a front-controller artifact, not behaviour. Rails routing and Turbo require distinct endpoints. |
| Legacy origin | `wp-login.php` |
| Implication for parity tests | URL-level comparison invalid for auth. **Compare behaviour and the literal message strings**, which are preserved verbatim. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-007 — the editing canvas cannot be specified

| Field | Value |
|---|---|
| Affected screen | `console.post`, `console.post-new`, `console.site-editor` |
| Type | `platform` |
| Description | The block editor and Site Editor canvases are a React SPA shipped only as build output. `target_screens.md` Part 4 specifies the **shell** — route, layout, entry/exit transitions, autosave, revisions, post locking, the publish state machine — and marks the canvas `raw-prose`. |
| Reason | TD-19 and Q6: `@wordpress/*` packages ship compiled; F-DS-07: component names, variants and props are unrecoverable. **Reversa extracted no client-side editor behaviour.** There is nothing to translate. |
| Legacy origin | `wp-admin/edit-form-blocks.php`, `wp-includes/js/dist/` |
| Implication for parity tests | *(void — see DEV-012)* |
| Approval | **`rejected`** |
| Rejected by | thies (owner) |
| Rejected at | 2026-08-21 |
| Rejection rationale | **"The editor needs to be on par."** The owner declined to exempt the editing experience from parity. This deviation asked to place the canvas out of scope on the grounds that its source is unreadable *from this checkout*; the ruling is that unreadable-here does not mean unspecifiable, and the editor must reach parity like everything else. |
| Propagates to `parity_specs.md § Exceptions` | no — a rejected deviation is archived, not propagated |
| Superseded by | **DEV-012** |
| Note | Per this log's conventions, a rejected deviation means the agent **regenerates the screen in conformant mode**. `target_screens.md` Part 4 has been rewritten accordingly. |

### DEV-008 — `admin_color` preference not reproduced

| Field | Value |
|---|---|
| Affected screen | `console.profile`, `console.user-edit`, `console.user.profile` |
| Type | `modernization` |
| Description | The per-user admin colour-scheme picker is removed; the `admin_color` user meta is not migrated. |
| Reason | Consequence of DEV-005. Carrying the field without the eight schemes behind it would present a control that does nothing. |
| Legacy origin | `wp-admin/user-edit.php`; `usermeta['admin_color']` |
| Implication for parity tests | One fewer field on the profile form. Not a parity failure. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-009 — the "Powered by WordPress" string

| Field | Value |
|---|---|
| Affected screen | `auth.login` and every `AuthLayout` screen |
| Type | `fix` |
| Description | The login screen's brand mark read `"Powered by WordPress"`. **Resolved: the WordPress branding is dropped.** The brand mark becomes the rebuild's own, and `console.about`, `console.credits`, `console.freedoms`, `console.contribute` become routes carrying the rebuild's own content rather than WordPress project pages. |
| Reason | ⚠️ **A judgement call this agent must not make alone.** No copy editing was approved, so the string is preserved — but this rebuild **is not WordPress**, and shipping the attribution verbatim states something untrue about what the software is. Preserving it is the correct default; keeping it permanently is a decision for the owner. The same applies to `console.about`, `console.credits`, `console.freedoms` and `console.contribute`, whose entire content describes the WordPress project (see DEV-011). |
| Legacy origin | `wp-login.php` |
| Implication for parity tests | ⚠️ The string diff on auth screens and on the five informational pages is now **expected**. This is the one place where "textual content preserved literally" is deliberately overridden, and the override is scoped to **branding and project-identity strings only** — every functional label, prompt, validation message and error string remains verbatim. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |

### DEV-010 — `auth.retrievepassword` is an alias

| Field | Value |
|---|---|
| Affected screen | `auth.retrievepassword` |
| Type | `technical` |
| Description | The legacy dispatches both `lostpassword` and `retrievepassword` to the same screen. The inventory counts it because the dispatch exists; the spec marks it an alias so it is not built twice. |
| Reason | A front-controller artifact. |
| Legacy origin | `wp-login.php` |
| Implication for parity tests | One route, not two. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | no |

### DEV-011 — eleven screens specified as not built

| Field | Value |
|---|---|
| Affected screen | `console.link-manager`, `console.link-add`, `console.link`, `console.plugin-editor`, `console.theme-editor`, `console.network.plugin-editor`, `console.network.theme-editor`, `console.press-this`, `console.media-upload`, `console.options-head`, `console.upgrade-functions` — plus the informational pages `console.about`, `console.credits`, `console.freedoms`, `console.contribute`, `console.privacy` (×3 scopes) |
| Type | `modernization` |
| Description | These screens are specified as **not built**, for four distinct reasons: (a) the Link Manager's `wp_links` table is dropped from the target data model; (b) editing PHP files from a web UI has no target concept; (c) bookmarklet endpoints and internal aliases are not user-facing screens; (d) the informational pages describe *the WordPress project*, not this system. |
| Reason | (a) is settled by `target_data_model.md` and F-DD-07. (b) follows from AD-01 — with no plugin mechanism, there are no plugin files to edit. (c) is inventory hygiene. ⚠️ **(d) is not settled by anything**, and neither is the underlying question it depends on: **what a "plugin" or a "theme" means in a system with no hook API.** `console.plugins`, `console.plugin-install`, `console.themes` and `console.theme-install` are specified as P-LIST instantiations, but what they list is undefined. |
| Legacy origin | various, `wp-admin/` |
| Implication for parity tests | These screens have no target, so no parity test applies. But the four extension-management screens that *are* specified have an undefined resource, which the Inspector cannot test around. |
| Approval | `approved` — **resolved: themes yes, plugins no** |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | yes |
| Note | ⚠️ **This was the deviation most worth reading, and it is now settled.** AD-01 discards the hook system and `migration_brief.md` states there is no compatibility burden — but neither said whether the rebuild has an extension mechanism at all. It was invisible to the Paradigm Advisor, the Curator, the Strategist and the Designer, because none of them owns the screen surface where someone has to draw a list. |

#### The ruling, applied

**Themes are real. Plugins are not.**

| Screen | Outcome | Reason |
|---|---|---|
| `console.themes` | **built** — P-LIST over `Presentation::Theme` | The data model already carries a `themes` table with `slug`, `parent_slug`, `version`, `active`. Theme switching is a real, backed operation. |
| `console.theme-install` | **built** — P-LIST over a remote directory, via `Egress` | ⚠️ SSRF policy applies (`BR-HTTP-01`, default-on validation) |
| `console.network.themes`, `console.network.site-themes` | **built** | Wave 5, re-scoped to the network |
| `console.plugins`, `console.plugin-install` | **not built** | With no hook system there is nothing for a plugin to attach to. AD-01 leaves no attachment surface, and no replacement was designed. |
| `console.network.plugins` | **not built** | same |
| `console.plugin-editor`, `console.theme-editor`, and their network variants | **not built** | Editing source files from a web UI has no target concept, independent of this ruling. |

**Consequence for the architecture**: `Presentation::Theme` gains a genuine lifecycle (install,
activate, deactivate, delete) that the Designer specified only as a table. The four theme screens are
its UI. **No extension registry is introduced** — a theme is data plus template files, not code that
hooks into the core, so this ruling does not reopen AD-01.

### DEV-012 — the editing experience must reach parity, and its specification does not exist here

| Field | Value |
|---|---|
| Affected screen | `console.post`, `console.post-new`, `console.site-editor` |
| Type | `platform` |
| Description | **Replaces the rejected DEV-007.** The owner ruled that the editor must be on par with the legacy. This deviation records not an exemption but a **change of method**: the editing experience is the one part of this migration whose specification cannot come from Reversa's extraction, because the extraction contains none of it. It must be specified from a *running oracle* and, where that is insufficient, from the upstream source that this checkout does not carry. |
| Reason | TD-19, Q6 and F-DS-07 are facts about **this checkout**, not about the world: `wp-includes/js/dist/` ships compiled bundles, so component names, variants and props are unreadable here. But the behaviour is fully **observable** from the reference WordPress instance that AD-08 already commits to building, and the source exists upstream in the `gutenberg` / `wordpress-develop` repositories, outside this tree. Unreadable-here is not unspecifiable. |
| Legacy origin | `wp-admin/edit-form-blocks.php`, `wp-admin/site-editor.php`, `wp-includes/js/dist/` (compiled) |
| Implication for parity tests | ⚠️ **Editor parity is behavioural and interaction-level, not rule-level.** None of the 363 migrated rules describes it — the 12 `block-editor` rules are all server-side. Parity specs for the editor must be authored **against the oracle**, by observation, and they are the only parity specs in this project with no `BR-MIGRATE-*` behind them. The Inspector must treat this as a distinct category, not fold it into the rule-level specs. |
| Approval | `approved` |
| Approved by | thies (owner) |
| Approved at | 2026-08-21 |
| Propagates to `parity_specs.md § Exceptions` | no — it propagates to `parity_specs.md` as **scope**, not as an exception |

#### ⚠️ Three consequences the owner should see stated plainly

1. **This is now the largest single work item in the project, and the only one with no upstream
   specification inside Reversa's artifacts.** Everything else in this migration is bounded by 363
   extracted rules. The editor is bounded by whatever the oracle does — which is roughly fifty
   `@wordpress/*` packages of React, a block-parsing client, an inspector-controls system, drag-and-
   drop, multi-block selection, patterns, and the Site Editor's template browsing. RISK-010 changes
   character: it stops being *unspecified scope* and becomes *specified-by-observation scope*, which
   is larger and slower to pin down, not smaller.

2. **It reopens the target-platform choice for exactly these three screens.** The confirmed target is
   `rails-hotwire` — server-rendered HTML with Turbo and Stimulus. The block editor is an inherently
   rich client application: a canvas with live block manipulation is not a Turbo-frame problem. Reaching
   parity almost certainly requires a **React island** inside the Hotwire console, which is the third
   option that was presented at the Phase 1 pause and not taken (*"Hotwire for console, React for the
   editor"*). This does not overturn the platform decision for the other 141 screens; it carves out
   three. Recorded here rather than silently assumed.

3. **The parity gate for Wave 4 is now much heavier.** `migration_strategy.md` places editing and API
   surfaces in Wave 4 and notes its scope is *"set by the Screen Translator, not by the rule set"*.
   That is now settled in the direction of maximum scope. Wave 4 was already the wave with the least
   specification behind it; it is now also the wave with the most work.

### DEV-009 applied — two console strings drop WordPress project-identity (coding note)

⚠️ **Recorded 2026-08-23 during Wave 4.** DEV-009 drops WordPress branding and
project-identity strings (scoped to those only; every functional string stays verbatim).
Two console help/error strings fall squarely in that scope, so the rebuild renders a
project-neutral form rather than the legacy verbatim — this is DEV-009 working as ruled,
not a copy edit, and it is logged here so a reviewer does not mistake it for one:

| Screen | Legacy string | Rebuild | Why |
|---|---|---|---|
| `console.options-general` tagline help | `In a few words, explain what this site is about. Example: "Just another WordPress site."` (options-general.php:90, `$sample_tagline`) | `In a few words, explain what this site is about.` | The example names *Just another **WordPress** site* — project-identity. The functional sentence is verbatim; the branded example is dropped. |
| `console.theme-install` fetch error | `An unexpected error occurred. Something may be wrong with WordPress.org or this server's configuration. If you continue to have problems, please try the support forums.` (theme-install.php:63) | `An unexpected error occurred. Something may be wrong with the theme directory.` | Names WordPress.org and the WordPress.org support forums — project-identity. The lead sentence is verbatim; the WordPress.org references are dropped. |

Everything else Wave 4's verifiers flagged as non-verbatim (`"No requests found."`,
`"Awaiting confirmation"`, the GDPR label `"Email Address"`, the two site-health
search-engine labels, two comment error strings) was a real copy edit and was **corrected
to the legacy verbatim**, not excused under DEV-009.

## Screens with more than one deviation

| Screen | IDs |
|---|---|
| all 18 `web.*` | DEV-001, DEV-005 *(by exclusion)* |
| `auth.login` | DEV-006, DEV-009 |
| `console.post`, `console.post-new`, `console.site-editor` | DEV-002, ~~DEV-007~~ *(rejected)*, DEV-012 |
| `console.profile`, `console.user-edit` | DEV-005, DEV-008 |
| `console.customize`, `console.widgets`, `console.custom-header`, `console.custom-background` | DEV-002 *(consolidation)*, DEV-005 |
| `console.themes`, `console.theme-install` | DEV-003, DEV-011 *(built)* |
| `console.plugins`, `console.plugin-install` | DEV-011 *(not built)* |
| `auth.*`, `console.about/credits/freedoms/contribute` | DEV-009 *(branding dropped)* |

## Notes

**All four pending deviations were resolved at the pause on 2026-08-21. Three went as expected; one
did not, and it is the one that matters.**

- **DEV-001** — approved *conditionally*. The owner committed to running the golden capture against
  the Wave 0 oracle, so the 18 literal screens get real observable parity rather than a permanent
  exemption. The Inspector must mark this exception for removal once `manifest.yaml` runs.
- **DEV-009** — resolved as a `fix`: the WordPress branding is dropped. Note the precise scope of
  this override, because it is the only place principle 2 is set aside: **branding and
  project-identity strings only.** Every functional label, prompt, validation message and error
  string is still preserved verbatim.
- **DEV-011** — resolved as **themes yes, plugins no**. Two screens gained a real backing model, two
  were struck. Importantly, this does **not** reopen AD-01: a theme is data plus template files, not
  code that hooks into the core, so no extension registry is reintroduced.
- ⚠️ **DEV-007 — REJECTED.** This is the consequential one. The deviation asked to place the editing
  experience outside parity because its source is unreadable *from this checkout*; the owner ruled
  that the editor must be on par. **DEV-012 replaces it**, and it does not record an exemption — it
  records a change of method. The editor becomes the only part of this migration specified by
  *observing a running oracle* rather than by reading extracted rules, because the extraction
  contains none of it.

**What DEV-012 costs, in one line**: the largest work item in the project, a Wave 4 parity gate that
is now maximally scoped, and a carve-out from the `rails-hotwire` target for three screens that
almost certainly need a React island.

**A lesson for the `php-server-rendered` → `rails-hotwire` adapter in v2**: a front controller per
URL over-counts screens. Of 144 inventoried, roughly 92 are two patterns repeated, 11 have no target
at all, and 3 are aliases or internals. An adapter for this pair should cluster by `WP_List_Table`
subclass and by `edit-form-*.php` include before counting, rather than treating one file as one
screen.

---

### Wave 5 verification — two post-landing corrections (2026-08-23)

- **DEV-013 — tenancy signup/confirm strings restored to verbatim.** The Wave 5 build
  first shipped `app/views/tenancy/signups/confirm.html.erb` with invented copy
  ("Congratulations! Your account is almost ready." / "before you can start using it").
  These are not among the 25 golden screens, so the parity harness could not catch them;
  an adversarial verifier did. The view now reproduces both legacy branches verbatim from
  `wp-signup.php`: `confirm_user_signup()` (`%s is your new username` …) and
  `confirm_blog_signup()` (`Congratulations! Your new site, %s, is almost ready.` … plus
  the "Still waiting for your email?" tips block). The controller recovers the signup by
  its `activation_key` to pick the correct branch.

- **BR-MS-04 per-site role ENFORCEMENT wired (was assignment-only).** The signup path
  already scoped an `administrator` role to the newly created site
  (`role_assignments.site_id`), but `Access::BasePolicy#actor_roles` read only
  `site_id: nil` rows, so a per-site role was never *enforced*. It now consults
  `Tenancy.current_site` — mirroring the existing `Tenancy.super_admin?` edge on the same
  line (Access already depends on Tenancy; Tenancy never depends on Access, so no cycle).
  **Strictly additive:** on a single site `Tenancy.current_site` is nil, so it resolves to
  `actor.roles(site_id: nil)` — byte-identical to Waves 0–4, proven by the 25/25 parity run
  and `spec/tenancy/per_site_role_enforcement_spec.rb` (which also asserts a stray
  site-scoped role does NOT leak into single-site evaluation, and that a site-A role grants
  capabilities only while site A is the served tenant).

---

### DEV-012 / D-3 — the React island is built (2026-08-24)

The block editor React island (D-3) is **implemented and verified** for the post/page
editor — `console.post` and `console.post-new`.

**What was built**
- `app/models/composition/serializer.rb` — the exact inverse of `Composition::Parser`
  (ports `serialize_block`/`serialize_block_attributes`/`get_comment_delimited_block_content`
  from wp-includes/blocks.php). Proven to round-trip all 22 corpus post bodies
  **byte-identically** (`spec/models/composition/serializer_spec.rb`).
- Blocks JSON API on `Console::PostsController` — `GET /console/posts/:id/blocks` hands the
  parsed tree to the client; `PATCH` accepts a JSON block tree and serializes it
  **server-side** through the one verified grammar, then runs the same Publishing::Post
  commands the noscript form does (`spec/requests/console/editor_blocks_api_spec.rb`).
- The React island itself — `app/frontend/editor/*` (React 18, esbuild → `app/assets/builds/
  editor.js`, served by propshaft; `bin/build_editor.mjs`). A genuine block editor: live
  contenteditable text blocks, recursive container blocks, honest labelled previews for
  dynamic/server-rendered blocks, a grouped inserter, a block toolbar, and an inspector.
  Progressive enhancement: the island hides the noscript `<form>`, which still works without
  JS.
- Behavioural proof (DEV-012's contract — verify by observation, no golden files):
  `editor_e2e/interaction.mjs` drives the real island in Chromium — sign in, edit the title
  and a paragraph, insert a Heading through the palette, publish — then reads the blocks API
  back and asserts the server serialized and stored the edited tree. Passes.

**Still a shell (not this pass): `console.site-editor`.** The Site Editor's template browser
and Global Styles surface is a distinct, larger island over `Composition::Template` and the
theme.json cascade; it remains the read-only shell. D-3 is resolved for the post/page editor;
the Site Editor island is the remaining forward item.

---

### DEV-014 — the console adopts wp-admin's skin (REVERSES part of the modernization ruling)

| Field | Value |
|---|---|
| Affected screen | all `console.*` |
| Type | `platform` — reverses a prior approval |
| Approved by | thies (owner) |
| Approved at | 2026-08-24 |

**What changed.** `screen_modernization_decision.md` (approved 2026-08-21) put the console in
**modernized** mode, and its design-system row said plainly: *"Modernized `console.*` screens
must **not** inherit the eight admin colour schemes."* The owner has since instructed
"make the admin work identical to the original", then set "pixel perfect" as a standing goal.
This deviation records the reversal rather than letting the code drift from the decision log.

**Scope of the reversal — the SKIN only.** The semantic contract is unchanged: literal strings
stay verbatim, and no golden files are introduced for the console. What changes is that the
console now renders in wp-admin's visual design system instead of its own.

**How the values were obtained.** Not copied from wp-admin's SCSS and not guessed:
`editor_e2e/measure_wpadmin.mjs` reads the **computed styles** off the live oracle and prints
them, and the skin is written from that output. WordPress 7.2-alpha ships a refreshed palette,
so the values differ from the well-known older ones: accent `#3858E9` (not `#0073AA`), chrome
`#1E1E1E` (not `#23282D`), submenu `#0C0C0C`. Dashicons are the oracle's own font file
(`wp-includes/fonts/dashicons.woff2`), trimmed to the twelve glyphs the menu uses.

**What is deliberately NOT reproduced, and why it is not a gap:**

| Absent | Ruling |
|---|---|
| The WordPress logo, the "About WordPress" menu, the W favicon | DEV-009 — project identity is dropped |
| The Plugins menu item | AD-01 — there is no extension system to manage |
| Screen Options / Help tabs | DEV-002 — hook-registered UI; nothing registers into them |
| The eight per-user admin colour schemes (`admin_color`) | DEV-005 stands — this is the default *fresh* scheme only, which is what the oracle serves |
| Collapse Menu, the avatar, the admin-bar search | Chrome with no rebuild surface behind it |

**Found while doing this** — a genuine functional gap, not styling: the Posts list was missing
wp-admin's **Sticky** view (`class-wp-posts-list-table.php:112-125`, `:398-415`). It is now
built, including the `show_sticky=1` filter arm, and the status tabs match the oracle
label-for-label and count-for-count.
