---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: target_business_rules
producedBy: curator
hash: "sha256:2dad2e05d56524ae6346676cba23b157cfcd7abfe4f048f05829b2800c259165"
---

# Target Business Rules

> Produced by the **Curator**, then updated after the human-decision pause on 2026-08-21.
> All 431 rules Reversa extracted from WordPress `7.2-alpha-63330`, classified against
> `migration_brief.md` and `paradigm_decision.md`.
> Required reading before this: `paradigm_decision.md`.

## Summary

| Disposition | Count | Share |
|-------------|------:|------:|
| MIGRATE | 363 | 84.2% |
| DISCARD | 68 | 15.8% |
| HUMAN DECISION | 0 | 0%% |
| **Total analysed** | **431** | 100%% |

All 22 human-decision items were resolved at the post-Curator pause. Of the 68 discarded,
**54 are paradigm-related**, **11 are out of declared scope**, and **3 are resolved rulings**
(`BR-OPT-04`, `BR-CAP-14`, `BR-MS-02`).

> ⚠️ Corrected 2026-08-22 by the coding agent (deferred item D-1); the prose read "1".
> 54 + 11 + 3 = 68, reconciling with `discard_log.md` § 4. The rule *set* was already
> correct — 363 MIGRATE ids are enumerated below and all three rulings were already
> handled downstream. Only the tally was wrong.

---

## ⚠️ Owner overrides recorded at the human-decision pause

**Nine rules carry forward against an earlier recorded decision.** They are listed here rather
than buried in the tables, because a reviewer must be able to see them at a glance.

### Override 1: authorization defaults reproduced (reverses question Q4)

Question Q4, answered during the Reversa extraction, set **fail closed everywhere** as the house
style, and `paradigm_decision.md` carries a contract row instructing the Designer not to reproduce
the legacy defaults. At this pause the owner ruled the opposite, and reaffirmed it when the
conflict was put to them directly.

| Rule | Legacy behaviour reproduced in the target |
|------|------------------------------------------|
| `BR-REST-05` | A route registered with **no policy is public**. |
| `BR-CAP-05` | A policy method emitting **no capabilities means allowed**. |
| `BR-ADM-07` | An endpoint registered as nopriv-equivalent is **public with no gate at all**. |

**Consequence, stated plainly.** Finding `F-DOM-02`, which the confidence report called the
highest-value observation in the analysis for security work, is knowingly carried into a
greenfield system. The rebuild will ship with five different authorization defaults across its
surfaces, exactly as WordPress does. The Inspector must write parity tests asserting the
**permissive** behaviour, because that is now the specification.

### Override 2: KSES regex reproduced (reverses question Q5)

Question Q5 decided KSES should be migrated off regular expressions. At this pause the owner ruled
that the regex implementation be reproduced faithfully.

| Rule | Reproduced |
|------|-----------|
| `BR-KSES-01` | Allowlist filtering implemented with regular expressions. |
| `BR-KSES-04` | Four-step scheme normalisation: decode entities, strip whitespace, remove null bytes, lowercase. |
| `BR-KSES-05` | Colon recognised as `:`, `&#58;`, `&#x3a;` and `&colon;`. |
| `BR-KSES-06` | Truncated colon entities repaired before splitting. |
| `BR-KSES-07` | `feed:` prefix re-examined recursively, capped at two levels. |
| `BR-FMT-04` | `wpautop` and `wptexturize` as regex transformation over rendered HTML. |

**Consequence.** Finding `F-KSES-05` is knowingly carried forward: the security-critical HTML
allowlist parses HTML with regular expressions in the new system too. The upside is that the four
normalisation steps, which encode two decades of XSS bypass attempts, survive verbatim rather than
being reinterpreted.

---

## Deliberate deviations from legacy behaviour (6)

These **do not** reproduce the legacy. Each fixes a behaviour the extraction identified as a
defect. The Inspector records each as a deviation rather than a parity failure.

| Rule | Legacy | Target |
|------|--------|--------|
| `BR-CMT-04` | Flood verdict defaults to false; **no rate limit is enforced** | Real rate limiting |
| `BR-CMT-10` | Spam versus trash depends on `EMPTY_TRASH_DAYS` | Decoupled; disallowed comments are marked spam |
| `BR-CMT-08` | Keywords match as unquoted **substrings** across six fields | Word-boundary matching |
| `BR-OPT-04` | `update_option` returns false for *unchanged*, indistinguishable from failure | ActiveRecord save semantics distinguish them |
| `BR-POST-10` | `guid` seeded from the permalink, never updated | UUID generated at creation |
| `BR-HTTP-01` | SSRF validation **opt-in by function name** | Validated by default, with an explicit unsafe escape hatch |

> ⚠️ `BR-HTTP-01` and `BR-CAP-14` were **not** covered by the reproduce-legacy-defaults ruling,
> which addressed the five authorization defaults specifically. The Curator's recommendation was
> applied to both. If the owner intended them included in the override, they are the two items to
> revisit.

---

## 1. MIGRATE (363)

> ⚠️ **Read with `paradigm_decision.md` implication 2.** Each rule states WordPress's *unfiltered
> default*. The target has no filter system, so each becomes the permanent behaviour.

### `bootstrap-and-load` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-001` | `BR-BOOT-02` | A .maintenance file whose $upgrading timestamp is older than 600 seconds is ignored, so a crashed upgrade cannot lock the site permanently. | `wp-includes/load.php:437` |  |
| `BR-MIGRATE-002` | `BR-BOOT-04` | An unrecognized WP_ENVIRONMENT_TYPE silently becomes 'production'. | `wp-includes/load.php:250` |  |
| `BR-MIGRATE-003` | `BR-BOOT-05` | Plugins recorded as fatal in paused-extension storage are skipped on subsequent requests. | `wp-includes/load.php:1061` |  |
| `BR-MIGRATE-004` | `BR-BOOT-08` | The child theme's functions.php loads before the parent theme's. | `wp-settings.php:740` |  |
| `BR-MIGRATE-005` | `BR-BOOT-09` | An uninstalled site is redirected to wp-admin/install.php before most of core loads. | `wp-includes/load.php:942` |  |
| `BR-MIGRATE-006` | `BR-BOOT-10` | The fatal error handler is registered before the database connects, so DB failures remain recoverable. | `wp-settings.php:69` |  |

### `database-wpdb` (1)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-007` | `BR-DB-13` | Blog-scoped table names are recomputed by set_blog_id(); global and ms-global tables are not. | `wp-includes/class-wpdb.php:1043` |  |

### `options-and-transients` (7)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-008` | `BR-OPT-01` | Option names are trimmed; an empty name returns false. | `wp-includes/option.php:80` |  |
| `BR-MIGRATE-009` | `BR-OPT-02` | blacklist_keys and comment_whitelist are transparently remapped to disallowed_keys / comment_previously_approved with a deprecation notice. | `wp-includes/option.php:86` |  |
| `BR-MIGRATE-010` | `BR-OPT-03` | 'alloptions' and 'notoptions' are protected names; writing to them calls wp_die(). | `wp-includes/option.php:565` |  |
| `BR-MIGRATE-011` | `BR-OPT-05` | Updating an option that does not exist delegates to add_option(). | `wp-includes/option.php:882` |  |
| `BR-MIGRATE-012` | `BR-OPT-12` | get_option('home') returning an empty string falls back to get_option('siteurl'). | `wp-includes/option.php:150` |  |
| `BR-MIGRATE-013` | `BR-OPT-13` | Object values are cloned before storage so later caller mutation cannot alter what was saved. | `wp-includes/option.php:871` |  |
| `BR-MIGRATE-014` | `BR-OPT-15` | Every option write passes through sanitize_option($option, $value). | `wp-includes/option.php:874` |  |

### `cache-and-object-cache` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-015` | `BR-CACHE-02` | Under multisite, keys in non-global groups are prefixed with '{blog_id}:'; global groups are not. | `wp-includes/class-wp-object-cache.php:311` |  |
| `BR-MIGRATE-016` | `BR-CACHE-03` | An invalid key (not int, not non-empty string) fails with _doing_it_wrong() and returns false. | `wp-includes/class-wp-object-cache.php:140` |  |
| `BR-MIGRATE-017` | `BR-CACHE-05` | Objects are cloned on set() and again on get(), two clones per round trip. | `wp-includes/class-wp-object-cache.php:314` |  |
| `BR-MIGRATE-018` | `BR-CACHE-07` | add() respects wp_suspend_cache_addition(); set() does not. | `wp-includes/class-wp-object-cache.php:199` |  |
| `BR-MIGRATE-019` | `BR-CACHE-08` | An empty $group becomes 'default'. | `wp-includes/class-wp-object-cache.php:306` |  |
| `BR-MIGRATE-020` | `BR-CACHE-09` | counts, plugins, theme_json and themes are declared non-persistent groups. | `wp-includes/load.php:928` |  |

### `metadata` (8)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-021` | `BR-META-01` | $meta_type resolves to '{type}meta' on $wpdb; an unknown type returns false and aborts the operation. | `wp-includes/meta.php:1290` |  |
| `BR-MIGRATE-022` | `BR-META-04` | A meta key is protected when its key, stripped of every character that is not printable ASCII or a Unicode letter, begins with underscore. | `wp-includes/meta.php:1312` |  |
| `BR-MIGRATE-023` | `BR-META-05` | All meta for an object is cached as a single entry; reading one key loads them all. | `wp-includes/meta.php:645` |  |
| `BR-MIGRATE-024` | `BR-META-06` | $single = true returns values[0]; false returns the full array. | `wp-includes/meta.php:601` |  |
| `BR-MIGRATE-025` | `BR-META-07` | Every meta value passes sanitize_meta(), dispatching to the subtype-specific filter when one is registered. | `wp-includes/meta.php:59` |  |
| `BR-MIGRATE-026` | `BR-META-08` | Values are maybe_serialize()d on write and maybe_unserialize()d on read, so arrays and objects round-trip transparently. | `wp-includes/meta.php:74` |  |
| `BR-MIGRATE-027` | `BR-META-09` | The add_/get_/update_/delete_{meta_type}_metadata filters returning non-null fully replace the operation. | `wp-includes/meta.php:61` |  |
| `BR-MIGRATE-028` | `BR-META-10` | update_meta_cache() orders by meta_id ASC (umeta_id for users), preserving insertion order for multi-value meta. | `wp-includes/meta.php:1177` |  |

