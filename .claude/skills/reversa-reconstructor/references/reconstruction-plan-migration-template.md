# Reconstruction Plan — {{PROJECT_NAME}}

**Source:** migration
**Target paradigm:** {{PARADIGM}}
**Topology:** {{TOPOLOGY}}
**Stack:** {{STACK}}
**Strategy:** {{STRATEGY}}
**Generated at:** {{DATE}}
**Status:** {{TOTAL}} tasks | {{DONE}} done | {{PENDING}} pending

---

## Pre-flight alerts

> Review these before starting. Items DEFERRED TO CODING in `ambiguity_log.md` that affect specific tasks are flagged.

{{#each PREFLIGHT_ALERTS}}
- ⚠️ **{{this.item}}** — affects Task {{this.task_number}} ({{this.task_name}}). Source: `_reversa_sdd/migration/ambiguity_log.md`
{{/each}}

{{#if NO_ALERTS}}
No blocking items. Safe to start.
{{/if}}

---

## Tasks

### Task 01 — New Project Setup
**Status:** pending
**Reads:** `_reversa_sdd/migration/topology_decision.md`, `_reversa_sdd/migration/paradigm_decision.md`
**Builds:** the initial folder/module structure, base configuration, minimal dependencies
**Done when:** The new repository's skeleton matches the approved topology and the chosen paradigm

---

### Task 02 — Target Database Schema
**Status:** pending
**Reads:** `_reversa_sdd/migration/target_data_model.md`
**Builds:** migrations, schema, ORM models (per the stack)
**Done when:** Every table/collection in the target data model exists with the correct types, constraints and relationships

---

### Task 03 — Data Migration Plan
**Status:** pending
**Reads:** `_reversa_sdd/migration/data_migration_plan.md`, `_reversa_sdd/migration/target_data_model.md`
**Builds:** ETL scripts/jobs, integrity validations, rollback
**Done when:** The migration scripts have been tested at a representative volume and the validations match the plan
**Note:** Skip this if the strategy in `migration_strategy.md` does not involve a data migration (e.g. a brand-new system with no legacy data)

---

### Task 04 — Target Domain Entities
**Status:** pending
**Reads:** `_reversa_sdd/migration/target_domain_model.md`, `_reversa_sdd/migration/target_business_rules.md`
**Builds:** entities, value objects, aggregates, business rules
**Done when:** The domain is implemented per the target model and the business rules are covered by tests

---

<!-- MODULE_TASKS_START -->
<!-- The Reconstructor inserts one task per module identified in target_architecture.md here, in dependency order. -->
<!-- Example: -->

### Task 05 — [Module Name]
**Status:** pending
**Reads:** `_reversa_sdd/migration/target_architecture.md` (section `[module]`), `_reversa_sdd/migration/target_domain_model.md`, `_reversa_sdd/migration/target_business_rules.md`
**Builds:** [the module path per the approved topology]
**Done when:** [the parity criterion taken from parity_specs.md, if applicable; otherwise the criterion in target_architecture.md]
**Alert:** [if there is an associated DEFERRED TO CODING item]

<!-- MODULE_TASKS_END -->

---

### Task {{CUTOVER_N}} — Cutover
**Status:** pending
**Reads:** `_reversa_sdd/migration/cutover_plan.md`
**Builds:** cutover scripts/checklists, the traffic switch, an executable rollback plan
**Done when:** The new system receives traffic per the plan and the legacy one can be shut down/frozen as decided

---

### Task {{PARITY_N}} — Parity Validation
**Status:** pending
**Reads:** `_reversa_sdd/migration/parity_specs.md`, `_reversa_sdd/migration/parity_tests/[list of .feature files]`
**Builds:** a parity test suite running against both the legacy and the new system, plus a divergence report
**Done when:** Every critical flow defined in parity_specs.md passes on both systems with equivalent results
