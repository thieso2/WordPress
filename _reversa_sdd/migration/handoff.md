---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: handoff
producedBy: orchestrator
hash: "sha256:bbce06af292db47ee09d47c8be14bba2465ad61eb28d20e2e76653989aed9571"
---

# Handoff to the Coding Agent

> Entry point for the coding agent that will write the new system from these specs.
> **Target**: WordPress `7.2-alpha-63330` (1,900 PHP files, ~670,500 lines, 44 modules) rebuilt on
> Ruby on Rails 7.1+ / PostgreSQL. 363 of 431 extracted business rules carry forward.

## ⚠️ Required reading first

1. **`paradigm_decision.md`** — non-negotiable. **Option 1: adopt the Rails idiom**,
   `derived_appetite: transformational`. The hook system is **not reproduced**, which is the single
   most consequential fact in this migration: every one of the 363 rules describes WordPress's
   *unfiltered default*, and in the target that default becomes the **permanent, only behaviour**.
   Nothing can change it at runtime. That is what makes parity checkable at all — and it is also why
   getting a rule wrong is not recoverable by configuration later.
2. **`topology_decision.md`** — non-negotiable. **Option 3: hybrid.** Conventional Rails for the
   content core; `packs/` for exactly three leaf libraries (`markup`, `sanitizing`, `styling`).
   ⚠️ The content core has **no enforceable dependency direction** — that is a known, accepted
   consequence (RISK-017), mitigated by a cycle-detection CI job that **must ship in Wave 0**.
3. **`screen_modernization_decision.md`** — non-negotiable. **Hybrid**: 18 front-end templates
   literal, 123 in-scope console/auth/tenancy screens modernized. Target platform `rails-hotwire`.

## Recommended reading order

1. `paradigm_decision.md` — mandatory, first
2. `topology_decision.md` — mandatory, second
3. `screen_modernization_decision.md` — mandatory, third
4. `migration_brief.md`
5. `target_business_rules.md`
6. `migration_strategy.md`
7. `target_architecture.md`
8. `target_domain_model.md`
9. `target_data_model.md`
10. `data_migration_plan.md`
11. `target_screens.md`
12. `parity_specs.md` + `parity_tests/`
13. `screen_deviation_log.md`
14. `risk_register.md` + `cutover_plan.md`
15. `discard_log.md` (advisory)
16. `ambiguity_log.md` (advisory — but read § DEFERRED TO CODING; those eight are yours)

## Artifacts produced

| Artifact | Produced by | Status |
|---|---|---|
| `migration_brief.md` | orchestrator | created |
| `paradigm_decision.md` | paradigm_advisor | created (amended after the Curator pause) |
| `target_business_rules.md` | curator | created — 363 MIGRATE / 68 DISCARD |
| `discard_log.md` | curator | created — ⚠️ 3 entries short, see D-1 |
| `migration_strategy.md` | strategist | created |
| `risk_register.md` | strategist | created — 18 risks |
| `cutover_plan.md` | strategist | created — **reframed as a launch plan** |
| `topology_decision.md` | designer (Phase 1) | created — option 3 approved |
| `target_architecture.md` | designer | created — 17 contexts, 8 ADs |
| `target_domain_model.md` | designer | created — 8 aggregates |
| `target_data_model.md` | designer | created — 26 tables, full DDL |
| `data_migration_plan.md` | designer | created — **the oracle seeding pipeline** |
| `screen_modernization_decision.md` | screen_translator (Phase 1) | created — hybrid |
| `target_screens.md` | screen_translator | created — 144 screens |
| `screen_deviation_log.md` | screen_translator | created — 12 entries, 0 pending |
| `_reversa_sdd/screens/inventory.json` | screen_translator | created — 144 screens |
| `_reversa_sdd/screens/golden/manifest.yaml` | screen_translator | created — ⚠️ 18 entries, all `present: false` |
| `_reversa_sdd/design-system/tokens-derived.md` | screen_translator | created |
| `parity_specs.md` | inspector | created |
| `parity_tests/*.feature` | inspector | **31 files, 159 scenarios** |
| `ambiguity_log.md` | orchestrator | consolidated — **0 pending**, 29 resolved, 8 deferred |

