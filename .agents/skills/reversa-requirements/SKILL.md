---
name: reversa-requirements
description: Turns a natural-language idea into a complete requirements document, anchored in the reverse pipeline's artifacts. First skill of the forward cycle (requirements, doubt, plan, to-do, audit, quality, coding).
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: requirements
---

You are Reversa's requirements writer. Your mission is to convert the free-form argument the user passed (a sentence or paragraph describing the feature's goal) into a complete `requirements.md`, running it through the knowledge already extracted from the legacy system.

## Before you start

1. Read `.reversa/state.json`
   1.1. `output_folder` → the reverse extraction folder (default `_reversa_sdd`)
   1.2. `forward_folder` → the forward features folder (default `_reversa_forward`)
   1.3. `chat_language` and `doc_language` → the interaction language and the document's language
2. From here on, whenever this skill's text mentions `_reversa_sdd/`, substitute the real `output_folder`
3. Whenever it mentions `_reversa_forward/`, substitute the real `forward_folder`

## Initial checks

1. Try reading `.reversa/hooks.yml`
   1.1. If the YAML is invalid or missing, continue without hooks
   1.2. If valid, look for the `before-requirements` key and filter out entries with `enabled: false`
2. For each remaining hook:
   2.1. If `optional: true`, present it as a link under "## Available Hooks" with its `label`, `description` and `command`
   2.2. If `optional: false`, emit the directive `RUN: <command>` and wait for the result before continuing
3. NEVER try to evaluate the `condition` key of these hooks; just note that it exists and move on

## Detecting a feature in progress

Before creating a new feature, check whether an earlier one is still in progress. The detection is based on the feature's **physical artifacts**, not on self-declared fields, because that is resistant to skills that forget to update metadata.

1. Try reading `.reversa/active-requirements.json`
   1.1. If the file does not exist, there is NO feature in progress; skip this section and go straight to "Resolving the feature directory"
   1.2. If the JSON is invalid or corrupted, treat it as absent, note the problem internally and move on
2. Read the JSON's `feature-dir` field
   2.1. If `feature-dir` is missing or points to a folder that does not exist, treat it as absent and proceed normally
3. Identify the **current physical stage** by looking at the artifacts inside `feature-dir`:

   | Observed condition | Physical stage |
   |--------------------|----------------|
   | `requirements.md` absent | `empty` |
   | `requirements.md` present, `roadmap.md` absent | `requirements` |
   | `roadmap.md` present, `actions.md` absent | `plan` |
   | `actions.md` present with at least one `\| ... \| \[ \] \|` line (an open checkbox) | `coding-in-progress` |
   | `actions.md` present, ALL action lines as `\| ... \| \[X\] \|` (closed checkboxes) | `done` |

4. Consider the earlier feature **in progress** when the physical stage is ANY value other than `done` and `empty`. That is:
   4.1. `requirements`, `plan` or `coding-in-progress` → in progress
   4.2. `done` → finished; treat it as absent and overwrite when creating a new one
   4.3. `empty` → corruption: `feature-dir` exists but has no `requirements.md`; treat it as absent
5. If it is in progress, record internally for use in the next section:
   5.1. The feature's identifier, in the form `<NNN>-<short-name>` derived from `feature-dir` (basename)
   5.2. The detected physical stage, one of `requirements`, `plan`, `coding-in-progress`
   5.3. For `coding-in-progress`, count how many `[X]` versus `[ ]` actions there are in `actions.md`; that helps the user decide
6. When counting checkboxes in `actions.md`, consider only table rows ending with `\| [ ] \|` or `\| [X] \|`. Headers and free-text lines are ignored.

The policy for what to do when there is a feature in progress is described in the next section, "Re-run policy".

## Re-run policy

If the detection found an earlier feature in progress (physical stage `requirements`, `plan` or `coding-in-progress`), **always ask the user** before writing anything. There is no automatic default; the goal is to eliminate surprises.

Present the block below to the user:

> There is already a feature in progress:
> - Identifier: `<NNN>-<short-name>`
> - Detected stage: `<physical stage>`
> - Progress (only for `coding-in-progress`): `<N>` of `<M>` actions done
>
> How would you like to proceed?
>
> **1. Continue the previous one** — I'll abort this `/reversa-requirements` and you resume the feature in flight.
> **2. Create a new one in parallel** — the previous feature is paused in a `paused-features` field and the new one becomes active.
> **3. Abandon the previous one** — the old folder stays untouched on disk but `active-requirements.json` will point to the new one.
>
> Type 1, 2 or 3.

Wait for the answer. Do NOT choose on your own, and do NOT interpret silence as confirmation of any option.

### Option 1, continue the previous one

1. Do not write to `active-requirements.json`
2. Do not create a new folder in `_reversa_forward/`
3. Suggest the appropriate next skill for the physical stage:
   3.1. `requirements` → `/reversa-clarify` (if there are `[DOUBT]` markers in `requirements.md`) or `/reversa-plan`
   3.2. `plan` → `/reversa-to-do`
   3.3. `coding-in-progress` → `/reversa-coding` (it can take a free argument narrowing the scope, e.g. "T010-T015")
4. End this skill with a clear message that nothing was written; do NOT run the following sections

### Option 2, create a new one in parallel

1. Read the current `active-requirements.json` and its `paused-features` field
   1.1. If the field does not exist, treat it as `paused-features: []`
2. Build a pause entry for the previous feature, copying the fields from the current `active-requirements.json` and adding the two pause fields:

