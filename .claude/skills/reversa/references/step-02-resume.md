# Step 2 — Resuming a session

## 0. Check for a migration in progress

Before anything else, read `.reversa/state.json` only to resolve `output_folder` (default `_reversa_sdd`).

Check whether `<output_folder>/migration/.state.json` exists. If it does not, skip this section and go to section 1.

If it does, read the file and classify the migration state:

| Condition | State |
|-----------|-------|
| `pendingAgents.length > 0` or `currentAgent.agent` other than `null` | in progress |
| `currentAgent.status == "awaiting_user_approval"` | intra-agent pause pending |
| `pendingAgents.length == 0`, `currentAgent.agent == null` and `<output_folder>/migration/handoff.md` exists | finished |

If the state is **finished**, skip this section (the migration is already done, nothing to ask) and go to section 1.

If the state is **in progress** or **intra-agent pause pending**, put the question to the user before anything else:

> "[Name], I found a **migration in progress** in `<output_folder>/migration/`.
>
> - Completed: <N> of 6 agents (<list of completedAgents>)
> - Pending: <list of pendingAgents>
> - Current state: <currentAgent.agent or \"awaiting human approval\">
>
> How would you like to continue:
>
> 1. **Resume the migration**: go back to the Migration Team where it left off
> 2. **Resume the Reversa flow**: continue discovery/forward, ignore the migration for now
> 3. **Cancel**: end this session without changing anything
> 4. **Other**: describe what you'd prefer to do
>
> Use the engine's interactive menu mechanism (in Claude Code, `AskUserQuestion`); on engines with no menu support, ask the user to type the number 1–4 or free text."

Wait for the answer. Do NOT decide on your own.

- If **1**: end `/reversa` here with the closing instruction:
  > "To resume the migration, type `/reversa-migrate`. It detects the saved state and offers the resume options."

  Do NOT activate `reversa-migrate` automatically; let the user type it (Reversa's explicit handoff pattern).
- If **2**: continue with section 1 of this step as normal.
- If **3**: end without doing anything.
- If **4** (free text): interpret the user's intent and offer the best available route, without inventing new flows. If the intent is ambiguous, ask the question once more before deciding.

## 1. Read the state

Read `.reversa/state.json` and `.reversa/plan.md`.

## 2. Version check

Compare `.reversa/version` with the npm registry. If a newer version exists, mention it discreetly:
> "💡 A new version is available. Run `npx reversa update` whenever you want to upgrade."

## 3. Greeting

Say: "[Name], welcome back to Reversa! 🎼"

## 4. Progress summary

Show:
- ✅ Completed phases (`completed` field in state.json)
- 🔄 Current phase (`phase` field) with the last task recorded in `checkpoints`
- ⏳ Upcoming phases (`pending` field)

Example:
> "Current progress:
> ✅ Recon complete
> 🔄 Excavation in progress — modules `auth` and `orders` analyzed, `payments` and `users` pending
> ⏳ Interpretation, Generation, Review"

## 5. Gap answering mode

If `answer_mode` is `"file"`:
> "Remember: your answers to the questions should be filled in at `_reversa_sdd/questions.md`. Let me know when you're done."

If `answer_mode` is `"chat"` (default):
> Continue normally — I'll ask the questions here in the chat.

## 6. Confirmation

Ask only: "Shall we continue from where we stopped? (CONTINUE to proceed)"

Once confirmed, resume the next pending task in the plan (`.reversa/plan.md`).

**🚫 Do not offer `/clear` + `/reversa` at this point.** The user has just resumed the session; asking them to clear and reopen now is redundant. The pause prompt between steps (described in `SKILL.md`, section "Preventive checkpoint between steps") only applies **after** an agent has completed work within this session, never in the resume greeting itself.

See `references/checkpoint-guide.md` for the rules on writing to state.json.
