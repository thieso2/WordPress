---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: migration_brief
producedBy: orchestrator
hash: "sha256:2bec430dab7af3b05b9d8a500a0c60d9418ecb187f480df2b988fdb635f70334"
---

# Migration Brief

> Migration criteria document collected in an interview at the start of `/reversa-migrate`.
> Consumed by all six agents of the Migration Team. It does not ask about the paradigm (the Paradigm Advisor's responsibility) nor the appetite (derived in `paradigm_decision.md`).

## Migration goal

**Rebuild WordPress core on a modern stack.**

Reimplement the CMS itself, preserving the behaviour that Reversa's 431 extracted business rules
describe. The legacy system is WordPress `7.2-alpha-63330`: 1,900 PHP files, ~670,500 lines,
44 modules, 565 actions and 1,638 filters.

The rebuild is **not** required to preserve WordPress's extension contract (see Constraints), so the
target is behavioural fidelity to the documented rules rather than drop-in replacement of the
platform.

## Success metrics

- **Behavioural parity with the documented rules.** Every one of the 431 business rules in
  `code-analysis.md` either holds in the new system or appears in a deviation log with a reason.
- **Parity specs pass.** The Inspector's Gherkin feature files execute green against the rebuild.
- **Explicit rule coverage.** No rule is silently dropped: each is either implemented, deliberately
  discarded in `discard_log.md`, or deferred with an owner.

## Constraints

- **Deadline**: not fixed. Incremental delivery is preferred over a dated big-bang.
- **Budget**: not stated.
- **Technical**: **no compatibility burden.** Nothing external depends on WordPress's APIs. The
  Designer is free to redesign the architecture, break the 23-module dependency cycle, drop the
  hook system, and discard the 9,112 lines of deprecation code. The 565 actions and 1,638 filters
  are **not** a contract that must be reproduced.
- **Operational**: not stated.

> ⚠️ **Note the tension between two answers, recorded deliberately.** The success metric is
> *behavioural parity*, but the constraint is *no compatibility burden*. These are compatible only
> under a precise reading: parity is owed to the **documented rules** (what WordPress does), not to
> the **extension contract** (how third parties change what it does). Every rule in the extraction
> describes WordPress's *unfiltered default* behaviour, which is exactly the surface parity applies
> to. The Curator must treat filter-dependent behaviour as out of parity scope.

## Known risk factors

- **The 23-module dependency cycle (primary risk).** 23 of the 44 modules form one strongly
  connected component: `admin-application`, `authentication-and-sessions`, `block-editor`,
  `block-supports`, `bootstrap-and-load`, `cron`, `error-handling-and-recovery-mode`,
  `filesystem-api`, `formatting-and-sanitization`, `global-styles-theme-json`, `http-api`,
  `internationalization`, `kses-security`, `multisite`, `options-and-transients`,
  `posts-and-post-types`, `query-and-loop`, `rewrite-and-permalinks`,
  `script-modules-and-assets`, `taxonomy-and-terms`, `themes-and-templates`,
  `updates-and-upgrader`, `users-roles-capabilities`.
  They cannot be built or validated independently. Any module-by-module migration sequence breaks
  on this, and the Strategist must plan an integration checkpoint spanning the whole set.
  Source: `traceability/spec-impact-matrix.md` section 1.

- Secondary, carried forward from the extraction and not selected as primary:
  - **Unverifiable behaviour.** This checkout is the built distribution, not `wordpress-develop`
    (question Q1). It contains no tests. All 431 rules were verified by reading, never by
    executing. Parity claims therefore rest on reading alone.
  - **Derived and implicit state.** Post status computed from dates, slugs uniqued by query loops,
    term counts padded at read time, all superglobal input arriving slashed. These are invisible in
    a schema and easily lost in an ActiveRecord port.

## Stakeholders

| Name / role | Responsibility in the migration |
|---|---|
| thies (owner) | Sole decision-maker. All human pauses resolve to this person. Owns every HUMAN DECISION item the Curator raises, the strategy choice, the topology approval and the screen mode approval. |

## Target stack

- **Language**: Ruby (modern, 3.3+)
- **Framework**: Ruby on Rails (modern, 7.1+)
- **Database**: PostgreSQL
- **Messaging** (if any): not specified. The legacy has no queue; WP-Cron is an option-backed queue
  drained by traffic, which Rails would replace with Solid Queue, Sidekiq or ActiveJob.
- **Infrastructure**: not specified.
- **Other relevant components**: not specified. The legacy assumes a persistent object cache
  (question Q8), which maps to Rails.cache backed by Redis or Solid Cache.

> Stack answered as free text: "modern rails and postgres".

## Declared scope

- **Included**: **42 of the 44 modules.** Everything the extraction covers except the two below.
- **Excluded**:
  - `deprecated-compat` (9,112 lines existing solely for backward compatibility). With no
    compatibility burden, there is nothing for it to be compatible with.
  - `xmlrpc` (78 methods, credentials on every call, no rate limit, unauthenticated
    `pingback.ping` SSRF). It has **zero dependents**, so removing it breaks nothing structurally.

> Note: `xmlrpc` was answered as *enabled* in the legacy analysis (question Q3), a decision about
> the **existing** system. Excluding it from the **rebuild** is consistent: the legacy keeps it for
> compatibility, and the rebuild has no compatibility burden.

## Free-form notes

Prior Reversa run: five phases complete, 195 artifacts, 44 units, 431 business rules, 222 findings,
12 retroactive ADRs. Overall confidence 86.7% CONFIRMED / 11.3% INFERRED / 2.0% GAP. Coverage 89.8%
of WordPress's own PHP.

Answers to the ten open questions were recorded on 2026-08-21 and are in `questions.md`. The three
that bear on this migration:

- **Q4** (authorization): fail closed everywhere is the house style. The rebuild should adopt it
  from the start rather than inherit WordPress's five conflicting defaults.
- **Q5** (KSES): should be migrated off regex HTML parsing. The rebuild has no reason to reproduce
  the regex allowlist at all.
- **Q7 / Q8** (cron, cache): the target deployment assumes a real scheduler and a persistent object
  cache, both of which Rails provides natively.

Two open gaps carried into this migration: `G-02` (fail-closed authorization) and `G-03` (KSES
migration). Both are *decided positions with work attached*, and both become design inputs here
rather than open questions.
