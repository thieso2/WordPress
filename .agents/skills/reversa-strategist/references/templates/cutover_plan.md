---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: cutover_plan
producedBy: strategist
hash: "sha256:<hash of the body below the front-matter>"
---

# Cutover Plan

> Plan for cutting over from the legacy system to the new one, aligned with the strategy chosen in `migration_strategy.md`.

## Base strategy
- **Confirmed strategy**: <reference to migration_strategy.md>

## Prerequisites
- [ ] <prerequisite 1: e.g. behavioral parity ≥ X% for N days>
- [ ] <prerequisite 2>
- [ ] <prerequisite 3>

## Cutover window
- **Target date**: <ISO-8601 or window>
- **Estimated duration**: <hours>
- **Affected environment**: <production / staging / other>
- **Advance communication**: <stakeholders notified, lead time>

## Cutover steps

| # | Step | Owner | Duration | Reversible? |
|---|---|---|---|---|
| 1 | <e.g. freeze writes on the legacy system> | | | |
| 2 | <e.g. final data ETL> | | | |
| 3 | <e.g. DNS routing> | | | |
| 4 | <e.g. smoke tests on the new system> | | | |

## Rollback plan
- **Trigger criteria**: <when a rollback is decided>
- **Steps**:
  1. <step>
  2. <step>
- **Maximum acceptable time before rollback**: <minutes / hours>
- **Rollback owner**: <name / role>

## Go / no-go criteria
- **Go**:
  - <criterion 1>
  - <criterion 2>
- **No-go**:
  - <criterion 1>
  - <criterion 2>

## Post-cutover
- [ ] Extended monitoring for <period>
- [ ] Parity validation per `parity_specs.md`
- [ ] Decommission the legacy system on <date>

## Notes
<Additional observations.>
