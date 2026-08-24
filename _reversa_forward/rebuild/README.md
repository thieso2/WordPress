# WordPress 7.2-alpha-63330 → Rails 8.1 / PostgreSQL

The rebuild specified by `_reversa_sdd/migration/`. Start with
[`handoff.md`](../../_reversa_sdd/migration/handoff.md), then the three non-negotiable
decisions: `paradigm_decision.md`, `topology_decision.md`,
`screen_modernization_decision.md`.

**Status: Wave 0 complete and gated. Waves 1–2 at parity.** Waves 3–5 not started.

The front end renders from PostgreSQL through a real server-side block renderer, and
**all 25 corpus screens are byte-identical to the oracle** through the parity harness —
the 18 literal `web.*` screens plus the 7 syndication surfaces. That is the Wave 1/2
parity gate as `parity_specs.md` defines it: zero unexplained divergence, five
consecutive clean runs, on a corpus proven reproducible across full oracle rebuilds.
See § Where this is weakest for what "byte-identical through the harness" does not cover.

---

## The three things that shape everything here

1. **There is no hook system.** (AD-01, `paradigm_decision.md` option 1.) No filters, no
   actions, no callback registry. Every one of the 363 migrated rules describes
   WordPress's *unfiltered default*, and here that default is the **permanent, only
   behaviour**. That is what makes parity checkable — and it is why getting a rule wrong
   is not recoverable by configuration later.

2. **Three packs, everything else conventional Rails.** (`topology_decision.md` option 3.)
   `packs/markup`, `packs/sanitizing`, `packs/styling` declare **zero dependencies** and
   CI enforces it. The content core lives in one `app/` with contexts as namespaces
   (`Publishing::Post`, never `Post`) and **no enforceable dependency direction** — a
   known, accepted consequence (RISK-017), mitigated by `bin/check_cycles`.

3. **The oracle is the specification.** (AD-08.) The legacy ships zero tests (TD-18) and
   all 431 rules were verified by *reading*, never by executing. There is no live
   deployment. So the reference WordPress instance in `../oracle/` is not test tooling —
   it is the project's only executable definition of the 363 rules.

---

## Verified state

```
bin/ci
  topology (RISK-017)     OK — the namespace graph is acyclic and every pack is a leaf
  rule coverage           201/363 rules carry a citation (coverage floor, not a parity claim)
  specs                   778 examples, 0 failures, 5 pending (documented gaps)
  seeding pipeline        13/13 quality validations, dead-letter queue EMPTY
  golden capture          25 requests, no unexplained divergence
  parity suite            172 scenarios — 87 passed, 85 undefined, 0 failed
  response diff           25 of 25 byte-match (5 consecutive clean runs)
Wave 0 gate: PASS
```

`bin/parity determinism 5` → **5 full oracle rebuilds produce byte-identical golden files.**
That is the precondition for `parity_specs.md`'s observation window ("green across the
agreed corpus for 5 consecutive runs"), which is unmeetable if the corpus drifts.

The 85 *undefined* scenarios are the screen features and everything needing a Wave 1+ HTTP
surface. Undefined never reports as passing.

## Quick start

```bash
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"

bin/oracle status          # the reference WordPress 7.2-alpha-63330 instance
bin/oracle up              # start it (PHP 8.4 + MariaDB, port 8099)
bin/rails oracle:inventory # count the corpus without loading anything
bin/rails oracle:seed      # MySQL -> PostgreSQL through Active Record, one-way
bin/check_cycles           # topology fidelity — must exit 0
bin/parity capture         # re-capture the golden files from the oracle

bin/parity determinism 5   # rebuild the oracle 5x, prove the goldens are byte-identical
bin/rule_coverage          # per-rule accounting against the 363 MIGRATE rules
bin/ci                     # the whole Wave 0 gate

bin/parity_worker          # the parity suite, in a PRIVATE database — see below
bin/rspec_worker           # unit + pack specs (778 examples), in a private database
```

