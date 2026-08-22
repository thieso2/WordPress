---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: data_migration_plan
producedBy: designer
hash: "sha256:3c3f077f0dd6950c98eaf9d0872335ae6ad796bde99bb255d5e4dde4074e2469"
---

# Data Migration Plan

> Mapping, transformations, ETL, cutover and validation for moving data from the legacy schema to
> the target one.
> Required reading before this: `target_data_model.md`, then `cutover_plan.md`.

> ## ⚠️ What this document actually is
>
> **There is no production data to migrate.** The owner confirmed at the post-Strategist pause that
> this is a **product rebuild with no live deployment** — no running site, no real users, no data at
> risk. So this is not a production migration plan, and writing it as one would describe work nobody
> is going to do.
>
> It is the **oracle corpus seeding pipeline**: the repeatable, idempotent path from the reference
> WordPress `7.2-alpha-63330` instance's MySQL database into PostgreSQL, used to prove that the
> target schema can faithfully hold what the legacy schema holds. It runs on **every corpus
> refresh**, not once at a cutover.
>
> That makes it more load-bearing than a one-shot ETL, not less. Under AD-08 the oracle is the only
> executable definition of the 363 rules, and **a corpus that does not round-trip is a corpus that
> cannot judge parity.** RISK-001 is the project's single point of failure and this pipeline is half
> of its mitigation.

## Summary

- **Estimated volume**: whatever the corpus is deliberately seeded with — the reference instance is
  *authored*, not inherited. Target shape: all 16 post types represented, hierarchical and flat
  taxonomies, threaded comments at depth, every role, drafts carrying `0000-00-00 00:00:00`,
  serialized `postmeta`/`options`/`usermeta`, 4-byte UTF-8 and emoji, quote- and backslash-heavy
  text. Scale is a test-design decision, not a production constraint — but ⚠️ **an oracle seeded with
  three posts proves very little** (`migration_strategy.md`, Strategy C cons).
- **Migration window**: none. See `cutover_plan.md`, which is a **launch plan** — there is no freeze,
  no write-authority flip and no reconciliation window.
- **Strategy**: **repeatable full load, one-way, idempotent.** Not backfill + delta + cutover: there
  is no live source to capture deltas from. The pipeline is re-run from scratch whenever the corpus
  changes.

## Legacy → new mapping

| Source | Target | Type | Notes |
|---|---|---|---|
| `wp_posts` WHERE `post_type` IN (`post`,`page`) | `posts` | **filter + rename** | STI `type` column set from `post_type` (AD-02) |
| `wp_posts` WHERE `post_type='revision'` | `revisions` | **split** | `post_parent` → `post_id`; drops status, slug, comment fields |
| `wp_posts` WHERE `post_type='attachment'` | `assets` | **split** | joins 4 postmeta keys into columns |
| `wp_posts` WHERE `post_type='nav_menu_item'` | `menu_items` | **split + materialize** | joins the 9 `_menu_item_*` postmeta keys (BR-MENU-02) |
| `wp_posts` WHERE `post_type` IN (`wp_template`,`wp_template_part`) | `templates` | split | `kind` derived from the source type |
| `wp_posts` WHERE `post_type='wp_block'` | `patterns` | split | |
| `wp_posts` WHERE `post_type='oembed_cache'` | `embed_caches` | split | ⚠️ a cache stops being content; TTL is **re-derived**, not migrated |
| `wp_posts` WHERE `post_type='user_request'` | `data_requests` | split | |
| `wp_posts` WHERE `post_type` IN (`customize_changeset`,`wp_global_styles`,`wp_font_family`,`wp_font_face`) | `Console` changesets / `styling` 📦 data | split | see T-09 |
| `wp_postmeta` (core-owned keys) | columns on `posts`, `assets`, `menu_items`, `redirects` | **promote** | AD-03; the full key list is `data-dictionary.md` §4.3 |
| `wp_postmeta` (remaining keys) | `post_attributes` + `posts.attributes` | narrow | `longtext` → `jsonb` |
| `wp_terms` + `wp_term_taxonomy` | `taxonomies` + `terms` | **merge + split** | one row per (term, taxonomy) pair — ⚠️ behavioural change, see T-06 |
| `wp_term_relationships` | `term_assignments` | rename | `object_id` → polymorphic `classifiable_*` |
| `wp_termmeta` | `terms` columns / dropped | promote | `description` is the only core-owned key |
| `wp_comments` | `comments` | rename | `comment_approved` varchar → enum (T-05) |
| `wp_commentmeta` | dropped | — | no core-owned keys of consequence |
| `wp_users` | `users` | rename | `user_pass` → `password_digest` (T-10) |
| `wp_usermeta['{prefix}capabilities']` | `role_assignments` | **explode** | serialized `role=>true` map → one row per role (T-03) |
| `wp_usermeta['session_tokens']` | `sessions` | **explode** | serialized array → rows |
| `wp_usermeta` (profile keys) | `users` columns | promote | `locale`, `nickname`, `first_name`, `last_name`, `description` |
| `wp_options` (settings) | `settings` | filter + rename | `longtext` → `jsonb`; `autoload` varchar → boolean |
| `wp_options['rewrite_rules']` | **discarded** | drop | derived state; recompiled by `Routing` (AD-06) |
| `wp_options['cron']` | **discarded** | drop | replaced by a real job queue (AD-06) |
| `wp_options['_transient_*']`, `_site_transient_*` | **discarded** | drop | replaced by `Rails.cache` (AD-06) |
| `wp_links` | **discarded** | drop | Link Manager hidden since 3.5; dead weight in every install (F-DD-07) |
| `wp_registration_log` | **discarded** | drop | declared and created but rarely read (F-DD-07) |
| `wp_blogs`, `wp_blogmeta`, `wp_site`, `wp_sitemeta`, `wp_signups` | deferred | Wave 5 | schema-per-site replaces most of it (`BR-MS-01`) |