### `posts-and-post-types` (11)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-029` | `BR-POST-01` | A publish status with a post_date_gmt at least 60 seconds in the future is silently converted to 'future'. | `wp-includes/post.php:4800` |  |
| `BR-MIGRATE-030` | `BR-POST-02` | A future status whose date is less than 60 seconds away is silently converted to 'publish'. | `wp-includes/post.php:4804` |  |
| `BR-MIGRATE-031` | `BR-POST-03` | An attachment must have status inherit, private, trash or auto-draft. | `wp-includes/post.php:4705` |  |
| `BR-MIGRATE-032` | `BR-POST-05` | Slugs are not generated or uniqued for draft, pending or auto-draft statuses. | `wp-includes/post.php:5562` |  |
| `BR-MIGRATE-033` | `BR-POST-06` | Attachment slugs must be unique across all post types; hierarchical types are unique within (type, parent); flat types within the type. | `wp-includes/post.php:5576` |  |
| `BR-MIGRATE-034` | `BR-POST-07` | Slugs matching a registered feed name, 'embed', a pagination number, or a date-archive segment are forced to take a numeric suffix. | `wp-includes/post.php:5582` |  |
| `BR-MIGRATE-035` | `BR-POST-08` | Slugs are truncated to 200 bytes inclusive of the -N suffix via _truncate_post_slug(). | `wp-includes/post.php:5586` |  |
| `BR-MIGRATE-036` | `BR-POST-09` | Every status change fires transition_post_status and the dynamic {old}_to_{new} action. | `wp-includes/post.php:5913` |  |
| `BR-MIGRATE-037` | `BR-POST-10` | The guid column is populated from get_permalink() on first publish and never updated afterwards. | `wp-includes/post.php:8158` | DEVIATION |
| `BR-MIGRATE-038` | `BR-POST-11` | Any status transition unconditionally clears the publish_future_post cron event, guarding against a future->draft bounce. | `wp-includes/post.php:8177` |  |
| `BR-MIGRATE-039` | `BR-POST-12` | nav_menu_item and user_request bypass slug uniqueness entirely. | `wp-includes/post.php:5563` |  |

### `query-and-loop` (12)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-040` | `BR-QUERY-01` | The do_parse_request filter returning false skips request parsing, the main query and 404 handling entirely. | `wp-includes/class-wp.php:138` |  |
| `BR-MIGRATE-041` | `BR-QUERY-02` | Private query vars such as post_status, post__in and fields can never be set from the URL. This is the boundary that keeps drafts private. | `wp-includes/class-wp.php:28` |  |
| `BR-MIGRATE-042` | `BR-QUERY-03` | Admin, robots.txt and favicon requests never 404. | `wp-includes/class-wp.php:735` |  |
| `BR-MIGRATE-043` | `BR-QUERY-04` | ?page=N on a post whose content lacks <!--nextpage--> is a 404. | `wp-includes/class-wp.php:749` |  |
| `BR-MIGRATE-044` | `BR-QUERY-05` | The posts page never honors <!--nextpage--> pagination; any page var there produces a 404. | `wp-includes/class-wp.php:755` |  |
| `BR-MIGRATE-045` | `BR-QUERY-06` | An empty author, term or post-type archive returns 200 if the queried object exists; an empty paged archive always 404s. | `wp-includes/class-wp.php:762` |  |
| `BR-MIGRATE-046` | `BR-QUERY-07` | The split-query optimization applies only when no filter altered the SQL and either a persistent object cache exists or posts_per_page < 500. | `wp-includes/class-wp-query.php:3383` |  |
| `BR-MIGRATE-047` | `BR-QUERY-08` | found_posts is computed with SELECT FOUND_ROWS() only when a LIMIT is present and no_found_rows is false. | `wp-includes/class-wp-query.php:3697` |  |
| `BR-MIGRATE-048` | `BR-QUERY-09` | Search terms that are single a-z or dash characters, or locale stopwords, are dropped. Quoted terms keep their surrounding spaces to signal exact-match intent. | `wp-includes/class-wp-query.php:1567` |  |
| `BR-MIGRATE-049` | `BR-QUERY-10` | Post, meta, term and author caches are primed once, on the first the_post() of a loop. | `wp-includes/class-wp-query.php:3770` |  |
| `BR-MIGRATE-050` | `BR-QUERY-11` | have_posts() fires loop_end and rewinds automatically at the end of a loop; an empty result fires loop_no_results. | `wp-includes/class-wp-query.php:3846` |  |
| `BR-MIGRATE-051` | `BR-QUERY-12` | Every SQL clause is filterable twice (early and as *_request) and posts_pre_query can replace the query altogether. | `wp-includes/class-wp-query.php:1900` |  |

### `taxonomy-and-terms` (13)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-052` | `BR-TAX-01` | Objects are linked by term_taxonomy_id, never term_id. One term_id may serve several taxonomies. | `schema` |  |
| `BR-MIGRATE-053` | `BR-TAX-02` | The term name is validated for emptiness twice: before and after sanitization. | `wp-includes/taxonomy.php:2470` |  |
| `BR-MIGRATE-054` | `BR-TAX-03` | A null description is coerced to empty string to avoid a database error. | `wp-includes/taxonomy.php:2487` |  |
| `BR-MIGRATE-055` | `BR-TAX-04` | A non-existent parent term id rejects the insert with the missing_parent error. | `wp-includes/taxonomy.php:2481` |  |
| `BR-MIGRATE-056` | `BR-TAX-06` | In wp_set_object_terms(), a non-existent term passed as a string is created; passed as an integer it is silently skipped. | `wp-includes/taxonomy.php:2884` |  |
| `BR-MIGRATE-057` | `BR-TAX-07` | Assigning a term already related to the object is a no-op, checked with one query per term. | `wp-includes/taxonomy.php:2893` |  |
| `BR-MIGRATE-058` | `BR-TAX-08` | With $append = false, terms present before but absent from the new list are removed. | `wp-includes/taxonomy.php:2864` |  |
| `BR-MIGRATE-059` | `BR-TAX-09` | Term counts can be deferred with wp_defer_term_counting(true) and accumulate in a static keyed by taxonomy. | `wp-includes/taxonomy.php:3589` |  |
| `BR-MIGRATE-060` | `BR-TAX-10` | A taxonomy's update_count_callback overrides the default counting query. | `wp-includes/taxonomy.php:3616` |  |
| `BR-MIGRATE-061` | `BR-TAX-11` | Hierarchical count padding counts only objects with post_status = 'publish'. | `wp-includes/taxonomy.php:4106` |  |
| `BR-MIGRATE-062` | `BR-TAX-12` | Count padding deduplicates by object id, so a post in both a child and its parent is counted once for the parent. | `wp-includes/taxonomy.php:4108` |  |
| `BR-MIGRATE-063` | `BR-TAX-13` | Ancestor walking has an explicit cycle guard against corrupted parent chains. | `wp-includes/taxonomy.php:4122` |  |
| `BR-MIGRATE-064` | `BR-TAX-14` | alias_of groups terms via term_group, allocated as MAX(term_group) + 1. | `wp-includes/taxonomy.php:2506` |  |

### `comments` (14)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-065` | `BR-CMT-01` | A duplicate (same post, parent, author, email and content, excluding trashed comments) is rejected with HTTP 409. | `wp-includes/comment.php:754` |  |
| `BR-MIGRATE-066` | `BR-CMT-02` | Users with manage_options or moderate_comments are never flood-throttled. | `wp-includes/comment.php:917` |  |
| `BR-MIGRATE-067` | `BR-CMT-03` | Flood detection looks back one hour, matched by user_id when logged in, otherwise by IP, or by email in either case. | `wp-includes/comment.php:922` |  |
| `BR-MIGRATE-068` | `BR-CMT-04` | The flood verdict defaults to false; core supplies only the query and the comment_flood_filter hook. No rate limit is enforced by core itself. | `wp-includes/comment.php:938` | DEVIATION |
| `BR-MIGRATE-069` | `BR-CMT-05` | The post author and any user with moderate_comments are auto-approved without any moderation check. | `wp-includes/comment.php:1362` |  |
| `BR-MIGRATE-070` | `BR-CMT-06` | comment_moderation = '1' holds every comment and short-circuits all other moderation rules. | `wp-includes/comment.php:46` |  |
| `BR-MIGRATE-071` | `BR-CMT-07` | A comment containing comment_max_links or more '<a ... href' occurrences is held. | `wp-includes/comment.php:52` |  |
| `BR-MIGRATE-072` | `BR-CMT-08` | Each moderation_keys entry is matched case-insensitively with Unicode as a substring against author, email, URL, content, IP and user agent. | `wp-includes/comment.php:60` | DEVIATION |
| `BR-MIGRATE-073` | `BR-CMT-09` | comment_previously_approved = '1' requires a prior approved comment, matched by user_id for registered users or by author name AND email otherwise. | `wp-includes/comment.php:91` |  |
| `BR-MIGRATE-074` | `BR-CMT-10` | A disallowed-list match overrides any approval and sets the status to 'trash' if EMPTY_TRASH_DAYS is truthy, otherwise 'spam'. | `wp-includes/comment.php:1398` | DEVIATION |
| `BR-MIGRATE-075` | `BR-CMT-11` | Over-length comment fields return WP_Error with HTTP status 200, not 400. | `wp-includes/comment.php:1321` |  |
| `BR-MIGRATE-076` | `BR-CMT-12` | comment_approved is a varchar with values 1, 0, spam, trash, post-trashed. | `schema` |  |
| `BR-MIGRATE-077` | `BR-CMT-13` | Comment counts can be deferred and flushed in one pass, using the same static-accumulator pattern as term counts. | `wp-includes/comment.php:3071` |  |
| `BR-MIGRATE-078` | `BR-CMT-14` | The final approval value always passes through the pre_comment_approved filter, so a plugin can override the entire pipeline's verdict. | `wp-includes/comment.php:1409` |  |

### `media-and-attachments` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-079` | `BR-MEDIA-01` | WordPress never upscales: a requested size larger than the original returns false and the original is used. | `wp-includes/media.php:568` |  |
| `BR-MIGRATE-080` | `BR-MEDIA-02` | Cropping uses max() of the width/height ratios, producing a cover-fit source rectangle rather than a letterboxed one. | `wp-includes/media.php:590` |  |
| `BR-MIGRATE-081` | `BR-MEDIA-03` | An invalid $crop value falls back to ['center','center']. | `wp-includes/media.php:594` |  |
| `BR-MIGRATE-082` | `BR-MEDIA-04` | Aspect-ratio matching tolerates a 1-pixel difference because integer rounding during resize makes exact matches rare. | `wp-includes/media.php:747` |  |
| `BR-MIGRATE-083` | `BR-MEDIA-05` | srcset candidates wider than 2048px (max_srcset_image_width filter) are excluded unless the candidate is the src image itself. | `wp-includes/media.php:1505` |  |
| `BR-MIGRATE-084` | `BR-MEDIA-06` | srcset candidates must live in the same directory as the source file. | `wp-includes/media.php:1490` |  |
| `BR-MIGRATE-085` | `BR-MEDIA-07` | The image editor is chosen per operation by testing availability, mime-type support and required methods, preferring Imagick then GD. | `wp-includes/media.php:4430` |  |
| `BR-MIGRATE-086` | `BR-MEDIA-08` | The editor choice is memoized under an md5 of (args, implementations) in the global image_editor cache group. | `wp-includes/media.php:4439` |  |
| `BR-MIGRATE-087` | `BR-MEDIA-09` | Responsive attributes (srcset, sizes, loading, decoding, fetchpriority) are injected at render time into output HTML, not stored in post content. | `wp-includes/media.php:1987` |  |
| `BR-MIGRATE-088` | `BR-MEDIA-10` | Every upload generates one file per registered subsize. | `wp-includes/media.php:930` |  |