⚠️ **Run the suites through `bin/parity_worker` and `bin/rspec_worker`, not `cucumber`/`rspec` directly.** The suite
truncates globally between scenarios, so two concurrent runs against one database race
each other and manufacture `PG::ForeignKeyViolation` / `ActiveRecord::Deadlocked` failures
on scenarios that are perfectly correct. That matters more here than in an ordinary suite:
`parity_specs.md` makes an unexplained divergence on a write path *disqualifying*, so a
harness that invents its own spends that budget on itself. Verified: three concurrent
workers, 87 passed / 0 failed each.

---

## What Wave 0 delivered

`handoff.md` § next steps 4 fixes the order: *the oracle → the diff harness → the seeding
pipeline → `markup` and `styling` → `bin/check_cycles`.*

| Component | Where | Notes |
|---|---|---|
| **Reference oracle** | `../oracle/wordpress` | WordPress 7.2-alpha-63330 on PHP 8.4 + MariaDB, serving HTTP. Never a copy-in-place: the legacy tree is untouched. |
| **Corpus seeder** | `../oracle/wordpress/tools/seed.php` | All **16 post types**, 3-deep category hierarchy + flat tags, 4-level comment threads, every role, 6 rows carrying `0000-00-00 00:00:00`, serialized postmeta/options/usermeta, 4-byte UTF-8, quote- and backslash-heavy text. |
| **Diff harness** | `spec/parity/harness/` | `bin/parity capture` — normalization rules transcribed from `screens/golden/manifest.yaml`, not invented. |
| **Golden files** | `spec/parity/golden/` | 25 captures: the 18 literal `web.*` screens + 7 syndication surfaces. **Closes deferred item D-4.** |
| **Seeding pipeline** | `lib/seeding/`, `lib/tasks/seeding.rake` | T-01…T-11 through Active Record. Dead-letter queue **fails the run**. |
| **Schema** | `db/migrate/` | The 26-table DDL from `target_data_model.md`, verbatim, plus one recorded deviation. |
| **Content core** | `app/models/` | 11 namespaces, ~30 models. |
| **`bin/check_cycles`** | `bin/check_cycles` | RISK-017. Pack isolation *prevented*; namespace cycles *detected*; the Access edge asserted. |
| **Leaf packs** | `packs/` | `markup` ← html-api, `sanitizing` ← kses+formatting, `styling` ← style-engine + global-styles + block-supports. |
| **Parity suite** | `spec/parity/features/` | The Inspector's 31 `.feature` files, **byte-identical copies**. |

---

## ⚠️ Deviations found while building, and what was done about them

These were not in the specs. Each is recorded here because
`parity_specs.md` requires every divergence to resolve to a written record.

### 1. `posts.attributes` cannot exist under the chosen paradigm — schema changed

`target_data_model.md` names AD-03's residual bucket `posts.attributes`. `attributes` is
an `ActiveRecord::Base` instance method, so defining an attribute over it raises
`ActiveRecord::DangerousAttributeError` at class-definition time: `Publishing::Post` is
**unloadable** with the column as specified.

Renamed to `posts.residual_attributes` (`db/migrate/20260822000011`). Nothing else about
AD-03 changes. This is precisely the class of finding `data_migration_plan.md` § Notes
predicts — *"a constraint that is wrong … fails here, in Wave 0, rather than in Wave 3"*.

### 2. `Publishing ↔ Library` is a cycle **in the specs themselves** — needs an owner ruling

