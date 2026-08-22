---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: parity_specs
producedBy: inspector
hash: "sha256:cb6dc239726aa289548da64dec0b483cbdf557113b44ed441b827a5e49d11c07"
---

# Parity Specs

> Strategy for validating behavioural equivalence between the legacy system and the new one,
> adapted to the paradigm chosen in `paradigm_decision.md`.
> Required reading before this: `paradigm_decision.md`, `topology_decision.md`,
> `screen_modernization_decision.md`.

## The single fact that shapes this entire document

**The legacy system ships with no tests.** `inventory.md` §1 and TD-18 record it: no PHPUnit config,
no `tests/`, no CI, and all 431 rules were verified by **reading**, never by executing. There is also
**no live deployment** (owner ruling), so there is no production traffic to mirror.

Everything below therefore rests on one component: the **reference WordPress `7.2-alpha-63330`
oracle** built in Wave 0 (AD-08). It is not test tooling — it is the project's only executable
definition of the 363 migrated rules. RISK-001 is the project's single point of failure, and this
document is what fails with it.

## General strategy

- **Applicable validation modes**:
  - [ ] ~~Shadow mode (traffic mirroring)~~ — **not applicable.** No live deployment, so there is no
        traffic to mirror. The nearest equivalent is *replay* against the oracle, below.
  - [x] **Characterization tests derived from the oracle** — ⚠️ **not from an existing suite.** The
        legacy has none. These are authored by replaying a request corpus against the reference
        instance and recording its responses as the expected behaviour.
  - [x] **Contract tests** — for `PublicApi` (the REST successor) and for `Egress` (outbound HTTP,
        including the SSRF policy).
  - [x] **Data parity** — counts and checksums after every oracle-corpus seeding run
        (`data_migration_plan.md` § Quality validation).
  - [x] **Golden-file comparison** — 18 `web.*` screens, per `screen_modernization_decision.md`
        hybrid mode. ⚠️ Currently **manual**: every entry in `_reversa_sdd/screens/golden/manifest.yaml`
        is `present: false` (DEV-001).
  - [x] **Screen contract tests** — the 123 in-scope modernized screens: component hierarchy,
        declared events, textual content, four states. No byte comparison.
  - [x] **Observation-authored interaction specs** — ⚠️ **a category unique to this project.** The
        editor (DEV-012) has *no* `BR-MIGRATE-*` behind it; its specs are authored by observing the
        oracle. See § Editor parity.
  - [x] **Differential fuzzing** — `sanitizing` 📦 only, against the PHP original (RISK-005).

## "Parity accepted" criteria

Per `references/parity-coverage-matrix.md`, this is a **web app without strong regulation**
(`migration_brief.md` records **no regulatory integrations**), whose baseline metric is *functional
divergence < 1% over 7 days*. That baseline is **tightened here**, for a reason specific to this
migration.

- **Primary metric**: **zero unexplained divergence** on any behaviour traceable to a
  `BR-MIGRATE-*` rule, measured over the parity gate's observation window. Every observed diff must
  resolve to one of:
  1. one of the **6 deliberate deviations** (`target_business_rules.md`),
  2. one of the **9 owner-override rules**,
  3. an entry in `screen_deviation_log.md` (10 approved + DEV-012),
  4. a **recorded accepted deviation** created during the wave and written down.

  Anything else is a defect.

- **Why zero and not < 1%.** A percentage threshold assumes divergences are noise. Here they are
  not: AD-01 removes the hook system, so **the documented default becomes the permanent, only
  behaviour** — there is no filter to correct it afterwards. A 1% tolerance would permanently bake in
  whatever fell inside it. The rule count is finite and enumerable (363), so per-rule accounting is
  achievable in a way it would not be for a system measured in request volume.

- **Observation window**: per wave, the diff harness green across the agreed corpus for **5
  consecutive runs** with no unexplained diff. ⚠️ Not a calendar period — with no production traffic,
  elapsed time proves nothing; only corpus coverage does.