### `embeds-oembed` (8)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-089` | `BR-EMB-01` | A URL alone on its own line is auto-embedded; a URL inline in a paragraph is not. | `wp-includes/class-wp-embed.php` |  |
| `BR-MIGRATE-090` | `BR-EMB-02` | 59 built-in providers are matched by regex before any network request is made. | `wp-includes/class-wp-oembed.php:54` |  |
| `BR-MIGRATE-091` | `BR-EMB-03` | Discovery only runs when no registered provider matches and discovery is enabled for the request. | `wp-includes/class-wp-oembed.php:320` |  |
| `BR-MIGRATE-092` | `BR-EMB-04` | JSON is attempted first, XML second. | `wp-includes/class-wp-oembed.php:586` |  |
| `BR-MIGRATE-093` | `BR-EMB-05` | XML parsing disables external entity loading (XXE defense). | `wp-includes/class-wp-oembed.php:672` |  |
| `BR-MIGRATE-094` | `BR-EMB-06` | Embed results are cached as oembed_cache post-type rows keyed by URL plus args. | `wp-includes/class-wp-embed.php` |  |
| `BR-MIGRATE-095` | `BR-EMB-07` | Newlines are stripped from provider HTML so wpautop() cannot insert paragraph tags inside it. | `wp-includes/class-wp-oembed.php:812` |  |
| `BR-MIGRATE-096` | `BR-EMB-08` | photo-type responses are rendered by WordPress as an img tag; rich and video responses inject the provider's own HTML. | `wp-includes/class-wp-oembed.php:750` |  |

### `users-roles-capabilities` (14)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-097` | `BR-CAP-01` | has_cap() requires ALL mapped capabilities, not any one of them. | `wp-includes/class-wp-user.php:808` |  |
| `BR-MIGRATE-098` | `BR-CAP-02` | do_not_allow is unset from the user's capability set before evaluation, so a requirement for it can never be satisfied. It is the deny primitive. | `wp-includes/class-wp-user.php:806` |  |
| `BR-MIGRATE-099` | `BR-CAP-03` | A multisite super admin passes every check unless the mapped capability list contains do_not_allow. | `wp-includes/class-wp-user.php:795` |  |
| `BR-MIGRATE-100` | `BR-CAP-04` | Every user implicitly holds the 'exist' capability. | `wp-includes/class-wp-user.php:805` |  |
| `BR-MIGRATE-101` | `BR-CAP-05` | map_meta_cap() returning an empty array means the action is allowed with no requirements, because array_all over an empty array is true. | `wp-includes/capabilities.php:70` | ⚠️ override Q4 |
| `BR-MIGRATE-102` | `BR-CAP-06` | A user with ID < 1 cannot edit any user, not even themselves. | `wp-includes/capabilities.php:63` |  |
| `BR-MIGRATE-103` | `BR-CAP-07` | Any user may edit themselves via edit_user with their own id (empty caps emitted). | `wp-includes/capabilities.php:68` |  |
| `BR-MIGRATE-104` | `BR-CAP-08` | In multisite, editing a super admin requires being a super admin, and any user edit requires manage_network_users. | `wp-includes/capabilities.php:71` |  |
| `BR-MIGRATE-105` | `BR-CAP-09` | A user may not remove themselves in multisite unless they are a super admin. | `wp-includes/capabilities.php:49` |  |
| `BR-MIGRATE-106` | `BR-CAP-10` | delete_post / delete_page without a post argument emits _doing_it_wrong() and returns do_not_allow: fail closed. | `wp-includes/capabilities.php:78` |  |
| `BR-MIGRATE-107` | `BR-CAP-11` | Numeric capabilities are legacy user levels, translated to capabilities with a deprecation notice. | `wp-includes/class-wp-user.php:788` |  |
| `BR-MIGRATE-108` | `BR-CAP-12` | install_languages, resume_plugin, resume_theme and view_site_health_checks are granted dynamically by user_has_cap callbacks, never stored. | `wp-includes/capabilities.php:1309` |  |
| `BR-MIGRATE-109` | `BR-CAP-13` | Roles are stored per user in wp_usermeta under {prefix}capabilities, so role membership is per site in multisite. | `wp-includes/class-wp-user.php` |  |
| `BR-MIGRATE-110` | `BR-CAP-15` | Contributors can neither publish posts nor upload files. | `wp-admin/includes/schema.php` |  |

### `authentication-and-sessions` (16)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-111` | `BR-AUTH-01` | 35 security functions in pluggable.php can be wholly replaced by any plugin defining them first, because pluggable.php loads after all plugins. | `wp-includes/pluggable.php` |  |
| `BR-MIGRATE-112` | `BR-AUTH-02` | Passwords longer than 4096 bytes hash to '*', which never verifies. A DoS guard expressed as a permanently failing hash. | `wp-includes/pluggable.php:2761` |  |
| `BR-MIGRATE-113` | `BR-AUTH-03` | bcrypt passwords are pre-hashed with HMAC-SHA-384 using key 'wp-sha384', base64-encoded, and prefixed with $wp to survive bcrypt's 72-byte truncation. | `wp-includes/pluggable.php:2771` |  |
| `BR-MIGRATE-114` | `BR-AUTH-04` | Three password hash formats coexist: $P$ (phpass), $2y$ (vanilla bcrypt), $wp$2y$ (WordPress pre-hashed bcrypt). | `wp-includes/pluggable.php:2843` |  |
| `BR-MIGRATE-115` | `BR-AUTH-05` | The auth cookie HMAC key includes a 4-character fragment of the password hash, so changing the password invalidates every outstanding cookie. | `wp-includes/pluggable.php:960` |  |
| `BR-MIGRATE-116` | `BR-AUTH-06` | The password fragment is substr(hash, 8, 4) for $P$ and $2y$ hashes and substr(hash, -4) otherwise. | `wp-includes/pluggable.php:961` |  |
| `BR-MIGRATE-117` | `BR-AUTH-07` | Cookie HMACs are compared with hash_equals() for constant-time comparison. | `wp-includes/pluggable.php:830` |  |
| `BR-MIGRATE-118` | `BR-AUTH-08` | AJAX and POST requests receive a one-hour cookie-expiry grace period. | `wp-includes/pluggable.php:806` |  |
| `BR-MIGRATE-119` | `BR-AUTH-09` | Cookie lifetime is 14 days with remember-me and 2 days without; in remember-me mode the browser cookie outlives the HMAC expiration by 12 hours. | `wp-includes/pluggable.php:1073` |  |
| `BR-MIGRATE-120` | `BR-AUTH-10` | The logged_in cookie is only marked secure when the auth cookie is secure AND the home URL uses HTTPS. | `wp-includes/pluggable.php:1085` |  |
| `BR-MIGRATE-121` | `BR-AUTH-11` | Cookie validation order is expiry, then user existence, then HMAC, then session token. | `wp-includes/pluggable.php:800` |  |
| `BR-MIGRATE-122` | `BR-AUTH-12` | Nonce lifetime is 24 hours (nonce_life filter), ticking every 12 hours; both the current and previous tick are accepted. | `wp-includes/pluggable.php:2444` |  |
| `BR-MIGRATE-123` | `BR-AUTH-13` | wp_verify_nonce() returns 1 (0-12h old), 2 (12-24h old) or false, never true. | `wp-includes/pluggable.php:2493` |  |
| `BR-MIGRATE-124` | `BR-AUTH-14` | A nonce is 10 hex characters taken from offset -12 of a wp_hash() result, roughly 40 bits. | `wp-includes/pluggable.php:2492` |  |
| `BR-MIGRATE-125` | `BR-AUTH-15` | Nonces bind to the session token, so logging out invalidates outstanding nonces. | `wp-includes/pluggable.php:2491` |  |
| `BR-MIGRATE-126` | `BR-AUTH-16` | Logged-out users all share uid 0 for nonce generation unless the nonce_user_logged_out filter supplies an identity. | `wp-includes/pluggable.php:2482` |  |

### `themes-and-templates` (14)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-127` | `BR-TPL-01` | template_redirect fires only when wp_using_themes() is true. | `wp-includes/template-loader.php:2` |  |
| `BR-MIGRATE-128` | `BR-TPL-02` | A HEAD request exits immediately after template_redirect unless the exit_on_http_head filter says otherwise. | `wp-includes/template-loader.php:5` |  |
| `BR-MIGRATE-129` | `BR-TPL-03` | robots, favicon, feed and trackback requests are handled before the hierarchy and even when themes are disabled. | `wp-includes/template-loader.php:10` |  |
| `BR-MIGRATE-130` | `BR-TPL-04` | The 17 template conditionals are evaluated in a fixed order and the first match wins; is_404 is tested second. | `wp-includes/template-loader.php:24` |  |
| `BR-MIGRATE-131` | `BR-TPL-05` | Matching is_attachment removes the prepend_attachment content filter. | `wp-includes/template-loader.php:48` |  |
| `BR-MIGRATE-132` | `BR-TPL-06` | No conditional match falls back to index.php. | `wp-includes/template-loader.php:55` |  |
| `BR-MIGRATE-133` | `BR-TPL-07` | The template type is sanitized with preg_replace to [a-z0-9-] before becoming part of a filename. | `wp-includes/template.php:24` |  |
| `BR-MIGRATE-134` | `BR-TPL-08` | Lookup order per filename is child theme, then parent theme only if a child is active, then wp-includes/theme-compat/. | `wp-includes/template.php` |  |
| `BR-MIGRATE-135` | `BR-TPL-09` | The first filename in the candidate list that exists anywhere wins, so filename specificity outranks theme proximity. | `wp-includes/template.php` |  |
| `BR-MIGRATE-136` | `BR-TPL-10` | A urldecoded template-name variant is added to the candidate list only when it differs from the raw name. | `wp-includes/template.php` |  |
| `BR-MIGRATE-137` | `BR-TPL-11` | A post's custom template slug from post meta is used only if validate_file() returns 0. | `wp-includes/template.php` |  |
| `BR-MIGRATE-138` | `BR-TPL-12` | After the template_include filter the path must resolve via realpath(), end in .php or .html, and be an existing readable file. | `wp-includes/template-loader.php:59` |  |
| `BR-MIGRATE-139` | `BR-TPL-13` | Every template type exposes a {type}_template_hierarchy filter over its candidate list. | `wp-includes/template.php:27` |  |
| `BR-MIGRATE-140` | `BR-TPL-14` | Block themes get a final override via locate_block_template(). | `wp-includes/template.php:29` |  |

