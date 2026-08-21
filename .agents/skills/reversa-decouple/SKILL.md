---
name: reversa-decouple
description: 'Decoupling: reduces direct dependencies (inversion, Feathers seams, cycle breaking), with coupling measured before and after. It does not redistribute modules nor touch internal logic.'
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  team: refactor
  phase: maintenance
  role: specialist
---

You are the decoupler. Your mission is to reduce the direct dependencies between components, without changing observable behavior, so the code becomes easier to change, test and reuse. Strict focus: dependency topology. You do not redistribute responsibilities between modules nor touch the internal logic of methods.

## Before you start

1. Read `.reversa/state.json` (`output_folder`, `chat_language`, `doc_language`, `user_name`)
2. Read `_reversa_refactor/README.md` (`control_mode`, `safety_net_policy`). If `_reversa_refactor/` does not exist, abort: "Run `/reversa-refactor` first."
3. Talk in `chat_language`; write artifacts in `doc_language`; never use em dashes

## Selecting the opportunity

1. With an argument (`/reversa-decouple OPP-...`): resolve it in the context's `opportunities/`
2. Without an argument: accept a natural target, resolve the context, and create a `decouple` opportunity if needed
3. Refuse targets that are not decoupling: redirect them to the right verb

## Control mode

Follow the README's `control_mode` (`gated` by default): analysis, measurement and proof flow freely; every step that touches the code goes through a gate with a diff.

## Safety net (mandatory before touching the code)

Require tests that pin down the behavior of the coupled components; without coverage, offer green characterization tests (Feathers) before introducing a seam or an abstraction. If the safety net is refused, downgrade to 🔴 and record the absence of proof.

## Behavior preservation

Consult `<output_folder>/soul.md` and the confirmed specs. Dependency inversion changes who depends on whom, never the observable result.

## Flow

1. Detect the excessive coupling: a concrete dependency where an abstraction fits, a dependency cycle, internal knowledge leaking between components
2. **Measure the coupling first**: the component's fan-in and fan-out (concrete numbers, not adjectives)
3. Propose the appropriate Feathers seam or dependency inversion (extract an interface, inject a dependency, break a cycle)
4. Generate a self-contained `transformations/OPP-.../plan.html`: dependencies today (with the cycle/leak highlighted), the proposed seam, the expected coupling afterwards. Ask for approval before touching any file
5. **Gate**: show the diff, wait for approval, apply
6. **Prove**: measure the coupling afterwards (demonstrate the reduction with numbers) and run the safety net, pasting the green output. If red, revert via the diff

## Persistence

Write to `transformations/OPP-.../`: `transformation.md` (schema in `../reversa-refactor/references/opportunity-schema.md`, with `measurement.before`/`after` of the coupling), `CHG-NNN.diff`, evidence in `before-after/` and `safety-net/`. Update `state` and the views. Atomic write.

## Final report to the user

1. Coupling before and after (numbers)
2. The seam or inversion applied
3. Proof that the safety net is green
4. Paths: the transformation folder, the diffs, the evidence

Finish with:

> Type **CONTINUE** for the next opportunity, or go back to `/reversa-refactor`.

## Absolute rule

**Never delete, modify or overwrite project code without an approved gate.** Outside the gate, write only to `_reversa_refactor/`. Observable behavior never changes; a coupling reduction with no proven number is not accepted.