## Transformations

### T-01: Zero dates → NULL
- **Applies to**: `post_date`, `post_date_gmt`, `post_modified`, `post_modified_gmt`,
  `comment_date`, `comment_date_gmt`, `user_registered`
- **Rule**: `'0000-00-00 00:00:00'` → `NULL`. The GMT column is the source of truth and becomes the
  single `timestamptz` (AD-07); the local column is **discarded**, since it is derivable from the
  site timezone.
- **Handling of invalid values**: any other unparseable datetime → **reject the row into the
  dead-letter queue**. Do not coerce. A silently-defaulted date is a parity bug that will surface
  later as a wrong publish state.
- **Rule origin**: BR-POST-04, BR-DB-10, ADR-007; RISK-007.
- ⚠️ This is the transformation most likely to fail loudly on first run, and that is desirable —
  `0000-00-00` is not merely an edge case, it is what **every draft carries**.

### T-02: PHP `serialize()` → `jsonb`
- **Applies to**: `wp_options.option_value`, `wp_postmeta.meta_value`, `wp_usermeta.meta_value`,
  `wp_termmeta.meta_value`, `wp_commentmeta.meta_value`
- **Rule**: parse the PHP serialization format. Scalars (`s:`, `i:`, `d:`, `b:`, `N;`) map directly.
  Arrays (`a:`) map to JSON objects or arrays depending on whether keys are a contiguous integer
  sequence. **Objects (`O:`) have no automatic mapping.**
- **Handling of invalid values**: unparseable payloads and every `O:` payload go to a **quarantine
  table preserving the raw bytes**. Never discard; never guess a class mapping.
- **Rule origin**: RISK-006.
- **Inventory first**: before the first full run, count `a:`, `O:` and scalar payloads across the
  corpus. If the `O:` count is non-zero, each distinct class is a human decision, not a pipeline
  bug.

### T-03: The serialized role map → rows
- **Applies to**: `wp_usermeta` where `meta_key` matches `{prefix}capabilities`
- **Rule**: unserialize the `role => true` map; emit one `role_assignments` row per truthy key.
  Under multisite the prefix encodes the site (`wp_capabilities`, `wp_3_capabilities`, …), so the
  site id is parsed out of the key and becomes `site_id` (F-MS-04).
- **Handling of invalid values**: a role name not in the known role set → **load it anyway** and
  report it. An unknown role is data, not corruption, and dropping it silently changes who can do
  what.
- **Rule origin**: BR-CAP-13, F-MS-04.
- ⚠️ `{prefix}user_level` (BR-CAP-11) is **not** migrated. `level_0`–`level_10` exist in every role
  for backward compatibility with plugins that still test for them (TD-17, ADR-002) — a
  compatibility burden the brief has deleted.

