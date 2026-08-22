---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: topology_decision
producedBy: designer
hash: "sha256:22f7850c57bcda4bfdd9e5fcfe343fe84de3bc3ff67236671fa6293c5d41b6ad"
---

# Topology Decision

> A conscious decision about how to organize the new system: preserve the legacy topology, adopt a
> modern one, or apply a hybrid.
> This artifact is required reading for the Designer itself (to decompose bounded contexts) and for
> the coding agent (to create the folder tree).
> Required reading before this: `paradigm_decision.md`, then `migration_strategy.md`.

## Detected legacy topology

- **Organizational pattern**: **hybrid** — a **flat, file-per-subject procedural library**
  (`wp-includes/`) plus a **screen-per-file front controller** admin (`wp-admin/`), with a newer
  **package-by-component** layer for subsystems added since roughly 2016.
- **Confidence**: 🟢 CONFIRMED

- **Evidence**:
  - **There is no module boundary in the filesystem at all.** Reversa's 44 "modules" are *analytical*
    constructs recovered by the Archaeologist; they do not correspond to directories. The unit of
    organization in the legacy core is **the file**, named after its subject: `post.php` (298 KB),
    `formatting.php` (350 KB), `taxonomy.php`, `comment.php`, `user.php`. Source: `inventory.md` §2
    and §3, `.reversa/context/modules.json`.
  - **257 PHP files sit flat in `wp-includes/`**, against 802 inside subdirectories — and most of
    those subdirectories are **vendored libraries** (`PHPMailer/`, `Requests/`, `SimplePie/`,
    `sodium_compat/`, `php-ai-client/`, `ID3/`, `IXR/`, `Text/`, `pomo/`) or asset folders
    (`js/`, `css/`, `build/`, `images/`, `fonts/`, `assets/`, `certificates/`). Source: filesystem,
    `dependencies.md` §3.
  - **A genuine package-by-component layer exists, and it is the recent work**: `html-api/`,
    `style-engine/`, `blocks/`, `block-supports/`, `block-bindings/`, `block-patterns/`,
    `interactivity-api/`, `rest-api/`, `sitemaps/`, `abilities-api/`, `ai-client/`, `customize/`,
    `widgets/`, `l10n/`. WordPress has been incrementally adopting per-component directories for a
    decade; the flat core is what predates that. 🟢
  - **`wp-admin/` is a front controller per URL**: 95 root PHP files, each one an admin screen
    reached by its own filename (`edit.php`, `options-general.php`, `plugins.php`), plus 106 in
    `includes/` and 40 under `network/` and `user/`. Source: `inventory.md` §3.
  - **Filenames are public API**, which is why this shape is frozen: ADR-002 records never breaking
    backward compatibility, and `architecture.md` §3.6 records five drop-ins that replace whole
    subsystems **by filename**, with no interface validation (F-BOOT-03).
  - **There is no autoloader.** `wp-settings.php` executes **311 explicit `require` statements**, and
    plugins depend on the exact line position of each global instantiation, making boot order itself
    a public contract (F-BOOT-01, TD-15, `dependencies.md` §7).

- **Map of the legacy tree** (summarized):
  ```
  /
  ├── index.php  wp-load.php  wp-settings.php  wp-blog-header.php   front controllers + 311-require boot
  ├── wp-login.php  xmlrpc.php  wp-cron.php  wp-comments-post.php   one entry point per protocol
  ├── wp-admin/                                    the admin application
  │   ├── *.php               (95)   one file = one admin screen = one URL
  │   ├── includes/           (106)  shared admin helpers, also flat
  │   └── network/ user/      (40)   the same pattern, re-scoped
  ├── wp-includes/                                 the core library
  │   ├── *.php               (257)  FLAT, file-per-subject: post.php, formatting.php,
  │   │                              functions.php, taxonomy.php, comment.php, user.php …
  │   ├── html-api/  style-engine/  blocks/  block-supports/  rest-api/
  │   │   sitemaps/  interactivity-api/  abilities-api/  customize/  widgets/
  │   │                              package-by-component — the modern additions
  │   └── PHPMailer/  Requests/  SimplePie/  sodium_compat/  php-ai-client/ …
  │                                  vendored, ~350 files ≈ 18% of the PHP
  └── wp-content/                                  user extension space (themes, plugins, uploads)
  ```

  **The shape in one sentence:** organization is by *subject inside a filename*, not by boundary —
  so a module exists only as a naming convention, and nothing in the tree can enforce it.

