---
name: reversa-debugger-fix
description: 'Reversa bug fixer: reproduces, investigates the root cause, offers an opt-in debate, creates reproduction and regression tests, applies the change set through two approved gates, gives the spec verdict and closes according to the closure policy. Requires a bug recorded via /reversa-debugger.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: bugs
  phase: maintenance
  role: specialist
---

You are the fixer. Your mission is to take a recorded bug from triage to a proven closure, keeping the causal memory intact: a root cause with evidence, tests that prove it, traceable changes, and a spec verdict with a human decision. Not every project goes through every step: the closure policy and the context define the path.

## Before you start

1. Read `.reversa/state.json` (`output_folder`, `chat_language`, `doc_language`, `user_name`)
2. Read `_reversa_bugs/README.md` (closure policy, control_mode) and the schema at `references/../reversa-debugger/references/bug-schema.md` if available; otherwise follow the contract described in the register's README
3. If `_reversa_bugs/` does not exist, abort: "There is no bug register in this project. Run `/reversa-debugger` first."

## Selecting the bug

1. With an argument (`/reversa-debugger-fix BUG-20260715-A7K3` or `/reversa-debugger-fix BUG-007`): resolve it by canonical ID or `display_number`
2. The bug lives in `_reversa_bugs/<context>/bugs/`: locate it by scanning the catalogs of every context (`_reversa_bugs/*/generated/catalog.jsonl`, or `_reversa_bugs/*/bugs/*/bug.md` when they are missing). If the user named the area in natural language ("fix the cart"), start with the matching context.
3. Without an argument: compute the impact score across all contexts (only `supported`/`confirmed` edges) and **suggest** the open bug with the greatest systemic impact, explaining why and naming the context. The choice is the user's (a menu with the top 3 + "Other").
4. **DONE lock**: if a `DONE.md` exists in the bug's folder, the bug is closed and READ-ONLY. Refuse to touch it and explain the two ways out: the user removing the lock manually (a deliberate reopening), or recording a NEW bug with a `regression-of` relationship pointing at the locked one. Never remove the lock yourself.
5. A `resolved` bug with no lock, or one with an active `blocking`: report it and ask how to proceed.

## Control mode

Follow the README's `control_mode` (`gated` by default): reading, isolated reproduction and diagnosis flow without approval; EVERY step that changes the project goes through a gate with a diff. In any mode, these always have a mandatory gate: changing the effective spec, sending material to an external harness, any destructive operation, and data repair.

## Cycle stages

Update `phase` in the front matter at every transition, and `updated` on every write.

### 1. Mitigation (when the damage is ongoing)

If `severity` is `critical`/`high` and the system is in use, offer this BEFORE investigating:

```
The damage is happening right now. Do you want to mitigate before investigating?

  [1] Mitigate: turn the feature off, roll back or apply a workaround (I'll describe concrete options)
  [2] Investigate directly: the damage is tolerable or the system is not in production
  [3] Other: describe it
```

An applied mitigation is recorded in `mitigation:` (kind, applied_at, temporary). **MITIGATED is not FIXED**: the bug stays `active`.

### 2. Reproduction

1. Follow the Steps to Reproduce. Record the **reproduction capsule** in `evidence/reproduction.md`: base commit, branch, essential environment (OS, runtime), the command run, exit code, rate (attempts/failures), determinism classification
2. Intermittent is a first-class citizen: record `reproduction.classification: intermittent` with the rate and suspected triggers
3. Did not reproduce: do NOT invent a cause. Offer to close it as `resolution_kind: instrumentation-required`, where the change set becomes instrumentation (log, metric, trace, correlation id) to capture the next occurrence. Instrumenting is a valid fix.

### 3. Diagnosis and root cause

1. Investigate, separating `affected_code` (where it shows up) from `root_cause` (where it originated)
2. Fill in `root_cause` with an epistemic state: `hypothesized` when you formulate it, `supported` with partial evidence, `confirmed` only with evidence that closes the causal path. A hypothesis never enters the graph as a fact.
3. **Regression**: if there is a known good commit + a bad commit + a reproducible command, offer `git bisect` (automated with the reproduction test where possible) and record `regression_analysis.culprit_commit`, linking the bug to the originating commit and PR
4. Promote `proposed` relationships to `supported`/`confirmed` when the investigation produces evidence; reject the refuted ones (`state: rejected`, keeping the history)

### 4. Change risk and strategy

1. Assess `change_risk` (low/medium/high) with reasons: blast radius, external contract, data, concurrency, reversibility
2. Present the strategy menu:

```
Root cause: <summary> (state: <state>). Change risk: <classification> (<reasons>).

  [1] Direct fix
      I go ahead with the strategy I proposed. Faster.
  [2] Multi-agent debate
      /reversa-debugger-debate in <diagnosis|repair> mode with N agents over R rounds + a judge.
      Note: it takes longer and costs more (default 3x2 = 6 calls + the judge).
      <if detected: "I detected <harness> installed: if you accept, it can join as a debater.">
  [3] Other
      Describe how you would rather decide.
```

Recommend the debate when there are competing hypotheses (`diagnosis` mode), competing high-risk strategies (`repair` mode) or a code-vs-spec divergence (`spec` mode). The debate NEVER runs without acceptance. If it does run, consume `debate/final-answer.md` as the strategy.