### T-04: The nine `_menu_item_*` keys → columns
- **Applies to**: `wp_posts` where `post_type='nav_menu_item'`, joined to `wp_postmeta`
- **Rule**: pivot `_menu_item_type`, `_menu_item_object`, `_menu_item_object_id`,
  `_menu_item_menu_item_parent`, `_menu_item_target`, `_menu_item_url`, `_menu_item_xfn`,
  `_menu_item_classes`, `_menu_item_position` into `menu_items` columns. `_menu_item_type` decides
  which arm of the `menu_items_one_target` CHECK applies: `post_type`/`taxonomy` → internal target;
  `custom` → `url`.
- **Handling of invalid values**: rows carrying `_menu_item_orphaned` are **dropped**, and the count
  is reported. These are tombstones (BR-MENU-05) that exist only because the legacy has no foreign
  keys (F-DD-01); the FK on `menu_items.menu_id` makes the condition they mark unrepresentable.
- **Rule origin**: BR-MENU-02, BR-MENU-05, AD-03.

### T-05: `comment_approved` varchar → enum
- **Applies to**: `wp_comments.comment_approved`
- **Rule**: `'1'` → `approved`; `'0'` → `pending`; `'spam'` → `spam`; `'trash'` → `trashed`;
  `'post-trashed'` → `trashed`.
- **Handling of invalid values**: any other value → **reject to the dead-letter queue**. The column
  is a `varchar(20)` with no constraint, so unexpected values are possible and are worth seeing.
- **Rule origin**: `BR-CMT-12`, resolved as an enum at the Curator pause.

### T-06: `terms` + `term_taxonomy` → one `terms` row per pair
- **Applies to**: `wp_terms` joined to `wp_term_taxonomy` on `term_id`
- **Rule**: emit one `terms` row per `term_taxonomy` row, copying `name`, `slug` and `term_group`
  from the shared `wp_terms` row. `taxonomy` resolves to a `taxonomies.id` FK. `parent` (an id into
  `term_taxonomy`) is remapped to the new `terms.id`.
- **Handling of invalid values**: a `parent` pointing at a non-existent or cross-taxonomy row →
  set `NULL` and report. The legacy needs a runtime ancestor-cycle guard (BR-TAX-13) precisely
  because nothing prevents these.
- **Rule origin**: AD-02-adjacent; `target_domain_model.md` note 2.
- ⚠️ **This is a behavioural change, not a reshaping.** In the legacy, one `wp_terms` row can serve
  several taxonomies — the same word being both a category and a tag, sharing a `term_id`. Here it
  becomes two independent rows. **Any oracle diff that depends on term-id sharing is expected**, and
  the Inspector should classify it as a recorded deviation rather than chase it. `term_taxonomy`
  carries the schema's only semantic unique key (F-DD-05), so this is exactly where the legacy's
  model is most deliberate.

### T-07: `guid` → UUID
- **Applies to**: `wp_posts.guid`
- **Rule**: **discard the legacy value; generate a fresh UUID.** The legacy `guid` is a permalink
  captured at first publish and never updated (BR-POST-10), so it is a stale URL, not an identifier.
- **Handling of invalid values**: n/a — the source is not read.
- **Rule origin**: deviation `BR-POST-10`, recorded at the Curator pause.
- ⚠️ **Expected oracle diff.** Feeds expose `guid` (`Syndication::Feed`), so feed output will differ
  from the oracle on this field by design. The harness must normalize it, or it fails on every feed.

### T-08: Slashing — no transformation, by definition
- **Applies to**: all text columns
- **Rule**: **none.** Data at rest in `wp_posts` and `wp_postmeta` is already unslashed;
  `wp_magic_quotes()` slashes *superglobals at request time*, and `wp_unslash()` is applied before
  writing (DR-02, F-FMT-05). The pipeline copies bytes.
- **Handling of invalid values**: n/a.
- **Rule origin**: `paradigm_decision.md` implication 6; RISK-008.
- ⚠️ **Recorded explicitly because the opposite is the tempting mistake.** RISK-008 is about
  *re-reading the rules* that assumed slashed input, not about transforming stored data. Adding an
  unslash pass here would corrupt every legitimate backslash in the corpus.

