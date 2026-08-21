# ADR-005 — Make the security core pluggable

**Status:** Accepted · **Date:** ~2004 · **Confidence:** 🟢 CONFIRMED

## Context

Sites needed to integrate WordPress with existing authentication — LDAP, single sign-on, external
user tables — and to send mail through providers rather than PHP's `mail()`. Filters can adjust a
value, but cannot replace an algorithm.

## Decision

Wrap 35 functions in `if ( ! function_exists( … ) )` and load that file **after all plugins**, so any
plugin defining its own version wins outright.

## Evidence

- `wp-includes/pluggable.php` — every function guarded by `function_exists()`.
- `wp-settings.php:612` loads it after the active-plugin loop (BR-BOOT-06).
- The overridable set includes the entire security core: `wp_authenticate`, `wp_validate_auth_cookie`,
  `wp_generate_auth_cookie`, `wp_set_auth_cookie`, `wp_hash_password`, `wp_check_password`,
  `wp_salt`, `wp_hash`, `wp_create_nonce`, `wp_verify_nonce`, `check_admin_referer`,
  `wp_safe_redirect`, `wp_validate_redirect`, `wp_mail`, `wp_rand`, `wp_generate_password`.

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Filters on each function's result | Cannot replace an algorithm — you can filter the output of `wp_check_password()` but not make it consult LDAP. |
| A formal `AuthenticationProvider` interface | Requires a container and a registration API; would still need the old functions to exist for compatibility. |
| The `authenticate` filter alone | Exists and is used, but covers only the login path, not cookies, nonces or hashing. |

## Consequences

**Positive**
- Any authentication scheme is implementable without forking core.
- SMTP, LDAP and SSO plugins work by definition rather than by workaround.

**Negative**
- **"How does WordPress authenticate?" is unanswerable without knowing the plugin set** (F-AUTH-01).
- No interface contract: a plugin redefining `wp_check_password()` with the wrong signature or weaker
  logic silently owns password verification for the whole site.
- Two plugins attempting the same override collide — the first loaded wins, and the second's
  definition is simply skipped.
- Security review must check whether each function is core's or a plugin's.
