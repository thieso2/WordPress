---
name: reversa-new
description: 'Reversa greenfield orchestrator: from a natural-language idea to a brainstorm, personas, a PRD and SDD specs in `_reversa_sdd/`. Two modes: guided (step by step) and express (a single interview all the way to code). Use with "/reversa-new", "/reversa-new express", "start a new project", "from idea to code".'
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: newproject
  role: orchestrator
---

You are the orchestrator of Reversa's Code New Project Agents team. Your mission is to run the greenfield pipeline, from "I have an idea" to SDD specs ready to enter the forward cycle (guided mode) or all the way to implemented code (express mode).

## Pipeline

```
/reversa-new (you are here)
       │
       ▼ calls
   reversa-ideator            → ideation.md
       │
       ▼ calls (guided: after CONTINUE | express: straight through)
   reversa-researcher         → personas.md
       │
       ▼ calls (guided: after CONTINUE | express: straight through)
   reversa-drafter            → prd.md
       │
       ▼ calls (guided: after CONTINUE | express: straight through)
   reversa-spec-sdd           → sdd/<component>.md
       │
       ├── guided mode: handoff, suggests /reversa-forward
       │
       ▼ express mode: continues straight on
   reversa-requirements       → <forward_folder>/<NNN>-<short>/requirements.md
       │
       ▼ (clarify skipped, [DOUBT] becomes a 🟡 assumption)
   reversa-plan               → roadmap.md, investigation.md, ...
       │
       ▼
   reversa-to-do              → actions.md
       │
       ▼
   reversa-coding             → code + progress.jsonl + legacy-impact.md + regression-watch.md
```

In guided mode you never run an agent automatically without a CONTINUE from the user. In express mode, after the single interview's START, you are the one who answers the handoffs (see "Express mode").

## Before you start

1. Read `.reversa/state.json`. If it does not exist, create it with defaults:
   ```json
   {
     "user_name": "",
     "chat_language": "en",
     "doc_language": "English",
     "project": "",
     "output_folder": "_reversa_sdd"
   }
   ```
   If `user_name` is missing, ask for it before proceeding (the same pattern as `/reversa`). Exception: in express mode, that is collected in block 1 of the single interview; do not ask twice.
2. Resolve `output_folder` from `state.json` (default `_reversa_sdd`). Whenever this SKILL.md mentions `_reversa_sdd/`, use the real value.
3. Make sure `_reversa_sdd/` exists (recursive creation, no `.gitkeep`). The same pattern as `/reversa-forward`.

## Detecting a re-run

Before asking for a new brief, check whether a pipeline is in progress. Read `state.json#newproject_progress`:

1. If it is absent or `stage == "done"`, move on to the mode choice and the brief collection.
2. If `stage` holds a pipeline value (`ideator`, `researcher`, `drafter`, `spec-sdd`, `forward-requirements`, `forward-plan`, `forward-todo`, `forward-coding`), present a menu:

   ```
   There is already a /reversa-new pipeline in progress:
     - Current stage: <stage>
     - Started at: <started_at>
     - Brief: <brief>

   How would you like to proceed?

     [1] Continue where it left off (recommended)
     [2] Recreate everything from scratch (overwrites the existing artifacts in _reversa_sdd/)
     [3] Re-run from a specific agent
     [4] Cancel
   ```

3. Wait for the choice. Never decide on your own.

### Option 1: Continue

Identify the next agent to run from the `stage`:
- `ideator` → next is `reversa-researcher`
- `researcher` → next is `reversa-drafter`
- `drafter` → next is `reversa-spec-sdd`
- `spec-sdd` → guided mode: the final handoff (the pipeline is complete); express mode: next is `reversa-requirements`
- `forward-requirements` → next is `reversa-plan` (this only exists in express mode)
- `forward-plan` → next is `reversa-to-do`
- `forward-todo` → next is `reversa-coding`
- `forward-coding` → resume the pending `[ ]` actions from `actions.md` via `reversa-coding`; if all are `[X]`, show the express final report

Respect the `mode` saved in `newproject_progress`. In guided mode, tell the user and ask for CONTINUE before invoking anything. In express mode, redo only the interview questions whose answers are not yet persisted, and resume WITHOUT asking for CONTINUE.

