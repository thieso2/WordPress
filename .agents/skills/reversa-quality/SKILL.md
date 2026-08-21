---
name: reversa-quality
description: Textual clarity audit of the requirements. Checks whether the prose is good enough to produce a plan without ambiguity. Does NOT mix in implementation-test auditing. Optional step of the forward cycle.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: quality
---

You are the text reviewer. Your mission is to check whether the active feature's `requirements.md` is written well enough, complete enough and coherent enough to become a plan and code without rework. This skill is purely a reader over `requirements.md`. The only write it is allowed is the audit report.

This skill evaluates WRITING QUALITY, not implementation TEST COVERAGE. If you feel the urge to add an item like "check that the button works", stop — that item does NOT belong here.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort
2. Check that `feature-dir/requirements.md` exists
3. Apply `before-quality` in the standard way

## Audit categories

Every item in the report falls into one of these categories:

| Category | Guiding question |
|----------|------------------|
| Clarity | Does every sentence have a subject, a verb and a single meaning? |
| Completeness | Are all the template's mandatory sections filled in? |
| Consistency | Are the project's glossary terms always used the same way? |
| Scenario coverage | Do happy paths, sad paths and edge cases appear in Gherkin? |
| Edge cases | Have numeric limits, empties, nulls and concurrency been considered? |
| No jargon | Would the writing be understood by someone new to the team? |
| No implicit solution | Does the text describe the what, not the how (no library name, no framework)? |
| Alignment with principles | Does every rule in the requirements respect `.reversa/principles.md`? |

## How to generate the items

1. Load the template `.reversa/templates/quality-template.md`
2. For each category, generate one to five evaluative questions based on the real content of `requirements.md`
3. Between ten and thirty items in total
4. Each item follows the format `- [ ] Q-NNN | <category> | <question>`
5. After evaluating, mark `[X]` for the ones that pass and `[ ]` for the ones that fail
6. For failures, add an extra line `> reason: <objective reason>`
7. For failures the writer could auto-correct, add an extra line `> suggestion: <short text>`

## Final verdict

At the end of the report, issue one of three classifications:

- **Approved**, every item passed
- **Approved with reservations**, up to three failed items, none CRITICAL
- **Rejected**, more than three failed items, or at least one CRITICAL (missing scenario coverage, violated principle, internal contradiction)

## Persistence

- Create `feature-dir/audit/` if it does not exist
- Write `requirements-audit.md` with an atomic write
- Always a full rewrite

## Post-execution hooks

Apply `after-quality` in the standard way.

## Final report to the user

1. The absolute path of `requirements-audit.md`
2. The verdict (Approved, Approved with reservations, Rejected)
3. The top three failed items, with reasons, if any
4. An explicit notice: `requirements.md` was NOT modified
5. A suggested next step:
   5.1. Approved, suggest `/reversa-plan`
   5.2. Approved with reservations, suggest `/reversa-clarify`
   5.3. Rejected, suggest a manual rewrite or a new run of `/reversa-requirements`

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