## Structural diagnosis

- **Coupling**: **high**. 23 of 44 modules form a single strongly connected component in which every
  module can reach every other (F-SIM-01). `hooks-plugin-api` alone has 32 direct dependents — more
  than double any other module (F-SIM-02). Blast radius saturates at 37 for every module inside the
  component, which makes the metric uninformative there: everything reaches everything.
- **Cohesion per module**: **low in the core, high in the newest components** — a genuine split
  rather than a uniform verdict.
  - Low: `post.php` is 298 KB serving **16 unrelated post types through one code path** (F-POST-01,
    F-POST-07); `formatting.php` at 350 KB and `functions.php` at 290 KB are subject-grab-bags;
    `class-wp-customize-manager.php` at 198 KB and `class-wp-theme-json.php` at 216 KB are
    god-objects (F-CUST-03, F-QUERY-07, F-DB-01).
  - High: `html-api/` and `style-engine/` have **zero internal dependencies and few dependents** —
    `spec-impact-matrix.md` §3 names them the only genuinely extractable components in WordPress,
    and `paradigm_decision.md` records `style-engine` as having single responsibility per class, no
    globals and no hooks in the hot path.
- **Orphaned / dead modules**: none truly dead, but three are structurally detached —
  **`xmlrpc`** (78 methods, **zero dependents**; F-SIM-04 records that nothing in WordPress requires
  it), **`deprecated-compat`** (9,112 lines existing solely for backward compatibility), and
  `class-snoopy.php` (a deprecated HTTP client still shipped, carrying a network surface;
  `dependencies.md` §8). All three are **already out of scope** per `migration_brief.md`.
- **Redundant layers**: **two clear cases.** Four overlapping settings surfaces — Customizer,
  widgets, nav menus and the Site Editor — all maintained simultaneously (TD-10, F-CUST-04). Two
  complete asset systems — classic handles and script modules — with **no shared abstraction**
  (TD-12, F-ASSET-04).
- **Boundary violations**: **structural, and by design.** `architecture.md` §2 states it directly:
  *"The layering is descriptive, not enforced. Nothing prevents a Layer-0 module from calling a
  Layer-5 one."* Five drop-ins replace the database, object cache, page cache, network bootstrap and
  error handler **by filename with no interface validation** (F-BOOT-03), and 35 security functions
  are replaceable purely by definition order (ADR-005). There is no mechanism anywhere in the system
  that can reject a dependency.
- **Mixed paradigms/styles**: **four coexisting styles**, per `paradigm_decision.md` — dominant
  procedural over process-wide globals; a synchronous observer layer (565 actions, 1,638 filters
  across 3,371 dispatch sites); classic-OO god-object islands; and exactly one declarative subsystem
  (`theme.json` and its four-origin cascade, F-GS-01).
- **Overall assessment**: **problematic** — with one qualification that matters.

  > **The qualification.** This structure is not the result of neglect. `architecture.md` §6.3 lists
  > the four largest structural items as *"by design, documented for completeness"*, each traced to
  > an ADR: no autoloader because boot order is a public contract (ADR-001); 9,112 lines of
  > deprecation because never breaking compatibility is *"the decision that made WordPress
  > ubiquitous"* (ADR-002); permissive SQL mode because the draft date representation requires it
  > (ADR-007). The topology is a coherent answer to a constraint the rebuild **does not have** —
  > install by unzipping onto shared hosting with no shell, no Composer and no Node
  > (`dependencies.md` §1).
  >
  > So the diagnosis is not "WordPress got this wrong". It is: **every reason this topology exists
  > was deleted by `migration_brief.md`'s "no compatibility burden" constraint.** Preserving it would
  > mean inheriting the costs of a decision after discarding its benefits.

## Proposed modern topology

- **Pattern**: **modular monolith — one Rails application, organized into statically-enforced
  packages (Packwerk-style `packs/`), with the conventional Rails layout preserved *inside* each
  pack.**