- **Blocking criterion**: any unexplained divergence on a **content write path** blocks the wave.
  On a write path, "we do not know why it differs" is disqualifying, because the legacy has no
  transactions with which to repair a divergence that reaches the data (TD-05, DR-07).

- **The Wave 3 gate is the one that matters**: the integration checkpoint spanning the former
  23-module component must exercise each coupling in `spec-impact-matrix.md` §6 end-to-end. See
  `parity_tests/12-cross-context-integration.feature`.

## Coverage adapted to the paradigm

**Detected transition: procedural (+ synchronous observer) → classic OO / Active Record.**

Per `references/parity-coverage-matrix.md`, the minimum for `procedural → OO` is
**`@parity` + `@invariant`**. Event-driven dimensions do **not** apply: `target_domain_model.md`
records no domain events, no outbox and no DLQ, because the chosen paradigm is not event-driven.
Scenarios tagged `@idempotency`, `@ordering`, `@dlq` or `@saga` are therefore **deliberately absent**
— generating them would test machinery this system does not have.

### Procedural → OO: the mandatory additional dimensions

- **Aggregate invariants** — every invariant the legacy enforced in PHP must be shown to hold *at
  the database*, not merely in the model. `paradigm_decision.md` implication 3 and AD-05 turn
  check-then-act loops into constraints, so the parity test must attempt the violation and assert
  the constraint rejects it. F-DOM-04 is the reason: **every uniqueness guarantee in WordPress is
  advisory**, so a test that only exercises the happy path proves nothing new.
- **Validation in factories / constructors** — derived state moved from inline procedure into the
  model (implication 4). Test the *behaviour*, not the mechanism: assert that publishing with a date
  90 seconds ahead yields a scheduled record, without asserting how the model computes it. This is
  the Inspector contract `paradigm_decision.md` set.

### Three dimensions this transition needs that the matrix does not list

1. **Filter-independence** (implication 2). Every rule states the *unfiltered default*. Any legacy
   behaviour that requires a filter to observe is **out of parity scope**, and must be noted here
   rather than tested. Conversely, a target behaviour that varies at runtime is a **defect**, because
   nothing in the target is supposed to be adjustable.
2. **Slashing-independence** (implication 6). The corpus must carry quote- and backslash-heavy text
   so that a rule mis-read as assuming slashed input fails visibly rather than silently (RISK-008).
3. **Regex-engine equivalence** (RISK-005). Owner override 2 reproduces KSES verbatim, so the ported
   patterns must be proven byte-identical to the PHP original across an XSS bypass corpus. PCRE and
   Onigmo differ on anchors, possessive quantifiers, backtracking limits and Unicode handling. This
   is the only place a *differential* test is mandatory rather than a comparative one.

## Screen parity

Mode is **hybrid** (`screen_modernization_decision.md`), so the strategy is declared per screen.

| Group | Screens | Strategy | Location |
|---|---:|---|---|
| `web.*` | 18 | **golden-file comparison**, within the `normalizationRules` declared in `manifest.yaml` | `parity_tests/screens/*.feature`, tagged `@visual-parity` |
| `console.*`, `auth.*`, `tenancy.*` | 123 in scope | **screen contract test** — hierarchy, declared events, textual content, four states. No byte comparison. | `parity_tests/screens/*.feature`, tagged `@screen-contract` |
| editor (3) | 3 | **observation-authored interaction specs** | § Editor parity below |
| not built | 14 | none | — |

⚠️ **The 18 `@visual-parity` scenarios are emitted, but validation is manual until capture runs.**
Every entry in `manifest.yaml` is `present: false`. Per the Screen Translator's edge case for
literal mode with no golden files, the scenarios exist so the work is visible; they cannot execute
yet. DEV-001 is approved **conditionally** on the capture happening — the Inspector must **remove
this exception** once `manifest.yaml` reports `present: true`, rather than letting a temporary
allowance become permanent.

### Editor parity — a category of its own

