# ADR-002 — Never break backward compatibility

**Status:** Accepted · **Date:** ongoing since ~2004 · **Confidence:** 🟢 CONFIRMED

## Context

WordPress powers sites whose owners do not read changelogs and whose plugins may be unmaintained.
An update that breaks a site is, from the user's perspective, WordPress breaking their site.

## Decision

Deprecate but never remove. Keep deprecated functions fully functional, warn only under `WP_DEBUG`,
and preserve even **filenames** as public API.

## Evidence

- **9,112 lines** of deprecation code: `deprecated.php` (6,534), `wp-admin/includes/deprecated.php`
  (1,602), `ms-deprecated.php` (755), `pluggable-deprecated.php` (221) — ~1.4% of the PHP codebase.
- Filename aliases: `class.wp-scripts.php` **and** `class-wp-scripts.php`; `wp-db.php` **and**
  `class-wpdb.php`.
- `level_0`–`level_10` capabilities in every role, deprecated since 2.0 (2005).
- Commits: `Restore and deprecate wp_register_development_scripts()` (2026-01-12);
  `Further preserve back-compat for wp.sanitize.stripTags()` (2026-02-03);
  `Revert the renaming of $s variable in wp-admin/plugins.php` (2025-10-13) — a *variable rename*
  reverted for compatibility.
- `apply_filters_deprecated()` fires the removed hook and warns only if someone is listening
  (BR-HOOK-11).
- `set_sql_mode()` strips six strict MySQL modes so old data keeps working (ADR-007).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Semantic versioning with breaking majors | Users do not choose when to update; auto-updates would break sites silently. |
| Deprecation with a removal deadline | Requires plugin authors to act. Most abandoned plugins never will, and their users would be the casualties. |
| A compatibility shim package | Splits the problem without solving it; the shim becomes mandatory. |

## Consequences

**Positive**
- A site built in 2008 upgrades to 7.2. This is *the* reason WordPress achieved its market position.
- Plugin authors can target a decade-old API and still work.

**Negative**
- The compatibility surface only grows; nothing has a sunset date (F-DEP-03).
- Two of everything, permanently: REST **and** XML-RPC, widgets **and** blocks, `WP_Error` **and**
  `WP_Exception`, phpass **and** bcrypt (DR-09).
- Deprecation notices are invisible in production, so a plugin can rely on deprecated APIs
  indefinitely without any user ever seeing a warning (F-DEP-04).
- Design mistakes are permanent. `comment_approved` as a varchar, `guid` seeded from a permalink,
  and the `term_id`/`tt_id` split can never be corrected.