### T-09: Global styles and font faces → `styling` 📦 data
- **Applies to**: `wp_posts` where `post_type` IN (`wp_global_styles`,`wp_font_family`,`wp_font_face`)
- **Rule**: the `post_content` of a global-styles row is a `theme.json`-shaped JSON document; load it
  as `jsonb` into the styling pack's own store, keyed by theme.
- **Handling of invalid values**: unparseable JSON → dead-letter queue.
- **Rule origin**: AD-02; F-GS-01 (the four-origin cascade is the only data-compiled-to-CSS design in
  core).

### T-10: Password hashes
- **Applies to**: `wp_users.user_pass`
- **Rule**: **copy the digest verbatim.** Do not rehash — the plaintext is unavailable by
  construction. The target must verify legacy phpass (`$P$`) and bcrypt (`$2y$`) digests, and
  transparently rehash to the target algorithm **on next successful login**.
- **Handling of invalid values**: an empty or malformed digest → load the user with authentication
  disabled and report. Never leave a user with a digest that accidentally verifies.
- **Rule origin**: `class-phpass.php` (`dependencies.md` §3); `authentication-and-sessions`.
- ⚠️ For an authored corpus this mostly does not matter — but the rehash-on-login path is a
  **behavioural rule** the parity harness should exercise, so seed at least one user of each digest
  format.

### T-11: Discarded sources
- **Applies to**: `wp_options['rewrite_rules']`, `wp_options['cron']`, all `_transient_*` and
  `_site_transient_*`, `wp_links`, `wp_registration_log`
- **Rule**: **not loaded.** Each is either derived state that the target recomputes, or a table the
  legacy keeps for compatibility with a retired feature.
- **Handling of invalid values**: n/a.
- **Rule origin**: AD-06 (routing, cron and transients leave `settings`); F-DD-07 (`links`,
  `registration_log`).
- ⚠️ **Report the row counts anyway.** A `rewrite_rules` option that had grown past the 150 KB
  autoload threshold (BR-OPT-06, F-RW-02) is evidence about the corpus, even though the value is
  discarded.

## ETL strategy

- **Tooling**: a **Rails-side rake task** reading the oracle's MySQL over a second Active Record
  connection, writing through the target models. Deliberately *not* raw SQL-to-SQL: routing the load
  through the models means every `CHECK`, unique index, FK and validation in
  `target_data_model.md` is exercised by the seeding itself. The pipeline is therefore also the first
  test of the schema.
- **Flow**:
  1. **Inventory** — count rows per legacy table; count `a:` / `O:` / scalar serialized payloads
     (T-02); count `0000-00-00` dates (T-01); count `_menu_item_orphaned` tombstones (T-04). Emit
     the report **before** loading anything.
  2. **Extract** — read per source table in dependency order.
  3. **Transform** — apply T-01 … T-11; anything unmappable goes to dead-letter or quarantine, never
     to a default.
  4. **Load** — in FK order: `users` → `settings` → `taxonomies` → `posts` → `assets` →
     `terms` → `term_assignments` → `comments` → `menus`/`menu_items` → the rest. ⚠️
     `posts.featured_asset_id` is a **deferred FK** added after `assets` exist, so featured images
     are set in a second pass.
  5. **Verify** — run the quality validation below; fail the whole run on any non-zero
     dead-letter count.
- **Idempotency**: the pipeline **drops and recreates the target schema** on every run. This is the
  simplest possible guarantee and it is available precisely because there is no production data —
  the one genuine benefit of having no live deployment. An id-mapping table (`legacy_id` →
  `new_id`, per source table) is retained within a run to resolve the `parent`/`object_id`
  remappings.
- **Expected throughput**: irrelevant at corpus scale. Going through the models is slow by design;
  if it ever becomes a constraint, the corpus has grown past what an oracle needs.

## Backfill and delta

**Not applicable.** There is no live source producing changes.

- **Backfill**: replaced by the full-load run above.
- **Delta capture**: **none, and deliberately none.** `migration_strategy.md` reduced the CDC seam to
  a seeding script when the owner confirmed no live deployment. ⚠️ **The residual of RISK-002 lives
  here**: the pipeline must remain **one-way**. The rebuild must never write to the oracle's MySQL
  database, and this script must never acquire a reverse mode "for convenience" — that would
  recreate the dual-write failure mode in miniature, with the oracle as the casualty.