DEV-012 (replacing the rejected DEV-007) rules that the editor must reach parity. This creates the
**only** parity specs in this project with no `BR-MIGRATE-*` behind them, and they must not be folded
into the rule-level specs.

| Layer | Specification source | Testable how |
|---|---|---|
| 115 block schemas, 23 block supports | ✅ readable — `block.json`, `block-supports/` | conventional contract tests against the schemas |
| server-side block rendering | ✅ readable — 6 `Composition::Renderer` rules | rule-level parity, in the numbered features |
| the `theme.json` four-origin cascade | ✅ readable — `BR-GS-01/05/06/07` | rule-level parity |
| the editing **canvas**, inspector, chrome | ❌ **observation only** | interaction specs authored against the running oracle |

⚠️ **Consequence for this document's primary metric**: "zero unexplained divergence traceable to a
`BR-MIGRATE-*` rule" **cannot** cover the editor's client half, because no such rule exists. Editor
parity is measured against *observed oracle behaviour*, which is a weaker and slower-converging
standard. Stated here so the metric is not read as covering more than it does.

## Test types to apply

- **Functional (rule-level)**: 363 `BR-MIGRATE-*` rules, executed against the oracle. Tooling: the
  Wave 0 diff harness + RSpec.
- **Invariant (constraint-level)**: attempt each violation the legacy enforced in PHP; assert the
  database rejects it. Covers the unique indexes and FKs added by AD-05 and `target_data_model.md`.
- **Contract**: `PublicApi` request/response shapes; `Egress` SSRF policy.
- **Differential**: `sanitizing` 📦 against the PHP original (RISK-005).
- **Data**: counts, checksums, referential integrity after each seeding run.
- **Load / performance**: ⚠️ **out of parity scope, deliberately.** RISK-013 records that
  performance and behaviour are entangled at the pager (`SQL_CALC_FOUND_ROWS`, TD-06), so DEV-003
  removes exact totals from scope on six screens. Performance is a target, not a parity criterion.
- **Resilience**: minimal — no queue, no distributed transaction, no external dependency in the
  critical path. `Egress` failure handling is the exception.

## Reuse of `characterization_specs` from the discovery team

⚠️ **`_reversa_sdd/characterization_specs/` does not exist. Nothing to reuse.**

The gap is documented here as the skill requires, and it is not a small one: characterization specs
are normally the bridge between a legacy system's observed behaviour and a rebuild's tests, and
their absence is why the oracle has to be built at all.

**What is available instead**, and how each is used:

| Available | Used for |
|---|---|
| `_reversa_sdd/flowcharts/` (15 modules) | deriving the critical flows below — the closest thing to sequences in this analysis |
| `code-analysis.md` (298 KB, 431 rules) | the rule statements themselves, each with a `file:line` |
| `traceability/spec-impact-matrix.md` §6 | the cross-module couplings, which drive feature 12 |
| `target_business_rules.md` | the 363 rules with their target ids |

⚠️ `_reversa_sdd/sequences/` does not exist either; `flowcharts/` covers 15 of 44 modules.

## Exceptions

Every approved deviation, propagated here with its origin.

### From `target_business_rules.md` — 6 deliberate deviations

| Rule | Legacy | Target |
|---|---|---|
| `BR-CMT-04` | flood verdict defaults false — **no rate limit enforced** | real rate limiting |
| `BR-CMT-08` | keywords match as unquoted substrings across six fields | word-boundary matching |
| `BR-CMT-10` | spam vs trash depends on `EMPTY_TRASH_DAYS` | decoupled; disallowed → spam |
| `BR-OPT-04` | `update_option` returns false for *unchanged* | Active Record save semantics |
| `BR-POST-10` | `guid` seeded from permalink, never updated | UUID at creation |
| `BR-HTTP-01` | SSRF validation opt-in by function name | validated by default |

### From `target_business_rules.md` — 9 owner overrides

