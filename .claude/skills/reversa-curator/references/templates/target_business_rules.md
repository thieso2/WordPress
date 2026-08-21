---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: target_business_rules
producedBy: curator
hash: "sha256:<hash of the body below the front-matter>"
---

# Target Business Rules

> Catalog of the legacy business rules with a migration decision: MIGRATE, DISCARD or HUMAN DECISION.
> Every item traces back to its origin in `_reversa_sdd/` and respects `paradigm_decision.md`.

## Summary
- Total rules analyzed: <N>
- MIGRATE: <n>
- DISCARD: <n> (detailed in `discard_log.md`)
- HUMAN DECISION: <n>

## MIGRATE rules

### BR-MIGRATE-001
- **Source**: `_reversa_sdd/<unit>/{requirements,design}.md` § <section>
- **Original confidence**: 🟢 | 🟡 | 🔴 | ⚠️
- **Description**: <rule>
- **Migration rationale**: <why it migrates>
- **Compatibility with the target paradigm**: <note; e.g. will need to be expressed as an event>

<repeat per rule>

## DISCARD rules (summary)

| ID | Source | Short reason | Paradigm-related? |
|---|---|---|---|
| BR-DISCARD-001 | <ref> | <reason> | yes/no |

> Full detail in `discard_log.md`.

## HUMAN DECISION rules

### BR-HUMAN-001
- **Source**: <ref>
- **Ambiguity type**: ⚠️ AMBIGUOUS | 🔴 GAP | stakeholder dependency
- **Description**: <rule>
- **Options**: <clear options>
- **Curator's recommendation**: <suggested option and why>
- **Status**: PENDING | RESOLVED (choice + decider + date)

<repeat per item>

## Notes
<General observations from the Curator. Items that will be consolidated into `ambiguity_log.md`.>
