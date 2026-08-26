---
kind: handoff
from: the agent that built and hardened this migration
updated: 2026-08-25
---

# Handoff

You are picking up a **reverse-engineered rebuild of WordPress 7.2-alpha-63330 in Ruby on
Rails 8.1 / PostgreSQL 17**, produced under the Reversa framework. It is not a prototype: the
public site is byte-identical to a live WordPress instance across 53 screens, the admin works,
and the editors run the real upstream Gutenberg against the rebuild's own REST API.

This document orients you. Two others carry the detail:

| Read | For |
|---|---|
| **`migration/as_built.md`** | what exists, what the gate proves, what is open |
| **`NEXT_AGENT_BRIEF.md`** | the evidence-backed attack plan for the three live risks — **start here for actual work** |
| `PROMPTING_RETROSPECTIVE.md` | what earlier passes learned the hard way |

⚠️ **The planning documents in `migration/` describe what was PLANNED.** Where
they and `as_built.md` disagree, `as_built.md` is current truth and the planning doc is the
historical record. Neither is wrong; they answer different questions.

---

## The shape of it

All paths below are relative to the repository root; this file lives in `_reversa_sdd/`.

```
_reversa_forward/rebuild/     the Rails app — 341 .rb, 110 .erb, 128 spec files, 22 migrations
_reversa_forward/oracle/      WordPress 7.2-alpha-63330 (PHP 8.4 / MariaDB) + tools/
_reversa_forward/report/      the oracle-vs-rebuild visual report generator
_reversa_sdd/                 Reversa's analysis, decisions and deviation logs
```

**Non-negotiable, from `CLAUDE.md`:** never modify the legacy WordPress tree. Reversa writes
only to `.reversa/`, `_reversa_sdd/`, `_reversa_docs/` and `_reversa_forward/`.

### The oracle is not a test fixture — it is the specification

AD-08 and RISK-001: with no production deployment, the running WordPress instance is **the
only executable definition** of the 363 migrated rules. When you do not know what correct
looks like, **ask it**, don't reason about it. Every late-stage defect on this project was
found by asking the oracle a question the corpus had not asked before.

```
oracle   http://127.0.0.1:8099    admin: oracle_admin / oracle-admin-pw
rebuild  http://127.0.0.1:3100    same credentials (the ETL migrates password digests)
```
Role logins are `oracle_<role>` / `pw-<role>` (see `oracle/wordpress/tools/seed.php:48`).

Start them:
```bash
cd _reversa_forward/rebuild
bin/oracle up                                          # WordPress on :8099
(setsid nohup env RAILS_ENV=development bin/rails server -p 3100 -b 127.0.0.1 \
   > /tmp/rails.log 2>&1 < /dev/null &)
```

---

## The gate

Run it on a **quiet machine**. Concurrent agents dirty the shared oracle and the test
database, and a flake read as a regression costs more than the run it saved. This bit us
repeatedly.

```bash
cd _reversa_forward/rebuild
./bin/parity compare          # 53/53 — run it 3x, it must be STABLE, not green once
./bin/parity determinism 2    # full oracle rebuilds produce byte-identical goldens
./bin/check_cycles            # acyclic; the 3 packs stay zero-dependency leaves
./bin/rspec_worker            # 1822 examples, 0 failures, 6 pending
./bin/parity_worker           # 172 scenarios, 168 passed
./bin/link_check              # does the site serve the URLs it advertises?
                              #   reports 41 today: 19 real + 22 siteurl artifacts (trap 4)
./editor_e2e/run.sh           # both editors, in a real browser
(cd editor_e2e && node gb_paths.mjs)   # 13 editor write-path checks
./bin/benchmark all           # only if you touched performance
```

`bin/rspec_worker` and `bin/parity_worker` use **private databases** so they can run while
something else holds the dev DB. Use them, not bare `rspec`.

### What "byte-identical" does and does not mean

The normalizer masks nonces, autoincrement ids, the UUID guid, timestamps and the site host,
and it **sorts class-attribute tokens** — so class *order* is invisible to the screen diff by
design, and is asserted by unit specs instead. The harness is authoritative for what it
covers. It is not a proof of equivalence.

---

## Six traps that will cost you hours

1. **`GET /console/posts/new` WRITES TO THE DATABASE.** It inserts an `auto_draft` and
   redirects. *Opening the editor mutates the parity corpus.* Re-run `./bin/parity compare`
   after any browser session.

2. **Browser tests can poison the corpus.** Three separate "regressions" on this project were
   test pollution — a Playwright run that edited a corpus post, a template, or Global Styles
   and left it dirty. The suites in `editor_e2e/` now snapshot and restore; keep it that way.
   If parity suddenly fails, **check for leftover test data before suspecting code**.

3. **`Configuration::Setting[key]` returns `false` when unset**, not nil — `get_option()`'s
   own contract. So `Array(false)` is `[false]` and `.to_i` raises. This broke every
   Posts-list spec once and the Site Editor mount once. Guard the type.

4. **`siteurl` holds the ORACLE's host**, because the corpus is seeded from it. Anything that
   generates a URL from the request host but validates it against the setting will disagree
   with itself in this environment and nowhere else. It sent every Gutenberg REST call to
   WordPress once, and it is why 22 oEmbed links look dead in `bin/link_check`.
   **Anything reading `siteurl` here is suspect.**

5. **The REST nonce is only emitted by the EDITOR layout**
   (`app/views/layouts/editor.html.erb`), not the console chrome. To exercise a REST write,
   fetch `/console/posts/<id>/edit` first and scrape `window.wpApiSettings`.