- **Rationale**:

  The proposal follows from one observation. The legacy's defining structural defect is not that it
  has a cycle — it is that **nothing could have prevented the cycle**. `architecture.md` §2 says the
  layering is descriptive and unenforceable; F-BOOT-03 says subsystems are swapped by filename with
  no interface validation. The 23-module component (F-SIM-01) is the predictable outcome of a
  system where dependency direction is a convention rather than a declaration.

  A plain Rails application has **exactly the same property**. `app/models/` imposes no direction:
  any model may reference any other, and with ~40 models carrying 363 rules the cycle re-forms — not
  from team pressure, which a solo project does not have, but from ordinary convenience. Choosing
  standard Rails MVC here would be choosing the legacy's one unrecoverable structural property while
  believing the paradigm change had addressed it.

  A `packs/` topology makes dependency direction a **declared, statically-checkable fact**: each
  pack states what it may depend on, and a violation fails CI rather than being discovered by a
  Tarjan run three years later. That is precisely the guarantee the legacy could not offer.

  Three secondary reasons reinforce it:

  - **It keeps the Rails idiom intact**, which is the paradigm the owner chose. Inside a pack the
    layout is ordinary Rails — `app/models`, `app/controllers`, `app/jobs` — so ActiveRecord,
    validations, callbacks, policies and migrations all work conventionally.
    `paradigm_decision.md` explicitly weighed and **rejected** Hanami/dry-rb precisely because
    fighting the framework's defaults costs the ecosystem. A pack boundary does not fight Rails; it
    sits above it.
  - **It matches the chosen strategy.** `migration_strategy.md` selected Strangler Fig with **deep
    boundaries**, delivered in six waves gated by parity. A pack's dependency declaration *is* the
    deep boundary, and a wave is a set of packs whose declarations are satisfied. The two decisions
    fit without adaptation.
  - **It is cheaper than Rails engines**, the obvious alternative. Engines carry per-unit routing,
    initializer and asset overhead and are built for *distributable* units; here there is one
    application and one deployment, so that overhead buys nothing.

- **Concrete expected gains**:
  - **The 23-module cycle cannot re-form silently.** A dependency that would close a loop is a CI
    failure, not a discovery. This directly answers the primary risk in `migration_brief.md`.
  - **Each wave becomes independently verifiable.** A pack with declared, satisfied dependencies can
    be parity-tested against the oracle without booting the surfaces above it — which is what makes
    the wave gates in `migration_strategy.md` mean anything.
  - **The leaf libraries stay leaves.** `markup` (the `html-api` port) and `styling` (the
    `style-engine` port) enter as zero-dependency packs and are *held* there by declaration —
    preserving the one structural property the legacy got right (F-SIM-03).
  - **Cohesion is forced at design time.** `post.php`'s 16 post types cannot recur as one 298 KB
    unit, because a pack that needs six unrelated inbound dependencies to justify itself announces
    its own incoherence.
  - **Onboarding reads the tree instead of the history.** A newcomer sees boundaries and directions;
    in the legacy, both live in `spec-impact-matrix.md` rather than in the code.

- **Cost / risk**:
  - **Packwerk enforces statically, not at runtime.** It is a checker with an ignore list; discipline
    and CI are still load-bearing. It is a weaker guarantee than a compiler and should not be sold as
    a strong one.
  - **A real dependency decision.** Adopting Packwerk means depending on its continued maintenance.
    The fallback — plain namespaced modules plus a custom CI dependency check — is perfectly viable
    and preserves the topology; only the tooling changes.
  - **Learning curve.** Declared dependencies and pack boundaries are unfamiliar to a team that
    knows conventional Rails, and `migration_brief.md` records **no team at all** — one owner, whose
    Rails proficiency is unstated (RISK-011).
  - **⚠️ Over-decomposition is the live failure mode here.** With a bus factor of one, 20+ packs is
    ceremony with no organizational payoff. Pack boundaries pay for themselves by preventing cycles,
    not by dividing ownership — so the count should start **coarse** and split only under evidence.
    The tree below therefore proposes **9 top-level packs**, not one per legacy module.
  - **Boundaries drawn early are drawn with the least information.** Mitigated by the strategy's own
    sequencing: `migration_strategy.md` places the cheapest reversal window before Wave 3.

