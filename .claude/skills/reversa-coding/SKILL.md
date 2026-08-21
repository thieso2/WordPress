---
name: reversa-coding
description: 'Turns actions.md into code: ticks the [X] checkboxes, writes progress.jsonl and generates legacy-impact.md and regression-watch.md. Works anchored to the legacy system (`_reversa_sdd/`) or greenfield (`/reversa-new`). The last step of the forward cycle.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: coding
---

You are the executor. Your mission is to turn `actions.md` into real code, phase by phase, respecting parallelism and dependencies. When you finish, leave two trails for future auditing: `legacy-impact.md` (what was touched in the legacy system) and `regression-watch.md` (what must remain true in the next extractions).

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Context anchor: legacy or greenfield

This skill **REQUIRES** a context anchor in `_reversa_sdd/`; otherwise the two central artifacts (`legacy-impact.md` and `regression-watch.md`) lose their value and the forward cycle becomes just another generic framework. Two anchors are valid:

1. **Legacy:** `_reversa_sdd/` contains `architecture.md` AND `domain.md` (an extraction by the Discovery Team via `/reversa`). The classic behavior.
2. **Greenfield:** `_reversa_sdd/` contains `prd.md` AND at least one spec in `_reversa_sdd/sdd/` (artifacts from `/reversa-new`). A new project is a valid case; the pipeline does not block because the extraction is missing. The skill's artifacts adapt as described in the generation sections.

If both anchors exist (a project that ran `/reversa` and `/reversa-new`), use the legacy one as the primary and the SDD specs as a complement.

The check stays strict when NO anchor exists: the skill aborts with a clear message, does NOT offer to proceed anyway, and does NOT write anything to disk.

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort with a message pointing to `/reversa-requirements`
2. Check that `feature-dir/actions.md` exists
   2.1. If absent, abort with a message pointing to `/reversa-to-do`
3. Check the context anchor:
   3.1. **Legacy anchor:** `_reversa_sdd/` exists AND contains `architecture.md` AND `domain.md`. If satisfied, record the scenario internally as **legacy** and go to step 4.
   3.2. **Greenfield anchor:** `_reversa_sdd/` exists AND contains `prd.md` AND at least one `.md` file in `_reversa_sdd/sdd/`. If satisfied (and the legacy one is not), record the scenario as **greenfield**, tell the user ("No legacy extraction; I'll anchor on the `/reversa-new` artifacts: `prd.md` and the SDD specs.") and go to step 4.
   3.3. If NEITHER anchor is satisfied, abort with the message:

       > 🛑 `/reversa-coding` needs a context anchor in `_reversa_sdd/` and I found none:
       >
       > - **Legacy:** `architecture.md` + `domain.md` (generate them with `/reversa`)
       > - **Greenfield:** `prd.md` + specs in `sdd/` (generate them with `/reversa-new`)
       >
       > Without that context, `legacy-impact.md` and `regression-watch.md` would have no anchor and the forward cycle would lose its edge. Run one of the two pipelines and come back here.

   3.4. In the case of step 3.3, do NOT create `legacy-impact.md`, do NOT create `regression-watch.md`, do NOT touch `actions.md`, do NOT write `progress.jsonl`. Just report and stop.

4. Apply `before-coding` in the standard way

## Scope of this round

1. If the free argument names a phase or an ID range (e.g. "Core only", "T001-T005"), restrict the execution to that scope
2. Otherwise, run every `[ ]` action that is not yet done, in order

## Execution loop per phase

For each phase, in the order Preparation, Tests, Core, Integration, Polish:

1. Select every action in the phase with status `[ ]`
2. Compute the independent set (actions with no open dependency)
3. Within the independent set, identify the subset marked `[//]`
   3.1. Run that subset treating each action as a coherent block, but report them separately
4. Run the remaining actions in the set sequentially
5. After each action:
   5.1. Update `feature-dir/actions.md`, changing `[ ]` to `[X]`
   5.2. Write a line in `feature-dir/progress.jsonl` with an ISO 8601 timestamp, the action's ID, the final status and the files touched
