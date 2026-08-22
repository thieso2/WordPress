---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: target_domain_model
producedBy: designer
hash: "sha256:3a18a1b49cc97f52833a19e62494abdd6a86616d3a9768901d80b0d5e5d270af"
---

# Target Domain Model

> Domain model of the new system, with explicit traceability back to `_reversa_sdd/domain.md` and
> `target_business_rules.md`.
> Required reading before this: `paradigm_decision.md`, `topology_decision.md`,
> `target_architecture.md`.

> **A note on form.** The target paradigm is **classic OO / Active Record**, not DDD-with-DI and not
> event-driven. "Aggregate" below therefore means *a model that owns a consistency boundary and
> enforces it with validations, callbacks and database constraints* — not a persistence-ignorant
> aggregate behind a repository. `paradigm_decision.md` weighed the DI/repository alternative and
> rejected it. Consequently there is **no domain-event section with published messages**: state
> transitions are model behaviour, not messages. Where the legacy fired an action on a transition,
> the transition is recorded, not broadcast.

## Aggregates

### AGG-Post — `Publishing::Post`
- **Aggregate root**: `Publishing::Post` (STI over content types: `Article`, `Page`, + custom)
- **Owns**: `Publishing::Revision`, `Publishing::Attribute`, `Publishing::StatusTransition`
- **Invariants**:
  - A publish request whose `published_at` is **≥ 60 seconds** in the future becomes `scheduled`;
    one **< 60 seconds** away becomes `published`. The threshold is a named model rule, confirmed by
    the owner as intended product behaviour, not an implementation accident. (`BR-MIGRATE-029/030`)
  - Slugs are not allocated for `draft`, `pending` or `auto_draft`. (`BR-MIGRATE-032`)
  - A slug is unique within `(type, parent)` for hierarchical types and within `(type)` for flat
    ones — enforced by a **unique index**, not by a query loop. (`BR-MIGRATE-033`, AD-05)
  - A slug may not collide with a reserved route segment; `Routing::SlugAllocator` decides, because
    only `Routing` knows the reserved set. (`BR-MIGRATE-034`)
  - Slugs truncate to 200 bytes **inclusive of any numeric suffix**. (`BR-MIGRATE-035`)
  - Every status change is recorded as a `StatusTransition`. (`BR-MIGRATE-036`)
  - `trashed_at` and `status_before_trash` are set together or not at all — restoring returns the
    prior status. (legacy `_wp_trash_meta_*`, AD-03)
- **Accepted commands**: `create`, `update`, `publish`, `schedule`, `unpublish`, `trash`, `restore`,
  `delete`, `revise`
- **Legacy origin**: `domain.md § Content lifecycle`; `posts-and-post-types` + `metadata`
- ⚠️ **Deviation** `BR-MIGRATE-037`: `guid` was seeded from the permalink and never updated. The
  target generates a **UUID at creation**, immutable thereafter. A permalink-shaped identifier that
  silently goes stale is a defect, and the UUID is what the column always meant.

### AGG-Term — `Classification::Term`
- **Aggregate root**: `Classification::Term`
- **Owns**: `Classification::Assignment`
- **Invariants**:
  - Unique on `(taxonomy, parent, slug)` — a **unique index**, replacing `wp_insert_term()`'s
    insert-then-detect-duplicate-then-delete-own-rows loop. (AD-05, F-TAX-02)
  - The hierarchy is acyclic: a term may not be its own ancestor. The legacy needed a runtime cycle
    guard (BR-TAX-13) because nothing prevented it; here a **foreign key plus an ancestry check on
    save** does.
  - `count` reflects **published content only** and is maintained as a counter cache, not computed by
    joining to posts on every render. (`BR-MIGRATE-064` family; F-TAX-05)
- **Accepted commands**: `create`, `rename`, `reslug`, `reparent`, `merge`, `delete`
- **Legacy origin**: `domain.md § Classification`; `taxonomy-and-terms`
- **Note on the surviving edge**: this aggregate **reads** `Publishing` for its counter cache and
  `Publishing` never reads it. That single direction is what keeps the legacy posts↔taxonomy cycle
  from re-forming (`target_architecture.md` BC-02).

