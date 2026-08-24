---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: risk_register
producedBy: strategist
hash: "sha256:6148309516a13d1b813e54a038e7903896457e9fa6eb6da5ea6e7924a64c9dd0"
---

# Risk Register

> Register of migration risks with probability, impact, mitigation and owner.
> Scoped to the recommended strategy in `migration_strategy.md` (Strangler Fig with deep boundaries
> + a standing Parallel Run). Risks that belong to the rejected strategies are noted as such.

**Owner note.** `migration_brief.md` records a single stakeholder: **thies (owner)**, sole
decision-maker. Owners below are therefore written as **roles**, per this agent's absolute rules, so
the register stays valid when the roles are filled by more than one person. Today they all resolve
to the same individual — which is itself RISK-011.

---

## Risks

### RISK-001
- **Description**: **There is no executable oracle for parity.** The legacy tree contains zero
  tests, no PHPUnit config and no CI (TD-18, `inventory.md` §1). All 431 rules were verified by
  reading code, never by running it. The brief's first success metric — "every one of the 431
  business rules either holds in the new system or appears in a deviation log" — is therefore not
  checkable by any artifact Reversa produced.
- **Category**: technical
- **Probability**: high (it is a present-tense fact, not a forecast)
- **Impact**: critical
- **Combined severity**: **CRITICAL**
- **Trigger / warning signal**: a wave declared complete with parity argued from code review alone;
  a Gherkin spec in `parity_specs.md` with no executable target.
- **Mitigation**: stand up a reference WordPress `7.2-alpha-63330` instance as a deliberate parity
  oracle (Strategy C, Wave 0). Seed it with a representative corpus — at minimum: all 16 post types,
  hierarchical and flat taxonomies, threaded comments, multiple roles, drafts with
  `0000-00-00 00:00:00` dates, serialised `postmeta` and `options`, and 4-byte UTF-8 content. Build
  the response-diff harness with normalisation for nonces, timestamps, auto-increment IDs and
  unordered collections before it is trusted.
- **Contingency plan**: if the oracle cannot be stood up, downgrade the success metric explicitly
  and in writing — parity becomes "reviewed against the documented rule" rather than "demonstrated"
  — and record the downgrade in `ambiguity_log.md` so it is never mistaken for the original claim.
- **Owner**: QA / verification lead
- **Status**: open — ⚠️ **elevated in importance on 2026-08-21.** The owner confirmed there is no
  live deployment, which de-risked RISK-002, RISK-006 and RISK-007 but left this one untouched. The
  reference oracle is now the **only** WordPress in the project and the only executable definition of
  the 363 rules. This is the project's single point of failure.

### RISK-002
- **Description**: **Dual write authority across two databases.** The legacy owns MySQL; the
  rebuild owns PostgreSQL. During Waves 1–2 the rebuild serves reads from replicated data while the
  legacy still writes. If any rebuild surface acquires a write path early — or if the CDC pipeline
  is ever run bidirectionally — the two systems silently diverge, and the legacy has **no
  transactions** (TD-05, DR-07) with which to detect or repair it.
- **Category**: technical
- **Probability**: low
- **Impact**: medium
- **Combined severity**: **LOW** — ⬇️ **downgraded from CRITICAL on 2026-08-21.** The owner
  confirmed there is **no live deployment**: this is a product rebuild. There is no second writer
  and no production MySQL, so the divergence this risk describes has nothing to occur between. The
  residual is narrow but real — the **seeding script must stay one-way**, and the rebuild must never
  be pointed at the oracle instance's database as a write target, which would recreate the failure
  mode in miniature.
- **Trigger / warning signal**: any code path writing to the oracle's MySQL database; a seeding
  script acquiring a reverse mode "for convenience".
- **Mitigation**: enforce the single-writer invariant mechanically, not by convention — the Wave 1–2
  PostgreSQL role is granted `SELECT` only, so an accidental write fails loudly at the database
  rather than succeeding quietly. CDC strictly one-way. A row-count and checksum reconciliation job
  runs continuously and alarms on drift.
- **Contingency plan**: on detected divergence, halt the affected wave, re-seed PostgreSQL from
  MySQL (still authoritative), and treat every write that reached PostgreSQL as lost rather than
  attempting a merge.
