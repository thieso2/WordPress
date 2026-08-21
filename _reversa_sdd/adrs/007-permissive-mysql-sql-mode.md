# ADR-007 — Run MySQL in permissive SQL mode

**Status:** Accepted · **Date:** 2014 (WordPress 4.1) · **Confidence:** 🟢 CONFIRMED

## Context

MySQL 5.6+ began shipping stricter default SQL modes. WordPress stores values those modes reject —
most importantly `0000-00-00 00:00:00`, which is the `post_date_gmt` of every draft.

## Decision

On connect, **remove** six SQL modes from the session rather than change the data model.

## Evidence

`wpdb::$incompatible_modes` (`class-wpdb.php:644`):

```
NO_ZERO_DATE, ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, STRICT_ALL_TABLES, TRADITIONAL, ANSI
```

stripped by `set_sql_mode()` (`class-wpdb.php:949`) on every connection.

The causal link is explicit in the schema: `wp-admin/includes/schema.php` declares
`post_date datetime NOT NULL default '0000-00-00 00:00:00'`, and `wp_insert_post()` writes that value
for drafts (BR-POST-04). `NO_ZERO_DATE` would reject every draft.

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| Make `post_date_gmt` nullable and use `NULL` for drafts | Would require migrating every row on every existing site, and every plugin comparing against `'0000-00-00 00:00:00'` would break (ADR-002). |
| Use a sentinel date like `1970-01-01` | Same migration cost, plus it becomes a legitimate-looking date. |
| Let strict mode reject the write and handle the error | Drafts would stop saving on modern MySQL. |

## Consequences

**Positive**
- Existing data and existing plugin code keep working on modern MySQL.
- No migration required on any site.

**Negative**
- **WordPress requires a permissively configured database.** A hardened DBA setting these modes
  globally will find WordPress silently overriding them per session.
- `ONLY_FULL_GROUP_BY` removal means core and plugin queries may rely on non-deterministic
  `GROUP BY` results.
- Strict-mode data-truncation protection is unavailable, which is why `wpdb` implements its own
  charset-and-length rejection in PHP instead (BR-DB-06) — a guard that exists *because* this
  decision removed the database's own.
- Two modules' constraints are causally locked: the post module's draft representation determines
  the database module's SQL mode (F-DOM-03).
