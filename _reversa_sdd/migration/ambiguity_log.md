---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: ambiguity_log
producedBy: orchestrator
hash: "sha256:82e23d845af354f7f3af698e8d6011c4019387b4909e31da600cccdd4165d695"
---

# Ambiguity Log

> Consolidated by the `/reversa-migrate` orchestrator after each agent.

## PENDING (0)

✅ **Zero pending items**, as the pipeline requires before handoff. P-1 and P-2 were resolved at the
post-Strategist pause; P-5 … P-8 at the post-Screen-Translator pause; **P-3 and P-4 were resolved by
the Inspector**, and **P-9 moved to DEFERRED TO CODING** because it is a build-time decision, not a
specification gap.

| # | Item | How it closed |
|---|------|---------------|
| P-3 | Discard-count disagreement across three tallies | **Reconciled by counting.** 363 MIGRATE + 68 DISCARD = 431 ✅ — **no rule was lost**. Two documents mis-state their own totals: three rules discarded *by owner ruling* (`BR-OPT-04`, `BR-CAP-14`, `BR-MS-02`) reached `target_business_rules.md`'s DISCARD table but were never written into `discard_log.md`, which was authored before the pause that produced them. Full working in `parity_specs.md` § Reconciliation. The document edit is **deferred**, below — the Inspector does not rewrite the Curator's artifacts, because doing so would erase the audit trail showing they predate the ruling. |
| P-4 | 47 `Platform` rules that may describe framework-absorbed machinery | **All 47 classified**, none reclassified out of MIGRATE — what changes is how each is *proven*: **15 PARITY**, **4 PARITY (contingent** on `console.theme-install` surviving DEV-011**)**, **18 DEVIATION** (mechanism replaced, invariant named), **10 VOID**. Full table in `parity_specs.md` § Classification. ⚠️ The VOID group is the finding: **seven of the ten are the recovery-mode cluster**, voided not by the paradigm change but by DEV-011 — a decision taken *four agents downstream*, at the screen layer, because that was the first agent that had to draw a list of plugins. |
| P-9 | A React island inside a Hotwire console | **Moved to DEFERRED TO CODING.** It is a build-time architecture decision (RISK-018), not something the specification can settle. |

## RESOLVED BY HUMAN DECISION (29 enumerated)

