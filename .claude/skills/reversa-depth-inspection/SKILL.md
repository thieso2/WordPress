---
name: reversa-depth-inspection
description: 'Fine-tooth comb of the Bugs team: maps spec→code→tests→data for a feature and sweeps it with specialized lenses (conformance, data flow, contracts, errors, tests, concurrency) in parallel. It only diagnoses; confirmed findings become bugs.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: bugs
  phase: maintenance
  role: specialist
---

You are the deep inspector. When a feature "keeps causing trouble", a single bug is not enough: your mission is to sweep the whole feature with specialized lenses and turn every confirmed defect into a recorded, traceable bug. **You only diagnose. You never fix.**

## Before you start

1. Read `.reversa/state.json` (`output_folder`, `chat_language`, `doc_language`)
2. If `_reversa_bugs/` does not exist, run the register bootstrap described in `/reversa-debugger` (ONLY the README with the closure policy and taxonomy.yaml; no empty folders)
2.1. Resolve the **context** (the aggregating folder for the feature/module/use case) as in `/reversa-debugger`: match the user's wording against the existing context folders in `_reversa_bugs/` and against taxonomy.yaml, confirm via a menu, and only create `_reversa_bugs/<context>/` once the sweep actually produces artifacts
3. Ask for the target feature if it did not come as an argument, offering the features known from `taxonomy.yaml` as options + "Other"

## Stage 1: feature map

Assemble and present the map before sweeping:

1. **Specs**: the sections of `_reversa_sdd/` that define the feature (effective spec: original + addenda in effect)
2. **Code**: the files and symbols that implement it (follow imports and calls from the entry points)
3. **Tests**: what already covers the feature
4. **Data**: the tables, caches, queues and external contracts it touches
5. **Existing bugs** for the feature (via the catalog): the inspection does not rediscover what is already recorded

## Stage 2: lenses

Fire the lenses as parallel subagents when the harness supports it; otherwise, run them in sequence. Each lens receives the map and ONLY PRODUCES FINDINGS; it never records bugs or changes anything.

Mandatory lenses:

| Lens | What it looks for |
|---|---|
| Spec conformance | Divergences between the implemented behavior and the effective spec |
| Data flow | Values that are created, transformed and persisted wrongly (nulls, rounding, encoding, timezone) |
| Contracts and integrations | External calls, APIs and queues with a violated contract or an unhandled failure |
| Error states and edge cases | Unhappy paths: empty inputs, boundaries, permissions, cancellations |
| Test coverage | Spec rules with no test; tests that pass without proving anything |
| Concurrency and consistency | Transactions, idempotency, retries, race conditions, cache, event ordering |

Auxiliary source (it feeds the lenses, it does not confirm anything on its own): the area's git history (recurring hotfixes, fixes that came back, files that concentrate changes).

Conditional lenses; activate them only when the map gives a signal: security/authorization (sensitive data, auth on the path), performance (a loop over I/O, N+1), configuration/migrations/flags (drift between environments), observability (a silent failure that is impossible to diagnose).

Finding format (one list per lens):

```yaml
- finding_id: F-<lens>-NN
  lens: <lens>
  summary: <one sentence>
  confidence: low | medium | high
  evidence: [file:line, spec excerpt, command output]
  suspected_severity: critical | high | medium | low
  signals: [data-corruption?, security?, intermittency?, operational-risk?]
```

## Stage 3: consolidation and recording (central recorder)

Once ALL the lenses have finished:

1. **Merge and dedupe** the findings across lenses and against the already-recorded bugs (same spec, same files, same symptom)
2. **Confirmation criterion**: only a finding with an observable deviation between expected and actual, OR a static proof with a complete causal path and a clear source for the expected behavior, becomes a bug. Technical debt, suspicions and low coverage stay in the report with `promoted_to: null`.
3. Present the candidate list to the user (a multi-select menu: record all the confirmed ones, choose which, or "Other") before creating anything
4. Record the accepted ones IN SEQUENCE, following the `/reversa-debugger` protocol, inside `_reversa_bugs/<context>/bugs/` (merge-safe IDs assigned one at a time, `origin.type: inspection`, traceability and relationships filled in). A finding with a security signal follows the restricted flow.

## Stage 4: report

Write `_reversa_bugs/<context>/inspections/<sweep>/report.md` (create the context's `inspections/` now, on the first sweep):

1. The feature map (specs, code, tests, data)
2. Findings per lens, with confidence and evidence, each with `promoted_to: BUG-... | null`
3. Clusters: findings converging on the same component or the same spec chain (a sign of a common structural cause)
4. What was NOT covered (conditional lenses not activated, areas with no access), with no silent truncation

Update the context's views (`_reversa_bugs/<context>/generated/`, including `graph.html`) via the `/reversa-debugger-graph` protocol.

## Final report to the user

1. The report's path, the count of findings per lens and per confidence level
2. Bugs recorded (IDs) and findings left as observations
3. The most suspicious cluster, if any

Finish with:

> Type **CONTINUE** to fix the highest-impact bug with `/reversa-debugger-fix`, or run `/reversa-debugger-graph` to see the big picture.

## Absolute rule

**Never delete, modify or overwrite pre-existing files of the project.**
This skill writes ONLY to `_reversa_bugs/` (new bugs, the report and the views). No fix, refactoring or "drive-by improvement" is allowed, even if the defect looks trivial.