⚠️ **These assert the *permissive* behaviour as specification.** `BR-REST-05`, `BR-CAP-05`,
`BR-ADM-07` (authorization defaults) and `BR-KSES-01/04/05/06/07`, `BR-FMT-04` (regex sanitisation).
See `parity_tests/04-authorization-defaults.feature` and `05-kses-sanitization.feature`.

### From `screen_deviation_log.md` — 10 approved + DEV-012

| ID | Effect on parity |
|---|---|
| DEV-001 | ⚠️ **temporary** — 18 `web.*` visual parity manual until capture; **remove on capture** |
| DEV-002 | screen composition not comparable; compare resulting fields and values |
| DEV-003 | exact pagination totals out of scope on 6 screens |
| DEV-004 | one extra confirmation step before destructive bulk actions; compare outcome |
| DEV-005 | console colours out of visual scope entirely |
| DEV-006 | auth URL comparison invalid; compare behaviour and literal strings |
| DEV-008 | `admin_color` field absent from the profile form |
| DEV-009 | ⚠️ branding and project-identity string diffs are **expected**; all functional strings remain verbatim |
| DEV-010 | `auth.retrievepassword` is one route, not two |
| DEV-011 | 5 plugin-management screens have no target; themes do |
| DEV-012 | editor parity is observation-based; see § Editor parity |

*(DEV-007 was rejected and is archived, not propagated.)*

## ⚠️ Reconciliation: the discard-count discrepancy (ambiguity P-3), RESOLVED

The Inspector was asked to reconcile three disagreeing counts before handoff. Done, by counting the
artifacts directly.

| Source | Claim | Actual |
|---|---|---|
| `target_business_rules.md` § Summary | 68 DISCARD | ✅ **68 rows, 68 distinct legacy ids** |
| `target_business_rules.md` prose | "54 paradigm, 11 out of scope, 1 resolved ruling" (= 66) | ❌ the reason column reads **54 paradigm, 11 scope, 3 ruling** = 68 |
| `discard_log.md` header | "65 discarded: 54 paradigm-related, 11 out of scope" | ✅ internally consistent — it documents 54 + 11 = **65** |

**Conclusion: no rule was lost.** 363 MIGRATE + 68 DISCARD = **431** ✅. The set is correct and
complete; two documents mis-state their own tallies.

**The exact gap**: three rules discarded **by owner ruling** appear in `target_business_rules.md`'s
DISCARD table but were never written into `discard_log.md`, which was authored before the pause that
produced them:

| Target id | Legacy id | Rule | Where the ruling is recorded |
|---|---|---|---|
| `BR-DISCARD-030` | `BR-OPT-04` | `update_option()` returns false when unchanged | `ambiguity_log.md` item 12 — also a deliberate deviation |
| `BR-DISCARD-046` | `BR-CAP-14` | `get_super_admins()` prefers the `$super_admins` global over the network option | `ambiguity_log.md` item 21 — discarded as a privilege-escalation vector |
| `BR-DISCARD-062` | `BR-MS-02` | `switch_to_blog()` keeps a stack requiring paired `restore_current_blog()` | `ambiguity_log.md` item 20 — replaced by `search_path` switching |

**The fix, not applied here**: `discard_log.md` needs three appended entries and a header of 68;
`target_business_rules.md`'s prose needs "3 resolved rulings". The Inspector does **not** rewrite the
Curator's artifacts — doing so would erase the audit trail showing the documents were authored
before the ruling. Recorded in `ambiguity_log.md` as **DEFERRED TO CODING**, with the exact edit
specified above.

**Effect on parity: none.** All three rules are already correctly handled — `BR-OPT-04` as an
exception above, `BR-CAP-14` as an `AGG-User` invariant, `BR-MS-02` in the Tenancy concern.

## ⚠️ Classification: the 47 Platform rules (ambiguity P-4), RESOLVED

