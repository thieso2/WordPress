---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: screen_modernization_decision
producedBy: screen-translator
decidedBy: <human-id, or null when mode=skipped>
decidedAt: <ISO-8601, or null when mode=skipped>
mode: literal | modernized | hybrid | skipped
sourcePlatform: <slug, or null when mode=skipped>
targetPlatform: <slug, or null when mode=skipped>
hash: "sha256:<hash of the body below the front-matter>"
---

> When `mode: skipped`, this decision **did not go through a human**: it was emitted automatically by the Screen Translator because the legacy system has no UI. Only the "Context" and "Decision" sections are filled in, with the reason for the omission; the rest stay as N/A. The Inspector reads `mode: skipped` in the front-matter and skips visual parity without asking.


# Screen Modernization Decision

> A conscious decision about how to translate the legacy system's screens: byte-for-byte observable parity, an idiomatic redesign for the target platform, or a screen-by-screen combination.
> This artifact is required reading for the Screen Translator itself (to generate `target_screens.md`), for the Inspector (to build parity tests suited to the mode) and for the coding agent.

## Context

- **Detected source platform**: <slug> (e.g. `cobol-ansi-tui`, `delphi-vcl`, `asp-classic`, `android-xml`)
- **Confidence**: 🟢 CONFIRMED | 🟡 INFERRED | 🔴 GAP | ⚠️ AMBIGUOUS
- **Target platform**: <slug> (e.g. `go-cli`, `web-spa`, `flutter`, `tauri`)
- **Screens inventoried**: <N>
- **Inventory source**: `_reversa_sdd/screens/inventory.json` + `_reversa_sdd/ui/inventory.md`
- **Adapter applied**: `<adapters/source__target>` (see `references/adapter-pairs.md`)

## Modes evaluated

### Mode: literal
- **Definition**: byte-for-byte or pixel-equivalent observable parity between the legacy system and the new one.
- **Trade-offs**:
  - Implementation cost: <high | medium | low>
  - Visual fidelity: <high | medium | low>
  - Feasibility of constructive parity tests: <yes | partial | no>
  - Expected end-user acceptance: <high | medium | low>
  - Future technical debt: <high | medium | low>
- **Recommended**: <yes | no>
- **Rationale**: <short text>

### Mode: modernized
- **Definition**: an idiomatic redesign for the target platform, preserving the information and the flow but re-expressing the hierarchy and the interaction.
- **Trade-offs**:
  - Implementation cost: <high | medium | low>
  - Visual fidelity: <high | medium | low>
  - Feasibility of constructive parity tests: <yes | partial | no>
  - Expected end-user acceptance: <high | medium | low>
  - Future technical debt: <high | medium | low>
- **Recommended**: <yes | no>
- **Rationale**: <short text>

### Mode: hybrid
- **Definition**: some screens literal, some modernized, with explicit lists.
- **Trade-offs**:
  - Implementation cost: <high | medium | low>
  - Mixed visual fidelity: <description>
  - Feasibility of parity tests: <description per subset>
  - Cost of maintaining the split: <high | medium | low>
- **Recommended**: <yes | no>
- **Rationale**: <short text>

## Decision

- **Chosen mode**: <literal | modernized | hybrid>
- **The human's rationale**: <text>
- **Rejected alternatives**: <a brief list with reasons>
- **Decided at**: <ISO-8601>
- **Decided by**: <name or identifier>

### In hybrid mode, the explicit lists (mandatory)

**Screens in literal mode**:
- <screen 1>
- <screen 2>

**Screens in modernized mode**:
- <screen 3>
- <screen 4>

> Empty lists block Phase 2. The agent refuses to proceed.

## Pending implications for Phase 2

| Step | Implication | How to honor it |
|---|---|---|
| Generating `target_screens.md` | <implication> | <expected action> |
| Capturing golden files | <implication> | <expected action> |
| Design-system tokens | <implication> | <expected action> |
| Textual content | Preserve it literally unless copy editing is explicitly approved | <expected action> |

## Implications for the Inspector

- **Parity strategy**:
  - Literal mode → byte-for-byte / pixel-equivalent observable parity, validated by golden files when the oracle runs.
  - Modernized mode → a semantic contract (events, transitions, textual content, states), with no byte-for-byte visual comparison.
  - Hybrid mode → a mixed strategy, declared per screen in `parity_specs.md`.
- **Known deviations to propagate**: see `screen_deviation_log.md`.

## Notes

<Additional points the coder, the Inspector and the agent need to know in order to honor the decision. It includes, for example, an explicit approval of copy editing, a tolerance for approximate rendering, or marking screens that cannot be modernized for regulatory reasons.>
