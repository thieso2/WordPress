---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: target_data_model
producedBy: designer
hash: "sha256:2325df9a6281156fc47fd641d403a474e8358c6206fb3b570704b62bde069ca4"
---

# Target Data Model

> Data model of the new system: schema, relationships and constraints.
> Required reading before this: `target_architecture.md`, then `target_domain_model.md`.

## Overview

**PostgreSQL 16+, single OLTP database, no event store and no outbox** — the target paradigm is
Active Record, not event-driven (`paradigm_decision.md` option 1). Binary content lives in Active
Storage; the object cache is `Rails.cache` on Redis or Solid Cache; the job queue is a real queue,
not a table of serialized options.

The schema differs from the legacy in four structural ways, each traceable to a decision:

1. **Foreign keys exist.** The legacy has **none anywhere** (F-DD-01); all 18 relationships are
   enforced in PHP or not at all. Every relationship below is a real FK with a declared delete rule.
2. **Uniqueness is enforced by the database**, replacing check-then-act loops (AD-05). The legacy's
   uniqueness guarantees are *advisory* (F-DOM-04).
3. **`wp_posts` is split**, not reproduced (AD-02) — content stays in one STI table; the eleven
   machinery post types get tables shaped like what they are.
4. **Core-owned metadata is columns** (AD-03); only genuinely arbitrary attributes remain key-value,
   as `jsonb` with a GIN index rather than an unindexed `longtext` (F-DD-02, TD-07).

Under multisite (Wave 5) every blog-scoped table below lives in a **per-site PostgreSQL schema**
selected by `search_path`; the four global tables live in a shared schema (`BR-MS-01`, RISK-009).

## Data entities

| Entity | Table | Owning aggregate | PK | Bounded context | Scope |
|---|---|---|---|---|---|
| `Publishing::Post` | `posts` | AGG-Post | `id` | Publishing | blog |
| `Publishing::Revision` | `revisions` | AGG-Post | `id` | Publishing | blog |
| `Publishing::Attribute` | `post_attributes` | AGG-Post | `id` | Publishing | blog |
| `Publishing::StatusTransition` | `post_status_transitions` | AGG-Post | `id` | Publishing | blog |
| `Classification::Taxonomy` | `taxonomies` | AGG-Term | `id` | Classification | blog |
| `Classification::Term` | `terms` | AGG-Term | `id` | Classification | blog |
| `Classification::Assignment` | `term_assignments` | AGG-Term | `id` | Classification | blog |
| `Discussion::Comment` | `comments` | AGG-Comment | `id` | Discussion | blog |
| `Discussion::ModerationVerdict` | `moderation_verdicts` | AGG-Comment | `id` | Discussion | blog |
| `Discussion::RateLimit` | `comment_rate_limits` | AGG-Comment | `id` | Discussion | blog |
| `Library::Asset` | `assets` | AGG-Asset | `id` | Library | blog |
| `Library::Variant` | `asset_variants` | AGG-Asset | `id` | Library | blog |
| `Identity::User` | `users` | AGG-User | `id` | Identity | **global** |
| `Identity::RoleAssignment` | `role_assignments` | AGG-User | `id` | Identity | **global** |
| `Identity::Session` | `sessions` | AGG-User | `id` | Identity | **global** |
| `Identity::ApplicationPassword` | `application_passwords` | AGG-User | `id` | Identity | **global** |
| `Identity::DataRequest` | `data_requests` | AGG-User | `id` | Identity | global |
| `Configuration::Setting` | `settings` | AGG-Setting | `id` | Configuration | blog |
| `Presentation::Menu` | `menus` | AGG-Menu | `id` | Presentation | blog |
| `Presentation::MenuItem` | `menu_items` | AGG-Menu | `id` | Presentation | blog |
| `Presentation::Theme` | `themes` | — | `id` | Presentation | blog |
| `Composition::Template` | `templates` | — | `id` | Composition | blog |
| `Composition::Pattern` | `patterns` | — | `id` | Composition | blog |
| `Routing::Redirect` | `redirects` | AGG-Permalink | `id` | Routing | blog |
| `Syndication::EmbedCache` | `embed_caches` | — | `id` | Syndication | blog |
| `Platform::SchemaVersion` | *(Rails `schema_migrations`)* | — | `version` | Platform | global |