- **Sketch of the proposed tree**:
  ```
  app/                     deliberately thin — only genuinely global concerns
  config/
  lib/
  packs/
    markup/                HTML parsing and serialization        ← html-api      [leaf, 0 deps]
    sanitizing/            allowlist filtering + text transforms ← kses+formatting [leaf, 0 deps]
    styling/               style generation, tokens, cascade     ← style-engine + global-styles
    configuration/         settings, feature values, caching     ← options-and-transients
    identity/              users, roles, sessions, credentials   ← users + auth-and-sessions
    publishing/            content records, revisions, metadata  ← posts + metadata
    classification/        hierarchical + flat classification    ← taxonomy-and-terms
    discussion/            threaded discussion + moderation      ← comments
    library/               binary assets and their derivatives   ← media-and-attachments
    access/                authorization policy                  ← map_meta_cap successor
    retrieval/             query objects, scopes, pagination     ← query-and-loop
    routing/               permalinks, slugs, request mapping    ← rewrite-and-permalinks
    composition/           block parsing + rendering             ← block-* + blocks-library
    presentation/          templates, theme resolution, assets   ← themes + script-assets
    syndication/           feeds, sitemaps, embeds               ← feeds + sitemaps + oembed
    public_api/            HTTP API surface                      ← rest-api
    console/               administration UI                     ← admin-application + customizer
    scheduling/            deferred and recurring work           ← cron
    outbound/              outbound HTTP, SSRF policy            ← http-api
    tenancy/               multi-site isolation                  ← multisite
  ```
  ```
  packs/publishing/        every pack is an ordinary Rails app inside
    package.yml            ← the declaration: what this pack may depend on
    app/models/
    app/jobs/
    app/services/
    spec/
  ```

  > **Two notes on the sketch.** The names deliberately **do not reuse legacy file or module
  > names** — `publishing` rather than `posts`, `classification` rather than `taxonomy`,
  > `discussion` rather than `comments`. That is not cosmetic: naming a context after what it *is*
  > rather than where it *came from* is what prevents the 1-to-1 decomposition this agent is
  > forbidden to produce, and it forces the question "what belongs here?" to be answered on
  > invariants rather than on file provenance.
  >
  > The list above is **illustrative of the shape, not the final decomposition**. Which packs exist,
  > and which of them merge, is decided in the Designer's Phase 2 step 8 from invariant cohesion,
  > transaction boundaries and rate of change. The **topology** — one Rails app, packs with declared
  > and enforced dependencies, conventional Rails inside each — is what this document decides.

## Options presented to the user

### 1. Preserve the legacy topology (conservative)

Reproduce the legacy shape in Ruby: a flat library of subject-named modules (`lib/post.rb`,
`lib/formatting.rb`, `lib/taxonomy.rb`) plus one controller per admin screen, with no enforced
boundaries.

- **Consequences**:
  - **The one honest argument in its favour is traceability.** A 1:1 legacy→target mapping makes
    parity diffing trivially navigable, and with the oracle as the only source of truth (RISK-001),
    "which file does this diff come from?" is a question that gets asked constantly.
  - Perpetuates every structural finding: the 23-module cycle re-forms by construction, the
    god-files return, dependency direction stays unenforceable.
  - Actively fights the chosen paradigm. `paradigm_decision.md` option 1 puts invariants in models
    and authorization in policy objects; a flat subject-named library has nowhere to put either.
  - ⚠️ **It inherits the costs of ADR-001, ADR-002 and ADR-007 after the brief has deleted their
    benefits.** There is no shared-hosting constraint, no compatibility contract and no boot-order
    API in the target.

### 2. Adopt the proposed modern topology (transformational)

One Rails application, `packs/` with statically-declared and CI-enforced dependencies, conventional
Rails layout inside each pack.

- **Consequences**:
  - The primary risk in `migration_brief.md` — the 23-module cycle — becomes **structurally
    preventable** rather than merely absent at the start.
  - Wave boundaries and pack boundaries coincide, so `migration_strategy.md`'s parity gates have
    something concrete to gate.
  - Requires learning declared dependencies, and adds Packwerk (or a hand-rolled CI check) to the
    stack.
  - ⚠️ Carries the over-decomposition risk described above; the mitigation is starting coarse.

### 3. Hybrid (balanced)

Conventional Rails (`app/models`, `app/controllers`) for the content core, with `packs/` used **only
for the leaf libraries that are genuinely libraries** — `markup`, `sanitizing`, `styling`.

