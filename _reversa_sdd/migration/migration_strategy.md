---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: migration_strategy
producedBy: strategist
hash: "sha256:200de109fadc566d6b8748affc9a95c2182d031fc282d9d1dfd0913e4873e6cc"
---

# Migration Strategy

> Migration strategies evaluated with explicit trade-offs. The recommended strategy is the
> Strategist's suggestion; the final decision is human.
> Required reading before this: `paradigm_decision.md`.

## Context synthesised

| Input | Value | Source |
|---|---|---|
| Size | 1,900 PHP files, ~670,500 LOC, 44 modules (**42 in scope**), 18 tables | `inventory.md`, `data-dictionary.md` |
| Rules to carry | **363 MIGRATE** of 431 analysed; 68 discarded; 6 deliberate deviations | `target_business_rules.md` |
| Derived appetite | **transformational** | `paradigm_decision.md` |
| Paradigm gap severity | **HIGH** (procedural + global observer → Rails Active Record) | `paradigm_decision.md` |
| Deadline | **none fixed**; incremental delivery explicitly preferred over a dated big-bang | `migration_brief.md` |
| Budget | not stated | `migration_brief.md` |
| Regulatory integrations | **none** | `migration_brief.md` |
| Compatibility burden | **none** — hooks, filters and `deprecated-compat` are not a contract | `migration_brief.md` |
| Critical rule clusters | authorization (`users-roles-capabilities`, 14), sanitisation (`kses-security`, 10), auth/sessions (16), HTTP/SSRF (13) | `target_business_rules.md` |
| Test oracle available | **none in the legacy tree** — zero tests, all 431 rules verified by reading only | `inventory.md` §1, TD-18 |

### Two facts that dominate every strategy below

**Fact 1 — the legacy has no test suite, so the only oracle for parity is a running WordPress
instance.** Reversa's 431 rules were verified by *reading* code, never by executing it
(`migration_brief.md`, known risk factors). No strategy can validate parity from the artifacts
alone. Every option therefore has to answer the same question: *against what do we check?*

**Fact 2 — the target database is PostgreSQL, so the legacy and the rebuild cannot share one
database.** This is the single most consequential technical constraint on strategy selection, and
it is not visible in the strategy catalog. The classic Strangler Fig — two applications, one
schema, routed per URL — is **unavailable here**. Legacy WordPress writes MySQL with permissive SQL
mode, `0000-00-00 00:00:00` draft dates and PHP-serialised values in `options` and `postmeta`
(BR-POST-04, BR-DB-10, ADR-007). A Rails/PostgreSQL application cannot co-own those tables. Any
incremental strategy must therefore carry a **replication seam** rather than a shared schema, and
must maintain a strict **single-writer invariant**: exactly one of the two systems owns writes for
a given entity at a given time. Never both.

---

## Strategies evaluated

### Strategy A: Strangler Fig with deep boundaries and a replication seam

- **Description**: a reverse proxy fronts both systems and routes by URL surface. The rebuild takes
  surfaces in waves, starting with read-only public output and ending with the content write path.
  Because the databases differ, a one-way change-data-capture pipeline keeps PostgreSQL current
  from MySQL while the legacy still owns writes; at the write-authority flip the direction is
  retired, not reversed.
- **When it applies**: system in production that cannot stop; incrementality required; routing
  possible. Two of the three hold here; the third (production system) is an open assumption — see
  *Open assumption* below.
- **Cost**: **high** (the catalog says medium; the replication seam and the dual-stack operating
  period push it up). **Risk**: **medium**. **Time**: **long**.
- **Fit with the derived appetite** (`transformational`): good. The catalog's rule for a
  transformational appetite on a system that is *not* small is exactly "Strangler Fig with deep
  boundaries". The boundaries available here are deep and real: nine terminal modules with zero
  dependents, and a clean read-path / write-path split.
