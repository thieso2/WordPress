# ADR-004 — Post types as generic object storage

**Status:** Accepted · **Date:** 2010 (WordPress 3.0) · **Confidence:** 🟢 CONFIRMED

## Context

By 2.9 WordPress needed to persist several kinds of structured data that were not blog posts: menu
items, revisions, attachments. Adding a table per entity would mean a schema migration per feature,
per site, and — under multisite — per blog.

## Decision

Register a **post type** instead. Any entity that needs persistence becomes rows in `wp_posts` with
a distinguishing `post_type`, gaining meta, revisions, capabilities, REST exposure and admin UI for
free.

## Evidence

16 built-in types in `create_initial_post_types()` (`post.php:20`–`845`), only three of which are
user-facing content:

`post`, `page`, `attachment`, `revision`, `nav_menu_item`, `custom_css`, `customize_changeset`,
`oembed_cache`, `user_request`, `wp_block`, `wp_template`, `wp_template_part`, `wp_global_styles`,
`wp_navigation`, `wp_font_family`, `wp_font_face`

The pattern is visible in what got added over time: Customizer draft state (2015), oEmbed cache
(2016), GDPR requests (2018), block templates and global styles (2021), the Font Library (2023).
**Every new persistence need became a post type.**

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| A table per entity | A schema migration per feature; under multisite, one per blog (F-MS-01). `dbDelta()` would run N×sites times. |
| A generic `wp_objects` table | Functionally identical to `wp_posts`, but would not inherit meta, revisions, capabilities, REST controllers or list tables. |
| Options / meta only | No querying, no indexes, no per-object capabilities. |

## Consequences

**Positive**
- New persisted entities cost **zero** schema changes.
- Each inherits the meta system, the capability model, REST endpoints and the admin list table.
- Multisite isolation is automatic — the table is already per-blog.

**Negative**
- `wp_posts` is not a posts table; it is WordPress's object store (F-POST-01).
- Every query must filter by `post_type`, which is why `type_status_date` and `type_status_author`
  are the two composite indexes on the table (F-DD-04).
- An oEmbed cache entry participates in post queries, revisions and exports (F-EMB-04).
- `post.php` grew to 298 KB serving 16 unrelated entity types in one code path (F-POST-07).
- Deleting a "post" may delete a Customizer changeset, a font face or a template.