### AGG-Comment — `Discussion::Comment`
- **Aggregate root**: `Discussion::Comment`
- **Owns**: `Discussion::ModerationVerdict`
- **Invariants**:
  - A comment belongs to exactly one commentable record and, optionally, one parent comment in the
    same thread. Both are **foreign keys**; the legacy had neither. (F-DD-01)
  - Threading depth is bounded by the configured maximum.
  - `status` is a **state enum**, not a `varchar` — resolved at the Curator pause (`BR-CMT-12`).
  - A comment is admitted only after a `ModerationVerdict`; the verdict, not the comment, carries the
    reason.
- **Accepted commands**: `submit`, `approve`, `unapprove`, `mark_spam`, `trash`, `restore`, `delete`
- **Legacy origin**: `domain.md § Moderation`; `comments`
- ⚠️ **Three deviations**, each fixing a defect rather than reproducing it:
  - `BR-MIGRATE-*` / `BR-CMT-04`: the legacy flood verdict defaults to false, so **no rate limit is
    actually enforced**. The target enforces one (`Discussion::RateLimit`).
  - `BR-CMT-08`: keywords matched as unquoted **substrings** across six fields — "press" matching
    "WordPress". The target matches on **word boundaries**.
  - `BR-CMT-10`: whether a disallowed comment became `trash` or `spam` depended on
    `EMPTY_TRASH_DAYS`, a coupling to `bootstrap` that no one would predict. The target decouples
    them: disallowed comments are marked spam.

### AGG-Asset — `Library::Asset`
- **Aggregate root**: `Library::Asset`
- **Owns**: `Library::Variant`
- **Invariants**:
  - An asset has exactly one original blob and zero or more generated variants; variants are
    derivable and may be regenerated without data loss.
  - MIME type is determined from content, not from the filename extension alone.
  - Alt text is an attribute of the asset, not of the post that displays it.
- **Accepted commands**: `upload`, `attach`, `detach`, `regenerate_variants`, `delete`
- **Legacy origin**: `media-and-attachments`; legacy `post_type = 'attachment'`
- **Note**: this aggregate exists *because* AD-02 split it out of `wp_posts`. In the legacy its whole
  model lived in four `_wp_attachment*` / `_thumbnail_id` postmeta keys precisely because the post
  shape did not fit it.

### AGG-User — `Identity::User`
- **Aggregate root**: `Identity::User`
- **Owns**: `Identity::RoleAssignment`, `Identity::Session`, `Identity::ApplicationPassword`,
  `Identity::DataRequest`
- **Invariants**:
  - `login` and `email` are unique — **unique indexes**; the legacy has only non-unique `KEY`s on
    both.
  - Roles are **rows**, not a serialized `role => true` map in a meta table. (F-MS-04, BR-CAP-13)
  - Destroying a session invalidates every outstanding nonce issued under it — one invariant
    spanning what were two legacy modules. (`BR-MIGRATE-*` / BR-AUTH-15)
  - ⚠️ `$super_admins`-style configuration **cannot** outrank stored superuser status. The global was
    discarded at the Curator pause as a privilege-escalation vector (`BR-CAP-14`).
- **Accepted commands**: `register`, `authenticate`, `start_session`, `end_session`,
  `end_all_sessions`, `assign_role`, `revoke_role`, `request_data_export`, `request_erasure`
- **Legacy origin**: `domain.md § Identity`; `users-roles-capabilities` + `authentication-and-sessions`

