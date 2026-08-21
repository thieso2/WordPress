---
name: reversa-resume
description: Resumes a paused feature (listed under paused-features in active-requirements.json) and makes it active. It does NOT create new features; it only swaps the active one for the chosen one and (where it makes sense) moves the current active one into paused-features.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: resume
---

You are the resumer. Your mission is to swap the active feature for one of the ones in `paused-features`, without losing the work on either.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort with the message:

       > 🛑 `/reversa-resume` needs an active feature to swap. `active-requirements.json` does not exist.
       >
       > Use `/reversa-requirements` to create the project's first feature.

2. Check the `paused-features` field
   2.1. If absent or an empty array, abort with the message:

       > 🛑 There are no paused features to resume. The `paused-features` array is empty.
       >
       > Features get paused when you run `/reversa-requirements` on an active feature in progress and choose option 2 (create a parallel one).

3. Apply the `before-resume` hooks in the standard way (read `.reversa/hooks.yml`, filter out `enabled: false`, same logic as the other forward-cycle skills)

## Listing the paused ones

For each entry in `paused-features`:

1. Check whether the `feature-dir` still exists on disk
   1.1. If it does NOT, mark it as `missing` (the folder was deleted manually, the entry is now junk)
2. If it exists, detect the **current physical stage** using the same logic as `/reversa-requirements`:

   | Condition observed in `feature-dir` | Physical stage |
   |-------------------------------------|----------------|
   | `requirements.md` absent | `empty` |
   | `requirements.md` present, `roadmap.md` absent | `requirements` |
   | `roadmap.md` present, `actions.md` absent | `plan` |
   | `actions.md` present with at least one `\| ... \| \[ \] \|` line | `coding-in-progress` |
   | `actions.md` present, every action as `\| ... \| \[X\] \|` | `done` |

3. For `coding-in-progress`, count the `[X]` versus `[ ]` actions

Present a numbered list to the user:

```
Paused features:

1. <NNN-short-name>  ·  stage: <physical>  ·  paused on <YYYY-MM-DD>  [· N of M actions]
2. <NNN-short-name>  ·  stage: <physical>  ·  paused on <YYYY-MM-DD>
3. <NNN-short-name>  ·  stage: missing     ·  paused on <YYYY-MM-DD>  (folder deleted, orphaned entry)
```

For `missing` entries, mark visually that they are orphaned.

## The user's choice

Ask:

> Which feature do you want to resume? Type the number from the list, or `0` to cancel.

Wait for the answer. Do NOT choose on your own.

## Handling an orphaned entry

If the user chose an entry with the `missing` stage:

1. Do NOT swap
2. Ask: "That feature's folder was deleted. Do you want to remove this entry from `paused-features`? (yes / no)"
3. If yes, remove only that entry from the array, write the updated `active-requirements.json` (atomically), and end the skill.
4. If no, end without changing anything.

## Detecting the state of the currently active feature

For the feature in `active-requirements.json#feature-dir`, detect the physical stage using the same table above. That value decides whether it is paused or discarded in the swap.

## Swap

1. Build the new pause entry for the **currently active** feature, copying every field from `active-requirements.json` except `paused-features`, and adding:
   - `paused-at`: the current ISO 8601 time
   - `paused-from-stage`: the detected physical stage of the current active one
2. Decide the destination of the current active feature:
   - 2.1. If the physical stage is `requirements`, `plan` or `coding-in-progress`: **pause it**, i.e. push the entry you built onto the `paused-features` array
   - 2.2. If the physical stage is `done`: **drop it from active**, do NOT push (the feature is finished, it does not deserve space in paused-features). Its folder stays untouched in `_reversa_forward/`
   - 2.3. If the physical stage is `empty`: **drop it from active**, do NOT push (corruption, a folder with no `requirements.md`)
3. Remove the chosen feature from the `paused-features` array
4. Build the new `active-requirements.json`:

```json
{
  "schema-version": 1,
  "feature-dir": "<feature-dir of the chosen one>",
  "feature-id": "<feature-id of the chosen one>",
  "short-name": "<short-name of the chosen one>",
  "started-at": "<original started-at of the chosen one>",
  "current-stage": "<original current-stage of the chosen one, or the detected physical stage>",
  "stages-completed": [<copied from the chosen one, or [] if absent>],
  "paused-features": [<updated array>]
}
```

   4.1. If the chosen one had no `started-at`/`current-stage`/`stages-completed` (an entry from an older version, before the rich schema), use the detected physical stage for `current-stage` and the current time for `started-at` (record that fallback in a message to the user)

5. Write the JSON atomically (tempfile plus rename)

## Post-execution hooks

Apply `after-resume` in the standard way.

## Final report to the user

1. Feature resumed: the identifier `<NNN-short-name>`
2. That feature's detected physical stage: one of `requirements` / `plan` / `coding-in-progress`
3. For `coding-in-progress`, show `N of M actions done`
4. Destination of the previously active feature:
   4.1. "paused" (if it was pushed to paused-features)
   4.2. "dropped from active (state: done)" or "dropped from active (state: empty)"
5. A suggested next skill based on the resumed feature's stage:
   5.1. `requirements` → suggest `/reversa-clarify` (if there are `[DOUBT]` markers) or `/reversa-plan`
   5.2. `plan` → suggest `/reversa-to-do`
   5.3. `coding-in-progress` → suggest `/reversa-coding` (with an optional argument to narrow the scope)

Always finish with:

> Type **CONTINUE** to proceed with the suggestion above.

Do NOT run the next skill automatically; leave the decision to the user.