6. **A dev-server code reload can leave the AD-04 registry HALF BUILT, and it looks exactly
   like a regression.** `config/initializers/authorization_declarations.rb` runs inside
   `to_prepare`, which begins with `Access::Declarations.reset!` — so every reload empties the
   registry and refills it. A request served in that window gets
   `Access::Declarations::Undeclared … has no authorization declaration (AD-04)` → **500**, and
   the partial registry PERSISTS until the next reload. The tell is that two identifiers
   declared by the *same* `.each` disagree: `POST public_api/posts#create` answered while
   `POST public_api/posts#update` 500'd. Nothing is wrong with the code — it 500s on routes you
   never touched (`themes#index`, `options#show`, `templates#lookup`). It bites when you edit
   files (or `git stash`/`pop`) while traffic is flowing, which is exactly what a browser suite
   does. **Cure: restart the server, let it settle, send ONE warm-up request, then run the
   suite — and touch no files while it runs.** Cost here: one full `editor_e2e/run.sh` read as
   a failure before the cause was found.

Environment: the **ssh-agent dies regularly**. When a push fails with "correct access
rights", find a live socket and repoint it:
```bash
SOCK=$(find /tmp -maxdepth 3 -name "agent.*" -type s 2>/dev/null | \
  while read s; do SSH_AUTH_SOCK=$s ssh-add -l >/dev/null 2>&1 && echo "$s" && break; done)
ln -sfn "$SOCK" ~/.ssh/ssh_auth_sock && export SSH_AUTH_SOCK="$SOCK"
```

---

## Where the work is

**Start with `NEXT_AGENT_BRIEF.md`.** It is backed by ~45 minutes of
reconnaissance and every claim carries a `file:line`, a number or a reproducing command. In
priority order:

1. ✅ **Security (RISK-023) is CLOSED — all seven.** V1 stored XSS, V2 arbitrary `author` on
   REST writes, V3 `/comments/feed/` leaking private-post comments, V4 the Posts list serving
   rows the oracle withholds, V5 the signup confirm screen trusting a query parameter, V6 the
   media upload's forgery tripwire, V7 the third `blogname` write path storing raw HTML.
   **The next work is the 19 dead links, then the performance backlog** — see below.

   Two habits paid for themselves across all seven and are worth keeping.

   **The corpus's data, not just its screens, decides what a green gate can see.** V3 was
   invisible because no comment sat on a non-public post; V4's private-row leak was invisible
   because nothing browses the console as a Contributor; V5 sits behind multisite, which is
   off here. Each was green at 53/53 throughout and would have stayed green.

   **Check every claim against the oracle before building to it.** Of the seven rows, five
   were real and two were not — V6, and the comments half of V4 — and in both of those the
   finding was that the ORACLE does the same thing, so the code was left alone. Three of the
   five real ones had a cause or a location different from the one the row named: V5's raw
   print is WordPress's own and the bug was a controller deviation; V7's line numbers had
   drifted; V4 missed the private-status rule entirely. Fixing what a row SAYS, rather than
   what the oracle shows, would have broken parity in at least two places.

2. 🟠 **The 19 real dead links** `bin/link_check` reports — 17 feed URLs the site prints in
   its own `<head>` and answers with its own 404, the RSD link, and the sitemap stylesheets.
   The tool prints **41**; the other 22 are the `siteurl` artifact in trap 4, and its header
   explains how to tell them apart. Do not "fix" those.

3. 🟡 **Performance (RISK-022).** The headline "1.99×" is misattributed: 26% is Rails
   development-mode overhead, and the biggest application cost is the global stylesheet
   regenerating from `theme.json` every request — not the block renderers. A costed backlog is
   in the brief, with two candidates already measured and **rejected** so you don't repeat them.

4. 🟡 **Coverage (RISK-021).** Largely a counting artifact — the 101 "uncited" rules are 13
   subsystems that cite the *legacy source path* instead of a `BR-MIGRATE` id. But ~31 are
   genuinely unimplemented, including six confirmed user-visible defects.

**Still open and needing a human:** no CI (RISK-020 — everything above was verified by hand),
D-2 theme-fatal recovery, D-6 typed settings registry, D-7 screen-inventory cross-check, D-8
production infrastructure.

---

## Two working practices worth inheriting

**Widen the question, not the confidence.** Every serious defect here — including a security
hole that served private posts to anonymous visitors — was found by asking something the
existing artifacts had not been asked, and each was invisible to a green gate right up to that
moment. Going from 25 to 53 corpus screens made **46% of the new URLs diverge on first
capture**. When you find something, prefer *adding it to the gate* over merely fixing it.

**Report what is true, not what is tidy.** This project's defect history is mostly things that
looked fine. If a test fails, say so with the output. If a number is misattributed, say which
part. If you left a probe row on the oracle, clean it up and mention it. A confidently wrong
report costs more than an honest gap.

---

## State at handoff

Branch `reversa/wordpress-7.2-analysis`, mirrored to GitHub `thieso2/WordPress` as
`reversa/wp-7.2-to-rails-migration`. Working tree clean apart from `node_modules/` and an
unrelated `yazi-*` download.

⚠️ **One commit is unpushed** — `d3feb16e99` (`bin/link_check`) — because the ssh-agent died.
Push it first:
```bash
git push github reversa/wp-7.2-to-rails-migration
```

Everything else is green as of this writing: parity 53/53, RSpec 1822/0, Cucumber 168 passed,
both editors driven in a browser, determinism reproducible, topology acyclic.