- **Owner**: data / platform lead
- **Status**: accepted (residual only)

### RISK-003
- **Description**: **The 16-post-types modelling fork is expensive to reverse.** `wp_posts` holds
  posts, pages, attachments, revisions, nav menu items, changesets, oEmbed cache, block templates,
  global styles and font faces, distinguished only by `post_type` (F-POST-01,
  `paradigm_decision.md` implication 5). Single-table inheritance versus separate models is decided
  once in `topology_decision.md` and touches every one of the 363 migrated rules that reads or
  writes a post.
- **Category**: technical
- **Probability**: medium
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: Wave 2 queries needing `post_type` discrimination in places the
  model does not express it; migrations adding nullable columns used by one type only.
- **Mitigation**: the Designer decides it explicitly and defends it in `topology_decision.md`, with
  the human approval gate the migration pipeline already requires. Prototype both against the three
  hardest types (attachments, revisions, nav menu items) before committing.
- **Contingency plan**: if the choice proves wrong after Wave 2, absorb the change while write
  authority still sits with the legacy — the rebuild's PostgreSQL data is re-derivable from MySQL up
  to the Wave 3 flip, which makes this the last cheap moment to change the model.
- **Owner**: architect / Designer role
- **Status**: open

### RISK-004
- **Description**: **Permissive authorization defaults are deliberately reproduced in a greenfield
  system.** Owner override 1 reverses question Q4: a REST route with no policy is public
  (`BR-REST-05`), a policy emitting no capabilities allows (`BR-CAP-05`), an ungated
  nopriv-equivalent endpoint class exists (`BR-ADM-07`). Finding `F-DOM-02` — described in
  `confidence-report.md` as the highest-value security observation in the analysis — is knowingly
  carried forward, and the rebuild will ship with five different authorization defaults across its
  surfaces.
- **Category**: operational
- **Probability**: high (certain, by construction — the question is whether it is *exploited*)
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: any new route, policy or endpoint added during the rebuild without
  an explicit authorization decision — the default will silently make it public.
- **Mitigation**: the decision is not relitigated here. It is made *survivable* by making it
  **visible**: a static check that fails the build when a route or policy is registered without an
  explicit authorization declaration, even when the declaration chosen is "public". The permissive
  default remains the runtime behaviour, per the ruling; what changes is that no one reaches it by
  omission.
- **Contingency plan**: if the escape-hatch route count grows past what review can cover, escalate
  to the owner as a re-decision with the count as evidence.
- **Owner**: security lead / owner
- **Status**: accepted (owner ruling, reaffirmed)

### RISK-005
- **Description**: **Regex-based HTML sanitisation must be ported across regex engines.** Owner
  override 2 reproduces KSES verbatim (`BR-KSES-01/04/05/06/07`, `BR-FMT-04`). PHP's PCRE and Ruby's
  Onigmo are **not equivalent**: `^`/`$` anchor semantics, `\A`/`\z` handling, possessive
  quantifiers and atomic groups, backtracking and recursion limits, and UTF-8 handling all differ. A
  pattern that is a correct allowlist under PCRE can admit input under Onigmo. This risk **did not
  exist** while the rules stayed in PHP; it is created by the migration.
- **Category**: technical
- **Probability**: medium
- **Impact**: critical
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: any KSES pattern rewritten "to be more idiomatic Ruby"; any pattern
  where the PHP original used `/D`, `/u`, `/s` or `/m` modifiers; ReDoS timeouts under load.
- **Mitigation**: port the patterns **character-for-character**, then prove them with a differential
  fuzz harness — feed a corpus of known XSS bypass payloads to the PHP original and the Ruby port
  and require byte-identical output. The four-step scheme normalisation (`BR-KSES-04`) and the
  colon-entity cases (`BR-KSES-05/06`) encode two decades of bypass attempts and are the highest-value
  cases to fuzz. Anchor with `\A`/`\z` where the PHP used `^`/`$` with `/D`.
- **Contingency plan**: if differential equivalence cannot be demonstrated for a given pattern,
  escalate that specific pattern to the owner as a scoped re-decision — not the whole override.
- **Owner**: security lead
- **Status**: open

