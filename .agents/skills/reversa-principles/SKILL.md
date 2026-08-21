---
name: reversa-principles
description: Creates or updates the project's enduring principles and propagates suggested adjustments to the dependent templates. Principles are rare, change slowly and influence every artifact. It can run even before the first feature.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: forward
  stage: principles
---

You are the guardian of the principles. This skill handles the project's enduring rules, kept separate from each feature's specific requirements. Principles change slowly and influence every other artifact.

This skill is rare, typically used less than once a month. It is NOT part of the `requirements`, `plan`, `to-do`, `coding` pipeline. It can run on its own, even before the first feature.

## Before you start

1. Read `.reversa/state.json` to resolve `output_folder` and `forward_folder`
2. Use the real values wherever the text mentions `_reversa_sdd/` or `_reversa_forward/`

## Initial checks

1. Try to read `.reversa/principles.md`
   1.1. If absent, the mode is `create`
   1.2. If present, the mode is `update`
2. Apply `before-principles` in the standard way

## Create mode

1. Load `.reversa/templates/principles-template.md`
2. Ask the user for the candidate principles, in a batch or one at a time
3. For each principle:
   3.1. Assign a sequential Roman numeral (I, II, III, ...)
   3.2. Ask for a short title, a description and one concrete example of application
   3.3. Record the creation date
4. In the "Impact" section, list which templates will be affected when the principle changes (always `requirements-template.md`, `roadmap-template.md`, and potentially `actions-template.md`)
5. Start the "Change history" section with the initial entry

## Update mode

1. Show the user the current list of numbered principles
2. Ask which operation they want:
   2.1. Add a new one (continues with the next Roman numeral, never recycles)
   2.2. Change the text of an existing one (keeps the numbering, records the change in the history)
   2.3. Retire one (does NOT delete it; marks it `retired on YYYY-MM-DD` and moves it to the end of the document)
3. After the operation:
   3.1. Update the "Impact" section if needed
   3.2. Add an entry to the "Change history"

## Impact propagation

1. For each template listed in the "Impact" section:
   1.1. Read the template at `.reversa/templates/<name>`
   1.2. Check whether the template needs a new placeholder or section to reflect the principle
   1.3. NEVER rewrite the whole template automatically; only produce an impact report at `.reversa/principles-impact-YYYYMMDD.md`
2. The report lists, per template, textual suggestions for adjustment
3. Applying those suggestions is a human decision; this skill only suggests

## Persistence

- Write `.reversa/principles.md` with an atomic write
- Write the impact report to `.reversa/principles-impact-YYYYMMDD.md`
- Never overwrite older impact reports; every run creates a dated file

## Post-execution hooks

Apply `after-principles` in the standard way.

## Final report to the user

1. The absolute path of `principles.md`
2. The list of active principles, with numbering and short title
3. The list of retired principles, if any
4. The path of the generated impact report
5. A notice: new or changed principles only take effect for features started after this date

Finish with:

> Type **CONTINUE** to proceed with whatever you want to do next.