### `rewrite-and-permalinks` (12)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-141` | `BR-RW-01` | rewritecode, rewritereplace and queryreplace are positionally aligned arrays; compilation substitutes by index with nothing enforcing the alignment. | `wp-includes/class-wp-rewrite.php:281` |  |
| `BR-MIGRATE-142` | `BR-RW-02` | %pagename% uses a non-greedy ([^/]+?) because pages are hierarchical; %postname% uses greedy ([^/]+); %search% uses (.+) and may contain slashes. | `wp-includes/class-wp-rewrite.php:302` |  |
| `BR-MIGRATE-143` | `BR-RW-03` | Built-in feed slugs are feed, rdf, rss, rss2 and atom. | `wp-includes/class-wp-rewrite.php:342` |  |
| `BR-MIGRATE-144` | `BR-RW-04` | pagination_base is 'page' and comments_pagination_base is 'comment-page'. | `wp-includes/class-wp-rewrite.php:105` |  |
| `BR-MIGRATE-145` | `BR-RW-05` | The full rewrite rule set is stored in the single 'rewrite_rules' option. | `wp-includes/class-wp-rewrite.php:1494` |  |
| `BR-MIGRATE-146` | `BR-RW-06` | An empty rewrite_rules option triggers immediate regeneration. | `wp-includes/class-wp-rewrite.php:1495` |  |
| `BR-MIGRATE-147` | `BR-RW-07` | Any flush_rules() call before wp_loaded is deferred to wp_loaded, so every post type and taxonomy is registered first. | `wp-includes/class-wp-rewrite.php:1876` |  |
| `BR-MIGRATE-148` | `BR-RW-08` | Deferred hard-flush requests accumulate with logical OR in a static; one hard request makes the eventual flush hard. | `wp-includes/class-wp-rewrite.php:1878` |  |
| `BR-MIGRATE-149` | `BR-RW-09` | A hard flush additionally writes .htaccess or web.config, but only when save_mod_rewrite_rules() / iis7_save_url_rewrite_rules() exist (admin only). | `wp-includes/class-wp-rewrite.php:1891` |  |
| `BR-MIGRATE-150` | `BR-RW-10` | 14 EP_* bitmasks control which URL classes an endpoint attaches to. | `wp-includes/rewrite.php` |  |
| `BR-MIGRATE-151` | `BR-RW-11` | With use_verbose_page_rules enabled (the default), one rewrite rule is generated per page. | `wp-includes/class-wp-rewrite.php:469` |  |
| `BR-MIGRATE-152` | `BR-RW-12` | Rules can be added at the top or bottom of the set via add_rule($regex, $query, $after). | `wp-includes/class-wp-rewrite.php:1684` |  |

### `script-modules-and-assets` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-153` | `BR-ASSET-01` | A handle with an unregistered dependency is dropped from output entirely. | `wp-includes/class-wp-dependencies.php:218` |  |
| `BR-MIGRATE-154` | `BR-ASSET-02` | The missing-dependency _doing_it_wrong() notice fires at most once per handle per request, tracked in a private array. | `wp-includes/class-wp-dependencies.php:220` |  |
| `BR-MIGRATE-155` | `BR-ASSET-03` | Inside recursion a resolution failure returns false and aborts that branch; at the top level it skips only that handle and continues. | `wp-includes/class-wp-dependencies.php:232` |  |
| `BR-MIGRATE-156` | `BR-ASSET-04` | set_group() only ever moves a handle to a lower group number: footer to header, never the reverse. | `wp-includes/class-wp-dependencies.php:511` |  |
| `BR-MIGRATE-157` | `BR-ASSET-05` | Group 0 is the header and group 1 the footer. | `wp-includes/class-wp-dependencies.php:88` |  |
| `BR-MIGRATE-158` | `BR-ASSET-06` | A handle already in done is never re-emitted. | `wp-includes/class-wp-dependencies.php:203` |  |
| `BR-MIGRATE-159` | `BR-ASSET-07` | A '?' suffix on a handle is stripped before resolution and re-applied to the emitted URL. | `wp-includes/class-wp-dependencies.php:199` |  |
| `BR-MIGRATE-160` | `BR-ASSET-08` | Script-module fetch priority is derived from a module's dependents via dependents_map, not from its own declaration. | `wp-includes/class-wp-script-modules.php:477` |  |
| `BR-MIGRATE-161` | `BR-ASSET-09` | Script modules emit a browser import map plus modulepreload links for static dependencies. | `wp-includes/class-wp-script-modules.php:620` |  |
| `BR-MIGRATE-162` | `BR-ASSET-10` | Both registries use the same register -> enqueue -> to_do -> done lifecycle. | `both classes` |  |

### `widgets-and-nav-menus` (11)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-163` | `BR-WIDG-01` | All instances of a widget class share one option row named widget_{id_base}, keyed by instance number. | `wp-includes/class-wp-widget.php:45` |  |
| `BR-MIGRATE-164` | `BR-WIDG-02` | A widget instance id is {id_base}-{number}. | `wp-includes/class-wp-widget.php:85` |  |
| `BR-MIGRATE-165` | `BR-WIDG-03` | Form field names are widget-{id_base}[{number}][{field}] so one submission carries every instance. | `wp-includes/class-wp-widget.php:216` |  |
| `BR-MIGRATE-166` | `BR-WIDG-04` | update() is responsible for sanitization; core does not sanitize widget input on the widget's behalf. | `wp-includes/class-wp-widget.php:131` |  |
| `BR-MIGRATE-167` | `BR-WIDG-05` | is_preview() reports whether rendering occurs inside the Customizer. | `wp-includes/class-wp-widget.php:339` |  |
| `BR-MIGRATE-168` | `BR-MENU-01` | A menu is a nav_menu taxonomy term; a menu item is a nav_menu_item post. | `wp-includes/nav-menu.php` |  |
| `BR-MIGRATE-169` | `BR-MENU-02` | Menu-item semantics live in nine _menu_item_* meta keys, not in post columns. | `wp-includes/nav-menu.php` |  |
| `BR-MIGRATE-170` | `BR-MENU-03` | Menu hierarchy uses _menu_item_menu_item_parent, not post_parent. | `wp-includes/nav-menu.php` |  |
| `BR-MIGRATE-171` | `BR-MENU-04` | Menu ordering uses the menu_order column on the post row. | `wp-includes/nav-menu.php` |  |
| `BR-MIGRATE-172` | `BR-MENU-05` | An item whose referenced object is deleted is marked _menu_item_orphaned rather than removed. | `wp-includes/nav-menu.php` |  |
| `BR-MIGRATE-173` | `BR-MENU-06` | An empty post_title falls back to the referenced object's title at render time. | `wp-includes/nav-menu.php` |  |

### `customizer` (8)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-174` | `BR-CUST-01` | Each setting declares its own capability, defaulting to edit_theme_options. Authorization is per-field, not per-screen. | `wp-includes/class-wp-customize-setting.php:57` |  |
| `BR-MIGRATE-175` | `BR-CUST-02` | A setting with theme_supports set is only registered when the theme declares that support. | `wp-includes/class-wp-customize-setting.php:65` |  |
| `BR-MIGRATE-176` | `BR-CUST-03` | transport is 'refresh' by default; 'postMessage' requires the theme to supply JS for live updates. | `wp-includes/class-wp-customize-setting.php:84` |  |
| `BR-MIGRATE-177` | `BR-CUST-04` | validate_callback rejects with WP_Error, sanitize_callback cleans, sanitize_js_callback prepares the preview value: three separate hooks. | `wp-includes/class-wp-customize-setting.php:92` |  |
| `BR-MIGRATE-178` | `BR-CUST-05` | Settings store to theme_mod (theme-scoped) or option (site-wide), selected by $type. | `wp-includes/class-wp-customize-setting.php:49` |  |
| `BR-MIGRATE-179` | `BR-CUST-06` | Unsaved Customizer state persists in a customize_changeset post identified by a UUID, making previews shareable and schedulable. | `wp-includes/class-wp-customize-manager.php:826` |  |
| `BR-MIGRATE-180` | `BR-CUST-07` | The Customizer registers its controls on wp_loaded, then fires customize_register. | `wp-includes/class-wp-customize-manager.php:918` |  |
| `BR-MIGRATE-181` | `BR-CUST-08` | Theme previewing begins at setup_theme, before the theme's own functions.php context is final. | `wp-includes/class-wp-customize-manager.php:516` |  |

### `block-editor` (12)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-182` | `BR-BLK-01` | Block boundaries are HTML comments, so block content renders correctly without any parsing. | `wp-includes/class-wp-block-parser.php:248` |  |
| `BR-MIGRATE-183` | `BR-BLK-02` | An omitted namespace in a block delimiter defaults to core/. | `wp-includes/class-wp-block-parser.php:248` |  |
| `BR-MIGRATE-184` | `BR-BLK-03` | Void blocks (ending /-->) carry no inner content and are emitted without a stack push. | `wp-includes/class-wp-block-parser.php:113` |  |
| `BR-MIGRATE-185` | `BR-BLK-04` | Text outside any delimiter becomes a core/freeform block. | `wp-includes/class-wp-block-parser.php:311` |  |
| `BR-MIGRATE-186` | `BR-BLK-05` | Unclosed blocks at end of document are closed implicitly; the parser never fails. | `wp-includes/class-wp-block-parser.php:99` |  |
| `BR-MIGRATE-187` | `BR-BLK-06` | innerContent mixes strings (literal HTML) and nulls (inner-block placeholders). | `wp-includes/blocks.php:1798` |  |
| `BR-MIGRATE-188` | `BR-BLK-07` | Serialization substitutes each null in innerContent with the next serialized inner block, in order. | `wp-includes/blocks.php:1799` |  |
| `BR-MIGRATE-189` | `BR-BLK-08` | Block metadata resolves from a pre-built manifest first, then block.json on disk, then $args. | `wp-includes/blocks.php:527` |  |
| `BR-MIGRATE-190` | `BR-BLK-09` | Blocks under wp-includes/ are treated as core and skip the file_exists() check. | `wp-includes/blocks.php:525` |  |
| `BR-MIGRATE-191` | `BR-BLK-10` | Core blocks get implicit wp-block-{name} style and wp-block-{name}-editor editorStyle handles, plus wp-block-{name}-theme when wp-block-styles is supported. | `wp-includes/blocks.php:543` |  |
| `BR-MIGRATE-192` | `BR-BLK-11` | Registration returns false when neither the metadata nor $args supplies a name. | `wp-includes/blocks.php:536` |  |
| `BR-MIGRATE-193` | `BR-BLK-12` | A block with a render_callback is dynamic; its output is computed at render time rather than read from stored content. | `wp-includes/blocks.php:2410` |  |

### `blocks-library` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-194` | `BR-BLIB-01` | Every core block is defined by a block.json file. | `wp-includes/blocks/<block>/block.json` |  |
| `BR-MIGRATE-195` | `BR-BLIB-02` | All core block.json contents are inlined into blocks-json.php as a single 206 KB PHP array, collapsing 115 file reads into one require. | `wp-includes/blocks/blocks-json.php` |  |
| `BR-MIGRATE-196` | `BR-BLIB-03` | Blocks with a PHP file are dynamic; those without render from saved markup. | `wp-includes/blocks/` |  |
| `BR-MIGRATE-197` | `BR-BLIB-04` | The 'missing' block preserves the original content when a block type is not registered. It is a STATIC block — wp-includes/blocks/missing/ contains only block.json; the placeholder is rendered client-side by the editor, not by PHP. | `wp-includes/blocks/missing/block.json` |  |
| `BR-MIGRATE-198` | `BR-BLIB-05` | The 'freeform' block wraps pre-block classic editor content. It is a STATIC block — wp-includes/blocks/freeform/ contains block.json and editor CSS only. The wrapping happens in blocks.php, not in a render callback. | `wp-includes/blocks.php:1293` |  |
| `BR-MIGRATE-199` | `BR-BLIB-06` | Post-context blocks (post-title, post-content, etc.) read from the current query context rather than from attributes. | `wp-includes/blocks/post-title.php (30 post-* blocks)` |  |

