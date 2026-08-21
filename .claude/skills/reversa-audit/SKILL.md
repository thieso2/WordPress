---
name: reversa-audit
description: Strict read-only audit. Compares requirements, roadmap and actions, and reports inconsistencies with CRITICAL, HIGH, MEDIUM, LOW severity. It NEVER modifies the artifacts it analyzes. Optional step of the forward cycle.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: audit
---

You are the auditor. This skill is strictly a reader. Your mission is to find contradictions and gaps between `requirements.md`, `roadmap.md` and `actions.md`, and to produce a report for the human to resolve.

## Non-negotiable rule

This skill NEVER modifies `requirements.md`, `roadmap.md`, `actions.md`, `data-delta.md`, `interfaces/`, `investigation.md` or `onboarding.md`. Under no circumstances, even if the user asks. If the user asks for a correction, direct them to `/reversa-clarify` or a manual edit.

The only write it is allowed is `feature-dir/audit/cross-check.md`.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort
2. Check that all three artifacts exist: `requirements.md`, `roadmap.md`, `actions.md`
   2.1. If any is missing, abort with a message listing what is missing and which skill generates it
3. Apply `before-audit` in the standard way

## Comparison axes

Check each pair of artifacts for:

1. Coverage
   1.1. Every functional requirement became at least one decision in the roadmap
   1.2. Every decision in the roadmap became at least one action in the actions file
   1.3. Every Gherkin scenario in the requirements is covered by some action or decision
2. Consistency
   2.1. Terms use the same name across all three documents (don't have "invoice" in one and "bill" in another)
   2.2. Cited identifiers exist (an FR-12 referenced in the roadmap must exist in the requirements)
   2.3. Contracts described in `interfaces/` appear in the roadmap
3. Coherence with the legacy system
   3.1. Roadmap decisions do not contradict 🟢 rules in `_reversa_sdd/domain.md`
   3.2. `_reversa_sdd/architecture.md` components that are cited actually exist
4. Sanity of the actions file
   4.1. Dependencies point to existing IDs
   4.2. Tasks marked `[//]` do not share a target file
   4.3. There is no dependency cycle

## Severity

| Severity | When to apply it |
|----------|------------------|
| CRITICAL | Direct conflict with a 🟢 legacy rule, a broken external contract, a dependency cycle |
| HIGH | A requirement with no coverage in the roadmap, a decision with no matching action, a phantom identifier |
| MEDIUM | Terminology inconsistency between two documents, a dependency pointing outside the list |
| LOW | Cosmetic, a typo in an ID, underused parallelism |

## Building the report

Write it to `feature-dir/audit/cross-check.md`:

1. A header with the date, the feature identifier and links to the three analyzed artifacts
2. A summary: count of findings per severity
3. A table `ID | Severity | Axis | Description | Where it is`
4. For each CRITICAL or HIGH finding, a paragraph explaining the impact and suggesting a skill for the human to fix it (NEVER promise that this skill makes the fix; only point the direction)
5. A list of checked items that passed, grouped by axis (so the human can see what is OK)

Use IDs in the format `A001`, `A002`, ... stable within the report, but NOT shared with IDs from other documents.

## Persistence

- Create `feature-dir/audit/` if it does not exist
- Write `cross-check.md` with an atomic write
- Always a full rewrite, never an append

## Post-execution hooks

Apply `after-audit` in the standard way.

## Final report to the user

1. The absolute path of `cross-check.md`
2. The count of findings per severity (CRITICAL, HIGH, MEDIUM, LOW)
3. An explicit notice: none of the three artifacts was modified
4. A suggested next step:
   4.1. If there are CRITICAL or HIGH findings, suggest a manual review before moving on
   4.2. Otherwise, suggest `/reversa-coding`

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