**26 tables against the legacy's 18** — the increase is entirely AD-02 and AD-03 splitting things
that shared a table without sharing a shape. Four legacy tables disappear: `links` (dead weight in
every install, F-DD-07), `registration_log`, and the four `postmeta`/`usermeta`/`commentmeta`/
`termmeta` stores collapse to one narrow `post_attributes` plus columns and `jsonb`.

## Schema (DDL)

```sql
-- ─────────────────────────────────────────────────────────────────────────
-- IDENTITY  (global scope — shared across sites under multisite)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    login           citext      NOT NULL,
    email           citext      NOT NULL,
    password_digest text        NOT NULL,
    nicename        citext      NOT NULL,
    display_name    text        NOT NULL DEFAULT '',
    url             text,
    status          text        NOT NULL DEFAULT 'active',
    registered_at   timestamptz NOT NULL DEFAULT now(),
    activation_key_digest text,
    locale          text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
-- Legacy has only non-unique KEYs on user_login / user_email. These are UNIQUE.
CREATE UNIQUE INDEX users_login_key    ON users (login);
CREATE UNIQUE INDEX users_email_key    ON users (email);
CREATE UNIQUE INDEX users_nicename_key ON users (nicename);

-- Replaces usermeta['{prefix}capabilities'], a serialized role=>true map (BR-CAP-13, F-MS-04).
CREATE TABLE role_assignments (
    id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id  bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role     text   NOT NULL,
    site_id  bigint,                       -- NULL = single-site / network-wide
    granted_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX role_assignments_unique ON role_assignments (user_id, role, coalesce(site_id, 0));

-- Replaces usermeta['session_tokens'] (BR-AUTH-15).
CREATE TABLE sessions (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_digest text        NOT NULL,
    ip           inet,
    user_agent   text,
    expires_at   timestamptz NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX sessions_token_key ON sessions (token_digest);
CREATE INDEX sessions_user_expiry ON sessions (user_id, expires_at);

CREATE TABLE application_passwords (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name         text   NOT NULL,
    digest       text   NOT NULL,
    last_used_at timestamptz,
    last_ip      inet,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE data_requests (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      bigint REFERENCES users(id) ON DELETE SET NULL,
    email        citext NOT NULL,
    kind         text   NOT NULL CHECK (kind IN ('export','erasure')),
    status       text   NOT NULL DEFAULT 'pending',
    confirmed_at timestamptz,
    completed_at timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────
-- CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────
-- AD-06: settings ONLY. The routing table and the job queue are structurally
-- barred from this table; transients live in Rails.cache.
CREATE TABLE settings (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       text        NOT NULL,
    value      jsonb       NOT NULL,
    autoload   boolean     NOT NULL DEFAULT false,   -- explicit policy, never a size heuristic
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX settings_name_key ON settings (name);
CREATE INDEX settings_autoload ON settings (autoload) WHERE autoload;  -- cf. F-DD-09

-- ─────────────────────────────────────────────────────────────────────────
-- PUBLISHING
-- ─────────────────────────────────────────────────────────────────────────
CREATE TYPE post_status AS ENUM
    ('auto_draft','draft','pending','scheduled','published','private','trashed');

-- AD-02: STI over CONTENT types only. Machinery post types have their own tables.
CREATE TABLE posts (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type                text        NOT NULL DEFAULT 'Publishing::Article',  -- STI discriminator
    author_id           bigint      REFERENCES users(id) ON DELETE SET NULL,
    parent_id           bigint      REFERENCES posts(id) ON DELETE CASCADE,
    featured_asset_id   bigint,     -- FK added after assets; replaces postmeta '_thumbnail_id'
    title               text        NOT NULL DEFAULT '',
    slug                text,       -- NULL until allocated: drafts have none (BR-MIGRATE-032)
    content             text        NOT NULL DEFAULT '',
    excerpt             text        NOT NULL DEFAULT '',
    status              post_status NOT NULL DEFAULT 'draft',
    -- AD-07: ONE timestamptz per event, not the legacy local/GMT pair.
    -- NULL replaces '0000-00-00 00:00:00' (RISK-007).
    published_at        timestamptz,
    modified_at         timestamptz NOT NULL DEFAULT now(),
    trashed_at          timestamptz,
    status_before_trash post_status,               -- replaces postmeta '_wp_trash_meta_status'
    comment_status      text        NOT NULL DEFAULT 'open',
    password_digest     text,
    menu_order          integer     NOT NULL DEFAULT 0,
    guid                uuid        NOT NULL DEFAULT gen_random_uuid(),  -- DEVIATION BR-POST-10
    template_slug       text,                       -- replaces postmeta '_wp_page_template'
    comment_count       integer     NOT NULL DEFAULT 0,   -- counter cache
    attributes          jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    -- Trash state is all-or-nothing.
    CONSTRAINT posts_trash_consistent CHECK (
        (trashed_at IS NULL     AND status_before_trash IS NULL) OR
        (trashed_at IS NOT NULL AND status_before_trash IS NOT NULL)),
    -- A published or scheduled record has a publication instant; a draft need not.
    CONSTRAINT posts_published_at_present CHECK (
        status NOT IN ('published','scheduled') OR published_at IS NOT NULL),
    -- BR-MIGRATE-035: 200 bytes INCLUDING any numeric suffix.
    CONSTRAINT posts_slug_length CHECK (slug IS NULL OR octet_length(slug) <= 200)
);

-- AD-05: replaces wp_unique_post_slug()'s query-per-attempt loop (F-POST-03).
-- Hierarchical types unique within (type, parent); flat types within (type). BR-MIGRATE-033.
CREATE UNIQUE INDEX posts_slug_hierarchical
    ON posts (type, coalesce(parent_id, 0), slug) WHERE slug IS NOT NULL;

-- Legacy's two composite indexes, kept: the schema was tuned for exactly these clauses (F-DD-04).
CREATE INDEX posts_type_status_published ON posts (type, status, published_at DESC NULLS LAST, id);
CREATE INDEX posts_type_status_author    ON posts (type, status, author_id);
CREATE INDEX posts_parent                ON posts (parent_id);
-- TD-07 / F-DD-02: the legacy never indexes meta_value. This one does.
CREATE INDEX posts_attributes_gin        ON posts USING gin (attributes jsonb_path_ops);

-- AD-02: split out of wp_posts. A revision is an audit record, not content —
-- which is why the legacy has to exclude post_type='revision' from nearly every query.
CREATE TABLE revisions (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id    bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id  bigint REFERENCES users(id) ON DELETE SET NULL,
    title      text   NOT NULL DEFAULT '',
    content    text   NOT NULL DEFAULT '',
    excerpt    text   NOT NULL DEFAULT '',
    autosave   boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX revisions_post ON revisions (post_id, created_at DESC);

-- AD-03: the RESIDUAL bucket only. Every core-owned key became a column above.
CREATE TABLE post_attributes (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    key     text   NOT NULL,
    value   jsonb  NOT NULL
);
-- AD-05: replaces add_metadata()'s SELECT COUNT(*) then INSERT with nothing behind it (F-META-02).
CREATE UNIQUE INDEX post_attributes_unique ON post_attributes (post_id, key);

-- Replaces the transition_post_status action: a row, not a broadcast (AD-01).
CREATE TABLE post_status_transitions (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id     bigint      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    from_status post_status,
    to_status   post_status NOT NULL,
    actor_id    bigint      REFERENCES users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX post_status_transitions_post ON post_status_transitions (post_id, occurred_at DESC);

-- ─────────────────────────────────────────────────────────────────────────
-- CLASSIFICATION
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE taxonomies (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         text    NOT NULL,
    hierarchical boolean NOT NULL DEFAULT false,
    object_types text[]  NOT NULL DEFAULT '{}'
);
CREATE UNIQUE INDEX taxonomies_name_key ON taxonomies (name);

CREATE TABLE terms (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    taxonomy_id bigint NOT NULL REFERENCES taxonomies(id) ON DELETE CASCADE,
    parent_id   bigint REFERENCES terms(id) ON DELETE CASCADE,
    name        text   NOT NULL,
    slug        text   NOT NULL,
    description text   NOT NULL DEFAULT '',
    count       integer NOT NULL DEFAULT 0,   -- counter cache: PUBLISHED only (BR-TAX-11)
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT terms_not_self_parent CHECK (parent_id IS DISTINCT FROM id)
);
-- AD-05: the constraint wp_insert_term() actually guards but the legacy schema does NOT
-- have — F-DD-05 records that term_taxonomy's UNIQUE KEY covers (term_id, taxonomy)
-- and therefore misses the (slug, parent, taxonomy) case entirely.
CREATE UNIQUE INDEX terms_unique ON terms (taxonomy_id, coalesce(parent_id, 0), slug);
CREATE INDEX terms_parent ON terms (parent_id);

CREATE TABLE term_assignments (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    term_id           bigint NOT NULL REFERENCES terms(id) ON DELETE CASCADE,
    classifiable_type text   NOT NULL,   -- 'Publishing::Post' | 'Library::Asset'
    classifiable_id   bigint NOT NULL,
    position          integer NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX term_assignments_unique
    ON term_assignments (term_id, classifiable_type, classifiable_id);
CREATE INDEX term_assignments_target ON term_assignments (classifiable_type, classifiable_id);

-- ─────────────────────────────────────────────────────────────────────────
-- DISCUSSION
-- ─────────────────────────────────────────────────────────────────────────
CREATE TYPE comment_status AS ENUM ('pending','approved','spam','trashed');

CREATE TABLE comments (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    post_id      bigint NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    parent_id    bigint REFERENCES comments(id) ON DELETE CASCADE,
    user_id      bigint REFERENCES users(id) ON DELETE SET NULL,
    author_name  text   NOT NULL DEFAULT '',
    author_email citext,
    author_url   text,
    author_ip    inet,
    user_agent   text,
    content      text   NOT NULL,
    status       comment_status NOT NULL DEFAULT 'pending',   -- BR-CMT-12: enum, not varchar
    kind         text   NOT NULL DEFAULT 'comment',
    submitted_at timestamptz NOT NULL DEFAULT now(),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_post_status ON comments (post_id, status, submitted_at DESC);
CREATE INDEX comments_parent      ON comments (parent_id);
-- F-DD-06: the legacy indexes comment_author_email to only 10 characters, so flood
-- control and previously-approved lookups scan a wide prefix bucket. Full index here.
CREATE INDEX comments_author_email ON comments (author_email);

CREATE TABLE moderation_verdicts (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    comment_id bigint NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    outcome    text   NOT NULL,
    reason     text   NOT NULL,
    decided_by bigint REFERENCES users(id) ON DELETE SET NULL,
    decided_at timestamptz NOT NULL DEFAULT now()
);

-- NEW: deviation BR-CMT-04. The legacy's flood verdict defaults to false,
-- so no rate limit is actually enforced anywhere.
CREATE TABLE comment_rate_limits (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    author_key   text        NOT NULL,
    window_start timestamptz NOT NULL,
    count        integer     NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX comment_rate_limits_key ON comment_rate_limits (author_key, window_start);

-- ─────────────────────────────────────────────────────────────────────────
-- LIBRARY
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE assets (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uploader_id  bigint REFERENCES users(id) ON DELETE SET NULL,
    attached_to_id bigint REFERENCES posts(id) ON DELETE SET NULL,
    title        text   NOT NULL DEFAULT '',
    slug         text   NOT NULL,
    alt_text     text   NOT NULL DEFAULT '',   -- postmeta '_wp_attachment_image_alt'
    caption      text   NOT NULL DEFAULT '',
    mime_type    text   NOT NULL,
    byte_size    bigint NOT NULL,
    width        integer,
    height       integer,
    metadata     jsonb  NOT NULL DEFAULT '{}'::jsonb,  -- EXIF etc.
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
-- BR-MIGRATE-033: attachment slugs are unique across ALL types in the legacy.
CREATE UNIQUE INDEX assets_slug_key ON assets (slug);
CREATE INDEX assets_attached_to ON assets (attached_to_id);

CREATE TABLE asset_variants (
    id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id  bigint NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
    size_name text   NOT NULL,
    width     integer NOT NULL,
    height    integer NOT NULL,
    mime_type text   NOT NULL
);
CREATE UNIQUE INDEX asset_variants_unique ON asset_variants (asset_id, size_name);

-- Deferred FK: posts.featured_asset_id → assets.id (replaces postmeta '_thumbnail_id').
ALTER TABLE posts ADD CONSTRAINT posts_featured_asset_fk
    FOREIGN KEY (featured_asset_id) REFERENCES assets(id) ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- PRESENTATION  —  menus materialized from nine postmeta keys (BR-MENU-02)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE menus (
    id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name     text NOT NULL,
    slug     text NOT NULL,
    location text
);
CREATE UNIQUE INDEX menus_slug_key ON menus (slug);

CREATE TABLE menu_items (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    menu_id     bigint  NOT NULL REFERENCES menus(id) ON DELETE CASCADE,
    parent_id   bigint  REFERENCES menu_items(id) ON DELETE CASCADE,
    position    integer NOT NULL DEFAULT 0,
    target_type text,           -- 'Publishing::Post' | 'Classification::Term' | NULL for custom
    target_id   bigint,
    url         text,
    label       text NOT NULL DEFAULT '',
    title       text NOT NULL DEFAULT '',
    css_classes text[] NOT NULL DEFAULT '{}',
    xfn         text NOT NULL DEFAULT '',
    -- Exactly one of: an internal target, or a custom URL. Never both, never neither.
    CONSTRAINT menu_items_one_target CHECK (
        (target_type IS NOT NULL AND target_id IS NOT NULL AND url IS NULL) OR
        (target_type IS NULL     AND target_id IS NULL     AND url IS NOT NULL))
);
CREATE INDEX menu_items_menu ON menu_items (menu_id, position);

CREATE TABLE themes (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug         text NOT NULL,
    parent_slug  text,
    version      text NOT NULL,
    active       boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX themes_slug_key ON themes (slug);

-- ─────────────────────────────────────────────────────────────────────────
-- COMPOSITION  —  split out of wp_posts (AD-02)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE templates (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    theme_slug text NOT NULL,
    slug       text NOT NULL,
    area       text,                       -- template parts only
    kind       text NOT NULL CHECK (kind IN ('template','part')),
    content    text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX templates_unique ON templates (theme_slug, kind, slug);

CREATE TABLE patterns (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug       text NOT NULL,
    title      text NOT NULL,
    content    text NOT NULL DEFAULT '',
    categories text[] NOT NULL DEFAULT '{}',
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX patterns_slug_key ON patterns (slug);

-- ─────────────────────────────────────────────────────────────────────────
-- ROUTING / SYNDICATION
-- ─────────────────────────────────────────────────────────────────────────
-- Replaces postmeta '_wp_old_slug' / '_wp_old_date'.
CREATE TABLE redirects (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_path   text   NOT NULL,
    post_id     bigint REFERENCES posts(id) ON DELETE CASCADE,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX redirects_from_key ON redirects (from_path);

-- The oEmbed cache was a POST TYPE in the legacy. It is a cache.
CREATE TABLE embed_caches (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    url_digest text  NOT NULL,
    payload    jsonb NOT NULL,
    fetched_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX embed_caches_url_key ON embed_caches (url_digest);
CREATE INDEX embed_caches_expiry ON embed_caches (expires_at);
```