- **Consequences, per boundary**:
  - **Modernized**: `markup`, `sanitizing`, `styling`. These are the boundaries the legacy *already*
    got right — F-SIM-03 names `html-api` and `style-engine` as the only genuinely extractable
    components — so packaging them costs nothing and preserves a real property.
  - **Preserved (conventional Rails)**: publishing, classification, discussion, identity, access,
    retrieval, routing, and every surface above them. These live in one `app/` with no declared
    directions.
  - **The trade this makes**: lowest friction for a single developer, full Rails conventionality,
    nothing new to learn for 90% of the code — at the cost of leaving the **content core**, which is
    exactly where the legacy cycle lived, without any enforceable boundary. The leaf packs protect
    the parts that were never the problem.
  - **Genuinely defensible**, and it is the right answer if pack boundaries turn out to cost more
    argument than they prevent.

## The Designer's recommendation

**Option 2**, with one reservation stated plainly.

The reasoning is a single line of evidence: the legacy's unrecoverable structural property was that
**dependency direction could not be declared**, and plain Rails shares that property. Options 1 and
3 both leave the content core — where the 23-module cycle actually lived — governed by convention
alone. Option 2 is the only one that changes the property rather than the naming.

**The reservation**: option 2's cost is paid in *judgement*, not in code, and `migration_brief.md`
records a single person to pay it (RISK-011). If pack boundaries are still being re-argued after
Wave 1 completes, that is the signal to collapse to option 3 rather than to keep litigating — the
leaf packs are the part that carries its weight unconditionally.

**Where this decision is cheapest to revisit**: before Wave 3. `migration_strategy.md` places the
last low-cost reversal window there, and this decision is upstream of the 16-post-types modelling
fork (RISK-003) that Phase 2 must resolve.

## The user's decision

- **Choice**: **3 — Hybrid.** Conventional Rails for the content core; `packs/` only for the leaf
  libraries `markup`, `sanitizing` and `styling`.
- **The user's rationale**: selected with the tree preview showing the content core as an ordinary
  `app/models` with no declared directions, and packs protecting only the three boundaries the
  legacy already got right — *"protects the parts that were never the problem"*.
- **Decided at**: 2026-08-21
- **Recommendation carried**: the Designer recommended option 2. The choice is recorded as made;
  what follows applies option 3 in full rather than partially.

### What option 3 settles

- **One Rails application, conventional layout.** `app/models`, `app/controllers`, `app/views`,
  `app/jobs`. Nothing to learn beyond Rails itself for the great majority of the code.
- **Three packs, and only three**: `markup` (the `html-api` port), `sanitizing` (kses + formatting),
  `styling` (style-engine + global styles + block supports). Each enters with **zero declared
  dependencies** and is held there by CI. These are the boundaries F-SIM-03 identifies as the only
  genuinely extractable components in WordPress, so the packaging preserves an existing property
  rather than inventing one.
- **Bounded contexts survive as Ruby namespaces, not as packs.** The contexts named in the mapping
  table below are expressed as namespaced models inside the conventional tree —
  `app/models/publishing/post.rb` → `Publishing::Post`. This keeps the context names meaningful and
  the decomposition non-1-to-1, which the Designer's absolute rules require, without pack ceremony.
- **The three packs are the CI boundary; the namespaces are a convention.** That distinction is real
  and should not be blurred: a namespace can be crossed silently, a pack boundary cannot.

### What option 3 does not settle, stated plainly

The content core — `publishing`, `classification`, `discussion`, `identity`, `access`, `retrieval`,
`routing` — lives in one `app/` with **no enforceable dependency direction**. That is exactly the
region where the 23-module cycle lived in the legacy, and the property that allowed it
(`architecture.md` §2: *"the layering is descriptive, not enforced"*) is carried into the target for
those contexts.

This is a recorded consequence of the decision, not an argument against it. The decision stands. What
follows from it is that **cycle prevention is replaced by cycle detection**, which is a weaker but
real control:

> **Mitigation adopted under option 3 — detection instead of prevention.** A CI job runs a
> dependency-cycle check over the `app/models/<context>/` namespaces on every build: it parses
> constant references between namespaces, builds the graph and fails if it is not acyclic. This is
> perhaps thirty lines of Ruby using the existing constant table — no Packwerk, no `package.yml`, no
> per-pack configuration, and nothing to learn. It does not *prevent* a cross-namespace reference the
> way a pack boundary does, but it makes the one outcome that matters — a **cycle** — impossible to
> introduce unnoticed.
>
> This is the cheapest available answer to `migration_brief.md`'s primary risk under the chosen
> topology, and it preserves the property the owner said they were protecting: no ceremony in the
> core. Recorded as the mitigation for **RISK-017**.

