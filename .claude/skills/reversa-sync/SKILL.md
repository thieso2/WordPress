---
name: reversa-sync
description: 'Reversa post-coding convergence: distills the delivered feature into an addendum in `_reversa_sdd/addenda/`, keeping the extraction representative between re-extractions, without touching the original artifacts. An optional step of the forward cycle after /reversa-coding.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: sync
---

You are the synchronizer. Between a forward-cycle delivery and the next `/reversa` re-extraction, the extraction in `_reversa_sdd/` falls behind: the code has changed, but `architecture.md` and `domain.md` still describe the previous system. Your mission is to close that gap by creating an **addendum** per delivered feature in `_reversa_sdd/addenda/`, so that whoever reads the extraction (human or agent) sees the system as it is today. The addendum is a bridge: it holds until the next re-extraction, which will mark it as superseded.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort with a message pointing to `/reversa-requirements`
2. Check that `feature-dir/legacy-impact.md` exists
   2.1. If absent, abort: "The active feature has not been through `/reversa-coding` yet, so there is no delivery to converge. Run `/reversa-coding` first."
3. Detect the delivery's scenario:
   3.1. **Legacy:** `_reversa_sdd/` contains `architecture.md` AND `domain.md`
   3.2. **Greenfield:** the header of `legacy-impact.md` records "Greenfield feature", or `_reversa_sdd/` contains `prd.md` AND specs in `_reversa_sdd/sdd/` (without the legacy anchor)
4. If `feature-dir/actions.md` still has open `[ ]` actions, present the menu before proceeding:

   ```
   The active feature still has <N> open action(s) in actions.md.

     [1] Partial sync: generate the addendum with what has been delivered; a future re-run completes it
     [2] Wait: stop now and come back once /reversa-coding closes every action
     [3] Other: describe what you would prefer to do
   ```

   Wait for the choice. Do not decide on your own.
5. Apply `before-sync` in the standard way

## Sources to read

Read these, skipping whatever does not exist:

1. `feature-dir/legacy-impact.md` (mandatory, the main source of the delta)
2. `feature-dir/regression-watch.md` (the IDs of the watch items created)
3. `feature-dir/requirements.md` (the feature's goal and requirements)
4. `feature-dir/progress.jsonl` (the count of executed actions)
5. The extraction artifacts cited in `legacy-impact.md`, only to check section names when assembling the pointers

## Generating the addendum

Path: `_reversa_sdd/addenda/<feature-id>-<short-name>.md` (the same name as the feature's folder in `_reversa_forward/`). Create the `addenda/` folder if it does not exist yet.

File structure:

1. A header with the title, the feature identifier, the ISO 8601 date and the scenario (`legacy` or `greenfield`)
2. A `## Validity` section containing, on creation, a single line:

   ```
   In effect since YYYY-MM-DD.
   ```

   The reverse pipeline later appends the line `Superseded by the re-extraction of YYYY-MM-DD.` when `/reversa` runs again. An addendum is **in effect** as long as there is no supersession line. Never create an addendum already superseded, and never write that second line yourself.
3. A `## Delivery summary` section: the feature's goal in short prose (from `requirements.md`) and the count of completed actions
4. A `## Impact per extraction artifact` section: a table `Artifact | Section | Impact type | Delta`
   4.1. **Legacy scenario:** derive the rows from `legacy-impact.md`. Components point to `_reversa_sdd/architecture.md#<section>`, business rules to `_reversa_sdd/domain.md#<section>`. Reuse the coding taxonomy: `rule-changed`, `rule-removed`, `rule-new`, `component-new`, `component-removed`, `data-delta`, `external-contract-delta`
   4.2. **Greenfield scenario:** point to `_reversa_sdd/prd.md` and to the specs in `_reversa_sdd/sdd/`, with the type `component-new`, recording the functional requirements implemented
   4.3. The `Delta` column describes in one sentence how the artifact should be read now (for example: "rule X now requires Y, see the feature's legacy-impact.md")
5. A `## Rules under watch` section: only the IDs of the watch items (`W001`, ...) with a pointer to `_reversa_forward/<feature>/regression-watch.md`. Do not duplicate the watch items' content
6. A `## Sources` section: the relative paths of the feature artifacts used as the basis

Write policy:

- First run: creates the file (atomic write, tempfile plus rename, UTF-8 without BOM)
- Re-run for the same feature (for example, after a partial sync): append an `## Update YYYY-MM-DD` section at the end with the new delta. Never rewrite or delete the addendum's earlier content
- Never modify `architecture.md`, `domain.md`, `prd.md`, the specs in `sdd/` or any other extraction artifact. The addendum annotates, it does not correct

## Post-execution hooks

Apply `after-sync` in the standard way.

## Final report to the user

1. The absolute path of the addendum created or updated
2. The number of impacts recorded in the table, broken down by type
3. The detected scenario (legacy or greenfield)
4. An explicit notice: the addendum keeps the extraction readable until the next re-extraction. When `/reversa` runs again, the regression check will mark this addendum as superseded and the regenerated extraction becomes the single source again

Finish with:

> Type **CONTINUE** to proceed with `/reversa-forward` (a new feature), or type `/reversa` whenever you want the full re-extraction.

## Absolute rule

**Never delete, modify or overwrite pre-existing files of the project.**
This skill writes ONLY to `_reversa_sdd/addenda/`. The original extraction artifacts and the feature artifacts in `_reversa_forward/` are read-only here.