## Relationships

| Source | Target | Cardinality | Integrity | Notes |
|---|---|---|---|---|
| `posts.author_id` | `users.id` | N:1 | FK `ON DELETE SET NULL` | legacy `post_author`, no FK |
| `posts.parent_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | legacy `post_parent`, no FK |
| `posts.featured_asset_id` | `assets.id` | N:1 | FK `ON DELETE SET NULL` | was postmeta `_thumbnail_id` |
| `revisions.post_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | was `post_parent` on a revision row |
| `post_attributes.post_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | legacy `postmeta`, no FK |
| `post_status_transitions.post_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | new |
| `terms.taxonomy_id` | `taxonomies.id` | N:1 | FK `ON DELETE CASCADE` | was `term_taxonomy.taxonomy` varchar |
| `terms.parent_id` | `terms.id` | N:1 | FK `ON DELETE CASCADE` | was `term_taxonomy.parent`, no FK |
| `term_assignments.term_id` | `terms.id` | N:1 | FK `ON DELETE CASCADE` | legacy `term_relationships`, no FK |
| `term_assignments.classifiable_*` | `posts` / `assets` | N:1 | ⚠️ **polymorphic — no FK possible** | see *Constraints* |
| `comments.post_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | legacy `comment_post_ID`, no FK |
| `comments.parent_id` | `comments.id` | N:1 | FK `ON DELETE CASCADE` | legacy `comment_parent`, no FK |
| `comments.user_id` | `users.id` | N:1 | FK `ON DELETE SET NULL` | legacy `user_id`, no FK |
| `moderation_verdicts.comment_id` | `comments.id` | N:1 | FK `ON DELETE CASCADE` | new |
| `assets.attached_to_id` | `posts.id` | N:1 | FK `ON DELETE SET NULL` | was `post_parent` on an attachment |
| `asset_variants.asset_id` | `assets.id` | N:1 | FK `ON DELETE CASCADE` | was `_wp_attachment_metadata['sizes']` |
| `role_assignments.user_id` | `users.id` | N:1 | FK `ON DELETE CASCADE` | was a serialized usermeta map |
| `sessions.user_id` | `users.id` | N:1 | FK `ON DELETE CASCADE` | was a serialized usermeta value |
| `menu_items.menu_id` | `menus.id` | N:1 | FK `ON DELETE CASCADE` | 🔑 **deletes the `_menu_item_orphaned` tombstone mechanism** (BR-MENU-05) |
| `menu_items.parent_id` | `menu_items.id` | N:1 | FK `ON DELETE CASCADE` | was `_menu_item_menu_item_parent` postmeta |
| `redirects.post_id` | `posts.id` | N:1 | FK `ON DELETE CASCADE` | was `_wp_old_slug` postmeta |

**18 of the 21 relationships above are foreign keys that the legacy does not have** — F-DD-01
records that *no foreign keys exist anywhere* in WordPress, which is the direct cause of orphan
tombstones, ancestor cycle guards and duplicate-detection loops throughout the codebase.

## Constraints

- **Uniqueness**:
  - `users`: `login`, `email`, `nicename` — all three are non-unique `KEY`s in the legacy.
  - `posts`: `(type, coalesce(parent_id,0), slug)` where slug is present — replaces
    `wp_unique_post_slug()`'s query-per-attempt loop (F-POST-03).
  - `terms`: `(taxonomy_id, coalesce(parent_id,0), slug)` — ⚠️ **the constraint the legacy is
    missing.** F-DD-05 records that `term_taxonomy`'s unique key covers `(term_id, taxonomy)` and
    therefore does not cover the case `wp_insert_term()` actually guards, which is why it must
    insert, re-query and delete its own rows (F-TAX-02).
  - `post_attributes`: `(post_id, key)` — makes `$unique` real; the legacy passes it as an argument
    with nothing behind it (F-META-02).
  - `settings`: `name`; `assets`: `slug`; `redirects`: `from_path`; `embed_caches`: `url_digest`;
    `role_assignments`: `(user_id, role, site_id)`; `asset_variants`: `(asset_id, size_name)`;
    `templates`: `(theme_slug, kind, slug)`.
- **Referential integrity**: **enabled everywhere it can be.** One exception:
  `term_assignments.classifiable_*` is polymorphic across `posts` and `assets`, so no FK is
  expressible. Mitigation: a `CHECK` restricting `classifiable_type` to the two known values, plus a
  nightly orphan-audit job. This is the legacy's `object_id` — which was polymorphic across posts,
  links *and* users — narrowed to two, not eliminated. Recorded as a knowing compromise.
- **Check constraints**: trash state all-or-nothing; published/scheduled implies `published_at`;
  slug ≤ 200 bytes; a menu item targets exactly one of internal-record or custom URL; a term is not
  its own parent; `data_requests.kind` ∈ {export, erasure}.
- **Partitioning / sharding**: none at launch. Under Wave 5 multisite, isolation is **schema-based**
  (one PostgreSQL schema per site via `search_path`, `BR-MS-01`), not partitioning. ⚠️ Note this
  gives a real boundary where the legacy had none: F-DD-10 records that multisite isolation is purely
  the table-name prefix, so a query with a hardcoded prefix silently crosses sites.
- **Critical indexes**:
  - `posts_type_status_published`, `posts_type_status_author` — the legacy's two composite indexes,
    preserved because F-DD-04 records the schema was tuned for exactly these clauses.
  - `posts_attributes_gin` — ⚠️ **the index the legacy never has.** F-DD-02: `meta_value` is
    unindexed in all six meta tables, making `meta_query` the dominant slow-query source (TD-07).
  - `settings_autoload` (partial) — the legacy's one place the schema optimizes for the cache layer
    (F-DD-09), kept and narrowed to a partial index.
  - `comments_author_email` — full, not the legacy's 10-character prefix (F-DD-06).
  - No index is prefix-truncated. F-DD-08 records that `$max_index_length` truncation makes
    `meta_key`, `post_name` and term `slug`/`name` indexes cover only the first 191 bytes under
    utf8mb4, so long keys sharing a prefix collide into one index entry. PostgreSQL has no such
    limit at these sizes.

## Considerations specific to the target paradigm

The target paradigm is **classic OO / Active Record**, so the paradigm-specific structures this
section usually carries are deliberately **absent**:

- **No outbox table.** There is no message bus to be consistent with.
- **No event store, no projections.** State is current-state rows; `post_status_transitions` is an
  audit trail, not a source of truth to replay.
- **No immutability requirement.** Rows are updated in place, as Active Record expects.

What the paradigm *does* impose on this schema:

- **Constraints carry invariants that were PHP loops.** This is implication 3 made concrete: three
  business rules become zero rules and one migration (AD-05).
- **Counter caches replace read-time computation.** `terms.count` and `posts.comment_count` are
  maintained on write. The legacy pads term counts at read time by joining `term_relationships` to
  `posts` filtered on `post_status='publish'` — on **every render** (F-TAX-05, BR-TAX-11).
- **Enums, not free-text status columns.** `post_status` and `comment_status` are PostgreSQL enum
  types. `BR-CMT-12` was resolved this way at the Curator pause.
- **Timestamps are `timestamptz` in UTC, single-column** (AD-07). ⚠️ `NULL` replaces
  `0000-00-00 00:00:00`, and `NULLS LAST` is stated explicitly in every index and ordering that
  touches a nullable timestamp — MySQL and PostgreSQL disagree on the default (RISK-007).

## Legacy origin

| New table | Legacy origin | Transformation |
|---|---|---|
| `posts` | `wp_posts` (content types only) | **split** — 11 machinery types removed (AD-02); date pairs collapsed (AD-07); core meta promoted to columns (AD-03); `guid` → UUID (deviation) |
| `revisions` | `wp_posts` where `post_type='revision'` | split out |
| `post_attributes` | `wp_postmeta` | narrowed to residual keys; `longtext` → `jsonb`; unique index added |
| `post_status_transitions` | *(none)* | new — replaces the `transition_post_status` action |
| `taxonomies` | `wp_term_taxonomy.taxonomy` column | promoted from a varchar to a table |
| `terms` | `wp_terms` **+** `wp_term_taxonomy` | **merged**; ⚠️ behavioural change — see `target_domain_model.md` note 2 |
| `term_assignments` | `wp_term_relationships` | renamed; surrogate PK; FK added |
| `comments` | `wp_comments` | date pair collapsed; `comment_approved` varchar → enum; FKs added |
| `moderation_verdicts` | *(none)* | new — the reason moves off the comment |
| `comment_rate_limits` | *(none)* | new — deviation `BR-CMT-04` |
| `assets` | `wp_posts` where `post_type='attachment'` + 4 postmeta keys | split out and materialized |
| `asset_variants` | `_wp_attachment_metadata['sizes']` | serialized array → rows |
| `users` | `wp_users` | non-unique keys → unique indexes; `citext` for login/email |
| `role_assignments` | `wp_usermeta['{prefix}capabilities']` | serialized map → rows |
| `sessions` | `wp_usermeta['session_tokens']` | serialized array → rows |
| `data_requests` | `wp_posts` where `post_type='user_request'` | split out |
| `settings` | `wp_options` | **narrowed** — routing, cron and transients leave (AD-06); `longtext` → `jsonb`; `autoload` varchar → boolean |
| `menus` / `menu_items` | `wp_terms` (nav_menu) + `wp_posts` (nav_menu_item) + 9 postmeta keys | **merged and materialized** |
| `templates` / `patterns` | `wp_posts` where type ∈ {`wp_template`,`wp_template_part`,`wp_block`} | split out |
| `redirects` | `wp_postmeta['_wp_old_slug'/'_wp_old_date']` | promoted to a table |
| `embed_caches` | `wp_posts` where `post_type='oembed_cache'` | split out; a cache stops being content |
| *(dropped)* | `wp_links` | ⚠️ **removed** — Link Manager UI hidden since 3.5; F-DD-07 calls it dead weight in every install |
| *(dropped)* | `wp_registration_log` | removed — declared and created but rarely read (F-DD-07) |
| *(dropped)* | `wp_termmeta`, `wp_commentmeta`, `wp_usermeta` | removed as tables — promoted to columns or `jsonb` on their owners (AD-03) |
| *(dropped)* | `wp_blogs`, `wp_blogmeta`, `wp_site`, `wp_sitemeta`, `wp_signups` | deferred to Wave 5 tenancy; the schema-per-site model replaces most of them (`BR-MS-01`) |

## Notes

**Two things in this schema are load-bearing and easy to undo by accident:**

1. **`posts.slug` is nullable, and that is the point.** `BR-MIGRATE-032` says slugs are not generated
   for draft, pending or auto-draft. Making the column `NOT NULL DEFAULT ''` — the legacy's
   representation — would silently collide every draft against every other draft in the unique
   index. The partial index `WHERE slug IS NOT NULL` is what makes the constraint expressible at all.

2. **The two composite indexes are kept deliberately, not by inertia.** F-DD-04 records that
   `wp_posts` carries six indexes "chosen precisely for `WP_Query`'s default clauses — the schema is
   tuned for exactly one query builder". `Retrieval` is that query builder's successor, so the tuning
   still applies. If `Retrieval`'s scopes diverge from those clauses, these indexes should be
   re-derived from the actual queries rather than inherited on faith.

**One open item for the coding agent**: `settings.value` is `jsonb`, but roughly 130 option names are
seeded at install (`data-dictionary.md` §4.1) and several are structural — `permalink_structure`,
`page_on_front`, `posts_per_page`, the comment-moderation set. A typed settings registry with
per-key validation is the natural next step and is **not** specified here; it is a design choice
about how far to push configuration into code, and it belongs to whoever writes `Configuration`.
