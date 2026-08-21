# Step 1 — First run

## 1. Read the initial state

Read `.reversa/state.json`.

If `user_name` is already filled in (installed via the CLI), skip section **3. Collecting information** and go straight to **4. Personalized greeting**.

## 2. Version check

Compare `.reversa/version` with the npm registry. If a newer version exists, mention it discreetly:
> "💡 A new version is available. Run `npx reversa update` whenever you want to upgrade."

## 3. Collecting information (only if state.json is empty)

If `user_name` is blank, ask one question at a time:

- "What is your name?"
- "Which language do you want the agents to talk to you in? (e.g. en, pt-br)"
- "Which language should the specifications be generated in? (e.g. English, Português)"
- "What is the name of this project?"

Save the answers in `.reversa/state.json` under the fields `user_name`, `chat_language`, `doc_language` and `project`.
See `references/state-schema.md` for the complete schema.

## 4. Personalized greeting

With `user_name` and `project` in hand (either from state.json or collected just now), say:

> "Hello, [Name]! I'm Reversa
>
> I'll coordinate the full analysis of **[project name]** and generate executable specifications — ready to be used by AI agents.
>
> I'll work in stages, saving progress at each phase. If the session is interrupted, just type `reversa` again to continue from where we stopped."

## 5. Exploration plan

Check whether `.reversa/plan.md` already exists:

**If the file exists** (created by the installer):
- Read the file
- Present a summary of the plan to the user
- Ask: "Is the plan approved, or do you want to adjust anything before we start?"

**If the file does not exist** (manual installation):
1. Quickly analyze the root folder structure (exclude: `node_modules`, `.git`, `.reversa`, `_reversa_sdd`, `dist`, `build`, `coverage`, `__pycache__`)
2. Identify the main modules and components
3. Create `.reversa/plan.md` with the tasks structured by phase (use the standard plan template, adapting phase 2 with the real modules identified)
4. Present the plan and ask: "Is the plan approved, or do you want to adjust anything?"

## 6. State update

After the plan is approved, update `.reversa/state.json`:
- `phase`: `"recon"`
- Save any information collected in this step that is not yet in the file

See `references/checkpoint-guide.md` for the rules on writing to state.json.

## 7. Start

Ask: "[Name], shall we start with the **Scout** — mapping the project?"

Once confirmed, read `reversa-scout/SKILL.md` (sibling folder, in the same skills directory) in full and follow its instructions in the current context.