6. If an action fails:
   6.1. Leave `[ ]` in the actions file
   6.2. Record `status: failed` in the progress file
   6.3. Stop the phase and report to the user

## Generating legacy-impact.md

After running (even partially):

**Greenfield scenario:** there is no legacy system to impact. Generate the file anyway, with adaptations: map each created file to the corresponding component in the specs under `_reversa_sdd/sdd/` (instead of `architecture.md`), use the impact type `component-new` for everything, and record in the header: "Greenfield feature, no pre-existing legacy system. Anchor: prd.md + SDD specs." The "Preserved" and "Modified" sections stay empty with that note. Skip steps 4 and 5 below.

**Legacy scenario:**

1. For each project file touched, map it to the corresponding component in `_reversa_sdd/architecture.md` where possible
2. For each affected component, classify the impact type: `rule-changed`, `rule-removed`, `rule-new`, `component-new`, `component-removed`, `data-delta`, `external-contract-delta`
3. Assign a severity aligned with `/reversa-audit` (CRITICAL, HIGH, MEDIUM, LOW)
4. List the 🟢 rules in `_reversa_sdd/domain.md` that remain intact (they go in the "Preserved" section)
5. List the 🟢 rules that were changed or removed (they go in the "Modified" section)

File structure:

1. A header with the date and the feature's identifier
2. A table `Affected file | Component | Type | Severity | Rationale`
3. A conceptual diff per component, in prose
4. A "Preserved" section
5. A "Modified" section

Write it to `feature-dir/legacy-impact.md` with an atomic write, as a full rewrite.

## Generating regression-watch.md

**Greenfield scenario:** there are no 🟢 rules to watch (nothing has been extracted from existing code yet). Generate the file with the standard structure, an empty main watch table, and record the implemented FRs (from the SDD specs) in the "Notes" section, with no regression weight. They gain weight when a future `/reversa` extraction over the new code confirms them as 🟢. Skip steps 1 to 4 below (step 5, stable IDs, still applies to the notes).

**Legacy scenario:**

1. For each rule in the "Modified" section of `legacy-impact.md`, generate a watch item
2. For rules explicitly removed, generate a watch item of type `absence`
3. For rules that changed, generate a watch item of type `wording` or `presence`, as appropriate
4. For rules whose confidence was lowered, generate a watch item of type `confidence`
5. Assign a stable ID `W001`, `W002`, ..., reusing the file's existing IDs if it already exists

Structure:

1. A header with the feature's identifier
2. A table `ID | Source (file, section) | Expected rule after change | Verification type | Violation signal`
3. A "Re-extraction history" section, initially empty; it will be filled in by the reverse agent when `/reversa` runs again
4. An "Archived" section, initially empty

NEVER put rules that were originally 🟡 or 🔴 in the main watch table; those go in a "Notes" section with no regression weight.

Write it to `feature-dir/regression-watch.md`. The first run creates the file; later runs append new items to the sections, never rewriting the history or the old IDs.

## Updating progress.jsonl

Each line must have, at minimum:

```json
{"ts":"2026-05-05T16:30:00Z","action":"T003","status":"done","files":["src/x/y.js"]}
```

Append-only. Never rewrite earlier lines, even if you discover they were wrong. To correct one, add a new line with `status: corrected` and the target ID.

## Post-execution hooks

Apply `after-coding` in the standard way.

## Final report to the user

1. How many actions ran successfully
2. How many failed (if any)
3. The absolute paths of `actions.md`, `progress.jsonl`, `legacy-impact.md`, `regression-watch.md`
4. How many watch items were created in this round
5. An explicit notice: run `/reversa-sync` to converge the delivery into `_reversa_sdd/addenda/`, and keep in mind running `/reversa` (a re-extraction) again at some future point to close the cycle
6. If the run was partial, name the next pending phase or action

NEVER trigger the re-extraction on your own; that is the user's decision.

Finish with:

> Type **CONTINUE** to proceed with `/reversa-sync` (converging the delivery into the extraction) or whatever else you want to do.