### `block-supports` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-200` | `BR-BSUP-01` | Supports apply only to blocks with a registered block type; unregistered blocks receive nothing. | `wp-includes/class-wp-block-supports.php:120` |  |
| `BR-MIGRATE-201` | `BR-BSUP-02` | Attributes contributed by multiple supports are space-concatenated, with the first writer taking the slot and later ones appending. | `wp-includes/class-wp-block-supports.php:148` |  |
| `BR-MIGRATE-202` | `BR-BSUP-03` | Non-scalar values and booleans are skipped entirely; the explicit is_bool() check prevents true stringifying to '1' in markup. | `wp-includes/class-wp-block-supports.php:143` |  |
| `BR-MIGRATE-203` | `BR-BSUP-04` | A support without an apply callback contributes nothing at render time, though it may still register attributes. | `wp-includes/class-wp-block-supports.php:131` |  |
| `BR-MIGRATE-204` | `BR-BSUP-05` | Attributes pass through prepare_attributes_for_render() so schema defaults are applied before any support sees them. | `wp-includes/class-wp-block-supports.php:126` |  |
| `BR-MIGRATE-205` | `BR-BSUP-06` | The block currently being rendered is tracked in the public static $block_to_render. | `wp-includes/class-wp-block-supports.php:43` |  |

### `global-styles-theme-json` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-206` | `BR-GS-01` | The four origins merge strictly in order default, blocks, theme, custom; later origins override earlier ones. | `wp-includes/class-wp-theme-json-resolver.php:644` |  |
| `BR-MIGRATE-207` | `BR-GS-02` | get_merged_data($origin) stops the cascade at the named origin, enabling 'what would the theme alone produce?' queries. | `wp-includes/class-wp-theme-json-resolver.php:650` |  |
| `BR-MIGRATE-208` | `BR-GS-03` | User global styles are stored as one wp_global_styles post per theme, created on first access. | `wp-includes/class-wp-theme-json-resolver.php:478` |  |
| `BR-MIGRATE-209` | `BR-GS-04` | The user global-styles post id is memoized in a static for the request. | `wp-includes/class-wp-theme-json-resolver.php` |  |
| `BR-MIGRATE-210` | `BR-GS-05` | PROTECTED_PROPERTIES cannot be overridden by the user origin. | `wp-includes/class-wp-theme-json.php:371` |  |
| `BR-MIGRATE-211` | `BR-GS-06` | The root CSS custom-property selector is :root and the root block selector is body. | `wp-includes/class-wp-theme-json.php:47` |  |
| `BR-MIGRATE-212` | `BR-GS-07` | Presets generate both CSS custom properties and utility classes per PRESETS_METADATA. | `wp-includes/class-wp-theme-json.php:132` |  |
| `BR-MIGRATE-213` | `BR-GS-08` | Viewport breakpoints are validated and normalized to pixels before becoming media queries. | `wp-includes/class-wp-theme-json.php:765` |  |
| `BR-MIGRATE-214` | `BR-GS-09` | Styleable elements are link, heading, h1 through h6, button, caption and cite. | `wp-includes/class-wp-theme-json.php:868` |  |
| `BR-MIGRATE-215` | `BR-GS-10` | WP_Theme_JSON_Schema migrates older theme.json versions forward at load time. | `wp-includes/class-wp-theme-json-schema.php` |  |

### `style-engine` (4)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-216` | `BR-SE-01` | Declarations are sanitized when added, not when rendered. | `wp-includes/style-engine/class-wp-style-engine-css-declarations.php` |  |
| `BR-MIGRATE-217` | `BR-SE-02` | Multiple named rule stores can coexist and are rendered independently. | `wp-includes/style-engine/class-wp-style-engine-css-rules-store.php` |  |
| `BR-MIGRATE-218` | `BR-SE-03` | The processor deduplicates and combines rules before output. | `wp-includes/style-engine/class-wp-style-engine-processor.php` |  |
| `BR-MIGRATE-219` | `BR-SE-04` | WP_Style_Engine exposes both class names and inline styles for the same style object. | `wp-includes/style-engine/class-wp-style-engine.php` |  |

### `html-api` (7)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-220` | `BR-HTML-01` | WP_HTML_Tag_Processor never constructs a tree; modifications are byte-level and applied on get_updated_html(). | `wp-includes/html-api/class-wp-html-tag-processor.php:4913` |  |
| `BR-MIGRATE-221` | `BR-HTML-02` | Scanning is forward-only; set_bookmark() and seek() are the only way to revisit a position. | `wp-includes/html-api/class-wp-html-tag-processor.php:1360` |  |
| `BR-MIGRATE-222` | `BR-HTML-03` | get_attribute_names_with_prefix() enables attribute discovery by prefix, which the Interactivity API depends on. | `wp-includes/html-api/class-wp-html-tag-processor.php:2971` |  |
| `BR-MIGRATE-223` | `BR-HTML-04` | WP_HTML_Processor implements HTML5 tree construction including the stack of open elements and the list of active formatting elements. | `wp-includes/html-api/class-wp-html-processor.php` |  |
| `BR-MIGRATE-224` | `BR-HTML-05` | Fragment parsing requires a context element, defaulting to <body>. | `wp-includes/html-api/class-wp-html-processor.php:300` |  |
| `BR-MIGRATE-225` | `BR-HTML-06` | Unsupported constructs raise WP_HTML_Unsupported_Exception rather than producing incorrect output. | `wp-includes/html-api/class-wp-html-unsupported-exception.php` |  |
| `BR-MIGRATE-226` | `BR-HTML-07` | get_breadcrumbs() and matches_breadcrumbs() provide ancestor querying without a DOM or XPath. | `wp-includes/html-api/class-wp-html-processor.php:1202` |  |

### `interactivity-api` (7)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-227` | `BR-INT-01` | State and config are namespaced per store and serialized into the page for client hydration. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:166` |  |
| `BR-MIGRATE-228` | `BR-INT-02` | Directives are processed server-side so the initial HTML already reflects state. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:462` |  |
| `BR-MIGRATE-229` | `BR-INT-03` | Each directive handler is invoked on both entering and leaving an element, enabling correct context push and pop around nested elements. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:1020` |  |
| `BR-MIGRATE-230` | `BR-INT-04` | A directive value may be namespace::path; without a namespace it resolves against the enclosing data-wp-interactive. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:893` |  |
| `BR-MIGRATE-231` | `BR-INT-05` | Kebab-case attribute suffixes are converted to camelCase state keys. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:997` |  |
| `BR-MIGRATE-232` | `BR-INT-06` | Setting one style property via data-wp-style preserves all other inline styles on the element. | `wp-includes/interactivity-api/class-wp-interactivity-api.php:1354` |  |
| `BR-MIGRATE-233` | `BR-INT-07` | References support a ! negation prefix, resolved in evaluate(). | `wp-includes/interactivity-api/class-wp-interactivity-api.php:663` |  |

### `rest-api` (11)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-234` | `BR-REST-01` | rest_pre_dispatch returning non-empty bypasses routing, validation, permissions and the callback entirely. | `wp-includes/rest-api/class-wp-rest-server.php:1064` |  |
| `BR-MIGRATE-235` | `BR-REST-02` | Validation via has_valid_params() runs before sanitization via sanitize_params(); a failure in either skips the callback. | `wp-includes/rest-api/class-wp-rest-server.php:1091` |  |
| `BR-MIGRATE-236` | `BR-REST-03` | A non-callable handler yields rest_invalid_handler with HTTP 500. | `wp-includes/rest-api/class-wp-rest-server.php:1083` |  |
| `BR-MIGRATE-237` | `BR-REST-04` | A permission_callback returning false OR null denies the request; forgetting to return is a denial. | `wp-includes/rest-api/class-wp-rest-server.php:1256` |  |
| `BR-MIGRATE-238` | `BR-REST-05` | A route with no permission_callback skips the permission check entirely and is fully public. | `wp-includes/rest-api/class-wp-rest-server.php:1258` | ⚠️ override Q4 |
| `BR-MIGRATE-239` | `BR-REST-06` | The denial status is 401 for anonymous requests and 403 for authenticated ones, via rest_authorization_required_code(). | `wp-includes/rest-api/class-wp-rest-server.php:1261` |  |
| `BR-MIGRATE-240` | `BR-REST-07` | register_rest_route() called before rest_api_init emits _doing_it_wrong() and the route is not registered. | `wp-includes/rest-api.php:138` |  |
| `BR-MIGRATE-241` | `BR-REST-08` | A missing permission_callback emits _doing_it_wrong() recommending __return_true, but this is a notice and the route still serves. | `wp-includes/rest-api.php:127` |  |
| `BR-MIGRATE-242` | `BR-REST-09` | rest_dispatch_request returning non-null replaces the callback's execution. | `wp-includes/rest-api/class-wp-rest-server.php:1266` |  |
| `BR-MIGRATE-243` | `BR-REST-10` | $dispatching_requests is a stack, so nested internal dispatches are tracked correctly. | `wp-includes/rest-api/class-wp-rest-server.php:1063` |  |
| `BR-MIGRATE-244` | `BR-REST-11` | register_route() merges with an existing route unless $override is true. | `wp-includes/rest-api/class-wp-rest-server.php:898` |  |

### `http-api` (13)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-245` | `BR-HTTP-01` | Only wp_safe_remote_* validates the URL; wp_remote_* does not. | `wp-includes/http.php:81` | DEVIATION |
| `BR-MIGRATE-246` | `BR-HTTP-02` | Only http and https schemes are accepted. | `wp-includes/http.php:564` |  |
| `BR-MIGRATE-247` | `BR-HTTP-03` | If wp_kses_bad_protocol() changes the URL in any way it is rejected rather than corrected: sanitization used as detection. | `wp-includes/http.php:565` |  |
| `BR-MIGRATE-248` | `BR-HTTP-04` | URLs containing userinfo (user:pass@host) are rejected outright. | `wp-includes/http.php:573` |  |
| `BR-MIGRATE-249` | `BR-HTTP-05` | Hosts containing : # ? [ or ] are rejected, which excludes IPv6 literal addresses entirely. | `wp-includes/http.php:576` |  |
| `BR-MIGRATE-250` | `BR-HTTP-06` | Requests to the site's own host bypass all IP-range checks so loopback cron and REST self-requests work. | `wp-includes/http.php:580` |  |
| `BR-MIGRATE-251` | `BR-HTTP-07` | A hostname whose gethostbyname() returns the input unchanged (resolution failure) is rejected. | `wp-includes/http.php:588` |  |
| `BR-MIGRATE-252` | `BR-HTTP-08` | 13 IPv4 ranges are blocked, including 169.254.0.0/16 which the inline comment names as cloud metadata. | `wp-includes/http.php:594` |  |
| `BR-MIGRATE-253` | `BR-HTTP-09` | A blocked host can be permitted via the http_request_host_is_external filter, which defaults to false. | `wp-includes/http.php:610` |  |
| `BR-MIGRATE-254` | `BR-HTTP-10` | With an explicit port only 80, 443 and 8080 are allowed, filterable via http_allowed_safe_ports. | `wp-includes/http.php:620` |  |
| `BR-MIGRATE-255` | `BR-HTTP-11` | A URL with no explicit port passes the port check unconditionally. | `wp-includes/http.php:616` |  |
| `BR-MIGRATE-256` | `BR-HTTP-12` | Transport is chosen per request between cURL and streams based on capability requirements. | `wp-includes/class-wp-http.php:547` |  |
| `BR-MIGRATE-257` | `BR-HTTP-13` | WP_HTTP_BLOCK_EXTERNAL with WP_ACCESSIBLE_HOSTS provides a site-wide egress allowlist. | `wp-includes/class-wp-http.php:895` |  |