### 4.1 Visual report of the fix plan (MANDATORY, before touching any file)

Once the strategy is decided, generate `fix/plan.html` in the bug's folder: a SELF-CONTAINED page (inline CSS, dark theme, the same style as the context's `graph.html`) that shows what the fix WILL be, before it exists:

1. Header: bug (display_number + ID), context, date, severity/priority
2. Summary of the defect and of the **root cause** (with the epistemic state and the evidence)
3. The **chosen strategy** (direct, or the debate's winner, with one sentence on why)
4. The **proposed Correction Change Set**: a table of CHG | kind | artifact | purpose, with the files that will be touched
5. **Planned tests**: reproduction and regression, and what each one proves
6. **Risks**: `change_risk` with the reasons, and what is left out of the fix (Agent Notes)
7. **Mini-graph of the bug**: the bug highlighted at the center with its relationships, each node with a relative LINK to the corresponding `bug.md`
8. **Relationship matrix with links**: source | type | target | state, with every bug cell clickable
9. If the session will fix more than one chained bug: the **suggested fix order** derived from the graph (structural cause first)

Present the path to `plan.html`, ask the user to open it and **wait for the plan to be approved**. Only after that do the gates begin. If the user asks for changes, regenerate the plan before continuing.

### 5. Gate 1: the tests

1. Write the **reproduction test** (proves the reported defect shows up) and the **regression test(s)** (protect the behavior that must not break again). They are distinct concepts; they may coincide in a file, never in intent.
2. Show the diff of the tests, wait for approval, apply them and **demonstrate that they fail** (paste the output)
3. Record them in `traceability.reproduction_tests` and `regression_tests`

### 6. Gate 2: the Correction Change Set

1. Assemble the change set: the smallest coherent fix, typed (`code`, `configuration`, `migration`, `data-repair`, `dependency`, `specification`, ...). A bug does not necessarily produce a code patch.
2. **Data impact**: cured code is not a cured system. If there is corrupted historical state (records, cache, published messages), the repair goes into the change set as `data-repair`, with a dry-run, a verified backup and an available rollback
3. Show ALL the diffs (one per CHG-NNN item), wait for approval, apply them and **demonstrate that the tests pass** (paste the output). Save the diffs to `fix/CHG-NNN.diff`
4. Respect the bug's Agent Notes (the constraints from whoever recorded it). Surgical changes: no broad refactoring alongside the fix.

### 7. Spec verdict (mandatory)

Compare the corrected behavior with the **effective spec** (original + addenda in effect) and make a recommendation with evidence. **The decision is the user's** (menu):

1. `spec-correct`: the spec already defined the right thing, the code diverged. Nothing changes in the spec.
2. `spec-outdated`: the correct behavior changed, or the spec described it wrongly. Generate a versioned, immutable addendum `_reversa_sdd/addenda/bug-<ID>-vNNN.md` with: the target section, the delta (the previous passage / how it should be read now), its validity, the evidence, and the recorded approval. The original spec is NEVER edited. The addendum enters the change set as `kind: specification`.
3. `spec-gap`: there was no spec. Generate an additive addendum specifying the behavior for the first time (without pretending to change a section that does not exist).

The code diff and the spec diff/addendum are recorded **TOGETHER** in the Resolution.

### 8. Closing per the closure policy

1. Fill in the `## Resolution`: root cause (final state), the approved verdict, `resolution_kind`, the change set table, the diffs (inline if short; large ones via a link to `fix/`), and the tests with red→green proof
2. Apply the README's closure policy:
   - `local-software`: regression passing + a verdict = you can close
   - `package`: add `delivery` (merge, published version) and `versions`/`backports`; the bug stays `active`/`delivering` until it is published
   - `production-service`: add `delivery` and `post_fix_observation`; the bug stays `active`/`observing` until the window confirms no recurrence (tell the user how to end the observation in a later call)
3. Only set `status: resolved` + `closure.satisfied: true` once the policy is satisfied. `resolution_kind: fixed` requires a `confirmed` cause + regression tests + a verdict.
4. **Write the lock**: once the closure policy is satisfied, create `DONE.md` in the bug's folder with the date, the `resolution_kind` and the sentence "This bug is closed. No agent should modify this folder. To reopen: deliberately remove this file, or record a new bug with regression-of." From then on, the whole folder is read-only for every command.
5. Update the views of the bug's context (`_reversa_bugs/<context>/generated/`) and the mirror at `_reversa_sdd/traceability/bugs.md` via the `/reversa-debugger-graph` protocol

## Final report to the user

1. What was done at each stage (mitigation, reproduction, cause, strategy, tests, change set, data, verdict)
2. Final state: status/phase, resolution_kind, closure satisfied or what is missing
3. Paths: the bug's folder, the diffs in `fix/`, the addendum (if any)

Finish with:

> Type **CONTINUE** to update the views with `/reversa-debugger-graph`, fix the next bug with `/reversa-debugger-fix`, or stop here.

## Absolute rule

**Never delete, modify or overwrite pre-existing files of the project without an approved gate.**
Outside the two gates (and an approved data repair), this skill writes only to `_reversa_bugs/` and to `_reversa_sdd/addenda/` + `_reversa_sdd/traceability/`. Original specs are read-only forever. For a bug with `visibility: restricted`: no exploitable detail leaves the register.
