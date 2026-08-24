---
kind: as_built
status: current
updated: 2026-08-24
---

# As Built

> The other documents in this directory record what was **planned**. This one records what
> was **built**, and where the two diverge. When they disagree, this file is the current
> truth and the planning document is the historical record — neither is wrong, they answer
> different questions.

Code lives in `_reversa_forward/rebuild/` (Rails 8.1 / PostgreSQL 17). The reference
WordPress 7.2-alpha-63330 instance lives in `_reversa_forward/oracle/wordpress/` and, per
AD-08, remains the only executable definition of the migrated behaviour.

## The gate, and what it actually proves

```
bin/parity compare      53 screens, byte-identical through the normalizer
bin/parity determinism  full oracle rebuilds produce byte-identical goldens
bin/check_cycles        acyclic; the three packs stay zero-dependency leaves
bin/rspec_worker        1822 examples, 0 failures, 6 pending
bin/parity_worker       172 scenarios, 168 passed, 4 pending
bin/benchmark           latency + SQL profile against the oracle
editor_e2e/run.sh       both editors driven in a real browser
editor_e2e/gb_paths.mjs 13 editor write-path checks
```

⚠️ **What "byte-identical" means.** The normalizer masks nonces, autoincrement ids, the UUID
guid, timestamps and the site host, and it **sorts class-attribute tokens** — so class ORDER
is invisible to the screen diff by design and is asserted by unit specs instead. Two panes
that look identical can still differ in bytes the harness masks. The harness is the
authority for what it covers; it is not a proof of total equivalence.

## Waves 0–5: complete

All six waves are built. Beyond them, the following was added after the original handoff.

## Beyond the plan

### The editors are the real Gutenberg (DEV-015)

`console.post`, `console.post-new` and `console.site-editor` mount the upstream
`@wordpress/*` packages — `edit-post`'s and `edit-site`'s own `initializeEditor`, called as
wp-admin calls them. The hand-built React island that D-3 originally answered with has been
**deleted**.

This was not an editor project but an API project. The boot contract was obtained by
observing the oracle: the 24 REST paths wp-admin preloads into the editor page. Against that
list the rebuild had 10 reads and zero writes. What exists now:

| Surface | Detail |
|---|---|
| Auth | Cookie + `X-WP-Nonce`, reproducing `rest_cookie_check_errors()` — including that a **missing** nonce discards the cookie identity and proceeds anonymously, while a **bad** one is a flat 403 on every verb |
| `context=edit` | `{raw, rendered}` pairs and edit-only fields, matched key-for-key **and in the oracle's field order**, plus `_fields` and `_locale` |
| Writes | posts/pages (create, update, trash, `?force=true`), autosaves, **revisions**, media upload, terms, comments — all through existing aggregate commands, never raw SQL |
| Site data | settings, themes, global styles (three shapes), templates + `templates/lookup`, block-pattern categories, reusable blocks |
| `OPTIONS` | Route descriptor + `Allow`, with the verbs **derived from the router's own table** so the answer cannot drift from what it accepts |

### The console has navigation and wears wp-admin's skin (DEV-014)

The console previously had **no navigation at all** — a `MENU` constant existed but no layout
rendered it. It now has the admin menu and admin bar, authored against the live oracle's own
`$menu`/`$submenu` (`oracle/wordpress/tools/dump_menu.php` dumps them).

DEV-014 then reversed the *styling* half of `screen_modernization_decision.md` at the owner's
instruction. Every value was **measured** from the oracle's computed styles
(`editor_e2e/measure_wpadmin.mjs`), which mattered: WordPress 7.2-alpha ships a refreshed
palette (accent `#3858E9`, chrome `#1E1E1E`), so the familiar older values would have been
wrong. `editor_e2e/skin_diff.mjs` measures the match — 44/45 computed properties identical,
the remainder a probe artifact.

The **semantic** contract is unchanged: literal strings verbatim, and still no golden files
for the console.

### Screens added after the handoff

`console.import` (a real WXR importer — modern `import.php` is only a plugin list, which
AD-01 leaves pointing at nothing), the four info pages rebuilt project-neutral under DEV-009,
and the nine network/multisite screens over the Wave 5 tenancy models.

