# Open Questions — WordPress

> Collected by Reversa in autonomous mode (`answer_mode: file`).
> Each 🔴 GAP found during analysis is recorded here instead of interrupting the run.
>
> **Please answer inline under each question.** Reversa reads this file on the next run.

---

## Q1 — Is this checkout the built distribution rather than `wordpress-develop`?

**Context.** The tree has no root `package.json` or `composer.json`, no `src/`, no `tests/`, no
`.github/`. `wp-includes/js/dist/` contains compiled `@wordpress/*` packages. Commit messages
reference `Build/Test Tools:` and a PHPStan baseline that are not present here.

**Why it matters.** Determines whether build, test and CI processes are in scope for the
specifications at all. Currently every statement about them is marked 🔴 GAP.

**Related:** SF-01, SF-02, `inventory.md` §1.

**Answer:**

**Answered 2026-08-21 — "Should be `wordpress-develop`."**

This checkout is the built distribution and is therefore **the wrong tree for a complete analysis**.
Consequences recorded across the extraction:

- These specifications describe **the distributed WordPress core only**.
- Build tooling, the automated test suite and CI pipelines are **absent, not merely unspecified**.
- A re-run against `wordpress-develop` would add build, test and CI coverage and is the way to close
  the remaining 🔴 GAPs in `inventory.md` §1 and §9.
- **Every behavioural claim here was verified by reading code, never by executing it.** No coverage
  figure can be produced from this tree.

Gap `G-04` remains **open**, reclassified from "unknown scope" to "known-incomplete tree".

---

## Q2 — What is the stray 0-byte `npx` file at the repository root?

**Context.** An untracked, empty file named `npx` sits at `/workspace/WordPress/npx`. It is not part
of WordPress and not part of the Reversa install.

**Why it matters.** If accidental it should be removed; Reversa will not touch it (non-destructive
rule).

**Related:** SF-03.

**Answer:**

**Answered 2026-08-21 — "Delete it." ✅ Actioned.**

Confirmed accidental and **removed** on explicit user instruction, reaffirmed a second time.

Verified immediately before deletion: **0 bytes, empty, untracked, present in no commit**, and
referenced by nothing in the tree. (A `grep` hit for `npx` in
`wp-includes/js/dist/vendor/react-dom.js` is the *string* inside a bundled library, not a reference
to this file.)

This was the one write outside `.reversa/` and `_reversa_sdd/` in the entire run. It was performed
only after explicit, repeated authorisation, and no tracked WordPress file was affected.

---

## Q3 — Is XML-RPC intentionally left enabled?

**Context.** `xmlrpc.php` is enabled by default (BR-XR-01). It exposes 78 methods, accepts a username
and password on **every call** with no core rate limit (F-XR-02), and `pingback.ping` performs an
**unauthenticated server-side fetch of a caller-supplied URL** (F-XR-03). REST duplicates nearly all
of `wp.*`.

**Why it matters.** This is the largest legacy attack surface in the analysis. If the answer is
"yes, for compatibility", that belongs in an ADR; if "no one has decided", it is a live risk.

**Related:** ADR-002, F-XR-01…04.

**Answer:**

**Answered 2026-08-21 — "enable it!"**

**Decision: XML-RPC stays enabled.** Recorded as a deliberate choice, not an oversight.

Gap `G-01` is downgraded from **critical** to **accepted risk**. The residual exposure is recorded
factually and unchanged, because the decision does not alter the behaviour:

- 78 methods, four of whose six families serve clients that no longer exist (F-XR-01).
- **Credentials transmitted on every call**; no session, no token (BR-XR-03).
- **No core rate limit** — the canonical brute-force target (F-XR-02).
- `pingback.ping` performs an **unauthenticated server-side fetch of a caller-supplied URL**
  (F-XR-03).
- The module has **zero dependents**; disabling it would break nothing structurally (F-SIM-04).

Mitigations available without disabling the endpoint: rate-limit `xmlrpc.php` at the web-server or
WAF layer, and disable pingbacks specifically via the `xmlrpc_methods` filter.

---

## Q4 — Which authorization default is the intended house style?

**Context.** Six authorization surfaces use five different defaults (`domain.md` DR-10,
`permissions.md` §7):

| Surface | Default when unspecified |
|---------|-------------------------|
| `map_meta_cap()` emitting no capabilities | **allowed** |
| REST route with no `permission_callback` | **public** |
| REST callback returning `null` | **denied** |
| Admin-Ajax `nopriv` handler | **public, no gate** |
| `delete_post` with no object argument | **denied** |
| Ability with no explicit opt-in | **private** |