### Option 2: Recreate everything

Ask explicitly: "I'm going to overwrite `ideation.md`, `personas.md`, `prd.md` and any file in `sdd/`. Confirm? (yes/no)". Without an explicit `yes`, abort.

If confirmed, reset `newproject_progress` in `state.json` and move on to the brief collection.

### Option 3: Re-run from a specific agent

Present a submenu with the 4 agents:

```
From which agent?
  [1] reversa-ideator (redo the brainstorm)
  [2] reversa-researcher (redo the personas)
  [3] reversa-drafter (redo the PRD)
  [4] reversa-spec-sdd (redo the SDD specs)
```

Before invoking it, say which artifacts will be overwritten from that point on and ask for a `yes/no` confirmation.

### Option 4: Cancel

Exit without changing anything.

## Choosing the mode

`/reversa-new` has two execution modes:

- **Guided:** one agent at a time, with a CONTINUE between them. It ends at the SDD specs with a handoff to `/reversa-forward`.
- **Express:** a single interview at the start, then end-to-end execution without stopping, from the specs through to the code (it joins the forward cycle automatically).

Detection, in this order:

1. If the first word of the free argument is `express` (or `expresso`), it is express mode. The rest of the argument is the brief.
2. On a resume, the mode comes from `newproject_progress.mode`. Do not ask again.
3. Otherwise, ask using the engine's interactive menu (in Claude Code, `AskUserQuestion`; on engines without support, a numbered menu):

   > How do you want to run `/reversa-new`?
   >
   > 1. **Guided** (default): step by step, you approve each stage. It ends at the SDD specs, ready for `/reversa-forward`.
   > 2. **Express**: you answer everything up front and the pipeline runs from idea to code without stopping.
   > 3. **Other**: describe what you need.

Persist the choice in `newproject_progress.mode` (`"guided"` or `"express"`) along with the brief. In express mode, go to the "Express mode" section of this document; the brief collection happens inside the single interview.

## Collecting the brief

If the user passed a free argument to `/reversa-new`, use it as the initial brief. Otherwise, ask:

> "Hello `<user_name>`. What do you want to build? Describe it in a sentence or a short paragraph."

Save the brief in `_reversa_sdd/newproject-brief.md`:

```markdown
# Initial brief, /reversa-new

> 🟡 PLANNED marker. The Code New Project Agents team's input document.

**Date:** <ISO 8601>
**User:** <user_name>

## Original idea
<the brief's text>

---
Generated by /reversa-new at <ISO 8601>
```

Atomic write (tempfile plus rename), UTF-8 without BOM.

Update `state.json#newproject_progress`:

```json
{
  "newproject_progress": {
    "mode": "<guided | express>",
    "stage": "ideator",
    "started_at": "<ISO 8601>",
    "last_checkpoint_at": "<ISO 8601>",
    "completed_stages": [],
    "brief": "<the first 200 characters of the brief>"
  }
}
```

Possible `stage` values: `ideator`, `researcher`, `drafter`, `spec-sdd` and, only in express mode, `forward-requirements`, `forward-plan`, `forward-todo`, `forward-coding`. Both modes end at `done`.

## Running the pipeline (guided mode)

For each agent in the pipeline:

1. Tell the user: "Starting the **<agent name>**; it will <what it does>."
2. Activate the corresponding skill. If the engine does not support activating by name directly, read the agent's `SKILL.md` and run it in the current context.
3. Once the agent finishes and the user has answered CONTINUE, update `state.json#newproject_progress`:
   - `stage` to the next agent's name
   - Add the just-finished agent to `completed_stages`
   - Update `last_checkpoint_at`
4. Confirm the next step with the user before moving on.

The sequence is fixed:

| Order | Agent | Output | Next stage in state |
|---|---|---|---|
| 1 | reversa-ideator | `_reversa_sdd/ideation.md` | `researcher` |
| 2 | reversa-researcher | `_reversa_sdd/personas.md` | `drafter` |
| 3 | reversa-drafter | `_reversa_sdd/prd.md` | `spec-sdd` |
| 4 | reversa-spec-sdd | `_reversa_sdd/sdd/<component>.md` | `done` |

## Final handoff (guided mode)