`target_architecture.md`'s intended graph says `Classification, Discussion, Library,
Routing → Publishing`, with no `Publishing → Library` edge. But `target_data_model.md`
specifies foreign keys in **both** directions:

- `posts.featured_asset_id → assets.id` (AD-03: postmeta `_thumbnail_id` becomes a real FK)
- `assets.attached_to_id → posts.id` (the legacy attachment's `post_parent`)

These cannot both hold with an acyclic graph, and it cannot be coded around while both
FKs exist. Recorded as an **acknowledged cycle** in `bin/check_cycles` — reported as a
`WARN` on every build rather than silenced, with the justification inline. **This wants a
decision**: drop one FK, or accept the edge and say so in `target_architecture.md`.

### 3. T-10 does not cover the digest format every corpus user actually has

`data_migration_plan.md` T-10 names phpass (`$P$`) and bcrypt (`$2y$`). WordPress 6.8+
writes a **third** format, and it is the one every user in a 7.2 corpus carries:

```php
'$wp' . password_hash( base64_encode( hash_hmac('sha384', trim($password), 'wp-sha384', true) ), PASSWORD_BCRYPT )
```

Without it the pipeline loaded **every user with authentication disabled** and said so in
its notes — the report was honest, the rule was incomplete. `Identity::LegacyDigest`
handles all four formats and is verified against `wp_check_password()` on the live oracle.
⚠️ It reproduces the legacy's asymmetry: `wp_hash_password()` trims the password,
`wp_check_password()` does not.

### 4. `post_password` has no transformation specified

`target_data_model.md` renames the legacy's **plaintext** `post_password` column to
`password_digest`, but `data_migration_plan.md` specifies no transformation for it. A
plaintext value in a column named `_digest` is worse than either option, so the pipeline
hashes it (`T.post_password_digest`). Consequence: the plaintext is not recoverable — which
is the point. Recorded because it is a pipeline decision, not a specified one.

### 5. `web.attachment` is not a rendered screen in WordPress 7.2 — feeds D-7

`golden/manifest.yaml` lists `web.attachment` among the 18 **literal** screens to be
byte-compared as HTML. It does not render. On a default 7.2 install
`wp_attachment_pages_enabled` is `'0'` and `wp-includes/canonical.php:553` **301-redirects**
every attachment URL to the file. Verified against all three corpus attachments.

Its golden is the redirect, captured as such rather than quietly followed. This is a
screen-inventory discrepancy and is evidence for deferred item **D-7**.

---

### 6. Two harness bugs that would have made the diff look green while proving nothing

Both were found by capturing against the oracle rather than by review, and both are the
failure mode `parity_specs.md` warns is worst — a check that passes without checking.

- **The normalizer transcoded instead of re-tagging.** `Net::HTTP` returns `ASCII-8BIT`;
  `String#encode(UTF_8, invalid: :replace)` from binary treats every **byte** as a
  character, so one emoji became four `U+FFFD`. It did so on *both* sides of the diff, so
  the two systems would have looked identical while the comparison was flattened out of
  existence — precisely RISK-014, "a divergence in the permissive direction that diffing
  tends to miss." Fixed to `force_encoding` + `scrub`.
- **The corpus was not reproducible.** Three separate causes: `wp_install()` stamps its
  seed content with the **real clock**; every seeded post shared one date and WP orders
  archives by `post_date DESC` with **no tiebreak**, so ties came back in arbitrary order;
  and the oEmbed screen carries a per-request `wp_unique_id` and `data-secret`. Fixed by
  pinning distinct deterministic dates and by normalizing the two per-request tokens —
  which is what the manifest's `seedRandom: 42` rule amounts to when the RNG lives in
  another process. `bin/parity determinism 5` now passes.

Two smaller ones, same character: `update_option()` expects **unslashed** input while
`wp_insert_post()` expects slashed, so the seeder was writing a literal backslash into the
blog title and thence into every capture; and `Seeding::PhpSerialization` rejected `N;`
(PHP `NULL`) as too short for its length guard and round-tripped it as the **string**
`"N;"` — found by spec, not by review.

## The seeding pipeline is the first honest test of the schema

`data_migration_plan.md` routes the load through Active Record on purpose, so every
`CHECK`, unique index, FK and validation is exercised against real WordPress data before a
feature is written. It reports:

- an **inventory** before loading anything (serialized `a:` / `O:` / scalar counts, zero
  dates, `_menu_item_orphaned` tombstones);
- a **quarantine** for `O:` payloads and unparseable serialization — never discarded,
  never guessed at (T-02, RISK-006);
- a **dead-letter queue** that **fails the run and commits nothing**. A pipeline that
  quietly coerced bad input into defaults would still fill the database and destroy the
  signal this step exists to produce.

All 13 quality validations from `data_migration_plan.md` § Quality validation pass,
including the two that are easy to get wrong:

- **text round-trip is byte-identical** (checksummed against the source) — this is what
  catches an accidental slashing pass (T-08). The corpus is deliberately backslash-heavy.
- **terms = `wp_term_taxonomy` row count, not `wp_terms`** (T-06) — *"getting this
  backwards is how the split gets missed."*

