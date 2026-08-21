# `--auto` defaults

When the user invokes `/reversa-migrate --auto`, the orchestrator skips the human pauses and applies these defaults. Before starting, the notice to the user lists every one of them. Each auto-applied item is recorded in `ambiguity_log.md` with the tag `auto-decided` for later review.

## Paradigm Advisor
- Chooses **option 1: adopt the target stack's natural paradigm**.
- `derived_appetite` = `transformational`.

## Curator
- HUMAN DECISION items are marked as pending in `ambiguity_log.md` and do not block the pipeline.
- 🟡 INFERRED items → MIGRATE (with the note "validate in the coding agent").
- 🔴 GAP and ⚠️ AMBIGUOUS items → DISCARD with the explicit note "auto-discarded, needs review".

## Strategist
- Adopts the strategy marked as **recommended**.
- `critical` risks that would need a human owner get `owner = "TBD"` in `risk_register.md`.

## Designer
- **Topology (Phase 1)**: accepts the proposed modern topology (option 2). The rationale recorded in `topology_decision.md` is the Designer's own; `ambiguity_log.md` keeps the `auto-decided` tag for later review. Rationale: `--auto` is for users who want the recommended path; refusing to decide would stop the pipeline and break the `--auto` contract.
- **Architecture (Phase 2)**: approves the first proposal without iterating.
- Bounded contexts, events and ADRs are accepted as proposed.

## Screen Translator
- **Mode (Phase 1)**: adopts the mode the agent recommends for the detected source→target pair (literal for textual pairs; modernized for platform changes; hybrid only with an explicit list, and therefore never in `--auto`).
- **Generation (Phase 2)**: accepts the generated `target_screens.md` and propagates deviations as `pending`. `--auto` does not approve deviations on its own; they stay in `ambiguity_log.md` as `auto-decided` for later review, without blocking the handoff (an exception within `--auto`: if a deviation has `type=fix` in literal mode, the agent refuses and asks for human approval even in `--auto`, since changing text without sign-off breaks expectations).
- **Golden file capture**: not automated in `--auto` (the oracle driver is OQ-02). It only emits a `manifest.yaml` with suggested commands.
- **Legacy system with no UI**: marks the status as `skipped` automatically, without asking.
- **Missing Discovery prerequisites** (`_reversa_sdd/design-system/` or `_reversa_sdd/ui/inventory.md`): creates a minimal `tokens-derived.md` and builds the inventory from the source code alone; raises an alert in `ambiguity_log.md`.

## Inspector
- Uses parity criteria derived directly from the chosen paradigm (see `parity-coverage-matrix.md` in the agent).
- Does not negotiate the "parity accepted" criterion with the user.

## Detected manual modifications
- Adopts **option (a)**: preserve the manually modified version and abort regenerating that artifact. It never destroys human work.

## Mandatory notice

Always present this before starting `--auto`:

> "⚠️ `--auto` mode enabled. The defaults below will be applied without pausing for confirmation:
> - Paradigm Advisor: adopt the stack's natural paradigm (transformational).
> - Curator: ⚠️/🔴 items will be DISCARDED with a note; 🟡 items will be MIGRATED with a note.
> - Strategist: the recommended strategy will be adopted.
> - Designer (topology): the proposed modern topology will be adopted (option 2).
> - Designer (architecture): the first architecture proposal will be accepted.
> - Screen Translator (mode): adopts the recommended mode for the source→target pair. Hybrid mode never in `--auto`. On a legacy system with no UI, status `skipped`.
> - Screen Translator (generation): deviations stay pending in `ambiguity_log.md` (not approved). Golden file capture is not automated (manifest only).
> - Inspector: parity criteria derived from the paradigm with no interactive adjustment.
>
> The final `handoff.md` will highlight every auto-decided item for later review.
> Confirm? (y/N)"
