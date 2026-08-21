# ADR-011 — Degrade instead of failing: recovery mode

**Status:** Accepted · **Date:** 2019 (WordPress 5.2) · **Confidence:** 🟢 CONFIRMED

## Context

A fatal PHP error in any plugin or theme took the entire site down — including the admin, so the
owner could not deactivate the offending plugin without FTP access. The "white screen of death" was
WordPress's most notorious failure mode, and the problem had been visible for over a decade.

## Decision

Catch fatal errors, attribute them to a specific extension, **pause that extension** so subsequent
requests skip it, and email the administrator a signed link to a recovery session.

## Evidence

The problem is documented in commits going back to 2007:

- `f7bf2c25ac Prevent plugins that generate PHP fatal errors from being activated` (2007-01-25)
- `0462e6f4ca Prevent plugins from taking down the install when plugin edits results in a fatal
  error` (2007-02-14)

Twelve years of point fixes preceded the systemic solution. The 5.2 implementation:

- `WP_Fatal_Error_Handler` registered at `wp-settings.php:69`, **before the database connects**
  (BR-BOOT-10).
- Handles exactly five error types: `E_ERROR`, `E_PARSE`, `E_USER_ERROR`, `E_COMPILE_ERROR`,
  `E_RECOVERABLE_ERROR` (BR-ERR-02).
- `WP_Recovery_Mode` plus four services (key, link, cookie, email).
- `wp_skip_paused_plugins()` / `wp_skip_paused_themes()` at boot (BR-BOOT-05) — the loop closes.

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Show a better error page | Does not restore access; the owner still cannot reach the admin. |
| Automatically deactivate the plugin | Destructive and possibly wrong — attribution is heuristic, and deactivation may lose configuration. *Pausing* is reversible. |
| Try/catch around plugin loading | PHP fatal errors are not catchable exceptions; only `register_shutdown_function` sees them. |
| Safe mode toggled by a URL parameter | Unauthenticated access to a plugin-disabling switch. |

## Consequences

**Positive**
- A fatal error now produces a **degraded but usable site** rather than a white screen (F-ERR-01).
- The full loop — detect, attribute, pause, skip, notify, recover — is genuinely well engineered and
  unusual in a CMS.
- `get_link_ttl()` returns `max($filtered_ttl, $rate_limit)`, so no filter misconfiguration can lock
  an administrator out (F-ERR-02).
- Composes with maintenance mode, auto-updates and paused extensions into a resilient story
  (F-UPD-03).

**Negative**
- Attribution is by **file path**. An error thrown inside core but caused by a plugin's data is
  attributed to core, and the wrong extension may be paused (F-ERR-03).
- The fatal-error handler is itself a drop-in, so a site can replace the mechanism that catches its
  own fatal errors (F-ERR-05).
- Only fatal errors trigger it; a plugin that renders a broken page without erroring is invisible to
  the mechanism.