| # | Item | Decision | Recorded in |
|---|------|----------|-------------|
| 1 | Target paradigm | Option 1, adopt the Rails idiom. `derived_appetite: transformational` | `paradigm_decision.md` |
| 2 | Multitenancy model | **PostgreSQL schemas**, one per site, switched via `search_path` | `BR-MS-01` |
| 3 | `BR-CAP-05` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q4 | `target_business_rules.md` |
| 4 | `BR-REST-05` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q4 | `target_business_rules.md` |
| 5 | `BR-FMT-04` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 6 | `BR-KSES-01` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 7 | `BR-KSES-04` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 8 | `BR-KSES-05` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 9 | `BR-KSES-06` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 10 | `BR-KSES-07` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q5 | `target_business_rules.md` |
| 11 | `BR-ADM-07` | ⚠️ **Override.** Reproduce the legacy behaviour, against question Q4 | `target_business_rules.md` |
| 12 | `BR-OPT-04` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 13 | `BR-POST-10` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 14 | `BR-CMT-04` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 15 | `BR-CMT-08` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 16 | `BR-CMT-10` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 17 | `BR-HTTP-01` | Deviation. Fix the defect rather than reproduce it | `target_business_rules.md` |
| 18 | `BR-POST-01` | 60-second publish threshold confirmed as intended product behaviour | `target_business_rules.md` |
| 19 | `BR-CMT-12` | Migrated as a state enum, not a varchar | `target_business_rules.md` |
| 20 | `BR-MS-02` | `switch_to_blog` mechanism discarded; `search_path` switching replaces it | `target_business_rules.md` |
| 21 | `BR-CAP-14` | `$super_admins` global discarded as a privilege-escalation vector | `target_business_rules.md` |
| 22 | **Migration strategy** | **A + C** — Strangler Fig with deep boundaries as the delivery strategy, plus a standing Parallel Run against a reference WordPress `7.2-alpha-63330` oracle as the verification strategy. Recommendation accepted as presented. | `migration_strategy.md` |
| 24 | **Screen translation mode** | **Hybrid.** 18 `web.*` screens literal (golden capture from the Wave 0 oracle); 126 console/auth/tenancy screens modernized. Literal was ruled out as a *global* mode on two independent grounds: FR-13 (no legacy screenshots) and F-DS-07 (`@wordpress/components` unrecoverable). | `screen_modernization_decision.md` |
| 25 | **Target frontend platform** | **`rails-hotwire`** — server-rendered HTML with Turbo and Stimulus. ⚠️ Now partially reopened for three screens; see P-9. | `screen_modernization_decision.md` |
| 26 | **DEV-001** — golden capture | **Approved conditionally.** The owner committed to running the capture, so the 18 literal screens get real observable parity rather than a permanent exemption. The Inspector marks the exception for removal once `manifest.yaml` runs. | `screen_deviation_log.md` |
| 27 | **DEV-009** — WordPress branding | **Dropped.** The rebuild ships its own brand mark; the five informational pages carry the rebuild's own content. ⚠️ The only override of "textual content preserved literally", scoped to **branding and project-identity strings only** — every functional label, prompt, validation and error string stays verbatim. | `screen_deviation_log.md` |
| 28 | **DEV-011** — extension mechanism | **Themes yes, plugins no.** `console.themes` and `console.theme-install` are built over `Presentation::Theme`, which already has a backing table; `console.plugins`, `console.plugin-install` and `console.network.plugins` are struck — with no hook system there is nothing for a plugin to attach to. Does **not** reopen AD-01: a theme is data plus template files, not code hooking into the core. | `screen_deviation_log.md` |
| 29 | ⚠️ **DEV-007 — REJECTED; the editor must reach parity** | The owner declined to place the editing experience outside parity. **DEV-012 replaces it**, recording a *change of method* rather than an exemption: the editor is the only part of this migration specified by **observing a running oracle** rather than by reading extracted rules, because the extraction contains none of it. Consequences: the largest work item in the project, a maximally-scoped Wave 4 gate, RISK-010 re-scoped, and P-9 opened. | `screen_deviation_log.md` DEV-012 |
| 23 | **Is there a live deployment?** | **No — product rebuild only.** No running site with real data or users. Consequences applied: `cutover_plan.md` reframed as a launch plan; the CDC seam reduced to a repeatable seeding script; no proxy routing; waves become internal milestones gated by parity. RISK-002 downgraded CRITICAL → LOW, RISK-006 and RISK-007 HIGH → MEDIUM. | `migration_strategy.md`, `cutover_plan.md`, `risk_register.md` |

### ⚠️ Two overrides carried against a prior recorded decision

Recorded here so the audit trail is explicit, not to relitigate them.

| Override | Reverses | Finding knowingly carried forward |
|----------|----------|-----------------------------------|
| Authorization defaults reproduced, including the permissive ones | Question **Q4** (fail closed everywhere) and the `paradigm_decision.md` Designer contract row | `F-DOM-02`, described in `confidence-report.md` as the highest-value security observation in the analysis |
| KSES regex implementation reproduced | Question **Q5** (migrate off regex parsing) | `F-KSES-05`, the security-critical allowlist parsing HTML with regular expressions |

The owner was shown the conflict directly and reaffirmed both. `paradigm_decision.md` has been
amended so its Designer contract no longer contradicts the ruling.

### Two items outside the scope of the override ruling

| Item | Why it was decided separately |
|------|------------------------------|
| `BR-HTTP-01` | SSRF validation, not an authorization default. Curator recommendation applied: validate by default. |
| `BR-CAP-14` | A configuration global outranking stored superuser status, not one of the five authorization defaults. Curator recommendation applied: discard. |

## DEFERRED TO CODING (8 — 2 resolved in Wave 0, 6 open)

