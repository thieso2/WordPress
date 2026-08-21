# ADR-001 — Hooks as the universal extension mechanism

**Status:** Accepted · **Date:** ~2003–2004 · **Confidence:** 🟢 CONFIRMED

## Context

WordPress needed third parties to modify behavior without editing core files, because users install
by unzipping onto shared hosting and update by overwriting those files. Any customization written
into core would be destroyed by the next update.

## Decision

Expose behavior through a global registry of named callbacks — **actions** (side effects) and
**filters** (value transformation) — implemented as one mechanism. Wrap essentially every value core
computes in `apply_filters()`.

## Evidence

- `wp-includes/plugin.php` and `class-wp-hook.php`; `do_action()` is `apply_filters()` with the
  return discarded (`class-wp-hook.php:375`).
- **565 unique actions, 1,638 unique filters**, 3,371 dispatch sites across `wp-includes` and
  `wp-admin`.
- `apply_filters('query', $sql)` — even SQL is filterable (`class-wpdb.php:2219`).
- `apply_filters('user_has_cap', …)` — even authorization is filterable
  (`class-wp-user.php:801`).
- The `'all'` hook intercepts every dispatch in the system (`plugin.php:182`).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Class inheritance / overriding | Requires an object graph and a container; PHP 4 had neither, and users cannot edit core anyway. |
| Configuration files | Cannot express behavior, only values. |
| A formal plugin API with declared interfaces | Would have required every extension point to be designed in advance; hooks let core add them incrementally. |

## Consequences

**Positive**
- The largest plugin ecosystem of any CMS.
- Core can add an extension point in one line, at any time.
- Behavior is customizable without forking.

**Negative**
- **No core behavior can be specified in isolation** (F-HOOK-06). Every "WordPress does X" is
  "WordPress does X unless a filter says otherwise".
- Every dispatch pays two `isset()` checks for the `'all'` hook (F-HOOK-05).
- Closures cannot practically be removed once registered (F-HOOK-02).
- A callback whose unique id cannot be built is dropped **silently** (BR-HOOK-03).
- `resort_active_iterations()` depends on PHP's internal array pointer and is the most fragile code
  in the kernel (F-HOOK-03).