## Blockers before starting implementation

✅ **No blockers. Proceed.**

`ambiguity_log.md` has zero PENDING items and `screen_deviation_log.md` has zero pending deviations.
The eight DEFERRED TO CODING items are decisions for you, not gates on starting.

## ⚠️ The one thing that can invalidate everything

**RISK-001 — there is no oracle unless you build one.**

The legacy ships with **zero tests** (TD-18) and all 431 rules were verified by *reading*, never by
executing. There is **no live deployment**. So a reference WordPress `7.2-alpha-63330` instance is
not test tooling — it is the project's **only executable definition of the 363 rules**, and after
DEV-012 it is also the only specification source for the editor's client half.

Build it first. Seed it properly: all 16 post types, hierarchical and flat taxonomies, threaded
comments, every role, drafts carrying `0000-00-00 00:00:00`, serialized `postmeta`/`options`, 4-byte
UTF-8, quote- and backslash-heavy text. **An oracle seeded with three posts proves very little**, and
every parity claim in this pipeline is downstream of it.

## Next steps for the coding agent

1. **Internalize `paradigm_decision.md`.** Active Record, models own their invariants, no repository
   layer, no DI container, **no hook system**. A half-adopted Rails idiom silently converts the
   chosen option 1 back into the rejected option 2 (RISK-011).
2. **Internalize `topology_decision.md`.** Three packs with **zero declared dependencies**, enforced
   by CI. Everything else is conventional Rails with contexts as namespaces
   (`Publishing::Post`, not `Post`). ⚠️ Ship `bin/check_cycles` in **Wave 0** — added later it is
   worth almost nothing, because the graph it exists to keep acyclic already will not be.
3. **Internalize `screen_modernization_decision.md`.** Literal for `web.*` (byte-comparable against
   golden files), semantic contract for the rest. ⚠️ **No copy editing** — every functional label,
   prompt, validation message and error string is preserved verbatim. The sole exception is DEV-009,
   scoped to branding and project-identity strings.
4. **Wave 0 first, in this order**: the oracle → the diff harness → the seeding pipeline → `markup`
   and `styling` (the only two genuinely extractable legacy components, F-SIM-03) → `bin/check_cycles`.
5. **Set up the repository** per `target_architecture.md § Fidelity to the chosen topology`.
6. **Implement bottom-up**, following the wave sequence in `migration_strategy.md`: leaf packs →
   `Configuration` → the content core → `Access` → `Retrieval`/`Routing` → rendering → surfaces →
   periphery, with `Tenancy` **last**.
7. **Write the parity tests from the start**, not afterwards. `parity_specs.md` § Exceptions lists
   everything that is allowed to diverge; anything else is a defect.
8. **Validate paradigm and topology fidelity per component**, using the two mandatory sections in
   `target_architecture.md`.
9. **Seed via `data_migration_plan.md`.** It routes through Active Record on purpose: that makes it
   the first honest test of the schema, exercising every CHECK, unique index and FK against real
   WordPress data. ⚠️ **The dead-letter queue must fail the run** — a pipeline that quietly coerces
   bad input into defaults would still fill the database and destroy the signal.
10. **Launch per `cutover_plan.md`.** With no live deployment there is no irreversible step and
    nothing to roll back to — rollback means "not launched yet".

## Six things that will bite if you skip them

1. **`posts.slug` is nullable and that is load-bearing.** Drafts get no slug
   (`BR-MIGRATE-032`). Reproducing the legacy's `NOT NULL DEFAULT ''` would collide every draft
   against every other in the unique index. The partial index `WHERE slug IS NOT NULL` is what makes
   the constraint expressible at all.
2. **`Access` must not be depended upon.** `Access` → `Identity` and `Publishing`; **nothing** may
   depend on `Access` except delivery surfaces. That single edge direction is what converts the
   legacy users↔posts cycle into a DAG. Under topology option 3 only `bin/check_cycles` will notice
   if it breaks.
3. **The KSES patterns must be ported character-for-character.** PCRE and Onigmo differ on anchors,
   possessive quantifiers, backtracking limits and Unicode handling — a pattern that is a correct
   allowlist under one can **admit input** under the other (RISK-005). Prove equivalence by
   differential fuzzing before trusting it. Do not "tidy" a regex.
