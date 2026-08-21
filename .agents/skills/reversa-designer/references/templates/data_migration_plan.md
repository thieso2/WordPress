---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: data_migration_plan
producedBy: designer
hash: "sha256:<hash of the body below the front-matter>"
---

# Data Migration Plan

> Plan for migrating data from the legacy system to the new one: mapping, transformations, ETL, data cutover and validation.

## Summary
- Estimated volume: <rows / GB per main entity>
- Migration window: <see `cutover_plan.md`>
- Strategy: prior backfill + delta + cutover | single bulk load | continuous replication

## Legacy → new mapping

| Source | Target | Type | Notes |
|---|---|---|---|
| `<legacy schema>.tb_pedidos` | `orders` | rename | type normalization |
| `<legacy schema>.tb_pedido_item` | `order_items` | rename | FK adjusted |
| `<legacy schema>.usr_x` | `users` (partial) + `profiles` | split | extracts profile data |

## Transformations

### Transformation T-01: <name>
- **Applies to**: <column or table>
- **Rule**: <explicit text>
- **Handling of invalid values**: <drop | reject | fill with default>
- **Rule origin**: <reference to `target_business_rules.md` or `discard_log.md`>

<repeat per transformation>

## ETL strategy

- **Tooling**: <e.g. SQL scripts, dbt, Airbyte, custom>
- **Flow**:
  1. <extract>
  2. <transform>
  3. <load>
- **Idempotency**: <how the ETL is safe to re-run>
- **Expected throughput**: <e.g. 50k rows/s>

## Backfill and delta

- **Backfill**: <start date, scope, duration>
- **Delta capture**:
  - **Mechanism**: CDC | log mining | timestamps | replication | trigger
  - **Acceptable latency**: <seconds>
- **Periodic reconciliation**: <frequency, scope>

## Data cutover

> See also `cutover_plan.md`. Only the data-specific part belongs here.

- **Window**: <ISO-8601>
- **Cutover sequence**:
  1. <step>
  2. <step>
- **Post-cutover verification**:
  - **Counts**: <which tables, tolerance>
  - **Checksums**: <critical columns>

## Quality validation

| Metric | Target | Measurement source |
|---|---|---|
| Count per entity | equal ± 0% | direct comparison |
| Sum of monetary values | equal ± 0.01% | financial reconciliation |
| Referential integrity | 0 orphans | audit scripts |

## Data-specific risks
- <RISK-XXX: see `risk_register.md`>

## Notes
<Additional observations.>
