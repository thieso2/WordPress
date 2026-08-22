---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: cutover_plan
producedBy: strategist
hash: "sha256:06e2482e2927380567b617f004bd8212ae8c3fc83efae2df37cf5d2ad56d15ef"
---

# Cutover Plan — *Launch Plan*

> Aligned with the strategy chosen in `migration_strategy.md`: **A + C**, Strangler Fig with deep
> boundaries plus a standing Parallel Run against a reference oracle.
>
> **Reframed on the owner's answer: there is no live deployment.** This is a product rebuild. There
> is no running WordPress site with real data and real users, so there is nothing to cut *from*.
> This document is therefore the **launch plan for the rebuild's first production deployment**, not
> a replacement of a running system. The template's name is kept so the pipeline's artifact contract
> holds; the content is what the decision actually calls for.

## Base strategy

- **Confirmed strategy**: **A + C**, as adapted for a product rebuild — see
  `migration_strategy.md` § *Open assumption resolved*.
- **Decided by**: thies (owner), 2026-08-21.

### What replaces the cutover

Under a live-deployment reading, the cutover was the Wave 3 write-authority flip: MySQL stops being
authoritative, PostgreSQL starts. **That moment does not exist here.** PostgreSQL is authoritative
from the first line of code, because nothing else ever was.

What takes its place:

| Was | Is now |
|---|---|
| Write-authority flip at Wave 3 | **The Wave 3 parity gate** — the last gate before Waves 4 and 5 can build on the content core. Still the project's most important checkpoint, but a *quality* gate rather than an *irreversible* one. |
| Cutover window with a write freeze | **First production launch**, scheduled independently of the waves and reversible in the ordinary way (do not launch, or roll back a deploy). |
| Rollback with data reconciliation | **Ordinary deployment rollback.** No pre-existing data is at stake, so rollback loses nothing but time. |

**The consequence worth stating plainly: this project has no irreversible step.** Every decision can
be revisited at a cost measured in effort, never in lost user data. That is the single largest
difference between this plan and the one written for a live system, and it should be spent
deliberately — on making the hard modelling choices early (RISK-003, the 16-post-types fork) while
reversing them is still cheap.

---

## Prerequisites

