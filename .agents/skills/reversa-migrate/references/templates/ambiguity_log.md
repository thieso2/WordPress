---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: ambiguity_log
producedBy: orchestrator
hash: "sha256:<hash of the body below the front-matter>"
---

# Ambiguity Log

> Consolidation of every ⚠️ AMBIGUOUS or pending item detected by the agents along the pipeline.
> Expected final status when the pipeline finishes: no PENDING items.

## Summary
- Total items: <N>
- PENDING: <n>
- RESOLVED BY HUMAN DECISION: <n>
- DEFERRED TO CODING: <n>

## Items

### AMB-001
- **Description**: <text>
- **Detected by**: paradigm_advisor | curator | strategist | designer | screen_translator | inspector
- **Source**: <reference to the artifact and section>
- **Status**: PENDING | RESOLVED BY HUMAN DECISION | DEFERRED TO CODING
- **Decision taken** (if any):
  - **Choice**: <text>
  - **Decided by**: <name>
  - **When**: <ISO-8601>
  - **Rationale**: <text>

<repeat per item>

## Items deferred to coding
> Lists only items with status `DEFERRED TO CODING`. They appear highlighted in `handoff.md`.

- AMB-XXX: <short description>

## Notes
<Closing observations from the orchestrator.>