**Route census: 46 of wp-admin's screens resolve to a console route.** The remainder are
discarded by a recorded ruling — no plugin screens (AD-01 removed what they manage), no
Customizer or widgets (DEV-002 folds them into the Site Editor), plus installers and internals.

## Bugs the widened gate found

The corpus went 25 → 53 screens and **13 of the 28 new URLs diverged on first capture (46%)**.
This is the single most valuable thing in this record: the gate was green the whole time the
bugs below were live.

| Severity | Defect |
|---|---|
| **Security** | Private posts served in full to anonymous visitors — `status: %w[published private]` in the singular controller, repeated in embeds and the page walk |
| High | The rebuild **printed pagination links to URLs it answered with its own 404** — no `/page/N/` routes existed while `core/query-pagination` emitted them on screens already in the corpus |
| High | Ruby's `String#gsub` expands `\&` and `\\` in a replacement where PHP's `str_replace()` does not, so a post whose title contains an escaped quote corrupted its **neighbours'** next/previous links |
| High | Public comment counts included pending, spam and trashed comments |
| High | Non-ASCII oEmbed lookups and percent-encoded term slugs 404'd |
| Medium | Empty date archives answered 200 where `WP::handle_404()` gives 404 |
| Medium | The sitemap index advertised three URLs the rebuild 404'd |
| Medium | Pingback/trackback comments requested a real gravatar |

Driving the editors (rather than testing the endpoints) found two more that every request
spec had missed, because the specs never asked:

- `/wp/v2/posts/:id/revisions` **did not exist** — Gutenberg's revisions panel 404'd.
- The `categories`/`tags` write parameters were accepted and **silently ignored** — the
  editor's category box appeared to work and lost the assignment.

**The lesson, stated plainly: every bug in this table was invisible to a green gate.** Widening
coverage found more defects per hour than any other activity in the project.

## Performance

`bin/benchmark` is the repeatable measurement. Current standing:

- **1.99× the oracle** in aggregate p50; 40 of 53 screens exceed 1.5×; the rebuild is
  genuinely *faster* on four screens that render few blocks.
- **Not a database problem.** 1397 queries / 260 ms against a 3838 ms corpus walk — SQL is
  ~7% of wall time. The cost is Ruby CPU in the block renderers.
- Two fixes landed (a per-request settings memo; a recursive CTE for term descendants), worth
  1.29× — without them the figure would be ~2.6×. Both proven behaviour-neutral by replaying
  all 53 screens byte-for-byte with the optimisation on and off.

## Open, and honest about it

| # | Item | Note |
|---|---|---|
| **LICENCE** | ⚠️ **Needs an owner decision.** The `@wordpress/*` packages are GPL-2.0-or-later and are now bundled into the build output. The rebuild carries **no LICENSE file of its own**. This is the only open item with legal rather than engineering exposure. |
| CI | There is `bin/ci` but no pipeline. Every result in this document was produced by hand on a quiet machine. Snapshots decay. |
| Rule coverage | 262/363 rules carry a citation; 101 do not. And a citation only means an id was written next to an implementation — it is a coverage floor, not proof of behaviour. |
| D-2 | Theme-fatal recovery — still undecided |
| D-6 | Typed settings registry — still undecided |
| D-7 | Screen inventory cross-check — `reversa-visor` never ran |
| D-8 | Production infrastructure — Dockerfiles exist; nothing connects them to an environment |
| Security review | 22 `html_safe`/`raw` uses in the render path, none reviewed. The private-post disclosure above suggests this deserves a pass of its own. |
| Multisite | Screens and models exist and are proven strictly additive (every network URL 404s single-site), but the system has never been run as a real multi-tenant install |
| Bundle | 21 MB of built JS is committed so the app runs without an npm install; it grows with every Gutenberg rebuild |

## Deviations added after the handoff

| ID | What |
|---|---|
| DEV-013 | Tenancy signup/confirm copy restored to verbatim `wp-signup.php` strings |
| DEV-014 | The console adopts wp-admin's skin — reverses the styling half of the modernization ruling |
| DEV-015 | The editors are the real Gutenberg, running on this backend |

Full text in `screen_deviation_log.md`.