- **Trade-offs**:
  - Pros:
    - Matches the brief's stated preference for incremental delivery over a dated big-bang.
    - The new stack reaches production in **wave 1** (feeds, sitemaps, oEmbed — read-only, zero
      write path), so the deployment, the data pipeline and the observability are proven on low-risk
      surfaces before any content rule is at stake.
    - Rollback is per-wave and cheap until the write-authority flip: revert one proxy rule.
    - The 363 rules arrive in reviewable batches instead of one 670k-LOC judgement.
  - Cons:
    - **The replication seam is genuine, permanent-feeling engineering that is thrown away at the
      end.** PHP-serialised `options`/`postmeta` values and `0000-00-00` dates must be transcoded
      continuously, not once (RISK-006, RISK-007).
    - A long dual-stack period: two runtimes, two databases, two deploy paths, one owner.
    - Wave boundaries must respect couplings that are *invisible from either module alone*
      (F-SIM-05): draft dates ↔ SQL mode, `pagination_base` ↔ legal slugs, autoload threshold ↔
      router. A boundary drawn on the module list alone will cut one of these.

### Strategy B: Big Bang with a rollback plan

- **Description**: build the whole rebuild off to the side, migrate data once, cut over in a single
  window, keep the legacy warm for rollback.
- **When it applies**: small system; tolerated downtime window; transformational appetite; few live
  integrations. **Three of four hold. The system is not small.**
- **Cost**: **medium**. **Risk**: **high**. **Time**: **long before anything ships, then short**.
- **Fit with the derived appetite** (`transformational`): the appetite fits; the *size* does not.
  The catalog reserves Big Bang for transformational appetite **on small systems**. 670,500 lines,
  42 modules and 363 rules is not that.
- **Trade-offs**:
  - Pros:
    - **No replication seam at all.** One offline ETL, MySQL → PostgreSQL, done once. This deletes
      RISK-002 outright and reduces RISK-006 and RISK-007 from continuous problems to one-time ones.
    - No dual-stack operating period; one runtime, one database, one deploy path.
    - The paradigm change is cleanest here: nothing forces the rebuild to keep a shape compatible
      with the legacy schema mid-flight, so the Designer is unconstrained.
    - With no compatibility burden and no external consumers, the usual Big Bang killer — breaking
      integrations — is absent.
  - Cons:
    - **Zero delivered value until everything is finished**, which directly contradicts the brief's
      "incremental delivery is preferred over a dated big-bang".
    - With no deadline as a forcing function, an all-or-nothing build has nothing to stop it
      drifting (RISK-012).
    - Parity is validated all at once, at the end, on 363 rules simultaneously — the worst possible
      moment to discover that the slashing convention (implication 6) was mis-read.
    - Rollback is all-or-nothing and degrades over time as data diverges.

### Strategy C: Parallel Run against a reference legacy instance

- **Description**: stand up a reference WordPress `7.2-alpha-63330` instance, seeded with
  representative data, purely as a **parity oracle**. Replay the same requests against it and
  against the rebuild, diff the responses, and treat every diff as either a confirmed parity failure
  or a recorded deviation.
- **When it applies**: critical logic needing proof of equivalence. The catalog frames this for
  financial/fiscal/regulatory logic. **Here the trigger is different and stronger: there is no test
  suite at all, and every rule was verified by reading.**
- **Cost**: **high**. **Risk**: **low** (it removes risk rather than carrying it). **Time**:
  **medium**, and it runs concurrently with the build rather than adding a phase.
- **Fit with the derived appetite** (`transformational`): the catalog assigns Parallel Run to a
  balanced appetite, and as a *primary* strategy that is right — it is expensive and conservative.
  But the catalog also carries the rule that decides this case: **large paradigm change +
  transformational appetite → recommend a Parallel Run to validate parity.** That rule fires here.