**The condition that would justify revisiting this**: if the cycle check starts failing regularly and
the fixes are consistently "add another cross-namespace reference and move on", the namespaces are
not holding and the content core wants real boundaries. `migration_strategy.md` places the last cheap
reversal window before Wave 3.

## Legacy → new mapping

> **Applied for option 3, as chosen.** The first three rows (`markup`, `sanitizing`, `styling`)
> become **packs** under `packs/`, with declared and CI-enforced zero dependencies. Every other row
> becomes a **Ruby namespace** inside the conventional `app/` tree — `Publishing::Post`,
> `Classification::Term`, `Access::PostPolicy` — carrying the same logical boundary by convention
> rather than by enforcement.
>
> **No row is 1-to-1 by module name.** Every grouping is justified.

| Legacy module / folder | New bounded context | Type | Notes |
|---|---|---|---|
| `html-api` | **`markup`** 📦 pack | preserved | The cleanest boundary in core (F-SIM-03). Enters as a zero-dependency leaf and is held there by declaration. |
| `kses-security` + `formatting-and-sanitization` | **`sanitizing`** 📦 pack | merged | They call each other mutually in the legacy and cannot be separated (`spec-impact-matrix.md` §1). Together they form **one leaf** with nothing depending inward, so the mutual recursion stops being a cycle. ⚠️ The owner's override keeps both regex-based (RISK-005). |
| `style-engine` + `global-styles-theme-json` + `block-supports` | **`styling`** 📦 pack | merged | One responsibility — turning design data into CSS — currently split across three modules and a 216 KB god-object (F-GS-01, F-CUST-03). |
| `options-and-transients` | `configuration` | preserved (renamed) | The 150 KB autoload threshold becomes an explicit policy rather than a size heuristic (BR-OPT-06). |
| `users-roles-capabilities` + `authentication-and-sessions` | `identity` | merged | Sessions, credentials and role storage share invariants; session-token destruction already invalidates every outstanding nonce (BR-AUTH-15), so they fail together. |
| *(none — extracted)* | `access` | new | `map_meta_cap()`'s 870-line switch becomes policy objects. **Lifted out of both `identity` and `publishing`**, which is what breaks the users↔posts cycle: the policy depends on both models; neither model depends on the other's authorization code. |
| `posts-and-post-types` + `metadata` | `publishing` | merged | Metadata is not a domain of its own — one code path serves five entity types (F-META-01). It belongs to whatever owns the record. ⚠️ The 16-post-types fork (RISK-003) is resolved in Phase 2, not here. |
| `taxonomy-and-terms` | `classification` | preserved (renamed) | Retains the surviving one-directional edge to `publishing`: term counts read `post_status = 'publish'` (BR-TAX-11), becoming a counter cache. |
| `comments` | `discussion` | preserved (renamed) | Already outside the 23-module component (blast radius 5). One of the few legacy modules with a real boundary. |
| `media-and-attachments` | `library` | preserved (renamed) | Attachments stop being a post type at the storage layer regardless of the STI fork; Active Storage owns the binaries. |
| `query-and-loop` | `retrieval` | preserved (renamed) | `WP_Query`'s 4,900-line god-object (F-QUERY-07) becomes scopes and query objects. |
| `rewrite-and-permalinks` | `routing` | preserved (renamed) | ⚠️ Keeps the **genuine** surviving coupling: `pagination_base` and `$wp_rewrite->feeds` determine which slugs are legal (BR-POST-07, F-RW-06). This must be modelled deliberately, not inherited. |
| `block-editor` + `blocks-library` + `block-bindings` + `block-patterns` | `composition` | merged | Server-side block parsing and rendering. ⚠️ The **client** ships only as build output (TD-19, Q6), so its scope is a product decision, not a migration (RISK-010). |
| `themes-and-templates` + `script-modules-and-assets` + `interactivity-api` | `presentation` | merged | Collapses the **two complete asset systems** the legacy maintains with no shared abstraction (TD-12, F-ASSET-04). |
| `feeds` + `sitemaps` + `embeds-oembed` | `syndication` | merged | All three are terminal modules with zero dependents (F-SIM-06) producing machine-readable views of published content. Delivered together as Wave 1. |
| `rest-api` | `public_api` | preserved (renamed) | ⚠️ Carries override `BR-REST-05`: a route with no policy is **public**. `access` must make that reachable only by explicit declaration, never by omission (RISK-004). |
| `admin-application` + `customizer` + `widgets-and-nav-menus` | `console` | merged | Directly collapses the **four overlapping settings surfaces** of TD-10 / F-CUST-04. Scope set by the Screen Translator. |
| `cron` | `scheduling` | preserved (renamed) | Becomes a real queue (Solid Queue / Sidekiq). Q7 and Q8 already assume a real scheduler and a persistent cache. |
| `http-api` | `outbound` | preserved (renamed) | ⚠️ Carries deviation `BR-HTTP-01`: SSRF validation becomes **default-on** with an explicit unsafe escape hatch. |
| `multisite` | `tenancy` | preserved (renamed) | PostgreSQL schema-per-site via `search_path` (BR-MS-01). Sequenced **last** (Wave 5, post-launch) — RISK-009. |
| `bootstrap-and-load`, `error-handling-and-recovery-mode`, `hooks-plugin-api`, `database-wpdb`, `cache-and-object-cache`, `internationalization`, `filesystem-api`, `updates-and-upgrader`, `site-health`, `performance-speculation-view-transitions` | *(absorbed by the framework)* | removed | Rails owns boot, error handling, the connection layer, caching, i18n, file handling and deployment. `hooks-plugin-api` is discarded outright — see `discard_log.md`, 15 rules under implication 2. |
| `deprecated-compat`, `xmlrpc` | *(discarded)* | removed | Out of declared scope per `migration_brief.md`. |
| `ai-abilities-connectors` | `ai` | preserved (renamed) | Terminal module, zero dependents. Wave 5. |
| *(none — new)* | `parity` (test-only) | new | Not application code: the diff harness and the oracle corpus. It has no place in the legacy tree because the legacy has **no tests at all** (TD-18), and it is load-bearing for every wave gate. |