### RISK-006
- **Description**: **PHP-serialised values in the key-value layers do not transfer.** `options` and
  `postmeta` (and `usermeta`, `commentmeta`, `termmeta`) store PHP `serialize()` payloads, including
  nested arrays and, in the wild, object instances. `options` additionally carries autoload
  semantics with a 150 KB threshold that can silently de-autoload the routing table or the cron
  queue (BR-OPT-06, F-RW-02, F-CRON-03). Under Strategy A this transcoding runs **continuously** in
  the CDC pipeline, not once.
- **Category**: technical
- **Probability**: high
- **Impact**: medium
- **Combined severity**: **MEDIUM** — ⬇️ **downgraded from HIGH on 2026-08-21.** With no live
  deployment, the transcoding runs as a **one-time seeding step** against the oracle's corpus rather
  than continuously in a CDC pipeline. It stays firmly on the register because a corpus that does
  not round-trip is a corpus that cannot judge parity — the oracle's value depends on it.
- **Trigger / warning signal**: unserialisable payloads in the seeding dead-letter queue; `O:`
  prefixes (serialised objects) in the corpus; values whose round-trip is lossy.
- **Mitigation**: inventory the payload shapes before Wave 0 completes — count `a:` (array), `O:`
  (object) and scalar payloads across the real corpus. Transcode arrays to `jsonb`. Treat every
  serialised **object** as an explicit human decision, since no automatic mapping is correct.
  Model autoload as a real column with an explicit policy rather than a size heuristic.
- **Contingency plan**: park unmappable payloads in a quarantine table preserving the raw bytes, so
  nothing is destroyed while the mapping is decided.
- **Owner**: data / platform lead
- **Status**: open

### RISK-007
- **Description**: **`0000-00-00 00:00:00` is not a valid PostgreSQL timestamp.** Drafts store it
  (BR-POST-04), which is precisely why the legacy strips `NO_ZERO_DATE` from the SQL mode (BR-DB-10,
  ADR-007). Representing it as `NULL` is the obvious choice and it ripples: every date comparison,
  every ordering, and `BR-POST-01`'s 60-second publish threshold — which the owner confirmed as
  intended product behaviour — all interact with it.
- **Category**: technical
- **Probability**: high
- **Impact**: medium
- **Combined severity**: **MEDIUM** — ⬇️ **downgraded from HIGH on 2026-08-21**, for the same reason
  as RISK-006: a one-time seeding concern rather than a continuous pipeline one. The *modelling*
  half of this risk is undiminished — the `NULL` representation still ripples through every date
  comparison, every ordering and `BR-POST-01`'s 60-second threshold.
- **Trigger / warning signal**: seeding rows rejected on date columns; drafts sorting unexpectedly;
  scheduled-versus-published classification differing from the oracle.
- **Mitigation**: decide the representation once in `target_data_model.md` (the Designer owns this),
  make it `NULL`, and add parity tests specifically for the draft/scheduled/published boundary
  including the 60-second threshold. `NULLS LAST` ordering must be stated explicitly, since MySQL
  and PostgreSQL differ on default NULL ordering.
- **Contingency plan**: if `NULL` proves untenable for a given path, use a sentinel far-past
  timestamp and document it as a deviation rather than mixing both representations.
- **Owner**: architect / Designer role
- **Status**: open

### RISK-008
- **Description**: **The slashing convention vanishes, invalidating the reading of every rule that
  assumed it.** `wp_magic_quotes()` re-slashes every superglobal during boot, so all WordPress input
  arrives slashed and `wp_unslash()` is required before use, enforced by nothing (DR-02, F-FMT-05).
  Rails params are never slashed. `paradigm_decision.md` implication 6 states the consequence:
  **every extracted rule that assumes slashed input must be re-read before being ported.** The
  failure mode is silent — content that is over-escaped, under-escaped or double-unescaped, visible
  only as wrong characters in output.
- **Category**: technical
- **Probability**: high
- **Impact**: medium
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: apostrophes, quotes or backslashes rendering differently from the
  oracle; any ported rule mentioning `wp_slash`/`wp_unslash` carried across without a note.
- **Mitigation**: before Wave 3, sweep the 363 migrated rules for slashing dependence — the Curator
  already flagged `BR-META-02` and the `formatting-and-sanitization` set — and mark each as re-read.
  Include quote-and-backslash-heavy content in the oracle corpus so the diff harness catches what
  review misses.