- **Trade-offs**:
  - Pros:
    - **It manufactures the missing oracle.** This is the only option that converts "verified by
      reading" into "verified by executing", and it does so without needing `wordpress-develop`.
    - It works whether or not a production site exists, because the reference instance is
      stood up deliberately rather than found.
    - It gives the Inspector's Gherkin specs something to execute against, which is the brief's
      second success metric.
    - Diffs are evidence. The 6 deliberate deviations and the 9 override rules become *expected*
      diffs, machine-checkable rather than argued.
  - Cons:
    - Expensive to build and to keep honest: response diffing needs normalisation for nonces,
      timestamps, IDs and ordering, or it drowns in false positives.
    - As a **standalone delivery strategy it delivers nothing** — it is a verification technique,
      not a way to get from A to B. It cannot be chosen alone.
    - Front-end HTML diffing is only as meaningful as the seeded corpus; an oracle seeded with three
      posts proves very little.

### Strategy D: Branch by Abstraction — **rejected, not evaluated further**

The catalog scopes this to "internal migration (the language or framework changes, the domain
stays)" via an abstraction seam **inside one codebase**. Here the language changes PHP → Ruby, so
there is no single codebase to host the seam, and no PHP-side abstraction layer exists to hang one
from: the legacy has no DI container, no repositories and no service layer (`dependencies.md` §7).
Building one inside 670k lines of procedural PHP in order to leave it would be a large investment in
the system being discarded. Recorded as considered and rejected.

---

## Comparison

| Criterion | A · Strangler Fig | B · Big Bang | C · Parallel Run | D · Branch by Abstraction |
|---|---|---|---|---|
| Cost | high | medium | high | high |
| Risk | medium | high | low | medium |
| Time to first production value | **short** (wave 1) | long (end) | n/a | long |
| Time to completion | long | long | n/a | long |
| Fit with appetite (`transformational`) | good | appetite yes, **size no** | as a companion, mandated | poor |
| Compatibility with the paradigm change | good — waves follow the *target* dependency shape | best — Designer unconstrained | neutral | poor — seam must be built in the discarded paradigm |
| Answers "against what do we check?" | no | no | **yes** | no |
| Survives the MySQL → PostgreSQL split | via a replication seam | trivially (one ETL) | n/a (oracle is separate) | no |
| Honours the brief's incremental preference | **yes** | no | n/a | yes |

---

## Strategist's recommendation

- **Recommended strategy**: **A + C** — **Strangler Fig with deep boundaries as the delivery
  strategy, with a Parallel Run harness as the standing verification strategy.**

These are not alternatives. A answers *how the work is sequenced and shipped*; C answers *how any of
it is known to be correct*. Choosing A without C means shipping wave after wave with no oracle.
Choosing C without a delivery strategy ships nothing.

- **Rationale**, traceable to the three inputs:

  1. **From the brief.** "Incremental delivery is preferred over a dated big-bang" is a direct
     instruction, and there is no deadline to force the alternative. Strategy B is ruled out by the
     brief's own words before any technical argument is needed.
  2. **From the size.** The catalog permits Big Bang for a transformational appetite **on small
     systems**, and directs transformational appetites on larger systems to "Strangler Fig with deep
     boundaries". At 670,500 lines and 42 in-scope modules this is unambiguously the larger case.
  3. **From the paradigm.** The catalog rule *large paradigm change + transformational appetite →
     recommend a Parallel Run to validate parity* fires exactly on this project's inputs
     (gap: HIGH; appetite: transformational). The rule is reinforced here by a condition the catalog
     does not anticipate: **the legacy ships with no tests**, so the Parallel Run is not merely
     advisable, it is the only source of executable truth.
  4. **From the rules themselves.** 363 rules describe the *unfiltered default*, which
     `paradigm_decision.md` implication 2 makes permanent and final in the target. Permanent
     behaviour deserves executed evidence, not read evidence — especially the 9 override rules,
     where the owner has deliberately reproduced permissive authorization and regex-based
     sanitisation. Those are precisely the rules where "we read it carefully" is weakest.

