---
kind: brief
audience: the next coding agent
updated: 2026-08-24
prerequisite_reading: [_reversa_sdd/migration/as_built.md, _reversa_sdd/migration/risk_register.md]
---

# Brief: attack RISK-021, RISK-022 and RISK-023

You are picking up a Rails 8.1 / PostgreSQL rebuild of WordPress 7.2-alpha, built under the
Reversa framework. It works: 53 front-end screens are byte-identical to a live WordPress
oracle, 1822 specs pass, both editors run the real upstream Gutenberg against the rebuild's
own `wp/v2` API. Read `as_built.md` before anything else.

**This brief is backed by reconnaissance, not speculation.** Three agents spent a combined
~45 minutes measuring, profiling and probing before it was written. Every claim below has a
`file:line`, a number, or a reproducing command. Where the recon was uncertain it says so.

**Run this with `ultracode`.** All three areas are independently parallelisable and the work
is exactly the shape workflows are for: fan out, verify adversarially, then integrate. Do not
attempt it serially — the security area alone has four independent fixes.

---

## Read this first: the three traps that will cost you hours

1. **`GET /console/posts/new` WRITES TO THE DATABASE.** It inserts an `auto_draft` and
   redirects. Merely opening the editor mutates the parity corpus. Anything that browses the
   console must clean up after itself, and you should re-run `./bin/parity compare` after any
   browser session.

2. **The parity normalizer SORTS class-attribute tokens by design.** Class-*order*
   regressions are invisible to `bin/parity compare`. Two of the performance changes below can
   reorder classes. Unit specs assert order; the screen diff does not.

3. **The REST nonce is only emitted by the EDITOR layout**
   (`app/views/layouts/editor.html.erb:31`), not by the console chrome. To exercise a REST
   write you must first fetch `/console/posts/<id>/edit` and scrape `window.wpApiSettings`.
   Seeded passwords are in `oracle/wordpress/tools/seed.php:48` (`pw-administrator`,
   `pw-editor`, `pw-author`, `pw-contributor`, `pw-subscriber`; the installer admin is
   `oracle_admin` / `oracle-admin-pw`).

---

## AREA 1 — Security (RISK-023). Do this first.

> **Status 2026-08-26: RISK-023 is CLOSED — V1 through V7.** Each fix was checked
> against the live oracle rather than against the source alone, and each carries specs that
> were confirmed to FAIL against the unfixed code before they were trusted. Two things worth
> carrying forward from V3: the leak was **latent** — no comment in the corpus sits on a
> non-public post, so `bin/parity compare` was green at 53/53 for the whole life of the
> defect and would have stayed green — and it took a probe comment on the oracle's private
> post to see it at all. **V4 is next**, and it is the same shape: an ownership scope that
> the corpus's data never exercises.

The recon found **four real defects**, one with a working public exploit. This outranks
everything else in this brief.

| # | Severity | Defect | Where |
|---|---|---|---|
| ~~**V1**~~ | ✅ **CLOSED** f557b32bb9 | **Stored XSS.** The post write path never runs KSES. WordPress's `kses_init_filters()` hangs `wp_filter_post_kses` on `content_save_pre`; AD-01 removed the hook system and nothing replaced this. Any Author can store and publish `<script>` that executes for anonymous visitors. | `public_api/posts_controller.rb:239-241`, and the autosave path |
| ~~**V2**~~ | ✅ **CLOSED** (this commit) | **Arbitrary `author` on REST writes.** WordPress refuses with `rest_cannot_edit_others` unless the caller holds `edit_others_posts`. The rebuild assigns whatever is sent. | `public_api/posts_controller.rb:246` |
| ~~**V3**~~ | ✅ **CLOSED** (this commit) | **`/comments/feed/` leaks comments on non-public posts** to anonymous visitors, including the private post's title. Comment status is filtered; post status is not. | `syndication/feeds_controller.rb:36` |
| ~~**V4**~~ | ✅ **CLOSED** (this commit) | **The Posts list was not ownership-scoped, and did not gate private rows.** See the correction below — this row overstated the defect in two ways and understated it in one. | `console/posts_list_controller.rb:77` |