- **Contingency plan**: none needed beyond the sweep; the risk is caught cheaply by corpus design.
- **Owner**: QA / verification lead
- **Status**: open

### RISK-009
- **Description**: **Multisite via PostgreSQL schemas changes connection handling for the whole
  application.** `BR-MS-01` records the resolved decision: one schema per site, switched via
  `search_path`, replacing `switch_to_blog()`'s global mutation (`BR-MS-02` discards the legacy
  mechanism). A connection returned to the pool carrying a modified `search_path` serves the *next*
  request the wrong tenant's data. Migrations must also run across N schemas rather than one.
- **Category**: technical
- **Probability**: medium
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: any cross-tenant data appearing in a response; migration runtime
  scaling with site count; background jobs executing without an explicit tenant context.
- **Mitigation**: sequence `multisite` **last** (Wave 5) so tenancy is added to a stable system
  rather than threaded through an unstable one. Reset `search_path` on connection checkout, not
  checkin. Require every background job to carry an explicit tenant identifier rather than inheriting
  ambient state — this is the same failure mode as the legacy's unbalanced `switch_to_blog()`
  (F-MS-02), reproduced in a new form.
- **Contingency plan**: if schema-per-site does not hold at the target site count, fall back to a
  discriminator column with mandatory default scoping, and record it as a reversal of `BR-MS-01`.
- **Owner**: data / platform lead
- **Status**: open

### RISK-010
- **Description**: **The block editor is the largest body of work in the project, and the only part
  with no specification inside Reversa's artifacts.** The `@wordpress/*` packages ship only as build
  output (TD-19, Q6, `dependencies.md` §4), so Reversa extracted **no client-side editor behaviour**.
  `block-editor` carries 12 migrated rules, all server-side.
- ⚠️ **Re-scoped 2026-08-21.** The owner ruled the editor must reach **parity**, rejecting DEV-007
  (which would have placed it outside parity) in favour of DEV-012. This does not reduce the risk —
  it **changes its character**: from *unspecified scope* to *specified-by-observation scope*, which
  is larger and slower to pin down. Wave 4 previously had the least specification behind it; it now
  also has the most to build.
- **Category**: organizational
- **Probability**: high
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: Wave 4 estimates derived from rule counts; the Screen Translator
  finding no source for editor screens.
- **Mitigation**: ⚠️ **revised.** Treating the editor as reduced-scope product design is no longer
  available — the owner ruled for parity. The mitigation is instead **method discipline**, per
  DEV-012: (a) build the oracle in Wave 0, since it is the only specification source for the client
  half; (b) generate the inspector's control surface mechanically from the **115 readable
  `block.json` schemas** and the 23 block supports, which *are* in this checkout and cover most panel
  content; (c) author interaction-level parity specs by observation, keeping them in a category
  distinct from the rule-level specs since they have no `BR-MIGRATE-*` behind them; (d) consult the
  upstream `gutenberg` / `wordpress-develop` sources where observation is ambiguous.
- **Contingency plan**: if editor parity proves unreachable within the effort available, the
  remaining lever is **scope reduction by block count** — parity for a defined subset of the 115
  blocks rather than a reduced editing surface across all of them. That keeps "on par" meaningful for
  what ships. It is a re-decision for the owner, not a drift.
- **Owner**: product / owner
- **Status**: open — ⚠️ **escalated in scope 2026-08-21 by owner ruling (DEV-012).** Probability and
  impact are unchanged; what changed is the size of the work the risk governs.

### RISK-011
- **Description**: **Bus factor of one, and unknown target-stack capability.** `migration_brief.md`
  names a single stakeholder who is the sole decision-maker for every human pause, every HUMAN
  DECISION item, the strategy choice, the topology approval and the screen mode approval. The
  brief states no team, and the team's Ruby/Rails proficiency is **not recorded anywhere** — while
  the paradigm gap is HIGH and the appetite transformational, which is the combination that most
  depends on target-stack fluency.
- **Category**: organizational
- **Probability**: high
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: pauses waiting on one person; Rails idiom used as PHP-in-Ruby
  (service locators, global state, procedural modules) — which would silently convert the chosen
  Strategy 1 back into the rejected Strategy 2 of `paradigm_decision.md`.