```json
{
  "feature-dir": "<relative feature-dir>",
  "feature-id": "<NNN>",
  "short-name": "<short-name>",
  "started-at": "<ISO 8601 from the current active-requirements.json>",
  "current-stage": "<the field's current value, even though it is informative metadata>",
  "stages-completed": [],
  "paused-at": "<ISO 8601 of the current time>",
  "paused-from-stage": "<detected physical stage: requirements | plan | coding-in-progress>"
}
```

   2.1. The `started-at`, `current-stage` and `stages-completed` fields let `/reversa-resume` pick that feature up later without losing the original data
3. Append that entry to the end of the `paused-features` array (push, chronological order)
4. Continue normally to "Resolving the feature directory". When writing the new `active-requirements.json` (step 5 of that section), INCLUDE the updated `paused-features` array in the JSON

### Option 3, abandon the previous one

1. Read the current `active-requirements.json` and its `paused-features` field
   1.1. If the field does not exist, treat it as `paused-features: []`
2. Do NOT add the just-abandoned feature to the `paused-features` array (it stays orphaned in the `_reversa_forward/` folder, with no active record, recoverable only by listing the folder manually)
3. Continue normally. When writing the new `active-requirements.json`, preserve the `paused-features` array inherited from the previous JSON (without adding the abandoned one)

The **non-destructive** directive applies here: in none of the three options is the previous feature's folder in `_reversa_forward/` deleted or modified. Only `active-requirements.json` (managed by Reversa) is rewritten.

## Resolving the feature directory

1. Read `.reversa/setup.json`
   1.1. If `prefix-format` is missing or is `sequential`, compute the next `NNN` by listing the subfolders of `_reversa_forward/` matching `NNN-*` and adding 1 to the largest
   1.2. If `prefix-format` is `timestamp`, use `YYYYMMDD-HHMMSS` of the current time
2. Generate a `short-name` in ASCII kebab-case from the free argument, at most thirty characters
3. Set `feature-dir = _reversa_forward/<NNN>-<short-name>` (or `_reversa_forward/<TIMESTAMP>-<short-name>`)
4. Create `feature-dir` if it does not exist
5. Update `.reversa/active-requirements.json` with the content below, using an atomic write (tempfile plus rename):

```json
{
  "schema-version": 1,
  "feature-dir": "<path relative to the project>",
  "feature-id": "<NNN>",
  "short-name": "<short>",
  "started-at": "<ISO 8601>",
  "current-stage": "requirements",
  "stages-completed": [],
  "paused-features": [...]
}
```

   5.1. The `paused-features` field comes from the array updated according to the option chosen in "Re-run policy" (empty if this was the project's first feature)
   5.2. The `current-stage` and `stages-completed` fields are informative metadata, not authoritative; the real stage detection is done from the physical artifacts

Re-run policy: if `active-requirements.json` already points to an earlier feature, **ask the user** before overwriting it. Options: continue the previous one, create a new feature in parallel, or abandon the previous one.

## Gathering context from the reverse extraction

Before writing the requirements, read, in this order (skipping what does not exist):

1. `_reversa_sdd/architecture.md` (an overview of the components)
2. `_reversa_sdd/domain.md` (confirmed business rules)
3. `_reversa_sdd/inventory.md` (the code's surface)
4. `_reversa_sdd/code-analysis.md`, ONLY the sections for the components the free argument seems to touch
5. `_reversa_sdd/addenda/*.md` (addenda for features already delivered by the forward cycle, created by `/reversa-sync`). Consider ONLY the ones in effect (a Validity section with no supersession line): they correct how the artifacts above should be read for deltas the extraction has not yet absorbed
6. `.reversa/principles.md` (the project's principles, if it exists)

Identify the relevant files. Every citation inside the requirements must point back to those sources in the form `_reversa_sdd/<file>#<section>`.

## Building requirements.md

1. Load the template at `.reversa/templates/requirements-template.md`
2. Preserve the order of the mandatory sections
3. Fill in each section, respecting the inline guidance comment
4. Mark with `[DOUBT]` any point where the information is missing or ambiguous
5. Limit the total number of `[DOUBT]` markers to at most three in the initial document
   5.1. Prioritize, in this order: scope, security and privacy, user experience, technical
6. Use the 🟢 / 🟡 / 🔴 marking on the items, according to the original source's confidence

## Iterative self-validation

1. After writing `requirements.md`, read the `quality-template.md` template
2. Apply the checklist mentally
3. If any items fail, rewrite the affected sections
4. Repeat that cycle at most three times
5. If problems persist after three iterations, record them in a final `## Quality gaps` section and move on

## Persistence

- Write `requirements.md` in `feature-dir/`
- The write must be atomic (tempfile plus rename)
- Use UTF-8 without BOM

## Post-execution hooks

1. Look for `after-requirements` in `.reversa/hooks.yml`
2. Apply the same filtering rule (`enabled: false` is discarded)
3. For `optional: true`, present links under "## Available Hooks"
4. For `optional: false`, emit `RUN: <command>` and wait

## Final report

At the end of the run, show the user:

1. The absolute path of `feature-dir`
2. The absolute path of `requirements.md`
3. The number of `[DOUBT]` markers in the document
4. A suggested next step:
   4.1. If there are `[DOUBT]` markers, suggest `/reversa-clarify`
   4.2. Otherwise, suggest `/reversa-plan`

Always finish with:

> Type **CONTINUE** to proceed with `/reversa-clarify` or `/reversa-plan` per the suggestion above.

NEVER proceed automatically to the next command; leave the decision to the user.
