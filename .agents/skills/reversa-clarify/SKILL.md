---
name: reversa-clarify
description: Generates up to five targeted questions to resolve ambiguous points in the requirements and folds the answers back into the document. Optional step of the forward cycle, between `/reversa-requirements` and `/reversa-plan`.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: clarify
---

You are the clarifier. Your mission is to find out what still needs to be known before the plan and to return the answers into the active feature's `requirements.md`.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` (reverse extraction) and `forward_folder` (forward features)
2. Whenever this skill's text mentions `_reversa_sdd/` or `_reversa_forward/`, use the real values from state.json

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If the file does not exist, abort with a clear message pointing the user to `/reversa-requirements`
2. Load the `requirements.md` of the indicated `feature-dir`
3. Apply the standard `before-clarify` hook rule read from `.reversa/hooks.yml` (same logic as the `reversa-requirements` skill)

## Generating the questions

1. Scan `requirements.md` for:
   1.1. Explicit `[DOUBT]` markers
   1.2. Vague phrasing ("probably", "maybe", "if possible", "some")
   1.3. Open terms with no definition (numeric limits, user profiles, expected formats)
   1.4. Obvious coverage gaps (missing negative scenario, implicit edge case)
2. Cross-check against the internal taxonomy below to choose candidates
3. Select at most five questions, ranked by their impact on the plan
4. Each question must be either multiple choice or short answer — never open-ended with no options

### Taxonomy for prioritizing

1. Functional scope and behavior
2. Domain model and data
3. Interaction flow and experience
4. Non-functional attributes (performance, security, observability)
5. Integrations and external dependencies
6. Permissions and authentication
7. Persistence and data migration
8. Auditing, logging and telemetry
9. Internationalization and localization
10. Failures and recovery
11. Compatibility with the legacy system mapped in `_reversa_sdd/`

## Presenting to the user

Present the questions in this format:

```
1. <question>
   a) <option>
   b) <option>
   c) <option>
   d) <option>
   e) Free-form answer

2. ...
```

If a question is short-answer, omit the options block and use the format `Expected answer: <hint about the type of value>`.

Wait for the user to reply. If they answer only some, proceed with just those.

## Folding it into requirements.md

1. Find or create the `## Clarifications` section
2. Inside it, create or update `### Session YYYY-MM-DD`
3. For each answered question:
   3.1. Add an item in the format `- **Q:** <question>` plus `**A:** <answer>`
   3.2. Find the passage in the requirements where the doubt lived
   3.3. Rewrite that passage in place, removing the corresponding `[DOUBT]`
4. Update the `## Gaps` section, removing resolved entries and keeping the unresolved ones

## Persistence

- Write the modified `requirements.md` atomically
- The `## Clarifications` section must sit right before `## Gaps`

## Post-execution hooks

Apply the standard rule for `after-clarify` (same logic as the `reversa-requirements` skill).

## Final report

1. The absolute path of `requirements.md`
2. How many doubts were resolved in this session
3. How many `[DOUBT]` markers remain
4. A suggested next step:
   4.1. If `[DOUBT]` markers remain, suggest running `/reversa-clarify` again
   4.2. If none remain, suggest `/reversa-plan`

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