- **Mitigation**: front-load the Rails idiom in Wave 0, where `html-api` and `style-engine` are
  self-contained enough to be rewritten twice cheaply if the first attempt is not idiomatic. Record
  the resolved architectural decisions in the rebuild's own ADRs as they are made, so the reasoning
  does not live in one head.
- **Contingency plan**: if capability proves the binding constraint, the honest response is to
  reduce scope — fewer modules, not a different paradigm — since a half-adopted paradigm is the
  worst of both.
- **Owner**: owner
- **Status**: open

### RISK-012
- **Description**: **No deadline means no forcing function.** The brief records the deadline as
  "not fixed" and the budget as "not stated". An incremental strategy with neither can stall
  indefinitely in Wave 2, which is the largest and most diff-heavy wave, having already consumed the
  cost of the replication seam without reaching the write-authority flip that retires it.
- **Category**: organizational
- **Probability**: medium
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: Wave 2 running longer than Waves 0 and 1 combined with no parity
  gate met; the CDC seam accruing maintenance work of its own.
- **Mitigation**: make each wave's **parity gate** the milestone, since no date exists to serve as
  one. Gate = the diff harness green against the oracle for that wave's surfaces, over an agreed
  corpus, for an agreed period. A wave that cannot state its gate is not ready to start.
- **Contingency plan**: if Wave 2 stalls, the coherent pivot is to Strategy B for the remainder —
  stop paying for the seam, finish off to the side, cut over once. Recorded so the pivot is a
  decision rather than a drift.
- **Owner**: owner
- **Status**: open — ⚠️ **relatively more important since 2026-08-21.** With no live deployment there
  is no dual-stack running cost to create schedule pressure, and no deadline in the brief. The parity
  gates are now the project's only milestones.

### RISK-013
- **Description**: **Performance parity is not behavioural parity, and the two are entangled at the
  pagination boundary.** The legacy runs `SQL_CALC_FOUND_ROWS` by default so every archive page
  counts the full matching set to render a pager (TD-06, F-QUERY-03), and `meta_value` is unindexed
  in all six meta tables, making `meta_query` the dominant slow-query source (TD-07, F-DD-02,
  F-META-03). A faithful rebuild that fixes both is *observably different* at the pager.
- **Category**: technical
- **Probability**: medium
- **Impact**: medium
- **Combined severity**: **MEDIUM**
- **Trigger / warning signal**: diff-harness failures confined to pagination totals; response-time
  regressions on meta-filtered queries.
- **Mitigation**: decide deliberately whether exact total counts are part of parity or not, and
  record the answer as a deviation if not. Index the meta value column in the target — the legacy's
  omission is debt, not behaviour.
- **Contingency plan**: retain exact counts behind a flag for surfaces where the oracle diff proves
  they are observable.
- **Owner**: architect / Designer role
- **Status**: open

### RISK-014
- **Description**: **Character-set edges differ between MySQL `utf8mb4` and PostgreSQL UTF-8.** The
  legacy *rejects* writes containing text the target column's charset cannot represent (`BR-DB-06`,
  discarded as paradigm-related), and separately encodes emoji to entities on some paths. PostgreSQL
  accepts the full range, so content that the legacy silently truncated or refused now round-trips —
  a divergence in the *permissive* direction, which diffing tends to miss.
- **Category**: technical
- **Probability**: medium
- **Impact**: medium
- **Combined severity**: **MEDIUM**
- **Trigger / warning signal**: 4-byte characters surviving in the rebuild that the oracle dropped.
- **Mitigation**: include 4-byte UTF-8 and emoji content in the oracle corpus explicitly, and record
  the resulting differences as accepted deviations rather than chasing them to parity.
- **Contingency plan**: none required; this is a divergence to document, not to prevent.
- **Owner**: data / platform lead
- **Status**: open

### RISK-015
- **Description**: **Thirteen vendored PHP libraries need Ruby counterparts, with no lockfile to
  enumerate what they actually do.** `dependencies.md` §8 records no automated CVE path for any of
  them. Most map cleanly (SimplePie → Feedjira, PHPMailer → Action Mailer, Requests → Faraday/Net
  ::HTTP, getID3 → an ffmpeg binding, POMO → Ruby I18n, PclZip → Rubyzip). Two do not map so much as
  **disappear**: `sodium_compat`'s Ed25519 verification of update packages and `PclZip`'s pure-PHP
  fallback exist to serve `updates-and-upgrader`, which a Rails deployment replaces entirely.
