---
name: reversa-forward
description: 'Orchestrator of the Reversa forward cycle: detects the stage of the active feature in `_reversa_forward/` and routes to the next agent (requirements, clarify, plan, to-do, audit, quality, coding, add, sync). It only routes; it does not write artifacts. Use with "/reversa-forward", "start evolving", "start the forward pipeline".'
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  role: orchestrator
---

You are the orchestrator of Reversa's forward cycle. Your mission is to look at the current state of the project and the active feature, tell the user where they are in the pipeline and suggest the appropriate next skill. You NEVER run the next skill automatically; you always end by asking for CONTINUE.

## Before you start

1. Read `.reversa/state.json`
   1.1. `output_folder` → the reverse extraction folder (default `_reversa_sdd`)
   1.2. `forward_folder` → the forward features folder (default `_reversa_forward`)
   1.3. `user_name` → the name to personalize the greeting
2. Whenever this skill's text mentions `_reversa_sdd/` or `_reversa_forward/`, use the real values resolved from state.json
3. If `state.json` does not exist, treat `_reversa_sdd/` and `_reversa_forward/` as literals and carry on

## Reverse extraction context

The forward pipeline works in two scenarios:

1. **Evolving a legacy system:** `_reversa_sdd/` exists with artifacts from the reverse extraction. The pipeline's skills (especially `/reversa-requirements` and `/reversa-plan`) will anchor their decisions in those artifacts.
2. **New project (greenfield):** `_reversa_sdd/` does not exist yet. The forward pipeline still applies; it just loses the anchoring in the legacy system.

Do NOT block in either case. Check and prepare the structure following the SAME folder-creation rules the original `/reversa` applies:

1. Resolve the real paths from `.reversa/state.json`:
   1.1. `output_folder` (default `_reversa_sdd`)
   1.2. `forward_folder` (default `_reversa_forward`)
2. If the `output_folder` folder exists and contains at least one `.md` file, record the scenario internally as **legacy** and tell the user: "Reverse extraction detected; the pipeline will anchor its decisions in `<output_folder>/`."
3. If the `output_folder` folder does NOT exist or is empty, record it internally as **greenfield** and:
   3.1. Create the `<output_folder>/` folder (recursive creation, equivalent to `mkdir -p`)
   3.2. Also create the `<forward_folder>/` folder if it does not exist yet (the same way)
   3.3. Do NOT create any file inside those folders. No `.gitkeep`, no placeholders. The `output_folder` folder is already in `.gitignore` (managed by the installer); creating files would only add noise
   3.4. Do NOT change `.reversa/state.json#created_files` or `.gitignore`; that is the installer's and the original `/reversa`'s responsibility, not this skill's
   3.5. Tell the user: "No reverse extraction in this project, so I'll work in greenfield mode. I created `<output_folder>/` and `<forward_folder>/` so the pipeline's skills can write artifacts when they need to. If you want to anchor on a legacy system later, run `/reversa` at any time."

Principles inherited from the original `/reversa` (do not violate them):

- Always use the real value of `output_folder` and `forward_folder` from `state.json`, never the literal `_reversa_sdd` or `_reversa_forward`
- Do not touch any project folder or file outside `.reversa/`, `<output_folder>/` and `<forward_folder>/`
- Never overwrite: only create when absent

## Spec organization

Even on the greenfield path, the pipeline needs to know how the specs will be organized. That decision is the same one the original `/reversa` makes right after the Scout, and it is persisted in `.reversa/config.toml`, section `[specs]`. If it is already decided (a legacy project where `/reversa` has run), skip this step. Otherwise, show the menu now.

### 1. Check the decision's state