### AGG-Setting — `Configuration::Setting`
- **Aggregate root**: `Configuration::Setting`
- **Invariants**:
  - `name` is unique (the legacy's one genuine unique index, preserved).
  - Value is typed `jsonb`, not an untyped serialized blob.
  - Load policy (`autoload`) is an **explicit attribute**, never a byte-size heuristic. (AD-06)
  - The routing table and the job queue **may not be stored here** — a structural rule, not a
    convention. (AD-06, F-DD-03)
- **Accepted commands**: `set`, `unset`, `set_load_policy`
- **Legacy origin**: `options-and-transients`
- ⚠️ **Deviation** `BR-OPT-04`: the legacy `update_option()` returns `false` for *unchanged*,
  indistinguishable from failure. Active Record's save semantics distinguish them.

### AGG-Menu — `Presentation::Menu`
- **Aggregate root**: `Presentation::Menu`
- **Owns**: `Presentation::MenuItem`
- **Invariants**:
  - Items form a tree within one menu; a real **foreign key** enforces membership.
  - An item targets exactly one of: a content record, a term, a custom URL. Not zero, not two.
- **Accepted commands**: `create`, `add_item`, `move_item`, `remove_item`, `delete`
- **Legacy origin**: `widgets-and-nav-menus`; legacy `post_type = 'nav_menu_item'`
- **Note**: 🔑 **the clearest single win in the model.** The legacy stores the entire menu-item model
  in nine `_menu_item_*` postmeta keys (BR-MENU-02), and maintains `_menu_item_orphaned` tombstones
  (BR-MENU-05) *solely* because there are no foreign keys to cascade (F-DD-01). Real columns plus one
  FK delete both the orphan problem and the machinery that worked around it.

### AGG-Permalink — `Routing::PermalinkStructure`
- **Aggregate root**: `Routing::PermalinkStructure`
- **Owns**: `Routing::ReservedSegment`, `Routing::Redirect`
- **Invariants**:
  - The reserved-segment set (pagination base, registered feed slugs, `embed`, date-archive
    segments) is **derived from the structure**, and slug allocation consults it. This is the
    genuine legacy coupling made explicit rather than inherited. (`BR-MIGRATE-034`, F-RW-06)
  - A slug change creates a `Redirect` from the old slug; the legacy did this via `_wp_old_slug`
    postmeta (AD-03).
  - The compiled route table is **derived state**, cached and rebuildable — never a stored setting.
    (AD-06)
- **Accepted commands**: `set_structure`, `recompile`, `allocate_slug`, `record_redirect`
- **Legacy origin**: `rewrite-and-permalinks`

## Entities

| Entity | Owning aggregate | Main attributes | Legacy origin |
|---|---|---|---|
| `Publishing::Revision` | AGG-Post | `post_id`, `author_id`, `title`, `content`, `excerpt`, `created_at` | legacy `post_type = 'revision'` — **split out** (AD-02) |
| `Publishing::Attribute` | AGG-Post | `post_id`, `key`, `value jsonb` | `postmeta`, minus every core-owned key (AD-03) |
| `Publishing::StatusTransition` | AGG-Post | `post_id`, `from`, `to`, `actor_id`, `occurred_at` | `transition_post_status` action, recorded rather than fired (AD-01) |
| `Classification::Taxonomy` | AGG-Term | `name`, `hierarchical`, `object_types` | `term_taxonomy.taxonomy`, promoted from a string column to a record |
| `Classification::Assignment` | AGG-Term | `term_id`, `classifiable_type`, `classifiable_id`, `position` | `term_relationships` |
| `Discussion::ModerationVerdict` | AGG-Comment | `comment_id`, `outcome`, `reason`, `decided_at` | `comment_approved` + the moderation option set |
| `Discussion::RateLimit` | AGG-Comment | `author_key`, `window_start`, `count` | **new** — `BR-CMT-04` deviation, the legacy enforces none |
| `Library::Variant` | AGG-Asset | `asset_id`, `size_name`, `width`, `height`, `blob` | `_wp_attachment_metadata['sizes']` |
| `Identity::RoleAssignment` | AGG-User | `user_id`, `role`, `site_id` | `usermeta['{prefix}capabilities']` serialized map (F-MS-04) |
| `Identity::Session` | AGG-User | `user_id`, `token_digest`, `expires_at`, `ip`, `ua` | `usermeta['session_tokens']` |
| `Identity::ApplicationPassword` | AGG-User | `user_id`, `name`, `digest`, `last_used_at` | `authentication-and-sessions` |
| `Identity::DataRequest` | AGG-User | `user_id`, `kind`, `status`, `confirmed_at` | legacy `post_type = 'user_request'` — **split out** (AD-02) |
| `Presentation::MenuItem` | AGG-Menu | `menu_id`, `parent_id`, `position`, `target_type`, `target_id`, `url`, `label`, `title`, `classes`, `xfn` | the nine `_menu_item_*` postmeta keys (BR-MENU-02) |
| `Presentation::Theme` | — | `slug`, `parent_slug`, `version` | `themes-and-templates` |
| `Composition::Template` | — | `slug`, `theme_slug`, `content`, `area` | legacy `post_type = 'wp_template'` / `'wp_template_part'` |
| `Composition::Pattern` | — | `slug`, `title`, `content`, `categories` | legacy `post_type = 'wp_block'` + `block-patterns` |
| `Syndication::EmbedCache` | — | `url_digest`, `payload jsonb`, `fetched_at`, `expires_at` | legacy `post_type = 'oembed_cache'` — a **cache living in the content table** |
| `Routing::Redirect` | AGG-Permalink | `from_path`, `to_post_id`, `recorded_at` | `_wp_old_slug` / `_wp_old_date` postmeta |
| `Platform::SchemaVersion` | — | `version`, `applied_at` | `options['db_version']` + `dbDelta()` |

## Value objects

| Value object | Attributes | Validations | Origin |
|---|---|---|---|
| `Slug` | `value` | ≤ 200 bytes **including** any numeric suffix; not a reserved segment | `BR-MIGRATE-034/035` |
| `PostStatus` | enum: `auto_draft`, `draft`, `pending`, `scheduled`, `published`, `private`, `trashed`, `inherit` | transitions constrained; `inherit` valid only for owned records | `post_status` varchar |
| `CommentStatus` | enum: `pending`, `approved`, `spam`, `trashed` | — | `BR-CMT-12`, resolved as an enum at the Curator pause |
| `MimeType` | `type`, `subtype` | determined from content, not extension | `post_mime_type` |
| `Capability` | `name` | must be declared; unknown capabilities are a load-time error, not a silent deny | `map_meta_cap()` primitives |
| `PermalinkStructure` | `pattern` | tokens validated; reserved segments derived | `options['permalink_structure']` |
| `Locale` | `code` | BCP-47; fallback chain resolved deterministically | `internationalization` |
| `SafeHtml` | `value` | produced only by `sanitizing` 📦; cannot be constructed directly | KSES output |
| `Url` | `value` | scheme allowlisted; `Egress::UrlPolicy` validates before any outbound fetch | `wp_http_validate_url()` |

**On `SafeHtml`**: making sanitized markup a distinct type is the one place this model adds a
guarantee the legacy could not. `architecture.md` §4 records output escaping as *"convention only,
no type system"* (F-FMT-02). A value object that only the sanitizing pack can construct converts
that convention into something the compiler-adjacent tooling can see. ⚠️ It does **not** change what
the sanitizer does — override 2 keeps the regex implementation verbatim (RISK-005).

## Domain events

**Not applicable — and that is a decision, not an omission.**

The target paradigm is classic OO / Active Record. `paradigm_decision.md` records no event-driven
option among the three presented, and the chosen option 1 explicitly makes behaviour *final and
in-process*. Publishing domain events would reintroduce, in a new form, precisely what AD-01
removed: an indirection where the effect of an operation is not readable at the call site. The
legacy's 565 actions were exactly that, and discarding them is the point of implication 2.

Where the legacy fired an action on a state change, the target **records the transition** instead:
`Publishing::StatusTransition` is a row, readable and queryable, rather than a broadcast. Anything
that must happen as a consequence happens in the model or in an explicitly enqueued job.

## Domain rules

> Complete mapping of all **363 MIGRATE** rules to their location in the new domain. Grouped by the
> legacy module block that produced them, since `target_business_rules.md` numbers them contiguously
> in that order. Load-bearing individual rules are called out beneath.

| Rule range | Count | Location in the new domain | Origin module |
|---|---:|---|---|
| `BR-MIGRATE-001` … `006` | 6 | `Platform::Environment`, `Platform::RecoveryMode`, `Presentation::Theme` (child-theme load order) | `bootstrap-and-load` |
| `BR-MIGRATE-007` | 1 | Tenancy concern (Wave 5) | `database-wpdb` |
| `BR-MIGRATE-008` … `014` | 7 | AGG-Setting | `options-and-transients` |
| `BR-MIGRATE-015` … `020` | 6 | `Platform` cache configuration + `Rails.cache` | `cache-and-object-cache` |
| `BR-MIGRATE-021` … `028` | 8 | `Publishing::Attribute`, plus the columns promoted by AD-03 | `metadata` |
| `BR-MIGRATE-029` … `039` | 11 | **AGG-Post** | `posts-and-post-types` |
| `BR-MIGRATE-040` … `051` | 12 | `Retrieval::PostQuery`, `Retrieval::Page` | `query-and-loop` |
| `BR-MIGRATE-052` … `064` | 13 | **AGG-Term** | `taxonomy-and-terms` |
| `BR-MIGRATE-065` … `078` | 14 | **AGG-Comment** | `comments` |
| `BR-MIGRATE-079` … `088` | 10 | **AGG-Asset** | `media-and-attachments` |
| `BR-MIGRATE-089` … `096` | 8 | `Syndication::EmbedProvider`, `Syndication::EmbedCache` | `embeds-oembed` |
| `BR-MIGRATE-097` … `110` | 14 | **AGG-User** (`RoleAssignment`) + `Access::*Policy` | `users-roles-capabilities` |
| `BR-MIGRATE-111` … `126` | 16 | **AGG-User** (`Session`, `ApplicationPassword`) | `authentication-and-sessions` |
| `BR-MIGRATE-127` … `140` | 14 | `Presentation::Theme`, `Presentation::TemplateResolver` | `themes-and-templates` |
| `BR-MIGRATE-141` … `152` | 12 | **AGG-Permalink** | `rewrite-and-permalinks` |
| `BR-MIGRATE-153` … `162` | 10 | `Presentation::AssetBundle` | `script-modules-and-assets` |
| `BR-MIGRATE-163` … `173` | 11 | **AGG-Menu** | `widgets-and-nav-menus` |
| `BR-MIGRATE-174` … `181` | 8 | `Console` changesets | `customizer` |
| `BR-MIGRATE-182` … `193` | 12 | `Composition::Block`, `Composition::BlockType` | `block-editor` |
| `BR-MIGRATE-194` … `199` | 6 | `Composition::Renderer` | `blocks-library` |
| `BR-MIGRATE-200` … `205` | 6 | `styling` 📦 | `block-supports` |
| `BR-MIGRATE-206` … `215` | 10 | `styling` 📦 | `global-styles-theme-json` |
| `BR-MIGRATE-216` … `219` | 4 | `styling` 📦 | `style-engine` |
| `BR-MIGRATE-220` … `226` | 7 | `markup` 📦 | `html-api` |
| `BR-MIGRATE-227` … `233` | 7 | `Presentation` (interactivity directives) | `interactivity-api` |
| `BR-MIGRATE-234` … `244` | 11 | `PublicApi` controllers + `Access::BasePolicy` | `rest-api` |
| `BR-MIGRATE-245` … `257` | 13 | `Egress::Client`, `Egress::UrlPolicy` | `http-api` |
| `BR-MIGRATE-258` … `263` | 6 | `Syndication::Feed` | `feeds` |
| `BR-MIGRATE-264` … `268` | 5 | `Syndication::Sitemap` | `sitemaps` |
| `BR-MIGRATE-269` … `278` | 10 | `Assistance::*` | `ai-abilities-connectors` |
| `BR-MIGRATE-279` … `282` | 4 | `Scheduling` (Active Job) | `cron` |
| `BR-MIGRATE-283` … `291` | 9 | `Localization::Locale`, `Localization::Catalogue` | `internationalization` |
| `BR-MIGRATE-292` … `297` | 6 | `sanitizing` 📦 | `formatting-and-sanitization` |
| `BR-MIGRATE-298` … `307` | 10 | `sanitizing` 📦 | `kses-security` |
| `BR-MIGRATE-308` … `317` | 10 | `Platform::RecoveryMode` | `error-handling-and-recovery-mode` |
| `BR-MIGRATE-318` … `323` | 6 | `Presentation` (speculation rules, view transitions) | `performance-speculation-view-transitions` |
| `BR-MIGRATE-324` … `331` | 8 | `Console` + `Access` | `admin-application` |
| `BR-MIGRATE-332` … `342` | 11 | `Platform::Storage` + Active Storage | `filesystem-api` |
| `BR-MIGRATE-343` … `351` | 9 | `Platform::SchemaVersion` | `updates-and-upgrader` |
| `BR-MIGRATE-352` … `356` | 5 | `Platform::Health` | `site-health` |
| `BR-MIGRATE-357` … `363` | 7 | Tenancy concern (Wave 5) | `multisite` |
| **Total** | **363** | | |

### The nine owner-override rules, individually

These are called out because AD-01 makes them **permanent**, and the Inspector must assert the
permissive behaviour as specification.

| Rule | Location | What is reproduced |
|---|---|---|
| `BR-REST-05` | `Access::BasePolicy` + `PublicApi` | A route with **no policy is public**. AD-04's build check makes that reachable only by explicit declaration. |
| `BR-CAP-05` | `Access::BasePolicy` | A policy method emitting **no capabilities allows**. |
| `BR-ADM-07` | `Console` | An ungated nopriv-equivalent endpoint class exists. |
| `BR-KSES-01` | `sanitizing` 📦 | Allowlist filtering implemented with regular expressions. |
| `BR-KSES-04` | `sanitizing` 📦 | Four-step scheme normalisation: decode entities, strip whitespace, remove nulls, lowercase. |
| `BR-KSES-05` | `sanitizing` 📦 | Colon recognised as `:`, `&#58;`, `&#x3a;`, `&colon;`. |
| `BR-KSES-06` | `sanitizing` 📦 | Truncated colon entities repaired before splitting. |
| `BR-KSES-07` | `sanitizing` 📦 | `feed:` prefix re-examined recursively, capped at two levels. |
| `BR-FMT-04` | `sanitizing` 📦 | `wpautop` / `wptexturize` as regex transformation over rendered HTML. |

⚠️ All six KSES/formatting rules land in one pack, which is deliberate: they must be ported
**character-for-character** and proven by differential fuzzing against the PHP original, because PCRE
and Onigmo are not equivalent (RISK-005). Concentrating them in a zero-dependency pack makes that
harness possible to write.

## Traceability to the legacy system

| New element | Legacy origin | Mapping type |
|---|---|---|
| AGG-Post | `domain.md § Content lifecycle`; `posts-and-post-types` + `metadata` | **merged**, then **split** — metadata absorbed (AD-03), eleven post types removed (AD-02) |
| AGG-Term | `domain.md § Classification`; `taxonomy-and-terms` | merged — `terms` + `term_taxonomy` collapse into one model |
| AGG-Comment | `domain.md § Moderation`; `comments` | 1-to-1, with three deviations |
| AGG-Asset | `media-and-attachments`; `post_type = 'attachment'` | **split** from AGG-Post |
| AGG-User | `users-roles-capabilities` + `authentication-and-sessions` | merged |
| AGG-Setting | `options-and-transients` | **split** — routing, jobs and transients leave (AD-06) |
| AGG-Menu | `widgets-and-nav-menus`; `post_type = 'nav_menu_item'` | **split** from AGG-Post, then materialized from postmeta |
| AGG-Permalink | `rewrite-and-permalinks` | 1-to-1, with slug allocation pulled in from `posts` |
| `Access::*Policy` | `map_meta_cap()` 870-line switch | **new** — extracted from two legacy modules, belongs to neither |
| `Discussion::RateLimit` | *(none)* | **new** — `BR-CMT-04` deviation; the legacy enforces no limit |
| `Publishing::StatusTransition` | `transition_post_status` action | **new** — a record replacing a broadcast (AD-01) |
| `Composition::Template` / `Pattern` | `wp_template`, `wp_template_part`, `wp_block` post types | **split** from AGG-Post |
| `Syndication::EmbedCache` | `oembed_cache` post type | **split** from AGG-Post |
| `Identity::DataRequest` | `user_request` post type | **split** from AGG-Post |
| `Platform::*` | `bootstrap` + `error-recovery` + `filesystem` + `updates` + `site-health` + `cache` | merged |
| `spec/parity/` | *(none — the legacy has no tests)* | **new** (AD-08) |
| `hooks-plugin-api`, `deprecated-compat`, `xmlrpc` | — | **removed** — see `discard_log.md` |

## Notes

**Three modelling claims worth checking before anyone writes code**, because each is a place this
model could be wrong:

1. **AD-02's split assumes the eleven machinery types have no shared behaviour worth inheriting.**
   The evidence says they do not — a font face and an article share `comment_status` only because
   they shared a table. But `nav_menu_item`, `wp_template` and `wp_block` all carry *content* that is
   parsed as blocks, so if `Composition` ends up duplicating parsing logic across three models, the
   split was drawn one boundary too fine. Prototype against these three first (RISK-003).

2. **AGG-Term merges `terms` and `term_taxonomy`, which the legacy deliberately separates.** The
   legacy split exists so one word can be several classifications — the same "News" term row serving
   a category and a tag. `term_taxonomy` even carries the schema's **only** semantic unique key
   (F-DD-05). Merging them means a term is created per taxonomy, and the shared-word case becomes two
   rows. That is almost certainly right for a rebuild, but it is a **behavioural change**, not a
   refactor, and the Inspector should expect diffs on any flow that relied on term-id sharing.

3. **`Publishing::Attribute` is a residual bucket, and residual buckets grow.** AD-03 promotes every
   *core-owned* key to a column, which is correct today because the extraction enumerated them
   (`data-dictionary.md` §4.3). The rule that keeps it honest: a key that the application itself
   reads by name belongs in a column. If new code starts querying `Attribute` by key, that is the
   signal a column was missed — not a reason to index `jsonb` harder.
