---
kind: retrospective
audience: whoever runs Reversa next
updated: 2026-08-24
---

# What I'd tell you to ask for next time

Written after taking this migration from handoff to a running system. Reversa's output was
genuinely strong — 363 extracted rules, a decision log that held up under pressure, and an
architecture that survived contact with the code. The gaps below are not failures of the
analysis. They are **things the analysis had no reason to know it should produce**, and every
one of them cost real time downstream.

Ordered by how much each would have saved.

---

## 1. Ask for a parity corpus sized to the risk, not to the screen inventory

**What happened.** The migration shipped with a 25-screen corpus. That gate was green for
days. Then the corpus was widened to 53 screens and **13 of the 28 new URLs diverged
immediately — a 46% failure rate.** Among them: private posts served in full to anonymous
visitors, and the site printing pagination links to URLs it answered with its own 404 page.

Both defects were live the entire time the gate was green.

**What to ask for instead.** Do not let the corpus be a list of *screens*; make it a list of
*request shapes*. Ask explicitly for:

> "For every route the legacy serves, enumerate the distinct **states** it can be in — empty,
> paged, filtered, permission-denied, not-found, redirected — and give me a corpus entry for
> each. Where a state cannot be reached with the seeded data, say so and tell me what data
> would reach it."

The 25 screens covered 25 *pages*. They covered almost none of the *states* those pages have.
Pagination, empty archives, private content, and 404s are where the bugs were, because they
are the paths a happy-path corpus never walks.

**Rule of thumb:** if a corpus has no 404 in it, it is not a parity corpus, it is a smoke test.

---

## 2. Ask which behaviours are language-shaped, not just which are business-shaped

**What happened.** A migrated post-title renderer produced corrupted output for one corpus
post. The cause: Ruby's `String#gsub` expands `\&` and `\\` inside a replacement string;
PHP's `str_replace()` substitutes literally. The rule was correctly extracted. The rule was
correctly implemented. The *language* silently changed the semantics.

Others in the same family: settings that return `false` when unset (`get_option()`'s contract,
which broke code twice — once taking down every Posts-list spec); `Array(false)` being
`[false]` rather than `[]`; PHP's `array()` vs Ruby's `{}` in serialized payloads.

**What to ask for instead.**

> "List every place where the source language's standard-library semantics differ from the
> target's in a way that changes behaviour — string replacement, truthiness, empty/null
> conventions, array/hash coercion, sort stability, integer division, date handling. Flag any
> extracted rule whose correctness depends on one of them."

This is exactly the analysis a discovery tool is well placed to do and a coding agent is
badly placed to remember at 3 a.m.

---

## 3. Ask for the "what does the client actually call" contract, not just the server surface

**What happened.** The block editor was recorded as unspecifiable because WordPress ships it
as compiled JavaScript — true, and correctly flagged as the project's biggest risk. The
resolution turned out to be trivial once framed correctly: **run the upstream editor and give
it the API it expects.**

Finding out what it expects took one script pointed at the running oracle: 24 preloaded REST
paths. That could have been in the handoff. Instead it was discovered late, after a
hand-built editor had been written, verified, and then deleted.

**What to ask for instead.**

> "For every screen whose behaviour lives in compiled client code, do not try to specify the
> client. Instead, record the **network contract**: every endpoint it calls, with request and
> response shapes captured from the running system. Treat the client as a black box with a
> documented interface."

The general principle: **when a component cannot be specified, specify its boundary.** A
compiled bundle is opaque; the HTTP it speaks is not.

---

## 4. Ask for the chrome, not only the screens

**What happened.** All 24 admin screens were built and specced, and every one of them was an
island: the console had **no navigation whatsoever**. A `MENU` constant existed with seven
flat entries and no layout ever rendered it. You could not get from one screen to another.

The screen inventory counted screens. Nobody had asked for the thing *between* screens.

**What to ask for instead.**

> "Inventory the persistent chrome as a first-class artifact: navigation (with the capability
> that reveals each item), the admin bar, breadcrumbs, notice/flash regions, and any
> per-screen furniture like tab bars. Give me the menu as data, including which capability
> gates each entry."

A related miss: the *capability* on each menu entry was recoverable in about a minute by
dumping `$menu`/`$submenu` from the running instance. Ask for that dump.

---

## 5. Ask for a performance baseline as an artifact of discovery

**What happened.** Nobody measured anything until the very end. The answer — 1.99× the oracle,
with the cost in Ruby CPU inside the block renderers rather than in SQL (~7% of wall time) —
was actionable and slightly surprising. Had it been measured at Wave 2, the renderer design
could have taken it into account. Measured at the end, it is an observation rather than an
input.

**What to ask for instead.**

> "Record the legacy's per-route latency profile and query counts as part of discovery, and
> state a performance budget the target must meet. Treat a route that exceeds it as a parity
> failure, not a follow-up."

Correct-and-slower is a real migration outcome and deserves a number in the risk register from
day one.

---

## 6. Ask for licence and dependency provenance up front

**What happened.** The only open item on this project with *legal* rather than engineering
exposure: the rebuild bundles GPL-2.0-or-later packages and **declares no licence of its
own**. The rebuild has no LICENSE file at all — which was true from the first commit and went
unnoticed until someone asked "what else is wrong?"

**What to ask for instead.**

> "State the legacy system's licence, every dependency's licence, and what licence the target
> must therefore carry. Make an explicit decision about it before the first line of target
> code."

Cheap to ask at the start. Awkward to discover after the code exists.

---

## 7. Ask that the gate be automated before it is trusted

**What happened.** Every verification result on this project was produced by hand, on a
machine deliberately quietened first. That worked because someone was watching. It does not
survive contact with a team.

Worse, the project has direct evidence of the failure mode: on three separate occasions a
"regression" turned out to be **test pollution** — a browser test that edited the parity
corpus and left it dirty. Each cost real diagnostic time, and each would have been obvious
with a clean-checkout CI run.

**What to ask for instead.**

> "Produce the CI pipeline definition as a first-class deliverable of the migration plan, not
> as a follow-up task. The gate is only a gate if something other than a person runs it."

---

## 8. Ask for the discard list to be adversarial

**What happened.** The discard decisions (no hook system, no plugins, no Customizer) held up
extremely well — they were principled and they survived. But their *consequences* surfaced
late and one at a time. `import.php`, for example, is only a plugin-installer list in modern
WordPress; with plugins discarded, that screen degenerates to a shell pointing at nothing, so
the honest equivalent is a real built-in importer. That reasoning happened during coding, not
during planning.

**What to ask for instead.**

> "For every discarded subsystem, walk the screens and features that DEPEND on it and state
> what each becomes: deleted, degraded, or replaced by something new. A discard is not
> complete until its dependents are re-specified."

---

## The one-paragraph version

Reversa's analysis was good; what it lacked was **breadth of interrogation**. Ask it to
enumerate *states* rather than screens, *boundaries* rather than opaque internals, *language
seams* rather than only business rules, and *consequences* of each discard. Ask for the chrome,
a performance budget, licence provenance, and a CI definition as deliverables. Every serious
defect on this project — including a security hole — was found by asking a question the
existing artifacts had not been asked to answer, and each was invisible to a green gate right
up until the moment someone widened the question.