~~Lower: **V5**, **V6**, **V7**~~ — ✅ **all three CLOSED.** What they turned out to be:

- **V5 — real, and the cause was not where the row pointed.** The raw print in
  `tenancy/signups/confirm.html.erb:19` is WordPress's own (`printf( __( '...%s...' ),
  $user_email )`, wp-signup.php:893, no `esc_html`) and is faithful. The defect was a
  *deviation on the controller side*: `#confirm` redirected and then read the address back
  out of the QUERY STRING, which the legacy never does — it hands `confirm_*_signup()` the
  address it validated microseconds earlier. Fixed by sourcing the address from the
  persisted signup; `params[:email]` is no longer read or emitted. Reachable only under
  multisite, which is a configuration, not a mitigation.
- **V6 — NOT a live vulnerability.** `#current_actor`'s cookie arm is
  `ApplicationController#current_actor`, which is `nil`, so no cookie-authenticated caller
  can reach the action and there is no ambient authority to forge with. Verified against
  the running app: a cookie-bearing cross-site-shaped POST answers **403**. The skip was a
  *tripwire* — the note on `#current_actor` invites exactly the change that would arm it —
  so it is now conditional on the request having no ambient authority. Two traps found while
  doing it, both worth knowing: `skip_before_action` folds `only:` and `if:` into one
  condition set and inverts the lot, so `only: :create, if: <cond>` skips unconditionally and
  the `if:` does nothing; and Rails renders `InvalidAuthenticityToken` as a **422 response**
  rather than propagating the exception, so assert on the status, not on a raise.
- **V7 — real, and the row's line numbers had drifted.** It is `#update_settings`
  (`console/network/site_edit_controller.rb:140`), which reached `Setting.set` directly —
  the equivalent of a raw DB write, not of `update_option()`. `update_option()` runs
  `sanitize_option()`, whose blogname/blogdescription arm is `esc_html`, and that is the
  premise `Configuration::Setting.display` relies on when it hands those two to a view as
  `html_safe`. The other two write paths both apply it; this third one did not, so a title
  submitted here became trusted markup wherever the site name is printed.

### V4 as it actually was — the row above got two things wrong

Measured against the oracle's own `edit.php` with the seeded roles, id for id:

| role | oracle | rebuild (before) |
|---|---|---|
| contributor (owns 0) | 14 — `1 4 5 6 8 10..18` | 15 — **also the private post** |
| author (owns 14 of 15) | 14 — `4 5 6 7 8 10..18` | 15 — **also the admin's post** |
| administrator | 15 | 15 ✓ |

**Overstated 1 — "and others' drafts".** Not a divergence. The ownership default is guarded by
`$this->user_posts_count &&`, so a Contributor who owns nothing is *not* scoped at all: the
ORACLE serves them other people's drafts too, on the default view and on `?post_status=draft`
alike. Reproducing that is correctness, not a hole.

**Overstated 2 — "and every commenter's email".** Not a divergence either. `edit-comments.php`
applies no ownership scope whatsoever; oracle_contributor, oracle_author and oracle_admin were
each served the same 9 comments with the same addresses, and so were all three on the rebuild.
`comments_list_controller.rb` was left alone. (The two systems number those comments
differently — the oracle's spam/trash are 7/8, the rebuild's are 4/5 — which is ordinary ETL id
assignment, and exactly what the parity normalizer masks.)

**Understated — the private row was a SECOND, independent rule.** The ownership default
(`class-wp-posts-list-table.php:104`) and the private-status gate (`class-wp-query.php:2759`)
are different mechanisms, and the first does not imply the second. The caller who was served
the private article is precisely the one the ownership default never fires for. Both are now
ported, along with the readable tab counts and the `all_posts=1` escape hatch on the All link.