- **What the recommendation costs, stated plainly.** This is the most expensive pairing in the
  table. It buys incrementality and evidence, and it pays for both with a replication seam
  (RISK-002, RISK-006, RISK-007) and a diff harness that has to be built before it earns anything.
  If the owner's real constraint is effort rather than schedule, **Strategy B is the coherent
  alternative** — and it should then still carry C, because the no-oracle problem is independent of
  delivery shape.

---

## Sequencing — does the 23-module cycle still bind?

> `paradigm_decision.md` instructs the Strategist to state this explicitly. This section is that
> statement.

**No. After the paradigm change the cycle does not bind the rebuild's sequencing — but it still
binds how the legacy must be *read*, and three of its edges survive as genuine data couplings.**

The 23-module strongly connected component (F-SIM-01) is measured over the **legacy** dependency
graph. Most of its edges exist because of mechanisms the rebuild does not reproduce:

| Cycle edge | Survives the paradigm change? | Why |
|---|---|---|
| everything ↔ `hooks-plugin-api` | **No** | 32 direct dependents, all through one discarded registry. Removing this single node removes the majority of the component's edges. |
| `bootstrap-and-load` ↔ `error-handling-and-recovery-mode` | **No** | Rails owns boot and error handling. Both modules dissolve into the framework. |
| `options-and-transients` → `formatting` → `kses` → `users-roles-capabilities` → `options` | **No** | Created by `sanitize_option()` running on every write plus capability checks reading options. In the target: sanitisation is a leaf library, settings are a model, policies read settings. A DAG. |
| `formatting-and-sanitization` ↔ `kses-security` | **No** (internally, yes) | The two call each other mutually, but together they form **one leaf library** with nothing depending inward. Mutual recursion inside a leaf is not a cycle in the module graph. Note the owner's override keeps this pair regex-based and tightly bound — that is a code-quality consequence, not a sequencing one. |
| `posts-and-post-types` ↔ `taxonomy-and-terms` | **Yes, but one-directional** | Term counts include only `post_status = 'publish'` (BR-TAX-11). In the target this is a counter cache or a scope: `Term` reads `Post`. `Post` no longer reads term counts. Edge survives, cycle does not. |
| `users-roles-capabilities` ↔ `posts-and-post-types` | **Yes, lifted out** | `map_meta_cap('edit_post')` reads the post; posts carry `post_author`. In the target the mutual dependency lifts into a **policy layer above both models**: `PostPolicy` depends on `User` and `Post`; neither model depends on the other's authorization code. |
| `rewrite-and-permalinks` ↔ `query-and-loop` | **Yes, genuinely** | `pagination_base` and `$wp_rewrite->feeds` determine which post slugs are legal (BR-POST-07, F-RW-06). This is a real, non-mechanical coupling: routing configuration constrains slug validation. It must be modelled deliberately in the target, not inherited by accident. |

**Consequence for sequencing.** The migration is sequenced by **target data dependency**, which is a
DAG, not by legacy module membership. The three surviving couplings above are not a cycle; they are
edges that must be crossed in the right order (sanitisation before settings; models before policies;
routing configuration before slug validation).

**Consequence for verification — the caveat that still binds.** F-SIM-05 states that the most
consequential couplings are invisible from either module alone. That is a fact about the *legacy
specification*, and no paradigm change repairs it. So the cycle survives as a **reading hazard**:
an integration checkpoint is required at the end of Wave 3 that exercises the entire former
component together, because a wave that is individually parity-clean can still be jointly wrong.
This is the checkpoint the brief's primary risk asked for, relocated from "before you can build
anything" to "before write authority moves".

### Delivery waves

Each wave is independently routable at the proxy and independently reversible until Wave 3.