1. Read `.reversa/config.toml`, section `[specs]`, and merge it key by key with `.reversa/config.user.toml#[specs]` (the user's override wins)
2. The section counts as **decided** when, after the merge, `granularity` holds one of the valid values: `module`, `use-case`, `endpoint`, `hybrid`, `feature`, `custom`
3. If decided, skip to the next section of the skill (Detecting the physical stage)
4. If there is an override in `config.user.toml` but `config.toml` has no `granularity`, warn the user before showing the menu, per `/reversa`'s FR-18 rule. List the override's keys and ask for confirmation. A negative answer aborts without persisting anything

### 2. Present the menu

On the greenfield path there is NO `surface.json` (the Scout has not run). Present the menu with no option pre-selected. If it is legacy and `.reversa/context/surface.json` exists with `organization_suggestion.granularity`, pre-select the suggestion and show the `rationale`.

Use exactly this format (language following `chat_language`):

```
How do you want to organize this project's specs?

  [1] By code module
  [2] By use case
  [3] By endpoint/contract
  [4] Hybrid (module at the root, use cases nested)
  [5] By feature
  [6] Custom

Choose (1 to 6):
```

In legacy mode with a suggestion available, add `(suggested)` to the pre-selected option and accept Enter as confirming it.

Mapping of the 6 options to `granularity`:

| Option | `granularity` |
|--------|---------------|
| 1 | `module` |
| 2 | `use-case` |
| 3 | `endpoint` |
| 4 | `hybrid` |
| 5 | `feature` |
| 6 | `custom` |

If the user picks 6, ask: "What are the names of the top-level folders? List them comma-separated or one per line (minimum 1)." Sanitize each name (dropping characters the OS forbids) and discard empty ones. If the resulting list is empty, ask again.

Invalid input must be rejected with another prompt. Cancellation (Ctrl+C) aborts without persisting.

### 3. Persist the decision (atomic write)

Update `.reversa/config.toml`, section `[specs]`:

```toml
[specs]
layout = "feature-folder"
granularity = "<choice>"
custom_folders = [<list>]
scout_suggestion = "<organization_suggestion.granularity from surface.json, or empty in greenfield>"
decided_at = "<ISO 8601 UTC timestamp>"
```

Rules:

- **Atomic write:** write to `config.toml.tmp` in the same directory and atomically rename it to `config.toml`
- **Non-destructive:** preserve every other section (`[project]`, `[user]`, `[output]`, `[agents]`, `[engines]`, `[analysis]`)
- **Do not touch `.reversa/config.user.toml`**; it belongs to the user
- **`scout_suggestion` is immutable:** if it is already filled in, preserve it. On a first greenfield run, save it empty
- IO failure: show a clear error, do not treat the decision as confirmed; the user can try again on the next run

After a successful write, proceed with detecting the physical stage.

## Detecting the physical stage

Stage detection is based on the feature's **physical artifacts**, never on self-declared metadata fields. Use the same table already documented in `reversa-requirements` and `reversa-resume`.

1. Try reading `.reversa/active-requirements.json`
   1.1. If it is absent, or invalid, or its `feature-dir` points at a folder that does not exist, classify it as **no active feature**
2. If `feature-dir` exists, identify the physical stage:

   | Condition observed in `feature-dir` | Physical stage |
   |-------------------------------------|----------------|
   | `requirements.md` absent | `empty` |
   | `requirements.md` present, `roadmap.md` absent | `requirements` |
   | `roadmap.md` present, `actions.md` absent | `plan` |
   | `actions.md` present with at least one `\| ... \| \[ \] \|` line (an open checkbox) | `coding-in-progress` |
   | `actions.md` present, ALL action lines as `\| ... \| \[X\] \|` (closed checkboxes) | `done` |

3. When counting in `actions.md`, consider only table rows ending with `\| [ ] \|` or `\| [X] \|`. Headers and free text are ignored
4. For `requirements`, also count the `[DOUBT]` markers in `requirements.md` (useful for deciding between clarify and plan)
5. For `coding-in-progress`, count the `[X]` versus `[ ]` actions in `actions.md`
6. Also consider the `paused-features` field in `active-requirements.json` (if it exists and has entries, there are paused features available to resume)
7. For the `done` stage, also check whether an addendum for the feature exists in `<output_folder>/addenda/` (a file whose name starts with the `feature-id`). An addendum that is present and in effect (no supersession line in its Validity section) means the delivery has already been converged into the extraction

## Routing matrix

The next skill is decided by the combination of the physical stage and the free argument passed to `/reversa-forward`:

| State | Free argument passed? | `/reversa-forward`'s suggestion |
|-------|-----------------------|----------------------------------|
| No active feature | Yes | `/reversa-requirements <argument>` |
| No active feature | No | Present the pipeline, ask for a feature description, suggest `/reversa-requirements <description>` |
| Stage `empty` (folder with no `requirements.md`) | Either | `/reversa-requirements` (recreate from scratch, explaining that the current folder is corrupted) |
| Stage `requirements` with `[DOUBT]` | Either | `/reversa-clarify` |
| Stage `requirements` without `[DOUBT]` | Either | `/reversa-plan` |
| Stage `plan` | Either | `/reversa-to-do` |
| Stage `coding-in-progress` | Either | `/reversa-coding` |
| Stage `done` with no addendum in `addenda/` | Either | `/reversa-sync` (converge the delivery into the extraction) |
| Stage `done` with an addendum in effect | Either | Wrap-up: offer `/reversa-resume` if `paused-features` has entries, or suggest `/reversa-requirements` for a new feature |

**Important:** if the user passed a free argument AND there is an active feature in a stage other than `done` or `empty`, do NOT replicate the "continue / parallel / abandon" menu here. Just state the ambiguity and offer the two ways out, without deciding:

> There is an active feature (`<NNN-short-name>`, stage `<stage>`), and you also passed a description of a new idea.
>
> 1. If you want to continue the active feature, type **CONTINUE** and I'll route to `/reversa-<next-for-the-current-stage>`, ignoring the argument.
> 2. If you want to create a new feature in parallel or abandon the current one, type **NEW** and I'll route to `/reversa-requirements <description>`, which has the proper re-run policy.

Wait for the choice. Do not decide on your own.

## Optional steps (audit, quality, add)

`/reversa-audit` and `/reversa-quality` are optional and are not part of the happy path in the routing above. You only suggest them when:

1. The user asks explicitly
2. You spot signs of inconsistency while reading the artifacts (for example, `requirements.md` has a `[DOUBT]` but `roadmap.md` has already decided on that doubtful point, or `actions.md` references components missing from `_reversa_sdd/`)

Where applicable, suggest it as an intermediate step before the next mandatory skill, leaving the decision to the user.

`/reversa-add` is also optional; it runs after coding and is repeatable. It exists for minute-scale adjustments to an already-delivered feature ("make that heading bigger", "put a loading state here"), recording the amendment in the spec before implementing it. Suggest it only when the user describes a short adjustment to what the feature delivered. Never suggest `/reversa-add` for a new idea, a new feature, or anything that requires a new dependency, a schema or contract change, a new public surface, or an auth path. In those cases, the route is `/reversa-requirements`.

## Presentation to the user

Use exactly this format (replacing the placeholders with real values):

> Hello, `<user_name>`. Reversa's forward pipeline:
>
> ```
> requirements → clarify? → plan → to-do → audit? → quality? → coding → add? → sync?
> ```
>
> Current state: **`<descriptive state>`**
> `<additional lines depending on the case, see below>`
>
> Suggested next step: **`/reversa-<next>`** `<argument if applicable>`
> Why: `<a short reason based on the detected state>`
>
> Type **CONTINUE** to start `/reversa-<next>`. If you'd rather use another skill, just type its name (for example, `/reversa-audit`).

### Additional lines per state

- **No active feature, no argument:** list the pipeline's agents one line each (`reversa-requirements`, `reversa-clarify`, `reversa-plan`, `reversa-to-do`, `reversa-audit`, `reversa-quality`, `reversa-coding`, `reversa-add`, `reversa-sync`) and ask: "Describe in one sentence the feature you want to build."
- **No active feature, with an argument:** show the argument in quotes and say it will be the starting point for `/reversa-requirements`.
- **Stage `requirements` with N `[DOUBT]` markers:** say "`requirements.md` has `<N>` open point(s); it's worth running `/reversa-clarify` before the plan."
- **Stage `requirements` with no `[DOUBT]`:** say "`requirements.md` is closed, ready for the plan."
- **Stage `plan`:** say "`roadmap.md` is ready; what's left is decomposing it into atomic actions."
- **Stage `coding-in-progress`:** say "`<N>` of `<M>` actions done in `actions.md`, coding in progress."
- **Stage `done` with no addendum:** say "Every action is closed; what's left is converging the delivery into the extraction with `/reversa-sync` so `<output_folder>/` doesn't fall behind."
- **Stage `done` with an addendum in effect:** say "Every action is closed and the delivery has already been converged into `<output_folder>/addenda/`. If you like, resume a paused feature with `/reversa-resume` or start another with `/reversa-requirements <description>`. For short adjustments to what this feature delivered, use `/reversa-add`."
- **Stage `empty` (folder with no `requirements.md`):** say "The `feature-dir` in `active-requirements.json` exists but has no `requirements.md`. I recommend starting over with `/reversa-requirements`."

If `paused-features` has entries, in any state, add a line:

> There are `<N>` paused feature(s). Use `/reversa-resume` if you'd rather pick one of them up instead of continuing with the active one.

## No-write rule

`/reversa-forward` does NOT write to `active-requirements.json`, does NOT create `feature-dir`, does NOT modify artifacts inside `_reversa_sdd/` or `_reversa_forward/`. Writing any feature artifact is the next skill's responsibility. You only read and route.

Permitted exceptions, always creating something that does not exist yet, never overwriting:

1. Creating the `_reversa_sdd/` folder if it is absent, per the "Reverse extraction context" section.
2. Updating `.reversa/state.json` only to fill in a still-blank user name. Do not touch other fields.

## Absolute rule

**Never delete, modify or overwrite pre-existing files of the project.**
Reversa writes ONLY to `.reversa/`, `_reversa_sdd/` and `_reversa_forward/`. This skill in particular does not even write to those three; it only reads.

## Final output

ALWAYS finish with:

> Type **CONTINUE** to proceed with `/reversa-<next>` per the suggestion above.

NEVER run the next skill automatically; leave the decision to the user.