- **Periodic reconciliation**: the validation table below runs at the end of **every** seeding run,
  which is the only moment the two databases are meant to agree.

## Data cutover

**There is no data cutover.** `cutover_plan.md` is a **launch plan**: PostgreSQL is authoritative
from the first line of code because nothing else ever was. No freeze, no write-authority flip, no
final delta sync, no reconciliation window.

The data-specific part of launch is one step: **run the seeding pipeline against production if any
initial content is to ship at launch, otherwise start empty.** See `cutover_plan.md` steps 3–4.

What *does* need a data gate is the **Wave 3 parity gate**, and its data criterion is exactly the
validation below: the corpus must round-trip with a zero-length dead-letter queue.

## Quality validation

| Metric | Target | Measurement source |
|---|---|---|
| Row count per content type | equal ± 0 | `wp_posts` grouped by `post_type` vs the target tables it split into (AD-02) |
| Terms | target = count of `wp_term_taxonomy` rows, **not** `wp_terms` rows | T-06 — the difference is the expected behavioural change, and getting this backwards is how the split gets missed |
| Comments, users, assets, menu items | equal ± 0 | direct comparison |
| Dead-letter queue | **0 rows** | the pipeline fails the run otherwise |
| Quarantine (`O:` payloads) | 0 rows, or every distinct class explicitly decided | T-02, RISK-006 |
| Zero dates reaching PostgreSQL | **0** | column scan for `NULL` correctness; RISK-007 |
| Referential integrity | **0 orphans** | FK enforcement makes most of this structural; one audit query for the polymorphic `term_assignments.classifiable_*`, which cannot have an FK |
| Counter caches | `terms.count` and `posts.comment_count` equal the recomputed values | recompute-and-compare; ⚠️ **published only** (BR-TAX-11) |
| Round-trip fidelity of text | byte-identical | checksum `post_content`, `post_title`, `comment_content` against the source — this is what catches an accidental slashing pass (T-08) |
| 4-byte UTF-8 survival | preserved | RISK-014; a divergence in the permissive direction that diffing tends to miss |

## Data-specific risks

| Risk | Relevance here |
|---|---|
| **RISK-006** — PHP-serialized payloads (MEDIUM, downgraded) | T-02. One-time per run rather than continuous, but a corpus that does not round-trip cannot judge parity. |
| **RISK-007** — `0000-00-00` dates (MEDIUM, downgraded) | T-01. The *modelling* half is undiminished: the `NULL` representation ripples into every date comparison and `BR-POST-01`'s threshold. |
| **RISK-002** — dual write authority (LOW, residual only) | The seeding script must stay one-way and must never target the oracle's database for writes. |
| **RISK-014** — charset edges (MEDIUM) | PostgreSQL accepts what MySQL's `utf8mb4` write-rejection (BR-DB-06) refused, so content round-trips that the oracle dropped. Document as an accepted deviation; do not chase it. |
| **RISK-001** — no oracle (CRITICAL) | This pipeline is half the mitigation. If it cannot load the corpus, the oracle cannot be compared against, and the project has no executable specification at all. |
| **RISK-003** — the 16-post-types fork (HIGH) | T-04, T-07 and T-09 are the *proof* of AD-02. If the pivots for menu items, templates and global styles turn out to be tangled, that is early evidence the split was drawn one boundary too fine — and it arrives while reversing is still cheap. |

## Notes

**The pipeline earns its keep twice, and the second time is the point.**

Its obvious job is to fill PostgreSQL. Its more valuable job is to be the **first honest test of
`target_data_model.md`**: because it loads through the models, every `CHECK`, unique index and
foreign key in that schema is exercised against real WordPress data before a single feature is
written. A constraint that is wrong — a slug uniqueness rule that is too strict, a menu-item CHECK
that no real row satisfies — fails here, in Wave 0, rather than in Wave 3.

That is why routing it through Active Record rather than SQL-to-SQL is a design decision and not an
inefficiency, and why **the dead-letter queue must fail the run**. A pipeline that quietly coerces
bad input into defaults would still fill the database, and would destroy exactly the signal this
step exists to produce.
