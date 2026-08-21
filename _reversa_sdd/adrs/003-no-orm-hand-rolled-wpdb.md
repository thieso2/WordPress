# ADR-003 — No ORM: a hand-rolled `wpdb` with `prepare()`

**Status:** Accepted · **Date:** 2003 · **Confidence:** 🟢 CONFIRMED

## Context

WordPress had to run on PHP 4 shared hosting with MySQL 3.23 and no extensions beyond `mysql`. No
ORM existed that would run there, and prepared statements were not available in the `mysql`
extension.

## Decision

Write a single database class exposing raw SQL, with an `sprintf()`-derived `prepare()` as the
injection boundary. No transactions, no query builder, no migrations framework.

## Evidence

- `class-wpdb.php`, ~4,230 lines, one class.
- `prepare()` (`class-wpdb.php:1458`) is regex-driven string interpolation, not a server-side
  prepared statement (F-DB-01).
- No `begin`/`commit`/`rollback` anywhere (F-DB-06).
- `update()`/`delete()` support only equality joined by `AND` (BR-DB-12).
- Migrations are `dbDelta()` diffing declared `CREATE TABLE` statements against the live schema
  (BR-UPD-08).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| An ORM (Doctrine, Eloquent) | Did not exist in 2003; would require Composer, which shared hosts did not have. |
| PDO with real prepared statements | PDO arrived in PHP 5.1 (2005), after `wpdb` was load-bearing; switching would break every plugin using `$wpdb->query()`. |
| A query builder | Would still need `$wpdb` underneath for compatibility, adding a layer without removing one. |

## Consequences

**Positive**
- Runs anywhere PHP and MySQL run.
- Plugins can write arbitrary SQL, which is why complex WordPress applications are possible.
- `prepare()`'s placeholder-escape sentinel is a genuinely good defense against second-order
  injection (`class-wpdb.php:2413`).

**Negative**
- **All SQL-injection defense rests on one regex-driven function** (F-DB-01).
- No transactions ⇒ every multi-table operation uses compensating logic instead (DR-07): term
  insert-then-delete, meta check-then-insert, slug loop-until-unique. Every uniqueness guarantee in
  WordPress is advisory (F-DOM-04).
- `$allow_unsafe_unquoted_parameters` stays `true` for compatibility, preserving the historically
  unsafe `%1$s`-as-identifier pattern (F-DB-03).
- The `db.php` drop-in can replace the whole class with no enforced interface (F-DB-08).