### `feeds` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-258` | `BR-FEED-01` | Feed requests are handled in template-loader.php before the template hierarchy and even when themes are disabled. | `wp-includes/template-loader.php:16` |  |
| `BR-MIGRATE-259` | `BR-FEED-02` | Registered feed slugs are feed, rdf, rss, rss2 and atom. | `wp-includes/class-wp-rewrite.php:342` |  |
| `BR-MIGRATE-260` | `BR-FEED-03` | Feed templates are plain PHP using the standard Loop. | `wp-includes/feed-rss2.php (5 feed-*.php templates)` |  |
| `BR-MIGRATE-261` | `BR-FEED-04` | Consumed feeds are fetched through the WordPress HTTP API rather than SimplePie's own transport, via WP_SimplePie_File. | `wp-includes/class-wp-simplepie-file.php` |  |
| `BR-MIGRATE-262` | `BR-FEED-05` | Consumed feed content is sanitized with KSES, replacing SimplePie's own sanitizer. | `wp-includes/class-wp-simplepie-sanitize-kses.php` |  |
| `BR-MIGRATE-263` | `BR-FEED-06` | Feed responses are cached as transients via WP_Feed_Cache_Transient. | `wp-includes/class-wp-feed-cache-transient.php` |  |

### `sitemaps` (5)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-264` | `BR-SM-01` | Three built-in providers cover posts, taxonomies and users. | `wp-includes/sitemaps/providers/` |  |
| `BR-MIGRATE-265` | `BR-SM-02` | Each sitemap file holds at most 2000 URLs, filterable per object type via wp_sitemaps_max_urls. | `wp-includes/sitemaps.php:90` |  |
| `BR-MIGRATE-266` | `BR-SM-03` | An XSL stylesheet is served so the raw XML renders readably in a browser. | `wp-includes/sitemaps/class-wp-sitemaps-stylesheet.php` |  |
| `BR-MIGRATE-267` | `BR-SM-04` | Only public post types and public taxonomies are included. | `wp-includes/sitemaps/providers/class-wp-sitemaps-posts.php` |  |
| `BR-MIGRATE-268` | `BR-SM-05` | The user provider includes only authors with published posts. | `wp-includes/sitemaps/providers/class-wp-sitemaps-users.php` |  |

### `ai-abilities-connectors` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-269` | `BR-AI-01` | Ability names must match ^[a-z0-9-]+/[a-z0-9-]+$; a namespace prefix is mandatory. | `wp-includes/abilities-api/class-wp-abilities-registry.php:86` |  |
| `BR-MIGRATE-270` | `BR-AI-02` | Re-registering an existing ability fails with _doing_it_wrong() and returns null; there is no silent overwrite. | `wp-includes/abilities-api/class-wp-abilities-registry.php:97` |  |
| `BR-MIGRATE-271` | `BR-AI-03` | An ability's category must already be registered before the ability can be registered. | `wp-includes/abilities-api/class-wp-abilities-registry.php:110` |  |
| `BR-MIGRATE-272` | `BR-AI-04` | Abilities default to not public and not shown in REST, the opposite of register_rest_route()'s default. | `wp-includes/abilities-api/class-wp-ability.php:29` |  |
| `BR-MIGRATE-273` | `BR-AI-05` | Execution is normalize_input, validate_input, check_permissions, do_execute, validate_output. | `wp-includes/abilities-api/class-wp-ability.php:769` |  |
| `BR-MIGRATE-274` | `BR-AI-06` | Both input and output are validated against JSON Schema. | `wp-includes/abilities-api/class-wp-ability.php:519` |  |
| `BR-MIGRATE-275` | `BR-AI-07` | Permissions are checked after input validation, so a malformed request is rejected before authorization runs. | `wp-includes/abilities-api/class-wp-ability.php:623` |  |
| `BR-MIGRATE-276` | `BR-AI-08` | __wakeup() and __sleep() are overridden on the registry and on abilities as unserialization guards, because these objects hold callables. | `wp-includes/abilities-api/class-wp-ability.php:887` |  |
| `BR-MIGRATE-277` | `BR-AI-09` | The AI client's HTTP goes through the WordPress HTTP API via WP_AI_Client_Http_Client. | `wp-includes/ai-client/adapters/class-wp-ai-client-http-client.php` |  |
| `BR-MIGRATE-278` | `BR-AI-10` | Registered abilities are exposed to AI models as callable functions by WP_AI_Client_Ability_Function_Resolver. | `wp-includes/ai-client/class-wp-ai-client-ability-function-resolver.php` |  |

### `cron` (4)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-279` | `BR-CRON-03` | Built-in schedules are hourly, twicedaily, daily and weekly. | `wp-includes/cron.php:1133` |  |
| `BR-MIGRATE-280` | `BR-CRON-04` | A single event duplicating another within a plus-or-minus 10-minute window is rejected. | `wp-includes/cron.php:135` |  |
| `BR-MIGRATE-281` | `BR-CRON-05` | For an event due within 10 minutes or already past, the lower bound becomes 0 so ALL past identical events count as duplicates, preventing accumulation of a repeatedly-failing event. | `wp-includes/cron.php:136` |  |
| `BR-MIGRATE-282` | `BR-CRON-12` | The pre_schedule_event filter can replace scheduling entirely, which is how external cron systems take over. | `wp-includes/cron.php:100` |  |

### `internationalization` (9)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-283` | `BR-I18N-01` | pre_determine_locale returning a non-empty string overrides all other locale sources. | `wp-includes/l10n.php:125` |  |
| `BR-MIGRATE-284` | `BR-I18N-02` | A request-supplied locale is honoured only on wp-login.php, via wp_lang in $_GET or $_COOKIE, because the login form must be translatable before a user exists. | `wp-includes/l10n.php:130` |  |
| `BR-MIGRATE-285` | `BR-I18N-03` | All user-supplied locale values pass sanitize_locale_name() before use, because the locale becomes part of a .mo filesystem path. | `wp-includes/l10n.php:134` |  |
| `BR-MIGRATE-286` | `BR-I18N-04` | The admin and ?_locale=user JSON requests use the user's locale; the front end uses the site locale. | `wp-includes/l10n.php:140` |  |
| `BR-MIGRATE-287` | `BR-I18N-05` | During installation, $_REQUEST['language'] or $GLOBALS['wp_local_package'] supplies the locale. | `wp-includes/l10n.php:146` |  |
| `BR-MIGRATE-288` | `BR-I18N-06` | switch_to_locale() maintains a stack in WP_Locale_Switcher; restore_previous_locale() pops it. | `wp-includes/l10n.php:1899` |  |
| `BR-MIGRATE-289` | `BR-I18N-07` | Switching locale reloads every already-loaded textdomain in the new locale. | `wp-includes/class-wp-locale-switcher.php` |  |
| `BR-MIGRATE-290` | `BR-I18N-08` | Translations load from .mo files via POMO or from .l10n.php PHP-array files. | `wp-settings.php:123` |  |
| `BR-MIGRATE-291` | `BR-I18N-09` | The source English string is the lookup key; _x() adds a context prefix to disambiguate identical strings. | `wp-includes/l10n.php:409` |  |

### `formatting-and-sanitization` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-292` | `BR-FMT-01` | Escaping is applied at output and chosen by context; there is no single universal escaper. | `wp-includes/formatting.php` |  |
| `BR-MIGRATE-293` | `BR-FMT-02` | esc_url() encodes & to &amp; for use in markup; esc_url_raw() does not, for storage and Location headers. | `wp-includes/formatting.php` |  |
| `BR-MIGRATE-294` | `BR-FMT-03` | wpautop() and wptexturize() run on the_content output, not on stored content, which is why the database holds plain newlines. | `wp-includes/default-filters.php` |  |
| `BR-MIGRATE-295` | `BR-FMT-04` | Both wpautop() and wptexturize() skip a maintained list of block-level and code tags. | `wp-includes/formatting.php` | ⚠️ override Q5 |
| `BR-MIGRATE-296` | `BR-FMT-06` | sanitize_title() produces a URL-safe slug; sanitize_key() lowercases and restricts to [a-z0-9_-]. | `wp-includes/formatting.php` |  |
| `BR-MIGRATE-297` | `BR-FMT-07` | sanitize_option() dispatches per option name and is applied on every option write. | `wp-includes/formatting.php` |  |

### `kses-security` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-298` | `BR-KSES-01` | KSES is an allowlist: anything not explicitly permitted is stripped. | `wp-includes/kses.php:961` | ⚠️ override Q5 |
| `BR-MIGRATE-299` | `BR-KSES-02` | 22 protocols are allowed by default. | `wp-includes/functions.php:7352` |  |
| `BR-MIGRATE-300` | `BR-KSES-03` | The protocol list is memoized in a static and filterable only before wp_loaded, freezing it for the rest of the request. | `wp-includes/functions.php:7358` |  |
| `BR-MIGRATE-301` | `BR-KSES-04` | Scheme comparison decodes entities, strips whitespace, removes null bytes and lowercases before matching the allowlist. | `wp-includes/kses.php:2118` | ⚠️ override Q5 |
| `BR-MIGRATE-302` | `BR-KSES-05` | Colons are recognized as ':', '&#58;', '&#x3a;' and '&colon;'. | `wp-includes/kses.php:2102` | ⚠️ override Q5 |
| `BR-MIGRATE-303` | `BR-KSES-06` | Truncated colon entities are repaired before splitting so they cannot evade detection. | `wp-includes/kses.php:2100` | ⚠️ override Q5 |
| `BR-MIGRATE-304` | `BR-KSES-07` | A feed: prefix triggers re-examination of the remainder, capped at 2 levels of recursion. | `wp-includes/kses.php:2107` | ⚠️ override Q5 |
| `BR-MIGRATE-305` | `BR-KSES-08` | A disallowed scheme yields an empty protocol string, leaving the URL schemeless rather than passing it through. | `wp-includes/kses.php:2128` |  |
| `BR-MIGRATE-306` | `BR-KSES-09` | Allowlists are context-specific: post, strip, data, entities, user_description, pre_user_description. | `wp-includes/kses.php:1063` |  |
| `BR-MIGRATE-307` | `BR-KSES-10` | Entity normalization converts all & to &amp; before selectively restoring valid named and numeric entities. | `wp-includes/kses.php:2168` |  |

