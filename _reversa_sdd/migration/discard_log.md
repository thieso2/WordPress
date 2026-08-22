---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: discard_log
producedBy: curator
hash: "sha256:0b04b2c56e5520a9ad3061cd1fbf0e4e4939af3ab9df8804489d0b954d07baa7"
---

# Discard Log

> Produced by the **Curator**. Every rule that does **not** carry forward, with the reason.
> 65 discarded of 431 analysed: 54 paradigm-related, 11 out of scope.

**The test applied** (from the Curator's decision policy): a rule is discarded when the new
paradigm absorbs the use case *by construction*, without needing the old manual mechanism. A rule
is **not** discarded merely for being "another way of doing it" when the business rule still exists.
Where a discarded mechanism protected a real invariant, the invariant is named and carried forward.

---

## 1. Paradigm-related discards (54)

Traceable to `paradigm_decision.md`, option 1 (adopt the Rails idiom), derived appetite
`transformational`.

### Hook mechanism (15) - implication 2

**`BR-BOOT-06`** - pluggable.php loads after all plugins, enabling plugins to redefine wp_mail(), wp_authenticate() and other pluggable functions.

- Source: `wp-settings.php:612`
- paradigm-related: **yes**
- How the new paradigm absorbs it: pluggable.php loading after plugins existed so functions could be redefined. Rails resolves collaborators by class, not by definition order.

**`BR-HOOK-01`** - Default priority is 10; lower runs earlier. A null priority becomes 0.

- Source: `wp-includes/class-wp-hook.php:91`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-02`** - Default accepted_args is 1. Callbacks receive a sliced argument list when they accept fewer args than passed.

- Source: `wp-includes/class-wp-hook.php:328`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-03`** - A callback whose unique id cannot be built is silently dropped with no error or notice.

- Source: `wp-includes/class-wp-hook.php:96`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-04`** - Within one priority, callbacks run in registration order.

- Source: `wp-includes/class-wp-hook.php:345`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-05`** - Re-registering the same callback at the same priority overwrites rather than duplicating.

- Source: `wp-includes/class-wp-hook.php:103`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-06`** - Registering a hook while it is executing re-sorts the live iteration; equal-priority additions still run in that pass, lower-priority ones do not.

- Source: `wp-includes/class-wp-hook.php:130`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-07`** - In an action every callback receives the original arguments; in a filter each receives the previous callback's return value as args[0].

- Source: `wp-includes/class-wp-hook.php:349`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-08`** - A filter callback that returns nothing returns null, which becomes the filtered value.

- Source: `wp-includes/class-wp-hook.php:353`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-09`** - register_uninstall_hook() rejects instance-method callbacks because the callback is serialized into the uninstall_plugins option.

- Source: `wp-includes/plugin.php:934`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-10`** - Callbacks registered on the 'all' hook fire before every hook dispatch in the system.

- Source: `wp-includes/plugin.php:182`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-11`** - apply_filters_deprecated() emits its notice only when a callback is actually registered.

- Source: `wp-includes/plugin.php:723`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-HOOK-12`** - has_filter() returns the integer priority when a specific callback is found; falsy comparison against priority 0 is a known trap.

- Source: `wp-includes/class-wp-hook.php:252`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The hook registry is not reproduced. Behaviour is expressed directly in models, services and policies, so there is no priority, no argument slicing and no callback identity to specify.

**`BR-DB-05`** - Every executed SQL string passes through apply_filters('query', $query).

- Source: `wp-includes/class-wpdb.php:2219`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The 'query' filter let any plugin rewrite every SQL statement. ActiveRecord composes queries in Ruby; there is no interception point and none is wanted.

**`BR-OPT-07`** - An explicit on/off autoload value is never overridden by the automatic heuristic; only auto, auto-on and auto-off are re-evaluated.

- Source: `wp-includes/option.php:891`
- paradigm-related: **yes**
- How the new paradigm absorbs it: pre_option/default_option filter interplay disappears with the filter system; a setting is read from one place.

### Compensating transactions (6) - implication 3

**`BR-DB-07`** - On MySQL error 2006 (server gone away) the query is retried exactly once after reconnection.

- Source: `wp-includes/class-wpdb.php:2260`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Retrying once on MySQL error 2006 compensates for a dropped connection. The Rails connection pool with reaping handles reconnection.

**`BR-DB-08`** - check_connection() retries 5 times with 1-second sleeps, blocking the request for up to ~5 seconds.

- Source: `wp-includes/class-wpdb.php:2135`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Five one-second reconnect sleeps inside a web request. The connection pool has a checkout timeout instead.

**`BR-DB-11`** - A failed INSERT/REPLACE resets insert_id to 0 so a stale id cannot leak.

- Source: `wp-includes/class-wpdb.php:2280`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Resetting insert_id after a failed INSERT guards against a stale id leaking. ActiveRecord returns the record or raises; there is no shared last-insert-id to leak.

**`BR-DB-14`** - If the connection is lost after template_redirect has fired, wpdb fails silently rather than emitting an error page into a partial response.

- Source: `wp-includes/class-wpdb.php:2151`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Failing silently after template_redirect avoids emitting an error page into a partial response. Rails buffers the response and renders error pages through the exception app.

**`BR-META-03`** - $unique = true is enforced by SELECT COUNT(*) before insert with no unique index, so concurrent writers can both succeed.

- Source: `wp-includes/meta.php:65`
- paradigm-related: **yes**
- How the new paradigm absorbs it: SELECT COUNT(*) then INSERT with no unique index is a check-then-act race. A partial unique index on (object, meta_key) where unique enforces it atomically.

**`BR-TAX-05`** - Duplicate detection happens after insert; only a row with a lower term_id counts as the duplicate, and the newly inserted rows are then deleted.

- Source: `wp-includes/taxonomy.php:2645`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Insert-then-detect-duplicate compensates for having no transactions. In Rails a unique index on (slug, parent_id, taxonomy) plus a transaction makes the duplicate impossible, so no compensating delete is needed.

### Hand-rolled data layer (9) - implication 3

**`BR-DB-01`** - prepare() adds its own quoting; callers must not wrap %s in quotes. Pre-existing quotes are stripped.

- Source: `wp-includes/class-wpdb.php:1497`
- paradigm-related: **yes**
- How the new paradigm absorbs it: prepare() adding its own quoting is a hand-rolled interpolator. ActiveRecord binds parameters; callers never quote.

**`BR-DB-02`** - An argument used as both %i identifier and %s value is a hard error: _doing_it_wrong() and prepare() returns null.

- Source: `wp-includes/class-wpdb.php:1643`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The %i identifier versus %s value conflict is specific to that interpolator.

**`BR-DB-03`** - Placeholder/argument count mismatch triggers _doing_it_wrong(); too few args returns empty string which query() refuses.

- Source: `wp-includes/class-wpdb.php:1657`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Placeholder and argument count mismatch is specific to that interpolator.

**`BR-DB-04`** - %f is always rewritten to %F so float formatting is locale-independent.

- Source: `wp-includes/class-wpdb.php:1533`
- paradigm-related: **yes**
- How the new paradigm absorbs it: %f rewritten to %F for locale-independence is specific to that interpolator.

**`BR-DB-06`** - A write containing text the target column's charset cannot represent is rejected outright, never truncated.

- Source: `wp-includes/class-wpdb.php:2230`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Rejecting writes whose text the column charset cannot represent compensates for strict mode being off. PostgreSQL rejects invalid encoding itself.

**`BR-DB-09`** - Charset utf8 is always upgraded to utf8mb4; utf8_general_ci becomes utf8mb4_unicode_ci, upgraded further to utf8mb4_unicode_520_ci when supported.

- Source: `wp-includes/class-wpdb.php:886`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Charset upgrade from utf8 to utf8mb4 is a MySQL migration artifact. PostgreSQL databases are UTF-8 throughout.

**`BR-DB-10`** - Six strict SQL modes (NO_ZERO_DATE, ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, STRICT_ALL_TABLES, TRADITIONAL, ANSI) are stripped on connect.

- Source: `wp-includes/class-wpdb.php:644`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Six strict SQL modes were stripped so MySQL would accept WordPress's data. PostgreSQL is strict by default and the target model has no zero dates to accommodate.

**`BR-DB-12`** - $where in update()/delete() supports only equality joined with AND; no OR and no operators.

- Source: `wp-includes/class-wpdb.php:2680`
- paradigm-related: **yes**
- How the new paradigm absorbs it: update() and delete() supporting only equality joined by AND is a limitation of the hand-rolled layer, not a business rule. ActiveRecord has a full query interface.

**`BR-POST-04`** - Drafts store post_date_gmt as 0000-00-00 00:00:00, requiring MySQL NO_ZERO_DATE mode to be off.

- Source: `wp-includes/post.php:4780`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Drafts store 0000-00-00 00:00:00 because the column is NOT NULL. In PostgreSQL published_at is nullable and a draft simply has NULL.

### Slashing convention (2) - implication 6

**`BR-META-02`** - Meta keys and values are wp_unslash()ed on write because input arrives slashed.

- Source: `wp-includes/meta.php:57`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Meta keys and values are unslashed on write because wp_magic_quotes re-slashed all input at boot. Rails params are never slashed, so the unslash step disappears entirely.

**`BR-FMT-05`** - All superglobal input is slashed by wp_magic_quotes(); wp_unslash() is required before use.

- Source: `wp-includes/load.php:1285`
- paradigm-related: **yes**
- How the new paradigm absorbs it: All superglobal input arriving slashed, with wp_unslash required before use, is a PHP magic-quotes legacy. Rails params arrive clean.

### Boot sequence (3) - implication 1

**`BR-BOOT-01`** - PHP < 7.4 or missing mysqli (with no db.php drop-in) aborts the request before any WordPress code runs.

- Source: `wp-includes/load.php:157`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The PHP and mysqli version gate is a runtime check for shared hosting. Ruby version and adapter requirements are handled by the Gemfile and bundler.

**`BR-BOOT-03`** - SHORTINIT truthy stops the boot immediately after the object cache and default filters.

- Source: `wp-settings.php:169`
- paradigm-related: **yes**
- How the new paradigm absorbs it: SHORTINIT exists because every request loads the whole codebase. Rails autoloads on demand, so there is nothing to short-circuit.

**`BR-BOOT-07`** - Initial post types and taxonomies are registered twice: at wp-settings.php:566 and again on the init hook.

- Source: `wp-settings.php:564`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Registering post types and taxonomies twice is an artifact of the boot ordering. In Rails they are class definitions loaded once.

### Caching and options storage (10) - brief Q8

**`BR-OPT-06`** - An option whose serialized value exceeds 150000 bytes (filterable via wp_max_autoloaded_option_size) is automatically set to auto-off.

- Source: `wp-includes/option.php:1353`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Demoting options over 150000 bytes out of autoload mitigates loading everything on every request. Rails loads settings on demand.

**`BR-OPT-08`** - A transient without an expiration is autoloaded; with an expiration it is not.

- Source: `wp-includes/option.php:1525`
- paradigm-related: **yes**
- How the new paradigm absorbs it: A transient without an expiry being autoloaded couples the autoload flag to expiry semantics. Rails.cache separates the two.

**`BR-OPT-09`** - Transient expiry is lazy: enforced on read, plus a scheduled delete_expired_transients() sweep.

- Source: `wp-includes/option.php:1447`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Lazy transient expiry on read compensates for having no TTL support. Rails.cache expires entries itself.

**`BR-OPT-10`** - With a persistent object cache present, transients never touch the database.

- Source: `wp-includes/option.php:1436`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Transients bypassing the database when a persistent cache exists is the dual-backend behaviour being removed. There is one cache.

**`BR-OPT-11`** - A transient whose value row exists but whose timeout row is missing is deleted and recreated.

- Source: `wp-includes/option.php:1528`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Repairing a transient whose timeout row vanished is specific to the two-row storage model.

**`BR-OPT-14`** - The wp_autoload_values_to_autoload filter can only remove values from the valid set, never add new ones (array_intersect guard).

- Source: `wp-includes/option.php:3259`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The array_intersect guard on the autoload filter protects a filterable enum. With no filters the enum is fixed.

**`BR-CACHE-01`** - The default object cache is request-scoped only; nothing survives the response.

- Source: `wp-includes/class-wp-object-cache.php:33`
- paradigm-related: **yes**
- How the new paradigm absorbs it: A request-scoped default cache is the artifact being replaced. Rails.cache with a real store persists across requests by construction.

**`BR-CACHE-04`** - A cached null is a genuine hit, distinguished from a miss by the array_key_exists() arm of _exists().

- Source: `wp-includes/class-wp-object-cache.php:178`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Distinguishing a cached null from a miss via array_key_exists compensates for PHP isset semantics. Rails.cache#fetch with a block has no such ambiguity.

**`BR-CACHE-06`** - $expire is accepted and ignored by the default implementation.

- Source: `wp-includes/class-wp-object-cache.php:301`
- paradigm-related: **yes**
- How the new paradigm absorbs it: $expire being accepted and ignored is a property of the non-persistent default. Rails.cache honours expires_in.

**`BR-CACHE-10`** - get() sets the by-reference $found parameter, the only reliable way to distinguish a cached false from a miss.

- Source: `wp-includes/class-wp-object-cache.php:362`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The by-reference $found parameter exists for the same reason. Rails.cache#exist? and #fetch cover it.

### Cron mechanism (9) - brief Q7

**`BR-CRON-01`** - All scheduled events live in the single autoloaded 'cron' option.

- Source: `wp-includes/cron.php:1261`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Storing the whole schedule in one autoloaded option is the artifact. A job backend owns its own queue.

**`BR-CRON-02`** - Event identity is timestamp, then hook, then md5(serialize(args)).

- Source: `wp-includes/cron.php:132`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Event identity as md5(serialize(args)) is specific to that option structure. A job backend has job ids.

**`BR-CRON-06`** - Cron cannot spawn while DOING_CRON is defined or the doing_wp_cron query arg is present.

- Source: `wp-includes/cron.php:903`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The DOING_CRON guard prevents recursive spawn from a loopback request. A scheduler invokes the worker directly.

**`BR-CRON-07`** - A doing_cron lock more than 10 minutes in the future is discarded as invalid, self-healing against clock skew.

- Source: `wp-includes/cron.php:917`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Discarding a lock more than ten minutes in the future self-heals a transient-based lock. A job backend has real locking.

**`BR-CRON-08`** - WP_CRON_LOCK_TIMEOUT (60 seconds) prevents spawning more than once a minute regardless of how many events are due.

- Source: `wp-includes/cron.php:921`
- paradigm-related: **yes**
- How the new paradigm absorbs it: WP_CRON_LOCK_TIMEOUT doubling as a rate limit compensates for traffic-driven spawning.

**`BR-CRON-09`** - Spawning aborts when no events are ready or the earliest ready timestamp is in the future.

- Source: `wp-includes/cron.php:927`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Aborting when nothing is ready is specific to spawn-on-request.

**`BR-CRON-10`** - ALTERNATE_WP_CRON runs cron via a visitor redirect and requires a GET request that is neither AJAX nor XML-RPC.

- Source: `wp-includes/cron.php:936`
- paradigm-related: **yes**
- How the new paradigm absorbs it: ALTERNATE_WP_CRON redirects the visitor's browser to run cron. Not applicable with a real scheduler.

**`BR-CRON-11`** - The default path issues a non-blocking loopback HTTP request to wp-cron.php.

- Source: `wp-includes/cron.php:960`
- paradigm-related: **yes**
- How the new paradigm absorbs it: The non-blocking loopback request to wp-cron.php is the mechanism being replaced.

**`BR-CRON-13`** - _get_cron_array() migrates pre-version-2 cron arrays on read via _upgrade_cron_array().

- Source: `wp-includes/cron.php:1268`
- paradigm-related: **yes**
- How the new paradigm absorbs it: Migrating pre-version-2 cron arrays on read is a data-format artifact.

---

## 2. Out-of-scope discards (11)

Excluded by `migration_brief.md`, section "Declared scope".

### `deprecated-compat` (6 rules)

Module 'deprecated-compat' is excluded by migration_brief.md. Nothing external depends on WordPress APIs, so there is no compatibility layer to build.

- **`BR-DEP-01`** - Deprecated functions remain fully functional; only a debug-time notice is added.  (`wp-includes/deprecated.php`)
- **`BR-DEP-02`** - Deprecation notices appear only when WP_DEBUG is enabled, so they are invisible in production.  (`wp-includes/functions.php`)
- **`BR-DEP-03`** - Deprecated hooks still fire, warning only if a callback is actually registered.  (`wp-includes/plugin.php:723`)
- **`BR-DEP-04`** - Old file paths are preserved as aliases (class.wp-scripts.php alongside class-wp-scripts.php) because plugins require them directly.  (`wp-includes/class.wp-scripts.php`)
- **`BR-DEP-05`** - compat.php and php-compat/ polyfill newer PHP functions so core can use modern syntax while supporting PHP 7.4.  (`wp-includes/compat.php`)
- **`BR-DEP-06`** - Nothing in the deprecated layer has a removal date.  (`wp-includes/deprecated.php`)

### `xmlrpc` (5 rules)

Module 'xmlrpc' is excluded by migration_brief.md. Zero dependents; removing it breaks nothing structurally.

- **`BR-XR-01`** - XML-RPC is enabled by default; disabling requires add_filter('xmlrpc_enabled', '__return_false').  (`wp-includes/class-wp-xmlrpc-server.php:195`)
- **`BR-XR-02`** - The enable_xmlrpc option is deprecated since 3.5.0; its pre_option and option filters are consulted only for back-compat.  (`wp-includes/class-wp-xmlrpc-server.php:191`)
- **`BR-XR-03`** - Every method authenticates independently with a username and password passed as XML-RPC parameters; there is no session, token or nonce.  (`wp-includes/class-wp-xmlrpc-server.php`)
- **`BR-XR-04`** - 78 methods span the wp, metaWeblog, mt, blogger, pingback and demo families.  (`wp-includes/class-wp-xmlrpc-server.php`)
- **`BR-XR-05`** - pingback.ping fetches a caller-supplied URL server-side, unauthenticated.  (`wp-includes/class-wp-xmlrpc-server.php`)

---

## 3. Invariants preserved from discarded mechanisms

Discarding a mechanism must not discard what it protected. These invariants move into the target
as database constraints or model validations, and the Designer owns them.

| Discarded rule | Mechanism dropped | Invariant that must survive | Target expression |
|----------------|-------------------|-----------------------------|-------------------|
| `BR-TAX-05` | insert, detect duplicate, delete own rows | A term is unique per slug, parent and taxonomy | `UNIQUE (taxonomy, parent_id, slug)` plus a transaction |
| `BR-META-03` | `SELECT COUNT(*)` then `INSERT` | A meta key is unique per object when uniqueness is requested | partial unique index on `(object_type, object_id, key)` |
| `BR-DB-06` | rejecting writes the column charset cannot hold | Text must be storable without silent truncation | PostgreSQL rejects invalid encoding natively |
| `BR-POST-04` | `0000-00-00 00:00:00` for drafts | A draft has no publication instant | nullable `published_at` |
| `BR-DB-11` | resetting `insert_id` after a failed insert | A failed write yields no usable id | `create!` raises; nothing to leak |
| `BR-CRON-01`, `BR-CRON-02` | schedule in one autoloaded option, identity by `md5(serialize(args))` | Scheduled work runs once, at the right time, and is deduplicated | a job backend with real job ids and uniqueness |
| `BR-OPT-09`, `BR-OPT-10` | lazy transient expiry, dual backend | Cached values expire | `Rails.cache` with `expires_in` |
| `BR-CAP-14` | `$super_admins` global outranking the database | Superuser status is authoritative and auditable | a stored role, no configuration override |
| `BR-MS-02` | `switch_to_blog` mutating globals | Tenant isolation for every query | scoping or `Current.tenant`, decided by `BR-HUMAN-019` |