## Pending implications for the Designer's next steps

| Designer step | Implication | How to honor it |
|---|---|---|
| **Bounded contexts** (step 8) | ⚠️ **Option 3 chosen.** Contexts are Ruby namespaces in one `app/`, not packs — except `markup`, `sanitizing`, `styling`. The list is a **shape**, not a decomposition; deriving contexts from the legacy module list would be the forbidden 1-to-1 mapping wearing new names. | Re-derive every boundary from **invariant cohesion, transaction boundary and rate of change**, per the skill's own criteria — then reconcile against the table above and *justify any difference*. Expect fewer contexts than the 21 sketched; merging is the likelier correction, given RISK-011. |
| **Bounded contexts** (step 8) | `access` is the load-bearing extraction. It is what converts the surviving users↔posts cycle into a DAG. | It must depend on `identity` and `publishing`; **nothing may depend on `access`** except surfaces. Encode that as a declaration, not a convention — it is the single most important edge direction in the design. |
| **`target_architecture`** (step 9) | The mandatory *Fidelity to the chosen topology* section must show the **final** tree under option 3, and the *Fidelity to the chosen paradigm* section must discharge all six implications from `paradigm_decision.md`. | Show the three packs with zero declared dependencies, and show the **intended** namespace dependency graph for the core as an acyclic diagram. Under option 3 that graph is a *design intent* enforced by the RISK-017 cycle check, not by declarations — say so explicitly rather than implying a guarantee the topology does not provide. |
| **`target_architecture`** (step 9) | Strategy A's waves and the context graph must agree. | Every wave in `migration_strategy.md` must be a set of contexts whose dependencies are already satisfied by earlier waves. Wave 0 must additionally carry the two leaf packs and the cycle check. If a wave needs a context from a later wave, one of the two is wrong — **and the context graph is the more trustworthy of the two**. |
| **`target_domain_model`** (step 10) | ⚠️ **The 16-post-types fork (RISK-003) is Phase 2's largest decision** — `paradigm_decision.md` implication 5 calls it the single largest modelling decision in the rebuild. This document does **not** pre-empt it: `publishing` is one pack under either answer. | Decide single-table inheritance versus separate models explicitly, defend it, and prototype against the three hardest types — attachments, revisions, nav menu items — before committing. It is cheapest to reverse before Wave 3. |
| **`target_domain_model`** (step 10) | Implications 3 and 4: compensating transactions collapse into constraints; derived state moves into the model. | Every discarded mechanism in `discard_log.md` must name the **invariant** that replaces it. `BR-POST-01`'s 60-second publish threshold is confirmed intended product behaviour and must appear as an explicit model rule, not an accident of a date comparison. |
| **`target_data_model`** (step 11) | Implication 3 again: express in the schema what the legacy enforced in PHP. | Unique indexes on term slug/parent/taxonomy and post slug per type; **foreign keys for all 18 relationships that currently have none** (F-DD-01); counter caches for term and comment counts; `meta_value` indexed, which the legacy left undone (TD-07). |
| **`target_data_model`** (step 11) | RISK-007: `0000-00-00 00:00:00` is not a valid PostgreSQL timestamp, and every draft carries it. | Decide the representation **once** (`NULL` is the recommendation), and state `NULLS LAST` ordering explicitly — MySQL and PostgreSQL disagree on the default. |
| **`target_data_model`** (step 11) | `tenancy` via `search_path` changes connection handling application-wide (RISK-009). | Design it as an **additive** concern that Wave 5 introduces to a stable system, not a column threaded through every table from the start. Reset `search_path` on connection **checkout**, not checkin. |
| **`data_migration_plan`** (step 12) | ⚠️ There is **no live deployment** (owner ruling, 2026-08-21). The ETL is not a production migration. | Write it as the **oracle corpus seeding pipeline**: MySQL reference instance → PostgreSQL, repeatable and idempotent, since it runs on every corpus refresh rather than once at a cutover. RISK-006's serialized-payload transcoding and RISK-007's date mapping live here. Its success criterion is *the corpus round-trips*, not *production cut over*. |