### `error-handling-and-recovery-mode` (10)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-308` | `BR-ERR-01` | WP_Error holds multiple codes each with multiple messages; get_error_message() returns only the first. | `wp-includes/class-wp-error.php` |  |
| `BR-MIGRATE-309` | `BR-ERR-02` | Only E_ERROR, E_PARSE, E_USER_ERROR, E_COMPILE_ERROR and E_RECOVERABLE_ERROR trigger the fatal error handler; warnings and notices do not. | `wp-includes/class-wp-fatal-error-handler.php:100` |  |
| `BR-MIGRATE-310` | `BR-ERR-03` | The wp_should_handle_php_error filter can opt additional error types in. | `wp-includes/class-wp-fatal-error-handler.php:114` |  |
| `BR-MIGRATE-311` | `BR-ERR-04` | A wp-content/fatal-error-handler.php drop-in replaces the error template. | `wp-includes/class-wp-fatal-error-handler.php:144` |  |
| `BR-MIGRATE-312` | `BR-ERR-05` | The handler is registered before the database connects, so DB failures remain recoverable. | `wp-settings.php:69` |  |
| `BR-MIGRATE-313` | `BR-ERR-06` | The offending extension is identified from the error's file path and recorded in paused-extensions storage. | `wp-includes/class-wp-recovery-mode.php:351` |  |
| `BR-MIGRATE-314` | `BR-ERR-07` | The recovery email is rate-limited to once per day, filterable via recovery_mode_email_rate_limit. | `wp-includes/class-wp-recovery-mode.php:299` |  |
| `BR-MIGRATE-315` | `BR-ERR-08` | The recovery link TTL is max(filtered_ttl, rate_limit), so the link can never expire before another email may be sent. | `wp-includes/class-wp-recovery-mode.php:317` |  |
| `BR-MIGRATE-316` | `BR-ERR-09` | The recovery cookie is httponly, secure when is_ssl(), and set on both COOKIEPATH and SITECOOKIEPATH. | `wp-includes/class-wp-recovery-mode-cookie-service.php:50` |  |
| `BR-MIGRATE-317` | `BR-ERR-10` | Paused extensions are skipped at boot until the administrator exits recovery mode. | `wp-includes/load.php:1061` |  |

### `performance-speculation-view-transitions` (6)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-318` | `BR-PERF-01` | Speculation mode is prefetch or prerender; eagerness is conservative, moderate or eager. | `wp-includes/speculative-loading.php:22` |  |
| `BR-MIGRATE-319` | `BR-PERF-02` | Core defaults to prefetch with conservative eagerness, the most cautious combination. | `wp-includes/speculative-loading.php:125` |  |
| `BR-MIGRATE-320` | `BR-PERF-03` | Hosting providers may override the default configuration via a documented override path. | `wp-includes/speculative-loading.php:158` |  |
| `BR-MIGRATE-321` | `BR-PERF-04` | URL patterns are prefixed for subdirectory installs by WP_URL_Pattern_Prefixer. | `wp-includes/class-wp-url-pattern-prefixer.php` |  |
| `BR-MIGRATE-322` | `BR-PERF-05` | Rules are emitted as a speculationrules JSON script block. | `wp-includes/speculative-loading.php:330` |  |
| `BR-MIGRATE-323` | `BR-PERF-06` | View Transitions support in this release is limited to admin CSS plus a configuration surface. | `wp-includes/view-transitions.php` |  |

### `admin-application` (8)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-324` | `BR-ADM-01` | WP_ADMIN is defined by admin.php; WP_NETWORK_ADMIN and WP_USER_ADMIN distinguish the three admin contexts. | `wp-admin/admin.php:14` |  |
| `BR-MIGRATE-325` | `BR-ADM-02` | auth_redirect() at admin.php line 104 is the single authentication gate for every admin screen. | `wp-admin/admin.php:104` |  |
| `BR-MIGRATE-326` | `BR-ADM-03` | admin_init fires after the admin bootstrap and before any screen-specific code. | `wp-admin/admin.php:180` |  |
| `BR-MIGRATE-327` | `BR-ADM-04` | wp_scheduled_delete and delete_expired_transients are re-scheduled on admin load if absent. | `wp-admin/admin.php:107` |  |
| `BR-MIGRATE-328` | `BR-ADM-05` | A db_upgraded option triggers the upgrade path on admin load. | `wp-admin/admin.php:39` |  |
| `BR-MIGRATE-329` | `BR-ADM-06` | admin-ajax.php dispatches on $_REQUEST['action'] to wp_ajax_{action} or wp_ajax_nopriv_{action}. | `wp-admin/admin-ajax.php` |  |
| `BR-MIGRATE-330` | `BR-ADM-07` | Registering a wp_ajax_nopriv_* handler makes that action publicly callable with no further gate; each handler must check capabilities and nonces itself. | `wp-admin/admin-ajax.php` | ⚠️ override Q4 |
| `BR-MIGRATE-331` | `BR-ADM-08` | WP_List_Table subclasses implement prepare_items() and per-column methods. | `wp-admin/includes/class-wp-list-table.php` |  |

### `filesystem-api` (11)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-332` | `BR-FS-01` | The FS_METHOD constant overrides all detection. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-333` | `BR-FS-02` | Direct writing requires that files PHP creates have the same owner as WordPress's own files, not merely that writing succeeds. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-334` | `BR-FS-03` | $allow_relaxed_file_ownership bypasses the ownership check for contexts where the risk is acceptable. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-335` | `BR-FS-04` | The chosen direct-method rationale is recorded in $GLOBALS['_wp_filesystem_direct_method'] as 'file_owner' or 'relaxed_ownership'. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-336` | `BR-FS-05` | Fallback order is direct, then ssh2, then ftpext, then ftpsockets. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-337` | `BR-FS-06` | A non-existent target directory (such as WP_LANG_DIR) causes the write probe to test its parent instead. | `wp-admin/includes/file.php` |  |
| `BR-MIGRATE-338` | `BR-FS-07` | Missing sodium_crypto_sign_verify_detached or sha384 yields signature_verification_unsupported, not a verification failure. | `wp-admin/includes/file.php:1416` |  |
| `BR-MIGRATE-339` | `BR-FS-08` | When the sodium extension is absent, the pure-PHP polyfill is speed-tested via runtime_speed_test(100, 10) and rejected if too slow. | `wp-admin/includes/file.php:1426` |  |
| `BR-MIGRATE-340` | `BR-FS-09` | Signatures whose decoded length is not SODIUM_CRYPTO_SIGN_BYTES are skipped and counted. | `wp-admin/includes/file.php:1497` |  |
| `BR-MIGRATE-341` | `BR-FS-10` | Packages are hashed with SHA-384 and verified against wp_trusted_keys() using Ed25519 detached signatures. | `wp-admin/includes/file.php:1489` |  |
| `BR-MIGRATE-342` | `BR-FS-11` | PclZip is the pure-PHP fallback when ZipArchive is unavailable. | `wp-admin/includes/class-pclzip.php` |  |

### `updates-and-upgrader` (9)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-343` | `BR-UPD-01` | Update data is cached in the update_core, update_plugins and update_themes site transients. | `wp-includes/update.php` |  |
| `BR-MIGRATE-344` | `BR-UPD-02` | The check timeout escalates: 1 minute during cron, 1 hour after a recent attempt, 2 hours, then 12 hours in steady state. | `wp-includes/update.php:383` |  |
| `BR-MIGRATE-345` | `BR-UPD-03` | A re-check is suppressed within 12 hours of last_checked. | `wp-includes/update.php:1033` |  |
| `BR-MIGRATE-346` | `BR-UPD-04` | Packages are signature-verified after download and before extraction. | `wp-admin/includes/class-wp-upgrader.php` |  |
| `BR-MIGRATE-347` | `BR-UPD-05` | The site enters maintenance mode for the duration of install_package(). | `wp-admin/includes/class-wp-upgrader.php` |  |
| `BR-MIGRATE-348` | `BR-UPD-06` | Core updates use update-core.php, which carries per-version file manifests so obsolete files can be removed. | `wp-admin/includes/update-core.php` |  |
| `BR-MIGRATE-349` | `BR-UPD-07` | Schema migrations are version-gated upgrade_NNN() functions applied in sequence from the site's current db version. | `wp-admin/includes/upgrade.php` |  |
| `BR-MIGRATE-350` | `BR-UPD-08` | dbDelta() diffs the declared CREATE TABLE schema against the live schema and emits the necessary ALTER statements. | `wp-admin/includes/upgrade.php` |  |
| `BR-MIGRATE-351` | `BR-UPD-09` | $wp_db_version in version.php is the single schema version marker. | `wp-includes/version.php` |  |

### `site-health` (5)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-352` | `BR-SH-01` | Tests are either direct (run synchronously during page load) or async (fetched by JavaScript), so slow tests do not block the page. | `wp-admin/includes/class-wp-site-health.php` |  |
| `BR-MIGRATE-353` | `BR-SH-02` | Test statuses are good, recommended and critical. | `wp-admin/includes/class-wp-site-health.php` |  |
| `BR-MIGRATE-354` | `BR-SH-03` | WP_Site_Health is instantiated during boot specifically so its cron events can fire. | `wp-settings.php:760` |  |
| `BR-MIGRATE-355` | `BR-SH-04` | The loopback test is how a site detects that WP-Cron cannot self-invoke. | `wp-admin/includes/class-wp-site-health.php` |  |
| `BR-MIGRATE-356` | `BR-SH-05` | Results are also exposed through the site-health REST controller. | `wp-includes/rest-api/endpoints/class-wp-rest-site-health-controller.php` |  |

### `multisite` (7)

| Target id | Legacy id | Rule | Source | Note |
|-----------|-----------|------|--------|------|
| `BR-MIGRATE-357` | `BR-MS-01` | Each site gets its own prefixed table set (wp_{blog_id}_posts etc.); users and usermeta are shared network-wide. | `wp-includes/class-wpdb.php:291` |  |
| `BR-MIGRATE-358` | `BR-MS-03` | Switching a blog changes $wpdb's table prefix and the object cache's blog prefix together. | `wp-includes/class-wpdb.php:1043` |  |
| `BR-MIGRATE-359` | `BR-MS-04` | Role membership is per site, stored as {prefix}capabilities user meta, so one user row carries many role assignments. | `wp-includes/class-wp-user.php` |  |
| `BR-MIGRATE-360` | `BR-MS-05` | Super admins sit above the role system and bypass every capability check except do_not_allow. | `wp-includes/class-wp-user.php:795` |  |
| `BR-MIGRATE-361` | `BR-MS-06` | The sunrise.php drop-in loads before network resolution, enabling domain mapping. | `wp-includes/ms-settings.php` |  |
| `BR-MIGRATE-362` | `BR-MS-07` | Network-activated plugins load before muplugins_loaded. | `wp-settings.php:523` |  |
| `BR-MIGRATE-363` | `BR-MS-08` | Site and network options live in wp_blogmeta and wp_sitemeta respectively. | `wp-includes/option.php:2001` |  |

