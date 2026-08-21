# Step 3 — Spec organization

This step happens right after the user picks the `doc_level` (Essential / Complete / Detailed) and before the Archaeologist is invoked. This is when Reversa decides and persists the structure the specs will be generated in.

## 1. Decide whether the menu should be shown

Read, in this order, and merge key by key (`config.user.toml` always wins):

1. `.reversa/config.toml`, section `[specs]` (config managed by Reversa)
2. `.reversa/config.user.toml`, section `[specs]` (manual user override)

The merge is evaluated per key: each key present in `config.user.toml` replaces the matching one in `config.toml`. Missing keys keep coming from `config.toml`.

The section counts as **decided** when, after the merge, `granularity` holds one of the valid values: `module`, `use-case`, `endpoint`, `hybrid`, `feature`, `custom`.

- **If decided:** skip this whole step. Go straight to invoking the Archaeologist.
- **If not decided** (section missing, or `granularity` empty): show the menu (step 2 below).

### Special case, FR-18

If `granularity` is empty in `config.toml` (or the section was removed) **and** a `[specs]` section exists in `config.user.toml` with any key filled in, warn the user before showing the menu. Use exactly this format:

> "I noticed `.reversa/config.toml` has no spec organization decision, but `.reversa/config.user.toml` contains an override in `[specs]`. The override will remain active after your choice and may overwrite fields you decide now.
>
> Current override in `config.user.toml`:
> [list keys and values]
>
> Do you want to proceed with the menu anyway? (y/N)"

Wait for an explicit affirmative answer before moving on to the menu. An empty or negative answer aborts without persisting anything.

## 2. Present the menu

Read `.reversa/context/surface.json` → `organization_suggestion`. Use the `granularity` field to pre-select the suggested option and the `rationale` field to show the reasoning.

If `surface.json` has no `organization_suggestion` filled in (the Scout did not run or failed), show the menu with no default and ask the user to choose manually, as per EC-01 of the organization spec.

Use exactly this format (language follows `chat_language` from `state.json`; the example below is in English):

```
How do you want to organize this project's specs?

The Scout analyzed the legacy system and suggests: [translation of the suggested granularity].
Reason: [organization_suggestion.rationale]

  [1] [marker] By code module
  [2] [marker] By use case
  [3] [marker] By endpoint/contract
  [4] [marker] Hybrid (module at the root, use cases nested)
  [5] [marker] By feature (the Scout lists the discovered features)
  [6] [marker] Custom

Choose (Enter accepts the suggestion):
```

Where `[marker]` is `*` (asterisk) on the pre-selected option and a space on the others. Add `(suggested)` next to the pre-selected option.

Mapping of the 6 options to the `granularity` value:

| Option | `granularity` |
|--------|---------------|
| 1 | `module` |
| 2 | `use-case` |
| 3 | `endpoint` |
| 4 | `hybrid` |
| 5 | `feature` |
| 6 | `custom` |

### Accepting the input

- Enter with nothing typed: accepts the pre-selected option.
- A number from 1 to 6: accepts the matching option.
- Any other input: ask again without persisting anything.
- Ctrl+C / ESC / cancellation: abort execution and persist nothing (EC-02).

### Option 6, custom

If the user picks 6, open the following prompt:

> "What are the names of the top-level folders? List them comma-separated or one per line (minimum 1)."

Accept the input, sanitize each name (remove characters the OS filesystem forbids, drop empty names). If the resulting list is empty, repeat the prompt (EC-07). The names go into `custom_folders`.

## 3. Detect a conflict with the structure already on disk (FR-11)

Before persisting the decision, check whether a spec structure is already materialized in `<output_folder>/` (defined in `state.json`).

If the output folder has subfolders matching a different granularity than the one chosen now (for example, `endpoint` was chosen but the disk holds folders that look like `module`), show a warning comparing the two structures and ask for confirmation:

> "I found specs already generated with the **[old]** structure in `<output_folder>/`. You just chose **[new]**, which differs from the previous one.
>
> I'll create the new structure alongside it, without touching the old one. Existing specs are preserved.
>
> Confirm? (y/N)"

Wait for an explicit affirmative answer. A refusal aborts without persisting.

The detection is heuristic and best-effort: compare top-level subfolder names against the modules identified by the Scout (`module`), against URIs/routes (`endpoint`), against features (`feature`), etc. When the heuristic cannot decide clearly, do **not** show the warning (this avoids false positives).

## 4. Persist the decision (NFR-03, atomic write)

Update `.reversa/config.toml`, section `[specs]`, with:

```toml
[specs]
layout = "feature-folder"
granularity = "<the user's choice>"
custom_folders = [<list>]   # only when granularity == "custom", otherwise []
scout_suggestion = "<organization_suggestion.granularity from surface.json>"
decided_at = "<ISO 8601 UTC timestamp, e.g. 2026-05-03T14:32:00Z>"
```

Rules:

- **Atomic write:** write to a temporary file in the same directory (`config.toml.tmp`) and atomically rename it to `config.toml`. A failure during the write must not leave `config.toml` corrupted.
- **scout_suggestion is immutable** (FR-14): if the `[specs]` section already existed but had an empty `granularity` and a filled `scout_suggestion`, preserve `scout_suggestion`. On the first run, copy the current value of `organization_suggestion.granularity` from `surface.json`.
- **Non-destructive:** preserve any key/section you are not explicitly updating. Do not touch `[project]`, `[user]`, `[output]`, `[agents]`, `[engines]`, `[analysis]` or any other section.
- **Do not touch `.reversa/config.user.toml`.** That file belongs to the user.
- **IO failure** (disk full, no permission, EC-06): show a clear error, do not create spec folders, and do not treat the choice as confirmed. The user can try again on the next run.

## 5. Continuing the flow

After a successful write, proceed with invoking the Archaeologist as per `plan.md`. The decision is then available to every agent that writes specs.

## 6. Showing the menu again manually (FR-17)

There is no dedicated CLI flag to reconfigure. The user brings the menu back by manually removing the `[specs]` section from `.reversa/config.toml` (or emptying `granularity`). On the next run, this step detects the "not decided" state and runs again.

## Folder language (FR-10)

The names Reversa uses for feature folders follow `doc_language` from `state.json`. Do not ask about language in this step. In an `en` installation the folders come out in English; in `pt-br`, in Portuguese.

## Checklist before moving on

- [ ] Read `[specs]` from `config.toml` and merge with `config.user.toml` key by key
- [ ] If already decided, skip the step
- [ ] If there is an override in `config.user.toml` but `config.toml` is empty, show the FR-18 warning
- [ ] Read `organization_suggestion` from `surface.json`
- [ ] Show the menu with the suggestion pre-selected
- [ ] Accept Enter, a number 1 to 6, or cancellation
- [ ] If option 6, collect `custom_folders`
- [ ] Detect a conflict with the structure on disk and ask for confirmation
- [ ] Atomic write to `config.toml`
- [ ] Preserve `scout_suggestion` on re-runs with a partial section
- [ ] Proceed to the Archaeologist
