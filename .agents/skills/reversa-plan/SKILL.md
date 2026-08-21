---
name: reversa-plan
description: Sketches the technical approach as a delta over the legacy system, producing the active feature's roadmap, investigation, data-delta, onboarding and interfaces. Third skill of the forward cycle, after `/reversa-requirements` and (optionally) `/reversa-clarify`.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: plan
---

You are Reversa's evolution architect. Your mission is to translate the active feature's `requirements.md` into a concrete technical proposal, expressed as a delta over what already exists in the legacy system.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Read `.reversa/active-requirements.json`
   1.1. If absent, abort with a message pointing to `/reversa-requirements`
2. Load the `requirements.md` of the `feature-dir`
   2.1. If the document still has `[DOUBT]` markers, warn the user and ask whether they would rather run `/reversa-clarify` first
   2.2. If the user confirms they want to proceed despite the doubts, each `[DOUBT]` becomes an explicit assumption in `roadmap.md`, with a visible warning
3. Apply the `before-plan` hooks in the standard way (same logic as the `reversa-requirements` skill)

## Gathering technical context

Read the reverse-pipeline artifacts in this order, skipping the ones that do not exist:

1. `_reversa_sdd/architecture.md` (components, internal dependencies)
2. `_reversa_sdd/c4-context.md` (external boundaries)
3. `_reversa_sdd/state-machines.md` (affected state machines)
4. `_reversa_sdd/dependencies.md` (libraries in use)
5. `_reversa_sdd/code-analysis.md`, but only the sections for the components mentioned in the requirements
6. `_reversa_sdd/addenda/*.md` (addenda still in effect from already-delivered features, created by `/reversa-sync`, carrying deltas the extraction has not yet absorbed)
7. `.reversa/principles.md` (mandatory principles)

Note which files the proposed change will touch. That list will become part of `legacy-impact.md` when `/reversa-coding` runs later, so keep it in mind as a draft.

## Checking the principles

For each principle in `principles.md`:

1. Evaluate whether the feature respects the principle
2. If there is a conflict, write the conflict in a `## Principles Applied` section of `roadmap.md`
3. NEVER rewrite or soften a principle here; that is `/reversa-principles`' job

## Generating the artifacts

Load the template at `.reversa/templates/roadmap-template.md` and generate the files below in the `feature-dir`:

| File | Expected content |
|------|------------------|
| `roadmap.md` | summary of the approach, principles applied, technical decisions, architectural delta, data delta, contract delta, migration plan, risks, definition of done |
| `investigation.md` | background research, alternatives evaluated, links to external sources, applicable patterns |
| `data-delta.md` | conceptual diff over the model extracted in `_reversa_sdd/`, new fields, removed fields, required migrations |
| `onboarding.md` | executable step-by-step instructions for a human testing the feature for the first time |
| `interfaces/<name>.md` | one file per affected external contract (HTTP, queue, gRPC, GraphQL), describing request, response, errors, idempotency, timeouts |

When the feature does not touch external contracts, omit the `interfaces/` directory.

## Writing rules

- Write `roadmap.md` as a delta; never re-describe the legacy system's entire architecture
- Cite `_reversa_sdd/` components by their literal name and source file
- Mark each technical decision with 🟢 / 🟡 / 🔴 according to the confidence in the source
- If a decision depends on a `[DOUBT]` accepted as an assumption, use 🟡

## Persistence

- Write every artifact with an atomic write
- Create `feature-dir/interfaces/` only if there is at least one file inside it

## Post-execution hooks

Apply `after-plan` in the standard way.

## Final report

1. The absolute paths of the generated artifacts
2. The list of conflicting principles, if any
3. The list of assumptions adopted from unresolved `[DOUBT]` markers
4. A suggested next step: `/reversa-to-do` (or `/reversa-audit` if something looks off)

Finish with:

> Type **CONTINUE** to proceed with the suggestion above.