The Designer flagged that `Platform` (BC-15) absorbs six legacy modules whose rules may describe
machinery the target does not have, and asked the Inspector to decide rule by rule. Done — all 47
classified below. **Nothing is reclassified out of MIGRATE**; what changes is *how each is proven*.

| Bucket | Count | Meaning |
|---|---:|---|
| **PARITY** | 15 | real behaviour; testable directly, sometimes via a different mechanism |
| **PARITY (contingent)** | 4 | real behaviour, but only because `console.theme-install` survived DEV-011 |
| **DEVIATION** | 18 | the mechanism is replaced by the framework; the **invariant** is named and kept |
| **VOID** | 10 | the rule presupposes something a *later decision* removed |

### PARITY — 15 rules, proven directly

`BR-BOOT-04` (unknown environment → production) · `BR-BOOT-08` (child theme loads before parent —
still meaningful, themes survived) · `BR-BOOT-10` / `BR-ERR-05` (error handling available before the
database connects) · `BR-CACHE-02` (per-tenant key namespacing, Wave 5) · `BR-CACHE-05` (a cached
object cannot be mutated by its caller — Rails.cache gives this by serializing rather than
double-cloning, **same guarantee, different mechanism**) · `BR-CACHE-09` (non-persistent groups) ·
`BR-ERR-01` (an error carries multiple messages; the first is surfaced — `ActiveModel::Errors`) ·
`BR-ERR-02` (which failures are fatal) · `BR-SH-01` (slow checks run out of band) · `BR-SH-02`
(three-level status) · `BR-SH-05` (health exposed over the API) · plus the three **invariants** below.

⚠️ `BR-UPD-07`, `BR-UPD-08`, `BR-UPD-09` are the interesting case: `upgrade_NNN()` sequencing,
`dbDelta()` schema diffing and `$wp_db_version` are replaced *wholesale* by Rails migrations — yet
the invariant survives **exactly**: one monotonic schema-version marker, migrations applied in
sequence from the current version. Test the invariant; do not test `dbDelta`.

### PARITY (contingent) — 4 rules

`BR-FS-07`, `BR-FS-09`, `BR-FS-10` and `BR-UPD-04` describe **Ed25519 signature verification of
downloaded packages** (SHA-384, detached signatures, trusted keys, verify-before-extract). These
survive **only because DEV-011 kept `console.theme-install`**. If theme installation from a remote
directory is ever dropped, all four become VOID together. ⚠️ They are security rules, so they are
worth keeping visible rather than quietly inherited: `parity_tests/11-egress-and-ssrf.feature`
covers the download path.

### DEVIATION — 18 rules, invariant named

- **`filesystem-api` (8 of 11)**: `BR-FS-01`…`06`, `BR-FS-08`, `BR-FS-11`. `FS_METHOD` detection,
  file-ownership probes, the direct→ssh2→ftpext→ftpsockets fallback chain, the pure-PHP sodium speed
  test and the PclZip fallback all exist for **one reason**: WordPress writes to its own directory on
  shared hosting with no shell (`dependencies.md` §1, ADR-003). A Rails deployment does not
  self-modify. **Invariant kept**: the application never writes outside its declared storage paths.
- **`updates-and-upgrader` (4)**: `BR-UPD-01`/`02`/`03` (update-check transients, escalating
  timeouts, 12-hour suppression) and `BR-UPD-05` (maintenance mode during install). **Invariant
  kept**: remote checks are rate-limited and never block a request.
- **`cache-and-object-cache` (3)**: `BR-CACHE-03` (invalid key → `_doing_it_wrong`), `BR-CACHE-07`
  (`add()` respects suspension, `set()` does not), `BR-CACHE-08` (empty group → `default`).
  **Invariant kept**: a malformed cache operation fails safely rather than corrupting a namespace.
- **`bootstrap-and-load` (2)**: `BR-BOOT-02` (`.maintenance` ignored after 600 s) — **invariant
  kept, and it is a good one**: *a crashed upgrade cannot lock the site permanently*. `BR-BOOT-09`
  (redirect to the web installer) — `console.install` is specified as not built.