### Two important negatives — do not "fix" these

- The **~150 `html_safe`/`raw` uses are almost all disciplined** (the recon found the real
  count is ~150, not the 22 the risk register guessed). Every user-controlled value is
  `ERB::Util.html_escape`d first. The whole-page `page.to_html.html_safe` and the raw post
  title in feeds are **faithful ports of WordPress's own behaviour**. Changing them breaks
  parity and fixes nothing.
- **`?context=edit` on `/wp/v2/users` is wider than the oracle's** (we return 200 where
  WordPress answers `rest_forbidden_context`). Real, but a parity bug rather than a
  vulnerability — bucket it accordingly.

### Sequencing note that matters

**Do NOT retro-apply KSES to stored content when fixing V1.** WordPress filters at the moment
of an authenticated HTTP write, based on the *requesting user's* capabilities — it does not
sanitise at render, and it does not rewrite history. Sanitising the existing corpus would
break the 53-screen byte comparison and would not match WordPress either.

---

## AREA 2 — Performance (RISK-022). The headline number is wrong.

The register says 1.99× the oracle with the cost in the block renderers. **The recon
contradicts both halves of that**, with measurements:

- **26% of the rebuild's per-request time is Rails development-mode overhead** — chiefly
  `ActiveRecord::LogSubscriber#query_source_location`, which walks the stack on every query.
  Measured A/B in one process across all 53 screens: 3720 ms dev vs 2741 ms production-like.
  **Settle this before optimising anything**, or you will spend effort on a number that is
  partly an artifact of how it was measured.
- **The biggest single application cost is not the renderers.** It is the **global stylesheet
  being regenerated from `theme.json` on every request** (`Presentation::GlobalStylesheet`),
  at 16–19% of a web request.

The recon's projection: four byte-identical fixes plus a production-config measurement take
the corpus walk from **3720 ms → 1753 ms against the oracle's 1914 ms — i.e. 0.92×, faster
than WordPress.** Treat that as a hypothesis to verify, not a promise.

Ranked backlog, in the recon's recommended landing order:

| Step | Change | Measured effect |
|---|---|---|
| 0 | Reproduce the rig. `gem install stackprof --no-document` — **system gem, never the Gemfile** | — |
| 1 | Settle dev-vs-production measurement | 26% of the gap |
| 2 | **OPT-2** emoji tables: `FeedText.encode_emoji` rebuilds its table per call | feeds 61→44 ms; fixes the 3 worst screens |
| 3 | **OPT-1** global stylesheet memo/cache — the big one | 421→335 ms over 5 screens |
| 4 | **OPT-3** memoise `Retrieval::PostQuery#relation`/`#records` | 361→337 ms over 6 |
| 5 | **OPT-4** batch `QueryBlocks::Support.taxonomy_classes` (one query per post today) | 5.64→2.01 ms |
| 6 | **OPT-5** hoist constant `Bytes.binary` conversions out of `wptexturize`'s loop | 6.08→5.37 ms |

**Already measured and REJECTED — do not redo:** bulk-loading autoload settings in one query
(the `wp_load_alloptions` shape) gained nothing; a `styles_block_nodes` memo gained nothing.

**Performance traps.** stackprof `mode: :cpu` under-samples this workload ~4×; use wall mode
for attribution. Monkeypatching `QueryBlocks::PostTemplate#render` infinite-loops because the
class `prepend`s `SupportChain`. The three embed screens contain a per-request random id in
`aria-controls` — in **both** systems, so it is not a regression.

---

## AREA 3 — Rule coverage (RISK-021). Mostly a measurement artifact — but it hides six real defects.

`bin/rule_coverage` reports 262/363 cited, 101 uncited. The recon establishes that **the 101
is largely an artifact of counting**, and that the *cited* number is also overstated:

- The 101 are **not scattered** — they are **13 whole subsystems** in which nobody wrote a
  `BR-MIGRATE` id. The codebase's actual convention is to cite the **legacy source path**
  (`wp-includes/template-loader.php:67`), which the script cannot see. `template_resolver.rb`
  is one of the best-documented files in the tree and counts as uncited.
- **59 of the 262 "cited" rules carry only a RANGE citation** — one `BR-MIGRATE-182..193`
  header at the top of a file, expanded into up to 60 individual credits. The genuinely
  specifically-cited count is **203, not 262**.
- `bin/rule_coverage` **counts itself** as an implementation (`bin` is in its search path and
  its own comment contains a rule range). Two rules sit in the strongest bucket because of it.

Estimated true split of the 101: **~30 implemented-but-uncited, ~40 absent by construction**
(AD-01/DEV-002 — though *half of those have no recorded ruling*, which is a documentation gap
worth closing), **~31 genuinely unimplemented.**

### Six confirmed defects inside that last group — all reproduced against the oracle

Every one of these was live while `bin/parity compare` sat green at 53/53.

| Defect | Evidence |
|---|---|
| **Every extra feed URL the rebuild prints in its own `<head>` is answered by its own 404** — category, tag, author, search and post-comment feeds. Same class as the pagination bug already in `as_built.md`. | `presentation/head.rb:235-248` emits them; `routes.rb:217-218` routes only `/feed` and `/comments/feed`. `/category/uncategorized/feed/` → 404 vs oracle 200 |
| **Two of five feed slugs return the wrong document and Content-Type** — `/feed/rdf` and `/feed/rss` both serve RSS 2.0 | `feeds_controller.rb:25` collapses everything not `atom` to `rss2` |
| **Every sitemap advertises an XSL stylesheet that 404s** | `sitemaps/*.xml.erb`; no route |
| **`/favicon.ico` 404s**; the oracle 302s | `BR-MIGRATE-129` — robots was done, favicon was not |
| **No maintenance cron at all** — trashed posts and comments are never purged | `config/recurring.yml` schedules only Solid Queue's own cleanup |
| **The oEmbed *consumer* does not exist** — no auto-embed, no provider list (the *provider* half is built) | `syndication/` holds only `embed_cache.rb` |

Also genuinely absent: the fatal-error handler and recovery mode (`BR-MIGRATE-309..317`),
which is open decision **D-2**.

### The lesson worth internalising

> The bug pattern this project keeps producing is **"the rebuild advertises a URL it then
> answers with its own 404."** Pagination links, feed links, sitemap stylesheets, sitemap
> entries. A screen-content comparison cannot see it, because the *page* matches — only the
> links it contains are dead.

**`bin/link_check` now does exactly this** — it was built and run while writing this brief.
It walks the corpus screens, extracts every same-origin URL each system emits, and asks each
system for **its own** links (cross-checking would flag every autoincrement id, since the two
assign different ids to the same record — which is why the parity normalizer masks them).

✅ **All 19 are now CLOSED** (2026-08-26), byte-identical to the oracle and added to the
corpus, which is why it went 53 → 65 screens. `bin/link_check` reports 22 today and all 22
are the oEmbed `siteurl` artifact below — the number to watch is not the total but whether a
NON-oEmbed entry ever appears again.

Three things that cost a diff each, and would cost the next person the same:

- **A feed is the same query with two vars changed.** `posts_per_page` becomes
  `posts_per_rss`, and search RELEVANCE ordering is SUPPRESSED — `class-wp-query.php:2561`
  gates the relevance prefix on `! $this->is_feed`, so `/search/x/feed/rss2/` is plain
  `post_date DESC` while `/?s=x` ranks by match quality. The two orders genuinely differ.
- **`feed-rss2-comments.php:49` is `is_single()`, not `is_singular()`.** A POST's comment
  feed links to its permalink; a PAGE's links to the site home.