> **Wave 0 progress, 2026-08-22 (coding agent).**
>
> - ✅ **D-1 RESOLVED.** `discard_log.md`'s header now reads 68 and gains a new
>   § 4 "Discarded by owner ruling (3)" carrying `BR-OPT-04`, `BR-CAP-14` and `BR-MS-02`;
>   `target_business_rules.md`'s prose reads "3 resolved rulings". 54 + 11 + 3 = 68.
>   As D-1 itself noted, the rule *set* was already correct — 363 MIGRATE ids, all three
>   rulings already handled downstream. Only the tallies were wrong.
> - ✅ **D-4 RESOLVED.** The Wave 0 oracle was built, seeded and captured.
>   `screens/golden/manifest.yaml` now carries `oracleAvailable: true`, an `oracleHash`,
>   and **18/18 entries at `present: true`** with sha256 and byte count. **DEV-001 is
>   removed from every screen's deviations list** — the condition it described
>   ("no golden capture exists") no longer holds. The Inspector is unblocked for these
>   screens.
> - ⚠️ **D-7 gained evidence.** `web.attachment` is listed among the 18 literal screens
>   but **does not render** on a default WordPress 7.2 install: `wp_attachment_pages_enabled`
>   is `'0'` and `wp-includes/canonical.php:553` 301-redirects attachment URLs to the file.
>   Verified against all three corpus attachments. Its golden is the redirect. This is the
>   first confirmed discrepancy in the screen inventory and it was found by *executing*,
>   which is exactly what D-7 says the inventory never had.
> - ⚠️ **New, not in this log: a conflict between two specs.** `target_architecture.md`'s
>   intended graph has no `Publishing → Library` edge, but `target_data_model.md`
>   specifies FKs in both directions (`posts.featured_asset_id` per AD-03, and
>   `assets.attached_to_id`). They cannot both hold. Recorded as an acknowledged cycle in
>   `bin/check_cycles` — reported on every build rather than silenced. **Wants an owner
>   ruling**: drop one FK, or accept the edge and say so.
>
> - ✅ **Waves 1–2 parity gate met, 2026-08-22.** All 25 corpus screens — the 18 literal
>   `web.*` screens and the 7 syndication surfaces — are byte-identical to the oracle through
>   the parity harness, across **five consecutive clean runs**, on a corpus proven
>   reproducible across three full oracle rebuilds (`bin/parity determinism`). Per
>   `parity_specs.md § "Parity accepted" criteria`: zero unexplained divergence. ⚠️ "Through
>   the harness" means the manifest's declared normalizations apply, including
>   `sortClassAttributeTokens`; class ORDER (BR-MIGRATE-201) is asserted by unit specs, two of
>   which are `pending` on a documented gap (block style variation rulesets,
>   `class-wp-theme-json.php:3834` step 6, not ported into `packs/styling`).
> - ⚠️ **New legacy finding, for Wave 3.** `canonical.php:554` reads
>   `get_query_var('attachment_id')`, which a slug-addressed attachment request never sets;
>   the redirect target therefore comes from the global-`$post` fallback inside
>   `wp_get_attachment_url(0)`, not from the queried object. Correct by coincidence for the
>   single-attachment requests the corpus makes. The rebuild resolves by slug and must keep
>   doing so; do not "fix" parity by reproducing the fallback.
> - ⚠️ **New pipeline finding, recorded as T-12 in `data_migration_plan.md`.** Option values
>   that carry record ids (`sticky_posts`, `page_on_front`, …) were copied verbatim and
>   pointed at the wrong records after id remapping. Silent; found by the screen diff.
>
> D-2, D-3, D-5, D-6, D-7, D-8 remain open.

Populated by the Inspector at the close of the pipeline. **None of these blocks implementation** —
each is a decision that belongs to the people writing the code, recorded here so it is made
deliberately rather than discovered.