Two sets, because two different things now need gating: the **Wave 3 parity gate** (the old
cutover's technical bar, which survives intact) and the **first launch** (new).

### Set 1 — the Wave 3 parity gate

These are the gates from the original cutover, unchanged in substance. They are what make the
content core trustworthy enough for Waves 4 and 5 to build on.

- [ ] **Oracle exists and is trusted.** A reference WordPress `7.2-alpha-63330` instance is running,
      seeded with the agreed corpus: all 16 post types, hierarchical and flat taxonomies, threaded
      comments, every role, drafts carrying `0000-00-00 00:00:00`, serialised `postmeta`/`options`,
      4-byte UTF-8 content, quote-and-backslash-heavy text. Mitigates RISK-001, RISK-008, RISK-014.
      **This is now the single point of failure for the whole project** — with no production system,
      the oracle is the only executable definition of the 363 rules that exists.
- [ ] **Parity gates green for Waves 1, 2 and 3**, held over the agreed observation period with no
      unexplained diff. Every remaining diff is classified as one of the 6 deliberate deviations,
      one of the 9 override rules, or an accepted deviation recorded in writing.
- [ ] **The Wave 3 integration checkpoint has passed** — the end-to-end run spanning the former
      23-module component, exercising each coupling in `spec-impact-matrix.md` §6 as a scenario:
      draft dates ↔ SQL mode, `pagination_base` ↔ legal slugs, autoload threshold ↔ router and cron
      queue, term counts ↔ `post_status`, session destruction ↔ outstanding nonces. Mitigates
      RISK-016. **This is the checkpoint `migration_brief.md`'s primary risk asked for.** It is the
      one prerequisite that did *not* get cheaper when the deployment question was answered.
- [ ] **Seeding round-trips correctly.** The oracle's corpus loads into PostgreSQL with a
      zero-length dead-letter queue: every PHP-`serialize()` payload transcoded, every serialised
      object explicitly mapped or quarantined (RISK-006), no `0000-00-00 00:00:00` value reaching a
      PostgreSQL timestamp column (RISK-007). Both are one-time problems now rather than continuous
      ones, but a corpus that does not load is a corpus that cannot judge.
- [ ] **KSES differential equivalence demonstrated** — the Ruby port and the PHP original produce
      byte-identical output across the XSS bypass corpus, with no pattern rewritten for idiom
      (RISK-005).
- [ ] **Authorization declarations complete.** Every route, policy and endpoint carries an explicit
      authorization declaration, including those declaring themselves public. The permissive runtime
      defaults stay exactly as the owner ruled; what is prevented is reaching them by omission
      (RISK-004).
- [ ] **Slashing sweep complete.** All 363 migrated rules checked for dependence on the vanished
      slashing convention, starting with `BR-META-02` and the `formatting-and-sanitization` set
      (RISK-008, implication 6).

### Set 2 — first production launch

- [ ] Waves 0–4 complete and parity-gated. Wave 5 may follow launch; `multisite` explicitly may.
- [ ] The Screen Translator's scope for Wave 4 is agreed and delivered, or deliberately reduced in
      writing. ⚠️ The block editor client ships only as build output (TD-19, Q6), so **no editor
      client behaviour was extracted** — Wave 4's scope is set by product decision, not by the rule
      set (RISK-010).
- [ ] Production infrastructure exists and is provisioned. `migration_brief.md` records
      infrastructure as "not specified"; it must be specified before this box can be ticked.
- [ ] Backup and restore verified **by restoring**, before the system holds anything worth losing.
      Cheap to establish now, expensive to retrofit.
- [ ] Observability in place: error rates, latency, and the parity harness able to run against
      production traffic patterns.
- [ ] `ambiguity_log.md` has **zero PENDING items**.
- [ ] The owner gives an explicit go.

---

## Launch window

- **Target date**: **not fixed**, deliberately. `migration_brief.md` records no deadline, and the
  strategy makes each wave's parity gate the milestone rather than a date (RISK-012). With the
  dual-stack cost gone, the parity gates are now the *only* schedule pressure the project has —
  which makes holding them honestly more important, not less.
- **Estimated duration**: **under 1 hour.** A first deployment with no data to migrate and no
  traffic to drain is an ordinary release, not an operation.
- **Affected environment**: production (first provisioning).
- **Advance communication**: none required internally — `migration_brief.md` names a single
  stakeholder who is also the decision-maker. There are no existing users to notify, since there is
  no existing deployment.

---

## Launch steps

| # | Step | Owner | Duration | Reversible? |
|---|---|---|---|:--:|
| 1 | Final go/no-go review against both prerequisite sets | owner | 30 min | n/a |
| 2 | Provision production infrastructure and PostgreSQL | platform lead | — (ahead of the window) | ✅ |
| 3 | Run schema migrations against production | data / platform lead | 10 min | ✅ |
| 4 | Seed initial content, if any is to ship at launch | data / platform lead | 10 min | ✅ |
| 5 | Verify backup and restore against the provisioned database | data / platform lead | 20 min | n/a |
| 6 | Deploy the rebuild | platform lead | 10 min | ✅ |
| 7 | Smoke tests: publish a post, publish a page, upload media, post and moderate a comment, create a term, log in and out, load an archive page and a feed | QA / verification lead | 20 min | n/a |
| 8 | Point DNS at the new system | platform lead | 5 min | ✅ |
| 9 | Run the parity harness against live traffic patterns for the observation period | QA / verification lead | continuous | n/a |
| 10 | Declare launch complete, or roll back the deploy | owner | 10 min | n/a |

**Every step is reversible.** There is no point of no return in this plan, because there is no
pre-existing data that a rollback could strand.

---

## Rollback plan

- **Trigger criteria** — any one is sufficient:
  - A smoke test in step 7 fails and is not fixed within 30 minutes.
  - The parity harness reports an unexplained diff on a content write path.
  - Authentication or authorization behaves differently from the oracle in the **restrictive**
    direction (users locked out), or in the **permissive** direction beyond the three override rules
    `BR-REST-05`, `BR-CAP-05` and `BR-ADM-07`.
  - Error rate or latency exceeds the agreed threshold and does not recover within 30 minutes.
  - The owner calls it, for any reason.

- **Steps**:
  1. Revert DNS, or roll back the deploy to the prior release if one exists.
  2. Capture anything written since step 8 — at launch this is likely nothing, but capture before
     concluding that.
  3. Fix forward. There is no legacy system to fall back to, which is the defining property of this
     plan: **rollback means "not launched yet", not "returned to the old system".**

- **Maximum acceptable time before rollback**: **not applicable.** The 4-hour ceiling in the
  live-deployment version existed because PostgreSQL-only writes accumulated past the point of
  practical reconciliation. With no second system, no such clock runs.

- **Rollback owner**: platform lead executes; the **owner** decides.

---

## Go / no-go criteria

- **Go** — all must hold:
  - Both prerequisite sets above are met and recorded.
  - The Wave 3 integration checkpoint passed, with each `spec-impact-matrix.md` §6 coupling
    exercised end-to-end.
  - Backup and restore verified against the production database.
  - `ambiguity_log.md` has zero PENDING items.
  - The owner gives an explicit go.

- **No-go** — any one blocks:
  - Any unexplained parity diff on a content write path. "We do not know why it differs" is
    disqualifying on a write path, because the target's behaviour is **final**: with the hook system
    not reproduced, the documented default is the whole specification and nothing can adjust it at
    runtime (`paradigm_decision.md` implication 2).
  - Any serialised payload unmapped and unquarantined, or any `0000-00-00 00:00:00` value reaching a
    PostgreSQL timestamp column during seeding.
  - KSES differential equivalence unproven for any pattern.
  - A route, policy or endpoint without an explicit authorization declaration.
  - Backup and restore unverified.
  - The oracle instance unavailable — without it the live system cannot be judged after launch.

---

## Post-launch

- [ ] **Extended monitoring for 14 days** — error rates, latency, and the parity harness running
      continuously against the oracle on live traffic patterns.
- [ ] **Parity validation per `parity_specs.md`** (the Inspector's Gherkin features) executed against
      production, results recorded **per rule**, so the brief's "no rule is silently dropped" metric
      is evidenced rather than asserted.
- [ ] **Reconcile the deviation ledger**: every observed diff maps to one of the 6 deliberate
      deviations, one of the 9 override rules, or a recorded accepted deviation. Anything unmapped is
      a defect, not a deviation.
- [ ] **Complete Wave 5** — periphery, ending with `multisite`. PostgreSQL schema-per-site
      (`BR-MS-01`) changes connection handling for the whole application (RISK-009), so it is added
      to a stable, launched system rather than carried through the build.
- [ ] **Keep the oracle instance running** until the last wave lands. It costs almost nothing and it
      remains the only executable definition of the rules that have not yet been proven.
- [ ] **Retire the seeding script** only when Wave 5 is parity-gated and the oracle is retired with
      it. Keep the oracle's seeded corpus archived — it is the project's regression suite, and there
      is no other.

## Notes

**Three properties of this plan invert what a cutover document normally assumes:**

1. **There is nothing to cut over from.** The absence of a legacy deployment removes the entire class
   of migration risk that usually dominates a plan like this — dual write authority, freeze windows,
   reconciliation, data loss on rollback. RISK-002 drops from critical to low on this fact alone.

2. **The oracle is now load-bearing in a way no production system would be.** In a live migration the
   running system is both the thing being replaced *and* the reference. Here it is only the
   reference — and it exists solely because the project chose to build it. If it is not built, the
   brief's first success metric cannot be evidenced at all (RISK-001, unchanged and now the project's
   single point of failure).

3. **`multisite` sits after launch, deliberately.** Tenancy via `search_path` switching reproduces
   the legacy's unbalanced-`switch_to_blog()` failure mode in a new form (RISK-009, F-MS-02). Adding
   it to a stable launched system is a different and much smaller job than threading it through an
   unstable one.