- **PHP's `?>`-swallows-one-newline rule is load-bearing in these templates.** When
  `the_category_rss()` prints nothing — a page, which has no categories — the two tabs on its
  line run straight onto the `<guid>` line and the two become ONE line. Likewise the tab
  before `</channel>` is the last loop iteration's, so an EMPTY feed closes at column 0.
  Both arms only appear once a feed contains a page or no items at all, which `/feed/` never
  does. None of this is visible in the PHP; all of it came out of diffing the oracle.

**The original finding, for the record — 19 genuinely dead links in three families.** Every
one was a page the site advertised and could not deliver, and every one was live at 53/53
green:

| Family | Count | Detail |
|---|---|---|
| **Feeds** | 17 | Per-post comment feeds (`/2026/03/<post>/feed/`, `/feed/atom/`), plus category, tag, author, search and privacy-policy feeds. `presentation/head.rb:235-248` emits them; `routes.rb:217-218` routes only `/feed` and `/comments/feed`. |
| **RSD** | 1 | `/xmlrpc.php?rsd` — emitted in every `<head>`, no route |
| **Sitemap XSL** | 1 | `/wp-sitemap.xsl`, `/wp-sitemap-index.xsl` |

⚠️ **A 22-link false positive you must understand before trusting a run.** The oEmbed
discovery links also report dead, and they are an **environment artifact, not a defect**: this
corpus is seeded FROM the oracle, so the rebuild's `siteurl`/`home` hold the ORACLE's host.
The rebuild GENERATES the `<head>` link from the request host (`:3100`) but VALIDATES it
against the setting (`:8099`), so it rejects its own URL — and accepts the `:8099` form.
Confirmed: `/wp-json/oembed/1.0/embed?url=<:3100>` → 404, `url=<:8099>` → 200. In a deployment
where `siteurl` is the site's own host, both agree. The tool documents this in its own header.

That same root cause — `siteurl` pointing at the oracle — already bit once before, when the
first Gutenberg mount sent every REST call to WordPress on :8099 instead of to the rebuild.
**Anything that reads `siteurl` in this environment is suspect.**

Also worth a look: **the oracle emits 142 distinct same-origin URLs across the corpus; the
rebuild emits 97.** That 45-URL gap is not necessarily wrong — but nobody has explained it,
and it is the sort of thing this project has learned to be curious about.

---

## Suggested workflow shape

Three areas, independently parallelisable. Security is the only one with an exploit, so land
it first; the other two can run concurrently with it.

```
Phase 1  Security      4 agents, one per defect (V1 alone, then V2+V3+V4 in parallel)
                       → adversarial verify: a second agent tries to bypass each fix
Phase 2  Performance   1 agent settles dev-vs-prod, then 4 in a pipeline for OPT-1..4
         Coverage      1 agent per defect cluster (feeds / sitemaps+favicon / cron / oEmbed)
Phase 3  Integrate     routes + AD-04 declarations centrally — agents must NOT edit
                       config/routes.rb or authorization_declarations.rb concurrently
Phase 4  Gate          the full gate, on a quiet machine, once
```

**Non-negotiable gate after every phase** (and it must be run on a quiet machine — concurrent
agents dirty the shared oracle and the test database, and a flake read as a regression costs
more than the run it saved):

```
./bin/parity compare        # 53/53, and run it 3x — it must be stable, not just green once
./bin/parity determinism 2
./bin/check_cycles
./bin/rspec_worker          # 1822 examples, 0 failures
./bin/parity_worker         # 168 passed
./editor_e2e/run.sh && (cd editor_e2e && node gb_paths.mjs)
./bin/benchmark all         # only if you touched performance
```

**Correctness outranks speed and outranks tidiness.** If a change cannot keep the 53-screen
byte comparison exact, report it instead of landing it. And when you find something, prefer
adding it to the gate over merely fixing it — this project's entire defect history is things
a green gate could not see.