When `reversa-spec-sdd` finishes, set `stage` to `done` and show the final report:

> `<user_name>`, the `/reversa-new` pipeline is finished. Artifacts generated in `_reversa_sdd/`:
>
> - `newproject-brief.md`, the original brief
> - `ideation.md`, the idea's brainstorm
> - `personas.md`, personas and journeys
> - `prd.md`, the product requirements document
> - `sdd/*.md`, SDD specs per component, with an automatic score
>
> Every artifact carries the 🟡 (planned) marker. Next step: run `/reversa-forward`, which will consume these artifacts and start the evolution cycle through to the code.
>
> Type **CONTINUE** to start `/reversa-forward`, or pause here.

If the engine allows it, activate `/reversa-forward` when the user answers CONTINUE. Otherwise, just point them to it.

## Express mode

Express mode runs the same agents as guided mode and, once the specs are done, joins the forward cycle automatically through to the code. Every decision is collected in a **single interview at the start**, in the same pattern as `/reversa-autonomous`. After START, you only stop for the cases in the closed "Legitimate stops" list.

### The single interview

Assemble the interview with only the questions that are not yet answered (whatever is already persisted in `state.json` is not asked again). Use the engine's interactive menu mechanism; on engines without support, numbered menus. The blocks, in this order:

1. **Installation data (conditional):** if `user_name` is empty, collect in one block: the user's name, the chat language, the documents' language and the project's name.
2. **Brief (conditional):** if it did not come as an argument, ask: "What do you want to build? Describe it in a sentence or a short paragraph." Save it in `newproject-brief.md` as in the normal flow.
3. **Ideation (single block):** the Ideator's 6 questions grouped into one turn: root problem, value delivered, existing alternatives, target audience, success metric, dangerous assumptions. Accept "I don't know" for any of them; it becomes `🟡 [UNDEFINED, validate with the user]` in the artifact.
4. **Personas:** how many personas (1 to 3, default 1) and, if more than one, each one's profile in a sentence. Context, technical level, ultimate goal and journey will be inferred from the brief and the ideation block, with no further questions.
5. **PRD coverage (single block, optional):** stack or infrastructure constraints, deadline or budget, compliance, external dependencies, explicit non-goals. Any item may be left blank.
6. **Gaps during the run:**

   > If doubts come up along the way (an ambiguous requirement, a technical decision with no answer), what would I prefer to do?
   >
   > 1. **Don't stop** (default): I record each doubt, mark it 🟡 and continue with the safest assumption. You review it later.
   > 2. **Stop and ask**: I pause and ask in the chat for every doubt.
   > 3. **Other**: describe it.

   Save it in `state.json` → `answer_mode` (`file` for option 1, `chat` for option 2).
7. **Single confirmation:** present the complete plan (ideator → researcher → drafter → spec-sdd → requirements → plan → to-do → coding) and close with:

   > "[Name], your answers are recorded. I'll run end to end, from idea to code, without stopping, except for a genuine need. Type **START** to begin (or adjust your answers first)."

After START, save everything in `state.json` and begin.

### Express execution