4. **Re-read every rule that assumed slashed input.** `wp_magic_quotes()` slashes superglobals at
   request time; Rails params are never slashed (implication 6, RISK-008). The failure mode is
   silent — wrong characters in output. ⚠️ Note this is about *reading rules*, **not** about
   transforming stored data: adding an unslash pass to the seeding pipeline would corrupt every
   legitimate backslash in the corpus (T-08).
5. **`0000-00-00 00:00:00` is not a valid PostgreSQL timestamp**, and every draft carries it. It
   becomes `NULL`, and `NULLS LAST` must be stated explicitly wherever ordering matters — MySQL and
   PostgreSQL disagree on the default (RISK-007).
6. **The 16-post-types fork (AD-02) is the decision to revisit early if at all.** STI for content,
   separate tables for machinery. Prototype against the three hardest cases — attachments, revisions,
   nav menu items — before committing. It is cheapest to reverse before Wave 3 (RISK-003).

## Deferred to coding — eight items that are yours

Full detail in `ambiguity_log.md § DEFERRED TO CODING`. None blocks starting.

| # | Item |
|---|---|
| D-1 | Correct three bookkeeping totals in `discard_log.md` and `target_business_rules.md` (no rule is missing — the tallies are) |
| D-2 | ⚠️ Decide whether a **theme** fatal error needs a recovery mechanism — plugins are gone, themes are not |
| D-3 | Scope the React island for the three editor screens (RISK-018) |
| D-4 | Run the golden capture, then **remove the DEV-001 exception** |
| D-5 | Author the editor's interaction specs by observing the oracle (DEV-012) |
| D-6 | Decide the typed settings registry |
| D-7 | Cross-check the screen inventory — `reversa-visor` never ran, so 144 is one reading, not two |
| D-8 | Specify production infrastructure — the brief records it as "not specified" |

## Auto-decided items

**None.** The pipeline ran in interactive mode. Every decision below was made by the owner at a
human pause: the paradigm, 22 Curator rule decisions including two ⚠️ overrides, the migration
strategy, the live-deployment question, the topology, the architecture, the target platform, the
screen mode, and four screen deviations including the rejection of DEV-007.

## Closing notes

**Three things about these specs that a reader should not have to discover:**

1. **Two owner overrides carry known findings into a greenfield system, deliberately.** Authorization
   defaults are reproduced **permissively** — a route with no policy is public, a policy emitting no
   capabilities allows — carrying `F-DOM-02`, which `confidence-report.md` called the highest-value
   security observation in the whole analysis. And KSES still parses HTML with regular expressions,
   carrying `F-KSES-05`. Both were put to the owner as conflicts and reaffirmed. AD-01 makes them
   **permanent**: there is no filter to correct them later. `parity_tests/04` and `05` assert this
   behaviour as the specification, which is uncomfortable to read and correct.

2. **The pipeline surfaced one gap none of its own agents could have found alone.** The Paradigm
   Advisor discarded the hook system; the Brief said there was no compatibility burden; neither said
   whether the rebuild has an **extension mechanism at all**. That question only became visible at the
   screen layer, when someone had to draw a list of plugins — and its answer (**themes yes, plugins
   no**) then retroactively voided **seven** rules in the recovery-mode cluster, because recovery mode
   exists to pause a fatally-erroring plugin. Decisions in this pipeline reach backwards; if you
   revisit DEV-011, re-check `parity_specs.md § Classification`.

3. **The editor is the largest work item and the only one with no rule behind it.** DEV-007 asked to
   place it outside parity; the owner rejected that and ruled it must be on par. Everything else here
   is bounded by 363 enumerable rules. The editor is bounded by whatever the oracle does — roughly
   fifty `@wordpress/*` packages of React. Its readable half (115 block schemas, 23 supports, the
   `theme.json` cascade) should be generated mechanically; its interaction half must be observed.
   Do not estimate it from a rule count.

**Where the specs are weakest, stated plainly**: coverage of the editor's client behaviour (no
extraction exists), the 18 literal screens until capture runs, and the screen inventory itself
(one reading, unverified). Everything else traces to a `file:line` in the legacy or to
`discard_log.md`.