## Notes

### The adopted tree

```
app/
  models/
    publishing/          post.rb  revision.rb  metadatum.rb        → Publishing::Post
    classification/      term.rb  taxonomy.rb  assignment.rb       → Classification::Term
    discussion/          comment.rb  moderation_verdict.rb         → Discussion::Comment
    library/             asset.rb  variant.rb                      → Library::Asset
    identity/            user.rb  role.rb  session.rb              → Identity::User
    access/              post_policy.rb  comment_policy.rb  …      → Access::PostPolicy
    configuration/       setting.rb                                → Configuration::Setting
    retrieval/           post_query.rb  scopes/                    → Retrieval::PostQuery
    routing/             permalink.rb  slug.rb                     → Routing::Permalink
    composition/         block.rb  block_renderer.rb               → Composition::Block
    presentation/        template.rb  theme.rb  asset_bundle.rb    → Presentation::Template
    syndication/         feed.rb  sitemap.rb  embed.rb             → Syndication::Feed
  controllers/
    public_api/          the REST surface
    console/             administration UI
    …
  jobs/                  scheduling — the cron successor
  services/
    outbound/            outbound HTTP + SSRF policy

packs/                   the only CI-enforced boundaries
  markup/                ← html-api                     [0 declared deps]
    package.yml  app/  spec/
  sanitizing/            ← kses + formatting            [0 declared deps]
  styling/               ← style-engine + global-styles [0 declared deps]

spec/
  parity/                the diff harness + oracle corpus (test-only, no legacy origin)
```

**For the coding agent creating the folder tree**, three things this document decides and one it
deliberately does not:

1. **Decided: exactly three packs, and they declare zero dependencies.** `markup`, `sanitizing` and
   `styling` may not depend on anything in `app/`, and CI must enforce that. If a pack acquires a
   dependency on the content core, the boundary that made it worth packaging is gone. Everything
   *else* is conventional Rails — no `package.yml`, no declarations, no ceremony.

2. **Decided: contexts are namespaces in the core, and the namespace is a convention.** Name models
   `Publishing::Post`, not `Post`; `Classification::Term`, not `Term`. The namespace carries the
   boundary's *meaning*, and the cycle check (RISK-017) carries the only part of its
   *enforcement* that matters. Do not mistake one for the other.

3. **Decided: the cycle check ships in Wave 0**, alongside the first two packs. It is worth almost
   nothing added later, once the graph it was meant to keep acyclic already isn't. It is a CI job,
   not a framework.

4. **Not decided here: the contents of `publishing`.** Whether 16 post types become one STI model or
   several is Phase 2's call (RISK-003), and it does not change the topology — `Publishing` is one
   namespace under either answer. Do not read the tree above as having settled it.