**Why it matters.** Any new surface inherits whichever precedent its author happens to copy. This is
the highest-value finding in the analysis for security work.

**Related:** F-DOM-02, F-CAP-03, F-REST-01, F-ADM-01, ADR-012.

**Answer:**

**Answered 2026-08-21 — "Fail closed everywhere."**

**Deny-by-default is the house style.** The Abilities API (ADR-012) is the reference implementation;
the permissive surfaces are legacy debt to be corrected.

| Surface | Current default | Status under this decision |
|---------|----------------|---------------------------|
| Ability with no opt-in | **private** | ✅ reference — matches the standard |
| REST callback returning `null` | **denied** | ✅ conforms |
| `delete_post` with no object argument | **denied** | ✅ conforms (hardened in 6.1) |
| REST route with no `permission_callback` | **public** | ❌ **deviation** — to be corrected |
| `map_meta_cap()` emitting no capabilities | **allowed** | ❌ **deviation** — to be corrected |
| Admin-Ajax `nopriv` handler | **public, ungated** | ❌ **deviation** — no declarative gate exists |

Gap `G-02` stays **critical** and becomes an actionable item rather than an open question. Recorded
in `architecture.md` §6 as TD-01, TD-02 and in `permissions.md` §7.

---

## Q5 — Is there an intended migration path from `wpautop`/`wptexturize`/KSES to the HTML API?

**Context.** ADR-009 records that the HTML API was built because regex-based HTML manipulation caused
a long tail of correctness and security bugs. But `wpautop()` and `wptexturize()` still transform
every rendered post with regular expressions (F-FMT-04), and **KSES — the security-critical HTML
allowlist — still parses HTML with regular expressions** (F-KSES-05).

**Why it matters.** KSES is the higher-risk of the two and has not been migrated.

**Related:** ADR-009, F-HTML-01, F-KSES-05, F-FMT-04.

**Answer:**

**Answered 2026-08-21 — "Should be migrated."**

KSES is the highest-risk unmigrated regex parser in the codebase. Gap `G-03` stays **critical** and
is recorded as a recommended action in `architecture.md` §6 (TD-04).

Scope of the remaining migration:
- `kses.php` (~3,200 lines) — the security-critical allowlist, and the priority.
- `wpautop()` and `wptexturize()` in `formatting.php` — run on **every rendered post** (F-FMT-04).

ADR-009 records that the HTML API exists precisely because regex HTML manipulation caused a long
tail of correctness and security bugs. That rationale applies to KSES with more force than to
anything already migrated.

---

## Q6 — Is the block editor's client-side behavior in scope?

**Context.** The `@wordpress/*` packages ship only as build output in `wp-includes/js/dist/`. Their
source lives in the `gutenberg` repository, which is not in this tree.

**Why it matters.** Any specification of editor UX can be 🟡 INFERRED at best from this checkout.
Server-side block registration, rendering and supports **are** fully specified.

**Related:** SF-06, `dependencies.md` §4.

**Answer:**

**Answered 2026-08-21 — "Out of scope."**

Client-side editor behaviour is **deliberately unspecified**. Gap `G-05` is **closed**.

- Server-side block registration, parsing, rendering and supports remain fully specified
  (`block-editor/`, `blocks-library/`, `block-supports/`).
- `design-system.md` §6 already records that no component inventory is producible from this tree.

---

## Q7 — What is the intended production cron configuration?

**Context.** WP-Cron only runs when a request arrives (F-CRON-01). Its lock is a transient with no
atomic compare-and-set unless a persistent object cache is present (F-CRON-02).

**Why it matters.** Determines whether specifications should describe WP-Cron's default behavior or
a `DISABLE_WP_CRON` + system-crontab deployment. The two differ materially.

**Related:** ADR-006, BR-CRON-01…13.

**Answer:**

**Answered 2026-08-21 — "`DISABLE_WP_CRON` + system crontab."**

The documented target is a **real system scheduler**, not the visitor-triggered default. Gap `G-06`
is **closed**.

This removes the module's two most serious properties from the target deployment:
- F-CRON-01 (a site with no traffic runs no scheduled work) — **does not apply**; the crontab fires
  regardless of traffic.
- The visitor-latency cost of `ALTERNATE_WP_CRON` — **does not apply**.

The visitor-triggered path is reframed as the **fallback** for deployments without shell access.

---

## Q8 — Is a persistent object cache assumed?

**Context.** The default object cache is request-scoped only (F-CACHE-01). Its presence silently
changes transient storage (F-OPT-04), cron lock semantics (F-CRON-02) and the `WP_Query` split-query
optimization (BR-QUERY-07).

