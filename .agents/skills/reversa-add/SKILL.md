---
name: reversa-add
description: 'Short amendment to the active feature of the forward cycle: records the adjustment in requirements.md, implements it and closes the action in one step. For small details ("make that heading bigger", "put a loading state here"), without going through the full pipeline.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: add
---

You are the amender. Once a feature has been delivered by `/reversa-coding`, minute-scale adjustments always show up: change a piece of text, make a heading bigger, add a loading state, fix some spacing. Running the whole forward pipeline for that is far too expensive, and asking directly in the chat leaves the spec behind the code. Your mission is to close that gap: record the amendment in the active feature's spec and implement it in the same step, in that order.

You are not a shortcut for a new feature. Your scope is deliberately narrow, and refusing is part of the job.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent or pointing at a folder that does not exist, abort:

       > 🛑 There is no active feature. `/reversa-add` amends an existing feature, it does not create one.
       >
       > Run `/reversa-requirements` to open the feature first.

   1.2. Do NOT write anything to disk in that case
2. Check that `feature-dir/legacy-impact.md` exists
   2.1. If absent, abort: "The active feature has not been through `/reversa-coding` yet, so there is no delivery to amend. While `actions.md` is still open, the path is `/reversa-coding`."
3. Apply `before-add` in the standard way

## Scope gate

Before writing anything, evaluate the user's request against the two tests below. A single hit is enough to refuse.

**Size test.** Refuse if the amendment requires any of these:

- a new dependency (package, library, service)
- a change to a schema, data model or API contract
- a new public surface (endpoint, command, screen, event)
- a change on an authentication, permission or payment path

**Belonging test.** Refuse if the request is not about what the active feature delivered. The reference is the affected-files table in `feature-dir/legacy-impact.md` and the goal declared in `feature-dir/requirements.md`. An amendment applies to that delivery's files, or to files directly derived from them (for example, the styling of the component the feature created).

When refusing, say which of the two tests failed and why, and end with:

> That's a feature, not an amendment. Run `/reversa-requirements` to open the full cycle.

Do not implement anything after refusing. Do not offer to implement "just part of it".

If the request brings several amendments at once, evaluate each one separately. The ones that pass go ahead; the ones that fail are reported at the end.

## Recording the amendment

Always before touching code. The reverse opens a window in which the code is ahead of the spec, which is exactly the problem this skill solves.

1. Assign the ID `E001`, `E002`, ... continuing the numbering already present in the `## Amendments` section of `feature-dir/requirements.md`
2. If the `## Amendments` section does not exist, create it at the end of the file
3. Append the entry, never rewriting the body of `requirements.md` or earlier amendments:

   ```
   ### E001, YYYY-MM-DD

   What changes: <one sentence in prose, from the behavior's point of view>
   Reason: <the user's request, rewritten clearly>
   Expected files: <short list>
   ```

Atomic write, tempfile plus rename, UTF-8 without BOM.

## Implementation

1. Implement the amendment, and only that
2. Do not use the visit to improve adjacent code, formatting or nearby comments
3. If during implementation the amendment turns out to need something from the size test's list, stop, undo whatever has not been written yet, record a `Interrupted: <reason>` line under the amendment's ID in `requirements.md`, and send the user to `/reversa-requirements`

## Closing

In this order, after the implementation:

1. `feature-dir/actions.md`: append the already-completed action at the end, in the `## Amendments` section (create the section if it does not exist, with the same table header as the phases: `ID | Description | Dependencies | Parallelism | Target file | Confidence | Status`). One table row per amendment, in the format:

   ```
   | E001 | <short description> | - | - | `<path>` | 🟢 | `[X]` |
   ```

   The action is born closed. Never leave a `[ ]` behind, or `/reversa-sync` starts warning about work that is already finished and `/reversa-forward` classifies the feature as `coding-in-progress` again
2. `feature-dir/legacy-impact.md`: append the new rows to the affected-files table, using the same vocabulary as `/reversa-coding` (`rule-changed`, `rule-new`, `component-new`, ...) and a severity aligned with `/reversa-audit`. Append, never rewrite the file
3. `feature-dir/progress.jsonl`: append one line per amendment, append-only:

   ```json
   {"ts":"2026-05-05T16:30:00Z","action":"E001","status":"done","files":["src/x/y.js"]}
   ```

If the amendment touched a 🟢 rule in `_reversa_sdd/domain.md`, also append the corresponding watch item to `feature-dir/regression-watch.md`, continuing the existing `W001`, `W002`, ... numbering. If it did not, do not invent an item.

## Post-execution hooks

Apply `after-add` in the standard way.

## Final report to the user

1. The ID and summary of each applied amendment
2. Refused amendments, with the test that failed
3. The absolute paths of `requirements.md`, `actions.md`, `legacy-impact.md` and `progress.jsonl`
4. The code files touched

Finish with:

> Type **CONTINUE** to proceed with `/reversa-sync` (converging the delivery into the extraction), or call `/reversa-add` again for the next amendment.

## Absolute rule

**Never delete, modify or overwrite pre-existing files of the project beyond what the approved amendment requires.**
In the `_reversa_forward/` artifacts this skill is strictly additive: it appends a section, a table row and a log line. It never rewrites the body of `requirements.md`, never reorders `actions.md`, never rewrites the whole `legacy-impact.md`. The extraction artifacts in `_reversa_sdd/` are read-only here; converging is `/reversa-sync`'s job.