⚠️ **One-way, structurally.** The Rails side connects to MySQL as `wporacle_ro`, which
holds `SELECT` and nothing else. RISK-002's residual is not a rule anyone has to remember.

---

## Reading the topology check

```
$ bin/check_cycles
  namespaces:      Access, Classification, Composition, Configuration, Discussion,
                   Identity, Library, Presentation, Publishing, Routing, Syndication
    Publishing       -> Identity, Library
    Routing          -> Configuration, Publishing
    ...
  OK — the namespace graph is acyclic and every pack is a leaf.
```

Three different guarantees, and the difference is the whole content of topology option 3:

- **Pack isolation — prevented.** A pack referencing `app/`, Rails or another pack fails
  the build.
- **Namespace acyclicity — detected, not prevented.** Cross-namespace references are
  allowed; a *cycle* is not.
- **The Access edge — asserted.** `Access → Identity, Publishing`; **nothing depends on
  Access** except delivery surfaces. `target_architecture.md` Note 2: *"If `Publishing`
  ever references `Access`, the users↔posts cycle is back and the topology has no
  mechanism to stop it — only `bin/check_cycles` will notice."*

It reads **string** constant references, not just literal ones, because Rails declares
most of its dependency graph as strings (`class_name: "Identity::User"`). A constant-only
parse reported 1 edge where there are 10 — a cycle detector that under-reports is worse
than none, because it gives assurance it has not earned.

**It caught the legacy's cycle re-forming on its first real run**:
`Classification ↔ Identity ↔ Library ↔ Publishing`. Two edges were gratuitous inverse
associations (`Identity::User has_many :posts` — literally the users↔posts cycle
`handoff.md` warns about) and were removed. The third is deviation 2 above.

---

## Where this is weakest, stated plainly

- **"Byte-identical through the harness" has a precise meaning.** The normalizer masks
  per-request nonces, autoincrement ids, the UUID guid (T-07, by design), timestamps,
  the site host, and — ⚠️ — **sorts class-attribute tokens**. That last rule is declared
  in `golden/manifest.yaml`, and it means class ORDER (BR-MIGRATE-201) is invisible to the
  screen diff by design. It is asserted by unit specs instead, and two of those are
  currently `pending` on a documented gap: block style variation rulesets
  (`class-wp-theme-json.php:3834`, step 6) are not ported into `packs/styling`, so
  block-level variations get neither their instance class nor their CSS. No golden screen
  exercises this. `pending` fails the build if it starts passing, so it cannot close
  silently.
- **Waves 3–5 are not started.** There is no write path, no session surface, no admin
  console and no editor. The password-protected post renders its form; the form posts to
  nothing.
- **The parity suite is partially wired.** All 31 feature files are present and 159
  scenarios are enumerated; step definitions exist for a subset. An unimplemented
  scenario reports as *undefined*, never as passing.
- **The packs are ports of the named rules, not transliterations.** Each pack's README
  states what was and was not ported, and each carries an adversarial verification pass.
  RISK-005 is discharged with evidence rather than assertion: `sanitizing` runs **5,490
  corpus entries × 30 functions = 164,700 byte-for-byte comparisons against the live PHP
  oracle**, at 100% with one documented divergence class. The fuzzer found seven real
  defects the hand-written cases missed, two of them exactly the class `handoff.md`
  predicted. The `^`/`$` anchor trap is translated at all twelve sites
  (`(?=\n?\z)`, not Ruby's `$`).
- ⚠️ **Two `markup` divergences are live risks, not cosmetic.** `set_attribute` does not
  run `esc_url()` on URI attributes — the legacy *rejects* the write when `esc_url` empties
  the value, this pack writes it through — so any caller writing URLs through that API must
  sanitize first. And Ruby has no deterministic destruction, so internal bookmarks are
  never released: parsing stops with `exceeded-max-bookmarks` at roughly **2,000
  elements**, which is a long article, not an outlier. Both are in
  `packs/markup/README.md`; the second is the first thing to fix before pointing that pack
  at real content.
- **The editor is untouched** and remains the largest work item with no rule behind it
  (DEV-012, RISK-018).