| Wave | Surfaces | Write authority | Reversible | Why here |
|---|---|---|---|---|
| **0 · Foundations** | reference oracle instance, diff harness, CDC pipeline MySQL → PostgreSQL, `html-api` and `style-engine` ports | legacy | n/a | `html-api` and `style-engine` are the only two modules with zero internal dependencies *and* few dependents (F-SIM-03) — the only genuinely extractable components. They are the ideal first Ruby code because nothing depends on getting them second. |
| **1 · Read-only public output** | `feeds`, `sitemaps`, `embeds-oembed`, `performance-speculation-view-transitions` | legacy | yes, trivially | All terminal modules, zero dependents (F-SIM-06). No write path. Proves deployment, replication and the diff harness against real output at near-zero blast radius. |
| **2 · Front-end read path** | `query-and-loop`, `rewrite-and-permalinks`, `themes-and-templates`, `block-supports`, `blocks-library`, `global-styles-theme-json`, `script-modules-and-assets`, `interactivity-api` | legacy | yes | The whole public site renders from PostgreSQL while MySQL is still authoritative. This is where the largest volume of front-end parity diffing happens, still with no write risk. Crosses the surviving `rewrite` ↔ `query` coupling. |
| **3 · Content write path** ⚠️ | `posts-and-post-types`, `taxonomy-and-terms`, `comments`, `metadata`, `media-and-attachments`, `users-roles-capabilities`, `authentication-and-sessions`, `options-and-transients`, `kses-security`, `formatting-and-sanitization`, `cache-and-object-cache` | **flips to the rebuild** | **no — this is the cutover** | The point of no return. Everything that writes moves at once, because the single-writer invariant admits no partial state. The integration checkpoint spanning the former 23-module component runs here. |
| **4 · Editing and API surfaces** | `rest-api`, `admin-application`, `block-editor`, `customizer`, `widgets-and-nav-menus` | rebuild | forward-only | ⚠️ Largest *unspecified* body of work: the block editor client ships only as build output (TD-19, Q6), so Reversa extracted no client-side behaviour to migrate. Scope here is set by the Screen Translator, not by the rule set. |
| **5 · Periphery** | `cron`, `http-api`, `updates-and-upgrader`, `site-health`, `filesystem-api`, `internationalization`, `ai-abilities-connectors`, `error-handling-and-recovery-mode`, `multisite` | rebuild | forward-only | Mostly replaced by framework or platform capability (Solid Queue / Sidekiq, `Rails.cache`, Active Storage, `i18n`). `multisite` sits last because PostgreSQL schema-per-site (`BR-MS-01`) changes connection handling for everything before it — it is added, not retrofitted. |

**Excluded throughout**: `deprecated-compat` and `xmlrpc`, per the brief's declared scope.

---

## Specific warning signals

- ⚠️ **Large paradigm change + transformational appetite → Parallel Run.** The catalog rule fires,
  and is escalated from advisory to mandatory by TD-18 (zero tests in the legacy tree). Recorded as
  RISK-001, the highest-severity item in the register.
- ⚠️ **The single-writer invariant is the safety property of this whole plan.** MySQL and PostgreSQL
  must never both accept writes for the same entity. Dual-write is not a fallback; it is the failure
  mode. Recorded as RISK-002.
- ⚠️ **Wave 3 is not a wave, it is the cutover.** Everything before it is reversible by a proxy
  rule; nothing after it is. `cutover_plan.md` plans this moment specifically.
- ⚠️ **Two owner overrides carry known findings into the rebuild** (`F-DOM-02` permissive
  authorization, `F-KSES-05` regex HTML allowlist). The strategy does not relitigate them, but the
  Parallel Run must assert the *permissive* behaviour as specification, and the regex port carries
  its own engine-difference risk (RISK-005) that did not exist while the rules stayed in PHP.
- ⚠️ **No deadline means no forcing function.** The brief records the deadline as "not fixed". An
  incremental strategy with no date can stall indefinitely in Wave 2, which is the largest
  diff-heavy wave. Recorded as RISK-012; mitigated by treating each wave's parity gate as the
  milestone instead of a date.

---

## Open assumption — flagged for the human pause