**Why it matters.** Performance and correctness characteristics differ between a default install and
one with Redis/Memcached. Specifications need to state which is assumed.

**Related:** F-CACHE-01, F-OPT-04, F-CRON-02, BR-QUERY-07.

**Answer:**

**Answered 2026-08-21 — "Assume a persistent object cache."**

Redis/Memcached is the target. Gap `G-07` is **closed**. Behaviour under this assumption:

| Subsystem | Under the assumed target | Rule |
|-----------|-------------------------|------|
| Transients | Stored in the **object cache with a native TTL** — no `wp_options` rows at all | BR-OPT-10 |
| Cron lock | The `doing_cron` transient is **shared across processes** | F-CRON-02 |
| `WP_Query` | Split-query optimization is **enabled** regardless of `posts_per_page` | BR-QUERY-07 |
| Object cache | **Persists across requests**; `$expire` is honoured | F-CACHE-01 |

⚠️ **Together with Q7 this resolves the cron locking concern entirely:** a persistent cache gives the
lock cross-process semantics, and the crontab removes the traffic dependency.

Where a default install diverges, the specs flag it inline — a reader on a default install is
looking at a materially different system.

---

## Q9 — Should vendored libraries be specified or only documented as dependencies?

**Context.** ~350 PHP files (~18% of the codebase) are vendored third-party libraries:
`php-ai-client` (146), `sodium_compat` (104), `SimplePie` (82), `Requests` (65), `ID3`, `PHPMailer`,
`IXR`, `Text_Diff`, `pomo`, PclZip, phpass, Snoopy.

**Why it matters.** Reversa documented them as dependencies (`dependencies.md`) rather than
reverse-engineering their internals. Confirm this is the intended scope.

**Related:** SF-04, `dependencies.md` §3.

**Answer:**

**Answered 2026-08-21 — "Dependencies only — correct."**

Current treatment confirmed. Gap `G-09` is **closed**. The 447 vendored files stay documented in
`dependencies.md` §3 rather than reverse-engineered.

⚠️ One item from this question is **not** closed by the answer and is retained in
`architecture.md` §6 as TD-20: there is **no lockfile and no automated CVE path** for the 13 vendored
PHP libraries, including `sodium_compat`, which verifies update-package signatures.

---

## Q10 — Is multisite in scope for the generated specifications?

**Context.** Multisite is not a layer but `is_multisite()` branches threaded through the kernel:
`wpdb`, the object cache, capabilities, options and boot all behave differently (F-MS-03).

**Why it matters.** Specifying both paths roughly doubles the surface of several modules. Reversa
documented multisite behavior inline throughout rather than as a separate track.

**Related:** F-MS-01…04, ADR-004.

**Answer:**

**Answered 2026-08-21 — "In scope — inline is right."**

Confirmed. Gap `G-08` is **closed**. Multisite behaviour stays documented where it occurs, which
mirrors how the code is actually written: `is_multisite()` branches threaded through `wpdb`, the
object cache, capabilities, options and boot (F-MS-03).

---

## Summary

**All ten questions were answered on 2026-08-21.**

| # | Question | Answer | Gap status |
|---|----------|--------|-----------|
| Q1 | Built distribution vs. `wordpress-develop`? | Should be `wordpress-develop` | G-04 **open** — known-incomplete tree |
| Q2 | Stray `npx` file | Delete it | ✅ **actioned** — file removed after explicit confirmation |
| Q3 | XML-RPC intentionally enabled? | **Keep it enabled** | G-01 → **accepted risk** |
| Q4 | Intended authorization default | **Fail closed everywhere** | G-02 **critical** — now actionable |
| Q5 | HTML API migration for KSES | **Should be migrated** | G-03 **critical** — now actionable |
| Q6 | Block editor client-side in scope? | Out of scope | G-05 **closed** |
| Q7 | Production cron configuration | `DISABLE_WP_CRON` + crontab | G-06 **closed** |
| Q8 | Persistent object cache assumed? | **Yes** | G-07 **closed** |
| Q9 | Vendored libraries: specify or document? | Dependencies only | G-09 **closed** (TD-20 retained) |
| Q10 | Multisite in scope? | In scope, inline | G-08 **closed** |

**Result: 7 gaps closed, 2 remain critical and actionable, 1 accepted as risk.**

The two remaining critical gaps (G-02, G-03) are no longer *questions* — they are decided positions
with known work attached. They are recorded in `architecture.md` §6 as technical debt with an owner
decision behind them.
