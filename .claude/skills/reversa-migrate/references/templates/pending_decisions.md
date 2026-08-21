---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: pending_decisions
producedBy: orchestrator
hash: "sha256:<hash of the body below the front-matter>"
---

# Pending Decisions

> Transient file used during human pauses. Each item describes an open decision with its context and options.
> Once the user answers, the item is moved to `ambiguity_log.md` (or to the artifact that owns the decision) and this file can be deleted.

## Open decisions

### PD-001
- **Requesting agent**: paradigm_advisor | curator | strategist | designer | screen_translator | inspector
- **Topic**: <short title>
- **Context**:
  <text explaining why this decision is needed here>
- **Options**:
  1. <option 1>
  2. <option 2>
  3. <option 3>
- **Proposed default** (used with `--auto`): <option number>
- **Impact if decided wrongly**: <text>
- **Where the decision will be recorded**: <e.g. `paradigm_decision.md § User decision`>

<repeat per decision>

## How to answer

- In the chat: reply directly to the agent with the option number and your reasoning.
- In a file: edit this `pending_decisions.md`, adding an `Answer:` field to each item.