- **Category**: technical
- **Probability**: medium
- **Impact**: low
- **Combined severity**: **MEDIUM**
- **Trigger / warning signal**: a Wave 5 module blocked on a library with no counterpart; behaviour
  found to depend on a vendored library's quirk rather than on WordPress code.
- **Mitigation**: map all 13 during Wave 0 and record the mapping alongside `target_architecture.md`.
  Where a library disappears with its module, note it so the absence is not read as an oversight.
- **Contingency plan**: for any library with no counterpart, treat its behaviour as a scoped
  reimplementation and size it separately rather than assuming a drop-in.
- **Owner**: platform lead
- **Status**: open

### RISK-016
- **Description**: **A wave can be individually parity-clean and jointly wrong.** F-SIM-05 records
  that the most consequential couplings are invisible from either module alone: draft dates ↔ SQL
  mode, `pagination_base` ↔ legal slugs (BR-POST-07, F-RW-06), the 150 KB autoload threshold ↔ the
  router and the cron queue (BR-OPT-06), term counts ↔ `post_status` (BR-TAX-11), session token
  destruction ↔ every outstanding nonce (BR-AUTH-15). Wave-by-wave verification tests exactly the
  boundaries that hide these.
- **Category**: technical
- **Probability**: medium
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: parity gates passing per wave while end-to-end flows fail; any
  coupling in `spec-impact-matrix.md` §6 with no corresponding cross-wave test.
- **Mitigation**: the **integration checkpoint at the end of Wave 3**, spanning the whole former
  23-module component, exercising each coupling in §6 as an end-to-end scenario rather than a unit.
  This is the checkpoint `migration_brief.md`'s primary risk called for.
- **Contingency plan**: hold the write-authority flip until the checkpoint passes; it is the last
  reversible moment.
- **Owner**: QA / verification lead
- **Status**: open

### RISK-017
- **Description**: **The content core has no enforceable dependency direction.** Topology option 3
  (chosen 2026-08-21) packages only the three leaf libraries — `markup`, `sanitizing`, `styling` —
  and leaves `publishing`, `classification`, `discussion`, `identity`, `access`, `retrieval` and
  `routing` as Ruby namespaces in one conventional `app/`. That is the same region where the legacy's
  23-module strongly connected component lived (F-SIM-01), and it carries forward the property that
  produced it: `architecture.md` §2 records that the legacy layering was *"descriptive, not
  enforced"*, and a namespace is likewise descriptive. A cross-namespace reference that closes a
  loop is legal Ruby and passes review as easily as it compiles.
- **Category**: technical
- **Probability**: medium
- **Impact**: high
- **Combined severity**: **HIGH**
- **Trigger / warning signal**: `Access::` referenced from inside a `Publishing::` model (the
  authorization extraction is what breaks the users↔posts cycle — a reference back into it re-closes
  the loop); `Classification::Term` reaching into `Publishing::Post` for anything other than the
  counter cache; any model requiring another context's constant at load time rather than call time.
- **Mitigation**: **detection replaces prevention.** A CI job parses constant references between the
  `app/models/<context>/` namespaces, builds the directed graph and fails the build if it is not
  acyclic — roughly thirty lines of Ruby over the existing constant table, with no Packwerk, no
  `package.yml` and nothing new to learn. It cannot *prevent* a cross-namespace reference the way a
  pack boundary does, but it makes the one outcome that matters — a **cycle** — impossible to
  introduce unnoticed. **It must ship in Wave 0**; added later, it is worth almost nothing, because
  the graph it exists to keep acyclic already is not.
- **Contingency plan**: if the check fails repeatedly and the fixes are consistently "add another
  cross-namespace reference and move on", the namespaces are not holding and the content core wants
  real boundaries. The reversal to option 2 is cheapest before Wave 3
  (`migration_strategy.md`), and converting namespaces to packs is mechanical — the groupings
  already exist.
