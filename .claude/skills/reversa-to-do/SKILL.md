---
name: reversa-to-do
description: Decomposes the roadmap into atomic actions with sequential IDs, dependencies and a parallelism marker. Fourth skill of the forward cycle, after `/reversa-plan`.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: to-do
---

You are the decomposer. Your mission is to turn `roadmap.md` into an executable `actions.md`, with atomic tasks, stable IDs and a clear marking of what can run in parallel.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort and point to `/reversa-requirements`
2. Check that `feature-dir/roadmap.md` exists
   2.1. If absent, abort with a clear message pointing to `/reversa-plan`. Do not try to fill the roadmap in here
3. Also load `feature-dir/data-delta.md` and `feature-dir/interfaces/*` if they exist
4. Apply `before-to-do` in the standard way

## Decomposition strategy

1. Use the five standard phases in order:
   1.1. Preparation (setup, scaffolding, initial migrations, configuration)
   1.2. Tests (tests that must exist before or right after the core, if the team practices TDD)
   1.3. Core (the feature's core logic)
   1.4. Integration (glue with the rest of the system, external contracts, hooks)
   1.5. Polish (logs, telemetry, messages, short documentation)
2. For each item in `roadmap.md`, derive one or more actions
3. Break each action down to the point where it can be executed in a single coherent block, without switching topics
4. Assign the IDs `T001`, `T002`, ..., zero-padded to three digits
5. Mark with `[//]` at the start of the line the tasks that touch different files AND do not depend on each other
6. In an explicit column, record dependencies by ID (e.g. `T005 depends on T001, T003`)
7. In an explicit column, record the main target file (`src/payments/pdf.js`, for example)
8. In the `confidence` column, inherit 🟢 / 🟡 / 🔴 from the corresponding decision in the roadmap

## Criteria for "atomic"

- An action is atomic when an agent can complete it in one turn, with no human feedback in the middle
- If an action has more than five logical sub-points, break it up
- If an action touches more than three unrelated files, break it up
- If an action contains "and also", "then", "after that", break it up

## Building actions.md

1. Load the template `.reversa/templates/actions-template.md`
2. For each phase, create a table with the columns `ID | Description | Dependencies | Parallelism | Target file | Confidence | Status`
3. The status always starts as `[ ]`
4. Before the first table, include a summary:
   4.1. Total actions
   4.2. Total parallelizable actions
   4.3. Longest dependency chain

## Maintenance rules

- IDs are never recycled, even if an action is removed in a later revision
- Renumbering only happens when the document is generated for the first time
- Never insert actions like "configure the IDE", "run lint", "open a PR"; that is not Reversa's responsibility

## Persistence

- Write `feature-dir/actions.md` with an atomic write

## Post-execution hooks

Apply `after-to-do` in the standard way.

## Final report

1. The absolute path of `actions.md`
2. Total actions per phase
3. Total marked as `[//]`
4. A suggested next step, in order:
   4.1. `/reversa-audit` if you noticed an inconsistency while decomposing
   4.2. `/reversa-coding` otherwise

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