| # | Item | Why it is deferred | Where it came from |
|---|------|--------------------|--------------------|
| D-1 | **Correct three bookkeeping totals.** Append the three ruling-discards (`BR-OPT-04`, `BR-CAP-14`, `BR-MS-02`) to `discard_log.md` and set its header to 68; change `target_business_rules.md`'s prose from "1 resolved ruling" to "3". | The rule *set* is already correct and all three rules are correctly handled — this is a documentation fix, and applying it inside the pipeline would erase evidence that both documents predate the ruling. | P-3, `parity_specs.md` |
| D-2 | ⚠️ **Does a fatal error in a theme need a recovery mechanism?** DEV-011 removed plugins, which voided seven recovery-mode rules. **Themes can still fatal.** If theme-fatal recovery is wanted, it needs a design with a much narrower blast radius than the legacy's. | A product decision, not a parity question. No parity test is written for the 10 VOID rules — writing one would produce a test that cannot pass. | P-4, `parity_specs.md` |
| D-3 | **Scope the React island for the three editor screens.** DEV-012 requires editor parity; a live block canvas is not a Turbo-frame problem. Decide it deliberately, keep the other 141 screens server-rendered, and treat the island's boundary as a real interface. | RISK-018. A build-time architecture decision the specification cannot make. | P-9, `screen_deviation_log.md` DEV-012 |
| D-4 | **Run the golden capture.** Every entry in `manifest.yaml` is `present: false`, so the 18 `@visual-parity` scenarios cannot execute. DEV-001 is approved **conditionally** on this happening. | The oracle is built in Wave 0 anyway; this is one manifest run while it is up. ⚠️ **Remove the DEV-001 exception once `present: true`** — a temporary allowance must not become permanent. | DEV-001, `parity_specs.md` |
| D-5 | **Author the editor's interaction specs by observing the oracle.** The only parity specs in this project with no `BR-MIGRATE-*` behind them; they must be tracked separately from the rule-level specs. | DEV-012. The extraction contains none of the editor's client behaviour, so specification is by observation. | `parity_specs.md` § Editor parity |
| D-6 | **Decide the typed settings registry.** `settings.value` is `jsonb`, but ~130 option names are seeded at install and several are structural (`permalink_structure`, `page_on_front`, `posts_per_page`, the comment-moderation set). | A choice about how far to push configuration into code; it belongs to whoever writes `Configuration`. | `target_data_model.md` § Notes |
| D-7 | **Cross-check the screen inventory.** `reversa-visor` never ran, so the FR-05 divergence rule could not be applied. 144 screens is **one reading, not two**. | Verification, not specification. Run `/reversa-visor` if a second reading is wanted before Wave 4. | `screen_modernization_decision.md`, EC-18 |
| D-8 | **Specify production infrastructure.** `migration_brief.md` records it as "not specified", and with no existing deployment nothing supplies it by default. | `cutover_plan.md` gates the launch on it. | Open assumptions, below |

---

## Open assumptions carried by the Strategist

Recorded so the Designer and the Inspector inherit them explicitly rather than by reading between
the lines of `migration_strategy.md`.

| Assumption | Consequence if wrong |
|---|---|
| A reference WordPress `7.2-alpha-63330` instance can be stood up as a parity oracle | RISK-001 has no mitigation. The brief's first success metric becomes unevidenceable and must be formally downgraded to "reviewed against the documented rule". |
| The legacy and the rebuild will never share one database | If a shared database is ever proposed to simplify seeding, it cannot work: MySQL permissive SQL mode, `0000-00-00` draft dates and PHP-serialised values are not representable in PostgreSQL. Now largely moot with no live deployment, but the residual holds — the rebuild must never write the oracle instance's database (RISK-002). |
| Team capability in Ruby/Rails is sufficient for a transformational rebuild | Not recorded anywhere in the brief (RISK-011). A half-adopted Rails idiom silently converts the chosen paradigm option 1 back into the rejected option 2. |
| The editor's specification can be recovered by observing the oracle | ⚠️ Load-bearing after the DEV-012 ruling. If the oracle cannot be stood up, the editor has **no** specification source at all — not a reduced one. This makes RISK-001 (no oracle) a dependency of editor parity as well as of rule parity. |
| A React island can be scoped to three routes without spreading | RISK-018. If it spreads, the console becomes two frontend stacks by drift rather than by decision. |
| Production infrastructure will be specified before launch | `migration_brief.md` records infrastructure as "not specified". With no existing deployment to inherit from, nothing supplies this by default — it is a decision someone must make, and `cutover_plan.md` gates the launch on it. |
