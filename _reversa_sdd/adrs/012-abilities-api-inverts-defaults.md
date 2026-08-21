# ADR-012 — Invert core's defaults for the Abilities API

**Status:** Accepted · **Date:** 2025 (WordPress 6.9) · **Confidence:** 🟢 CONFIRMED

## Context

WordPress needed a way for AI agents to discover and invoke site operations. Unlike a REST endpoint —
called by a developer who read the docs — an ability may be invoked by a language model choosing
autonomously from a list. The consequences of a permissive default are different in kind.

Core's existing defaults were, variously: a REST route without `permission_callback` is **public**
(BR-REST-05); `map_meta_cap()` emitting no capabilities means **allowed** (BR-CAP-05); an
Admin-Ajax `nopriv` handler is **public with no gate** (BR-ADM-07); `register_post_type()` and
`add_filter()` silently **overwrite** existing registrations.

## Decision

Choose the opposite default at every point.

## Evidence

Introduced `d3fe16afc4 Abilities API: Introduce server-side registry and REST API endpoints`
(2025-10-21), then hardened over the following week: input normalization from schema (10-22),
categories controller (10-22), core abilities registration (10-26), refactors and documentation
(10-27), and `90d7aada35 AI: Sync Ability_Function_Resolver API enhancement to harden security`
(2026-03-03).

| Concern | Core's usual default | Abilities API |
|---------|---------------------|---------------|
| Naming | any string | **mandatory** `^[a-z0-9-]+/[a-z0-9-]+$` namespace (BR-AI-01) |
| Re-registration | silently overwrites | **fails** with `_doing_it_wrong()` (BR-AI-02) |
| Category | free-form | **must already be registered** (BR-AI-03) |
| Visibility | public unless restricted | **`DEFAULT_PUBLIC = false`**, `DEFAULT_SHOW_IN_REST = false` (BR-AI-04) |
| Input | ad hoc validation | **JSON Schema validated** (BR-AI-06) |
| Output | never checked | **JSON Schema validated** (BR-AI-06) |
| Unserialization | unguarded | `__wakeup()` / `__sleep()` **overridden** (BR-AI-08) |

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Expose abilities as ordinary REST routes | Would inherit BR-REST-05: a forgotten `permission_callback` makes an AI-invocable operation public. |
| Reuse the existing hook registry | Hooks have no schema, no permission model and no identity beyond a string. |
| Match core's existing defaults for consistency | Rejected — see the evidence. Every default was deliberately inverted. |

## Consequences

**Positive**
- **The strictest contracts in WordPress** (F-AI-01), in the subsystem where strictness matters most.
- Output validation is unique in core: nothing else verifies that a callback returned what it
  promised (F-AI-02).
- One declaration yields both a REST endpoint and an LLM-callable function, via
  `WP_AI_Client_Ability_Function_Resolver` (BR-AI-10).
- The AI client routes its HTTP through the WordPress HTTP API, inheriting the SSRF guards of
  ADR-003's sibling module (BR-AI-09).

**Negative**
- **Two philosophies now coexist in one codebase.** A developer's intuition from REST or Admin-Ajax
  is wrong here, and vice versa — adding a sixth entry to the six-defaults problem (DR-10).
- Every registered ability is potentially reachable by a language model, with `permission_callback`
  as the only gate, in a context its author may not have anticipated (F-AI-04).
- Permissions are checked *after* input validation, so an unauthorized caller learns whether their
  input was well-formed (F-AI-03).
- 156 PHP files of AI infrastructure now ship in core with no counterpart in existing WordPress
  documentation (F-AI-05).