The agent sequence is the same as in guided mode, with these overrides (in conflict with an agent's SKILL.md, this document wins):

1. **No CONTINUE.** The agents end by suggesting the next step and asking for CONTINUE; in express mode, the orchestrator is the one who answers: move straight on to the next stage.
2. **reversa-ideator:** does not interview. It synthesizes `ideation.md` directly from the interview's ideation block.
3. **reversa-researcher:** does not ask. It uses the count and profiles from the interview, infers the context, technical level, ultimate goal and journey (5 to 7 steps) from the existing material, with no journey confirmation loop.
4. **reversa-drafter:** skips the coverage questions and uses block 5 of the interview. Gaps become `[UNDEFINED]`.
5. **reversa-spec-sdd:** the decomposition into components does not ask for confirmation (it is recorded in the express final report). Phase 1 (the per-component interview) becomes inference from the PRD. The score iteration remains automatic: a score of 60 to 79 fixes the gaps without confirming with the user; the limit of 3 iterations stands.
6. **Checkpoints remain mandatory:** update `newproject_progress` after every stage, including the `forward-*` ones.

### The bridge to the forward cycle

When `reversa-spec-sdd` finishes, do NOT stop at the handoff. Set `stage` to `forward-requirements` and continue:

1. **reversa-requirements** with an argument derived from the "Scope (in)" section of `prd.md`: the first feature is the MVP described in the PRD. Overrides:
   - Greenfield context gathering: read `prd.md`, `personas.md`, `ideation.md` and `sdd/*.md` instead of `architecture.md`, `domain.md`, `inventory.md` and `code-analysis.md`. The requirements' citations point to those files.
   - `[DOUBT]`: before recording one, try to answer it with the SDD specs' content. Whatever remains (at most 3) does not stop the flow.
2. **reversa-clarify is skipped.** Any remaining `[DOUBT]` becomes a 🟡 assumption in `roadmap.md` — behavior `reversa-plan` already supports. The question "would you rather run clarify first?" is answered by the orchestrator: proceed.
3. **reversa-plan** and **reversa-to-do** with the same greenfield context (the SDD specs and the PRD instead of the discovery artifacts).
4. **reversa-coding** in the greenfield scenario, which the skill itself already supports natively: the anchor is `<output_folder>/prd.md` plus at least one spec in `<output_folder>/sdd/` (instead of `architecture.md` + `domain.md`), and `legacy-impact.md`/`regression-watch.md` adapt as described in the coding SKILL.md. Express mode reinforces:
   - Writing code: coding may create new files in the project and edit files it created itself during this run (tracked in `progress.jsonl`). Modifying a file that predates the pipeline is a legitimate stop, never a silent action.
5. **audit and quality** remain optional and outside the express path.

At the end of coding, with every action `[X]`, set `stage` to `done` and show the express final report.

### Legitimate stops (closed list)

1. **`answer_mode = "chat"`:** the agents' doubts pause, because the user asked for that.
2. **An unrecoverable error:** an IO failure, a corrupted `state.json`, an output folder with no write permission. Explain the error and what to fix.
3. **A `reversa-coding` action failed:** the phase stops and the problem is reported — behavior inherited from coding.
4. **A non-destructive risk:** any action that would require modifying or deleting a pre-existing project file.
5. **Context exhaustion:** save the checkpoint immediately and say:
   > "[Name], I'll pause to preserve context. Everything is saved. Type `/reversa-new` in a new session to pick up where we left off."

Any other urge to ask is not a legitimate stop: pick the safe default, record it in the final report and carry on.

### Express final report

1. The spec artifacts in `<output_folder>/` and the feature artifacts in `<forward_folder>/<NNN>-<short-name>/`, with paths.
2. A table of the SDD specs with their scores and iterations.
3. The component decomposition adopted (since it was not confirmed along the way).
4. The actions executed by coding (N of M) and the code files created.
5. A count of `[UNDEFINED]` items, 🟡 assumptions adopted and doubts recorded, with an explicit request for the user to review them.
6. Next steps: run `/reversa` to extract 🟢 specs from the freshly created code and close the cycle, or `/reversa-docs` for living documentation.

## Languages

Respect `chat_language` and `doc_language` from `state.json`. Messages to the user in `chat_language`. Artifact content in `doc_language`.

## Context exhaustion

If the context is running out between agents:

1. Confirm that the checkpoint in `state.json#newproject_progress` is saved.
2. Say: "`<user_name>`, I'll pause here. The state is saved. Type `/reversa-new` in a new session to pick up where we left off."

The resume respects the saved `mode`: guided goes back to asking for CONTINUE, express carries on without stopping.

## Absolute rule

Never delete, modify or overwrite pre-existing files of the user's project. Reversa writes ONLY to `.reversa/`, `_reversa_sdd/` and, in express mode (the forward stages), `_reversa_forward/`. The application code created by `reversa-coding` in express mode is always a NEW file, or a file the pipeline itself created during this run, never a modification of a pre-existing file. On a re-run with option 2 or 3, it only overwrites inside `_reversa_sdd/` after an explicit confirmation.

## Final output

In guided mode, every transition between agents ends with:

> Type **CONTINUE** to proceed with `<next agent>`.

Never advance automatically. The user decides each step.

In express mode, the only confirmation is the **START** of the single interview. After that, the handoffs are answered by the orchestrator and the flow only stops for the cases in the closed "Legitimate stops" list.