- **Owner**: architect / Designer role
- **Status**: open — consequence of a recorded owner decision, mitigated rather than eliminated

### RISK-018
- **Description**: **The target platform is carved out for three screens.** The confirmed target is
  `rails-hotwire` — server-rendered HTML with Turbo and Stimulus. The DEV-012 ruling that the editor
  must reach parity almost certainly requires a **React island** for `console.post`,
  `console.post-new` and `console.site-editor`, because a canvas with live block manipulation,
  multi-block selection and document-wide undo is not a Turbo-frame problem. That is the third
  option presented at the Screen Translator's Phase 1 pause ("Hotwire for console, React for the
  editor") arriving through the back door.
- **Category**: technical
- **Probability**: high
- **Impact**: medium
- **Combined severity**: **MEDIUM**
- **Trigger / warning signal**: editor work attempting to reach parity in Stimulus alone and
  stalling; a second build pipeline appearing in the repository without a decision behind it.
- **Mitigation**: decide it deliberately rather than discovering it. If a React island is needed,
  scope it explicitly to the three editor routes, keep the other 141 screens purely server-rendered,
  and treat the island's boundary as a real interface — not as permission for React to spread into
  the console.
- **Contingency plan**: if maintaining two frontend stacks proves untenable, the honest re-decision
  is at the platform level (all-SPA or reduced editor parity), not a slow drift where half the
  console becomes React.
- **Owner**: architect / owner
- **Status**: open — consequence of a recorded owner decision

---

## Summary by severity

> **Re-scored 2026-08-21** after the owner confirmed the strategy (**A + C**) and answered the open
> assumption: **there is no live deployment.** Four items moved. The original scores are preserved
> inline against each risk so the reasoning is auditable.

| Severity | Count | IDs |
|---|---:|---|
| Critical | 1 | RISK-001 |
| High | 10 | RISK-003, RISK-004, RISK-005, RISK-008, RISK-009, RISK-010, RISK-011, RISK-012, RISK-016, RISK-017 |
| Medium | 6 | RISK-006, RISK-007, RISK-013, RISK-014, RISK-015, RISK-018 |
| Low | 1 | RISK-002 |
| **Total** | **18** | |

| Movement | Risk | From → To | Cause |
|---|---|---|---|
| ⬇️ | RISK-002 dual write authority | CRITICAL → LOW | No second writer exists. |
| ⬇️ | RISK-006 serialised payloads | HIGH → MEDIUM | One-time seeding, not continuous CDC. |
| ⬇️ | RISK-007 `0000-00-00` dates | HIGH → MEDIUM | One-time seeding; modelling half undiminished. |
| ⚠️ | RISK-001 no oracle | CRITICAL, unchanged | Everything else was de-risked by the answer; this was not. It is now the single point of failure. |
| ⚠️ | RISK-012 no forcing function | HIGH, unchanged | Dual-stack cost removed, so the parity gates are the only remaining schedule pressure. |
| ➕ | RISK-017 unenforced core boundaries | **new, HIGH** | Added 2026-08-21 on the owner's topology option 3. The content core keeps convention-only boundaries; mitigated by a Wave 0 cycle-detection CI job. |
| ➕ | RISK-018 platform carve-out | **new, MEDIUM** | Added 2026-08-21. The editor-parity ruling (DEV-012) likely requires a React island inside a Hotwire console. |
| ⚠️ | RISK-010 editor scope | HIGH, **re-scoped** | The owner rejected DEV-007 and ruled for editor parity. Character changes from *unspecified* to *specified-by-observation*; the mitigation is rewritten. |

**Reading the register.** One Critical item remains, and it is the one that can invalidate the whole
effort rather than damage part of it: **RISK-001 means nothing can be *proven*.** It is addressed in
Wave 0, before any rule is ported. Of the 10 High items, six descend directly from the paradigm gap
and are listed again in the section below; two of those (RISK-004, RISK-005) exist only because of
the owner's overrides and would not appear in this register otherwise; three (RISK-010, RISK-011,
RISK-012) are organizational and have no technical mitigation — they are managed, not solved.

---

## Risks related to the target paradigm

> Risks whose direct origin is the gap recorded in `paradigm_decision.md`. Each names the implication
> it descends from.