- **`site-health` (1)**: `BR-SH-03` (instantiated at boot so its cron can fire) — a scheduling
  artifact; Active Job needs no such hook.

### ⚠️ VOID — 10 rules, and why this is the finding worth reading

These rules are not wrong and were not mis-classified by the Curator. They **presuppose something a
later decision removed**, and in seven cases that decision was made *four agents downstream*.

| Rule | Presupposes | Removed by |
|---|---|---|
| `BR-ERR-03` | the `wp_should_handle_php_error` filter | **AD-01** — no hook system |
| `BR-ERR-04` | a `fatal-error-handler.php` drop-in | **AD-01** / F-BOOT-03 — filename-based replacement discarded |
| `BR-BOOT-05` | paused **plugins** skipped at boot | **DEV-011** — plugins do not exist |
| `BR-ERR-06` | identifying the offending **extension** from a file path | DEV-011 |
| `BR-ERR-07` | recovery-mode email rate limiting | DEV-011 |
| `BR-ERR-08` | recovery-link TTL ≥ email rate limit | DEV-011 |
| `BR-ERR-09` | the recovery-mode cookie | DEV-011 |
| `BR-ERR-10` | paused extensions skipped until recovery exits | DEV-011 |
| `BR-UPD-06` | per-version file manifests removing obsolete **core** files | core self-update does not exist |
| `BR-SH-04` | the loopback test detecting that **WP-Cron cannot self-invoke** | **Q7** — a real scheduler was adopted at extraction time |

**The finding: an entire subsystem's rules were voided by a decision taken at the screen layer.**
Six of the ten (`BR-ERR-06`…`10`, `BR-BOOT-05`) are the **recovery-mode cluster**, and recovery mode
exists to pause a fatally-erroring *plugin*. `migration_brief.md` names recovery mode nowhere;
`paradigm_decision.md` does not touch it; the Curator classified all ten MIGRATE in good faith. They
became unreachable only when DEV-011 answered *"does the rebuild have plugins?"* with **no** — a
question first asked by the Screen Translator, because it was the first agent that had to draw a
list of them.

⚠️ **Themes can still fatal.** If a fatal error in a *theme* should be recoverable, then a
recovery mechanism is still wanted — with a narrower blast radius and a much simpler design than the
legacy's. That is a **product decision, not a parity question**, and it is recorded in
`ambiguity_log.md` as DEFERRED TO CODING rather than decided here.

**No parity test is written for the 10 VOID rules.** Writing one would produce a test that cannot
pass, which the Designer's P-4 note explicitly warned against.

## Outputs

- `parity_tests/*.feature` — **12** numbered critical flows.
- `parity_tests/screens/*.feature` — **19**: 18 `@visual-parity` (one per literal screen) and 1
  `@screen-contract` covering the modernized set by pattern.

## Notes

**Three things to hold on to when reading the feature files:**

1. **`@invariant` scenarios attempt the violation.** F-DOM-04 records that every uniqueness guarantee
   in WordPress is *advisory* — enforced by a check-then-act loop with no constraint behind it. A
   parity test that only walks the happy path would pass against both systems and prove nothing about
   the thing AD-05 actually changed. Every `@invariant` scenario therefore tries to break the rule
   and asserts the **database** refuses.

2. **The 9 override scenarios assert permissive behaviour on purpose.** Reading
   `04-authorization-defaults.feature` for the first time is uncomfortable — it asserts that an
   unguarded route is public. That is the specification, by owner ruling, reaffirmed when the
   conflict was put directly. AD-01 makes it permanent. The test's job is to make it **visible and
   deliberate** rather than accidental.

3. **The corpus is the coverage.** With no production traffic and no legacy test suite, a scenario is
   only as strong as the data the oracle was seeded with. `data_migration_plan.md` defines that
   corpus, and an under-seeded oracle produces green tests that prove very little. If any single
   thing in this pipeline deserves over-investment, it is the corpus.