The brief describes rebuilding **WordPress core as a product**. It does not say whether a **live
WordPress deployment with real data and real users** exists to be migrated. Strategy A's proxy
routing, its CDC seam and `cutover_plan.md` all assume one.

- **If a live site exists**: the plan above applies as written.
- **If it does not** (a pure product rebuild, no deployment): Wave 1's and Wave 2's production
  routing has nothing to route, and the waves become internal delivery milestones instead. The CDC
  seam reduces to a repeatable seeding script, and `cutover_plan.md` becomes the launch plan for the
  first deployment rather than a replacement of a running one. **Strategy C is unaffected and
  becomes even more central**, because the reference oracle instance is then the *only* WordPress
  that exists in the project.

Recorded in `ambiguity_log.md`. The recommendation does not change under either reading; the cutover
plan's framing does.

---

## Human decision

- **Chosen strategy**: **A + C** — Strangler Fig with deep boundaries as the delivery strategy, with
  a standing Parallel Run against a reference oracle as the verification strategy.
- **Decided by**: thies (owner)
- **When**: 2026-08-21
- **Decider's rationale**: the Strategist's recommendation accepted as presented, together with the
  answer to the open assumption below.

### Open assumption resolved: **there is no live deployment**

The owner confirms this is a **product rebuild only**. No running WordPress site with real data and
real users is to be migrated.

**This simplifies the chosen strategy substantially, and the simplification should be taken rather
than politely ignored.** Strategy A was priced for a live system; three of its most expensive parts
were paying for a condition that does not hold:

| Element of Strategy A | Status now | Effect |
|---|---|---|
| Reverse proxy routing per URL surface | **Not built** | There is no production traffic to route. |
| One-way CDC pipeline MySQL → PostgreSQL | **Reduced to a repeatable seeding script** | Runs on demand against the oracle's data, not continuously against production. The largest piece of throwaway engineering in the plan is deleted before it is written. |
| Dual-stack operating period | **Does not exist** | One runtime, one database. |
| The write-authority flip | **Becomes the first production launch** | See `cutover_plan.md`, reframed as a launch plan. |

**What survives, and why it still matters:**

- **The wave sequence survives unchanged.** It was derived from *target data dependency*, not from
  proxy routability, so it is just as valid as an internal delivery order. Waves 0–5 are now
  milestones gated by parity rather than by routing.
- **The single-writer invariant survives in a smaller form.** Nothing writes MySQL any more, so the
  divergence risk collapses — but the seeding script must still remain one-way, and the oracle's
  database must never become a write target of the rebuild.
- **Strategy C becomes the centre of the project.** The reference instance is now the *only*
  WordPress that exists here. It is not a testing aid; it is the executable definition of the 363
  rules, and every parity gate resolves against it.
- **The integration checkpoint survives and moves.** It was placed before the write-authority flip
  because that was the last reversible moment. With no flip, it attaches to the **end of Wave 3** as
  the gate that Waves 4 and 5 depend on, for the reason that has not changed: a wave can be
  individually parity-clean and jointly wrong (F-SIM-05, RISK-016).

**Risk register consequences**, applied in `risk_register.md`:

- **RISK-002** (dual write authority) drops from **CRITICAL to LOW** and moves to `accepted`. There
  is no second writer.
- **RISK-006** (PHP-serialised payloads) and **RISK-007** (`0000-00-00` dates) drop from **HIGH to
  MEDIUM**. They become one-time seeding problems rather than continuous pipeline problems — still
  real, since the oracle's corpus must round-trip correctly for parity to mean anything.
- **RISK-012** (no forcing function) rises in relative importance. It was partly held in check by
  the cost of running a dual stack; that pressure is now gone, and the parity gates are the only
  milestones left.
- **RISK-001** (no oracle) is **unchanged and now the single point of failure for the entire
  project.** Everything else was de-risked by this answer; this one was not.

All other risks stand as written.