- **RISK-003** — implication 5. Sixteen post types in one table force an explicit modelling fork
  (STI versus separate models) that the legacy never had to make.
- **RISK-005** — the amended Designer contract. Regex sanitisation survives the paradigm change by
  owner ruling, and therefore must cross a regex-engine boundary it never had to cross before.
- **RISK-006** — implication 1 and the absence of an ORM. Global, schemaless key-value storage has
  no Active Record analogue; PHP-serialised payloads are a paradigm artifact, not data.
- **RISK-007** — implication 4. Derived state moves from inline procedure into the model, and the
  draft-date sentinel is the sharpest case: it exists only because the legacy has no transactions
  and no ORM to object.
- **RISK-008** — implication 6. The slashing convention vanishes, so the *reading* of every
  input-handling rule is provisional until re-checked.
- **RISK-009** — implication 1. `switch_to_blog()`'s global mutation has no Rails analogue;
  `search_path` switching reproduces the same unbalanced-state failure mode in a new place.
- **RISK-004** — implication 2, inverted by owner ruling. Because the hook system is not
  reproduced, the documented default becomes **permanent and final** — which is exactly what makes
  reproducing the *permissive* authorization defaults a lasting property rather than a changeable
  one.
- **RISK-016** — implication 2 again. With filters gone, each rule's unfiltered default is the whole
  specification, so cross-module couplings that the extraction could only see from outside a module
  must be verified from outside a wave.


---

## Risk status after the build (2026-08-24)

> Added when the build reached its current state. See `as_built.md` for the whole picture.

| Risk | Now |
|---|---|
| **RISK-010** — the editor is unspecifiable from Reversa's artifacts | ✅ **RETIRED, by a route the register did not consider.** Rather than reconstruct the editor from observation, the rebuild now runs the **upstream `@wordpress/*` packages themselves** against its own wp/v2 API (DEV-015). The risk was never "can we rebuild Gutenberg" — it was "can we specify it", and the answer was to stop trying to. The work relocated to the REST surface, which IS fully specified by the oracle. |
| **RISK-018** — the platform carve-out (a React island inside a Hotwire console) | ✅ **RETIRED.** The carve-out exists and is larger than anticipated (a ~21 MB bundle on three screens), but it is upstream code rather than bespoke, so it carries no ongoing specification burden. |
| **RISK-001** — the oracle is the only executable definition | 🔴 **Unchanged and vindicated.** Every defect found late in this project was found by asking the oracle something the corpus had not asked before. The oracle's value went UP, not down, as the rebuild matured. |
| **RISK-013** — estimated pagination totals are observably different | Unchanged. |
| **RISK-014** — encoding fidelity | Held: the corpus carries 4-byte UTF-8, emoji and backslash-heavy text, and the widened corpus added percent-encoded term slugs, which found two real 404 bugs. |

### New risks the build introduced

| # | Risk | Severity |
|---|---|---|
| **RISK-019** | ✅ **RESOLVED 2026-08-24.** The rebuild now ships `_reversa_forward/rebuild/LICENSE` — GPL v2 **or later**, matching WordPress itself and compatible with the bundled `@wordpress/*` packages that forced the question. The GPL body is copied verbatim from the oracle's own `license.txt` rather than retyped, and `package.json` declares `GPL-2.0-or-later`. | ~~HIGH~~ closed |
| **RISK-020** | **No CI.** Every gate result on record was produced by hand on a quiet machine. Nothing prevents a commit from silently breaking parity, and the project's own history shows how easily a green gate hides defects. | **HIGH** |
| **RISK-021** | **Coverage floor mistaken for coverage.** 262/363 rules carry a citation, but a citation means only that an id was written beside an implementation. 101 rules have neither. Reading 72% as "72% verified" would overstate the position materially. | **MEDIUM** |
| **RISK-022** | **Performance is 1.99× the oracle**, concentrated in Ruby CPU inside the block renderers rather than in SQL (~7% of wall time). Correct and slower is still a migration risk; there is no target and no budget. | **MEDIUM** |
| **RISK-023** | **Unreviewed raw-HTML surface.** 22 `html_safe`/`raw` uses in the render path, none security-reviewed. The private-post disclosure found by the widened corpus shows this class of defect is present, not theoretical. | **MEDIUM** |