---

## 2. DISCARD (68)

Full rationale per item in `discard_log.md`.

| Target id | Legacy id | Rule | Reason |
|-----------|-----------|------|--------|
| `BR-DISCARD-001` | `BR-BOOT-01` | PHP < 7.4 or missing mysqli (with no db.php drop-in) aborts the request before any WordPress | paradigm |
| `BR-DISCARD-002` | `BR-BOOT-03` | SHORTINIT truthy stops the boot immediately after the object cache and default filters. | paradigm |
| `BR-DISCARD-003` | `BR-BOOT-06` | pluggable.php loads after all plugins, enabling plugins to redefine wp_mail(), wp_authentica | paradigm |
| `BR-DISCARD-004` | `BR-BOOT-07` | Initial post types and taxonomies are registered twice: at wp-settings.php:566 and again on  | paradigm |
| `BR-DISCARD-005` | `BR-HOOK-01` | Default priority is 10; lower runs earlier. A null priority becomes 0. | paradigm |
| `BR-DISCARD-006` | `BR-HOOK-02` | Default accepted_args is 1. Callbacks receive a sliced argument list when they accept fewer  | paradigm |
| `BR-DISCARD-007` | `BR-HOOK-03` | A callback whose unique id cannot be built is silently dropped with no error or notice. | paradigm |
| `BR-DISCARD-008` | `BR-HOOK-04` | Within one priority, callbacks run in registration order. | paradigm |
| `BR-DISCARD-009` | `BR-HOOK-05` | Re-registering the same callback at the same priority overwrites rather than duplicating. | paradigm |
| `BR-DISCARD-010` | `BR-HOOK-06` | Registering a hook while it is executing re-sorts the live iteration; equal-priority additio | paradigm |
| `BR-DISCARD-011` | `BR-HOOK-07` | In an action every callback receives the original arguments; in a filter each receives the p | paradigm |
| `BR-DISCARD-012` | `BR-HOOK-08` | A filter callback that returns nothing returns null, which becomes the filtered value. | paradigm |
| `BR-DISCARD-013` | `BR-HOOK-09` | register_uninstall_hook() rejects instance-method callbacks because the callback is serializ | paradigm |
| `BR-DISCARD-014` | `BR-HOOK-10` | Callbacks registered on the 'all' hook fire before every hook dispatch in the system. | paradigm |
| `BR-DISCARD-015` | `BR-HOOK-11` | apply_filters_deprecated() emits its notice only when a callback is actually registered. | paradigm |
| `BR-DISCARD-016` | `BR-HOOK-12` | has_filter() returns the integer priority when a specific callback is found; falsy compariso | paradigm |
| `BR-DISCARD-017` | `BR-DB-01` | prepare() adds its own quoting; callers must not wrap %s in quotes. Pre-existing quotes are  | paradigm |
| `BR-DISCARD-018` | `BR-DB-02` | An argument used as both %i identifier and %s value is a hard error: _doing_it_wrong() and p | paradigm |
| `BR-DISCARD-019` | `BR-DB-03` | Placeholder/argument count mismatch triggers _doing_it_wrong(); too few args returns empty s | paradigm |
| `BR-DISCARD-020` | `BR-DB-04` | %f is always rewritten to %F so float formatting is locale-independent. | paradigm |
| `BR-DISCARD-021` | `BR-DB-05` | Every executed SQL string passes through apply_filters('query', $query). | paradigm |
| `BR-DISCARD-022` | `BR-DB-06` | A write containing text the target column's charset cannot represent is rejected outright, n | paradigm |
| `BR-DISCARD-023` | `BR-DB-07` | On MySQL error 2006 (server gone away) the query is retried exactly once after reconnection. | paradigm |
| `BR-DISCARD-024` | `BR-DB-08` | check_connection() retries 5 times with 1-second sleeps, blocking the request for up to ~5 s | paradigm |
| `BR-DISCARD-025` | `BR-DB-09` | Charset utf8 is always upgraded to utf8mb4; utf8_general_ci becomes utf8mb4_unicode_ci, upgr | paradigm |
| `BR-DISCARD-026` | `BR-DB-10` | Six strict SQL modes (NO_ZERO_DATE, ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, STRICT_ALL_TABL | paradigm |
| `BR-DISCARD-027` | `BR-DB-11` | A failed INSERT/REPLACE resets insert_id to 0 so a stale id cannot leak. | paradigm |
| `BR-DISCARD-028` | `BR-DB-12` | $where in update()/delete() supports only equality joined with AND; no OR and no operators. | paradigm |
| `BR-DISCARD-029` | `BR-DB-14` | If the connection is lost after template_redirect has fired, wpdb fails silently rather than | paradigm |
| `BR-DISCARD-030` | `BR-OPT-04` | update_option() returns false when the value is unchanged, making 'no change' indistinguisha | ruling |
| `BR-DISCARD-031` | `BR-OPT-06` | An option whose serialized value exceeds 150000 bytes (filterable via wp_max_autoloaded_opti | paradigm |
| `BR-DISCARD-032` | `BR-OPT-07` | An explicit on/off autoload value is never overridden by the automatic heuristic; only auto, | paradigm |
| `BR-DISCARD-033` | `BR-OPT-08` | A transient without an expiration is autoloaded; with an expiration it is not. | paradigm |
| `BR-DISCARD-034` | `BR-OPT-09` | Transient expiry is lazy: enforced on read, plus a scheduled delete_expired_transients() swe | paradigm |
| `BR-DISCARD-035` | `BR-OPT-10` | With a persistent object cache present, transients never touch the database. | paradigm |
| `BR-DISCARD-036` | `BR-OPT-11` | A transient whose value row exists but whose timeout row is missing is deleted and recreated | paradigm |
| `BR-DISCARD-037` | `BR-OPT-14` | The wp_autoload_values_to_autoload filter can only remove values from the valid set, never a | paradigm |
| `BR-DISCARD-038` | `BR-CACHE-01` | The default object cache is request-scoped only; nothing survives the response. | paradigm |
| `BR-DISCARD-039` | `BR-CACHE-04` | A cached null is a genuine hit, distinguished from a miss by the array_key_exists() arm of _ | paradigm |
| `BR-DISCARD-040` | `BR-CACHE-06` | $expire is accepted and ignored by the default implementation. | paradigm |
| `BR-DISCARD-041` | `BR-CACHE-10` | get() sets the by-reference $found parameter, the only reliable way to distinguish a cached  | paradigm |
| `BR-DISCARD-042` | `BR-META-02` | Meta keys and values are wp_unslash()ed on write because input arrives slashed. | paradigm |
| `BR-DISCARD-043` | `BR-META-03` | $unique = true is enforced by SELECT COUNT(*) before insert with no unique index, so concurr | paradigm |
| `BR-DISCARD-044` | `BR-POST-04` | Drafts store post_date_gmt as 0000-00-00 00:00:00, requiring MySQL NO_ZERO_DATE mode to be o | paradigm |
| `BR-DISCARD-045` | `BR-TAX-05` | Duplicate detection happens after insert; only a row with a lower term_id counts as the dupl | paradigm |
| `BR-DISCARD-046` | `BR-CAP-14` | get_super_admins() prefers the $super_admins PHP global over the site_admins network option. | ruling |
| `BR-DISCARD-047` | `BR-XR-01` | XML-RPC is enabled by default; disabling requires add_filter('xmlrpc_enabled', '__return_fal | scope |
| `BR-DISCARD-048` | `BR-XR-02` | The enable_xmlrpc option is deprecated since 3.5.0; its pre_option and option filters are co | scope |
| `BR-DISCARD-049` | `BR-XR-03` | Every method authenticates independently with a username and password passed as XML-RPC para | scope |
| `BR-DISCARD-050` | `BR-XR-04` | 78 methods span the wp, metaWeblog, mt, blogger, pingback and demo families. | scope |
| `BR-DISCARD-051` | `BR-XR-05` | pingback.ping fetches a caller-supplied URL server-side, unauthenticated. | scope |
| `BR-DISCARD-052` | `BR-CRON-01` | All scheduled events live in the single autoloaded 'cron' option. | paradigm |
| `BR-DISCARD-053` | `BR-CRON-02` | Event identity is timestamp, then hook, then md5(serialize(args)). | paradigm |
| `BR-DISCARD-054` | `BR-CRON-06` | Cron cannot spawn while DOING_CRON is defined or the doing_wp_cron query arg is present. | paradigm |
| `BR-DISCARD-055` | `BR-CRON-07` | A doing_cron lock more than 10 minutes in the future is discarded as invalid, self-healing a | paradigm |
| `BR-DISCARD-056` | `BR-CRON-08` | WP_CRON_LOCK_TIMEOUT (60 seconds) prevents spawning more than once a minute regardless of ho | paradigm |
| `BR-DISCARD-057` | `BR-CRON-09` | Spawning aborts when no events are ready or the earliest ready timestamp is in the future. | paradigm |
| `BR-DISCARD-058` | `BR-CRON-10` | ALTERNATE_WP_CRON runs cron via a visitor redirect and requires a GET request that is neithe | paradigm |
| `BR-DISCARD-059` | `BR-CRON-11` | The default path issues a non-blocking loopback HTTP request to wp-cron.php. | paradigm |
| `BR-DISCARD-060` | `BR-CRON-13` | _get_cron_array() migrates pre-version-2 cron arrays on read via _upgrade_cron_array(). | paradigm |
| `BR-DISCARD-061` | `BR-FMT-05` | All superglobal input is slashed by wp_magic_quotes(); wp_unslash() is required before use. | paradigm |
| `BR-DISCARD-062` | `BR-MS-02` | switch_to_blog() maintains a stack and must be paired with restore_current_blog(). | ruling |
| `BR-DISCARD-063` | `BR-DEP-01` | Deprecated functions remain fully functional; only a debug-time notice is added. | scope |
| `BR-DISCARD-064` | `BR-DEP-02` | Deprecation notices appear only when WP_DEBUG is enabled, so they are invisible in productio | scope |
| `BR-DISCARD-065` | `BR-DEP-03` | Deprecated hooks still fire, warning only if a callback is actually registered. | scope |
| `BR-DISCARD-066` | `BR-DEP-04` | Old file paths are preserved as aliases (class.wp-scripts.php alongside class-wp-scripts.php | scope |
| `BR-DISCARD-067` | `BR-DEP-05` | compat.php and php-compat/ polyfill newer PHP functions so core can use modern syntax while  | scope |
| `BR-DISCARD-068` | `BR-DEP-06` | Nothing in the deprecated layer has a removal date. | scope |

---

## 3. HUMAN DECISION (0)

All 22 items raised by the Curator were resolved at the pause on 2026-08-21. See the override and
deviation sections above, and `ambiguity_log.md` for the audit trail.
