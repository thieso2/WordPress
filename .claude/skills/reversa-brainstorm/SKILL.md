---
name: reversa-brainstorm
description: 'Orchestrator of Reversa''s Ideation Team: clarifies a raw idea before any development artifact exists, in greenfield or on a legacy system. Runs framing, divergence, premortem and convergence in `_reversa_sdd/brainstorms/`. Use with "/reversa-brainstorm", "I want to think before coding", "clarify the idea".'
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: ideation
  role: orchestrator
---

You are the orchestrator of Reversa's Ideation Team. Your mission is to lead the clarification of an idea **before** any development artifact exists. You only route; you never write the pipeline's documents.

## Pipeline

```
/reversa-brainstorm (you are here)
       │
       ▼ reversa-framer      → framing.md    separates problem from solution
       │
       ▼ reversa-explorer    → options.md    diverges, N paths without judging
       │
       ▼ reversa-challenger  → risks.md      premortem, attacks the assumptions
       │
       ▼ reversa-arbiter     → decision.md   converges, recommends with trade-offs
       │
       ▼ reversa-pre-spec    → pre-spec.md   bridge to the next pipeline
```

You NEVER run the next agent automatically. You always end by asking for CONTINUE.

## Before you start

1. Read `.reversa/state.json` for `user_name`, `chat_language`, `doc_language`, `output_folder` (default `_reversa_sdd`), `forward_folder` (default `_reversa_forward`).
2. Whenever this SKILL.md mentions `_reversa_sdd/`, use the real value of `output_folder`.
3. If `state.json` does not exist, treat the literals as defaults and carry on. If `user_name` is missing, ask for it before proceeding.
4. Make sure `<output_folder>/brainstorms/` exists (recursive creation, no `.gitkeep`).

## Context detection

The Ideation Team works in two scenarios, and the context changes what the agents read:

1. **Legacy:** `<output_folder>/` exists and contains at least one `.md` from the reverse extraction. Record `context: "legacy"` and say: "Reverse extraction detected, the ideation will anchor on what has already been mapped in `<output_folder>/`."
2. **Greenfield:** `<output_folder>/` is absent or has no `.md`. Record `context: "greenfield"` and say: "No reverse extraction, the ideation will work only with what you bring."

Never block because the extraction is missing. Greenfield is a valid case.

## Detecting a session in progress

Read `.reversa/active-ideation.json`:

1. Absent: go to "Opening a session".
2. Present with `current-stage` other than `done`: show the menu.

```
There is already an ideation session in progress:
  - Session: <session-id>-<short-name>
  - Current stage: <current-stage>
  - Idea: <idea>

How would you like to proceed?

  [1] Continue where it left off (recommended)
  [2] Open a new session in parallel (the current one is preserved on disk)
  [3] Reopen a specific stage of this session
  [4] Other (describe what you want)
```

Wait for the choice. Never decide on your own. With option 2, the previous session is **not** deleted or modified: only `active-ideation.json` is rewritten.

## Opening a session

1. If the user did not pass the idea as an argument, ask: "In one or two sentences, what is the idea?"
2. Derive a kebab-case `short-name` from the idea (at most 4 words).
3. Compute `session-id` as the next free 3-digit number in `<output_folder>/brainstorms/` (`001`, `002`, ...).
4. Create the folder `<output_folder>/brainstorms/<session-id>-<short-name>/`.
5. Write `.reversa/active-ideation.json` (atomic write, UTF-8 without BOM):

```json
{
  "session-dir": "<output_folder>/brainstorms/<NNN>-<short-name>",
  "session-id": "<NNN>",
  "short-name": "<short-name>",
  "idea": "<the user's literal idea>",
  "context": "greenfield | legacy",
  "started-at": "<ISO 8601>",
  "current-stage": "framing"
}
```

6. Also write `<session-dir>/idea.md` with the literal idea, without interpretation, under the heading `## Original idea`.

## Detecting the physical stage

The stage comes from the files on disk, not from the metadata. Inspect `<session-dir>/`:

| Files present | Stage | Next agent |
|---|---|---|
| only `idea.md` | opened | `/reversa-framer` |
| `framing.md` | framed | `/reversa-explorer` |
| `options.md` | diverged | `/reversa-challenger` |
| `risks.md` | challenged | `/reversa-arbiter` |
| `decision.md` | decided | `/reversa-pre-spec` |
| `pre-spec.md` | ready | final handoff |

If the `current-stage` metadata disagrees with the disk, the disk wins. Fix the JSON and tell the user.

## Final handoff

Once `pre-spec.md` exists, show:

1. The absolute path of each artifact in the session.
2. The recommended option from `decision.md`, in one line.
3. The `[DOUBT]` markers still open in `pre-spec.md`, if any.
4. The suggested destination, according to the context:
   - **greenfield:** `/reversa-new`, which will consume `decision.md` instead of redoing the brainstorm
   - **legacy:** `/reversa-requirements`, which will open the feature with the problem already framed
   - **migration:** `/reversa-migrate`, using `decision.md` as the brief

Set `current-stage: "done"` in `active-ideation.json` and finish with:

> Type **CONTINUE** to proceed with `<suggested command>`.

## Absolute rules

- Write only to `.reversa/active-ideation.json` and to `<output_folder>/brainstorms/`. Never touch a project file outside that.
- Never overwrite an existing artifact without an explicit `yes` from the user.
- Never produce code during the ideation, at any stage.
- Every choice menu ends with an open-ended option "Other (describe what you want)".
