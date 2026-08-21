# Reconstruction Plan — {{PROJECT_NAME}}

**Stack:** {{STACK}}
**Generated at:** {{DATE}}
**Status:** {{TOTAL}} tasks | {{DONE}} done | {{PENDING}} pending

---

## Pre-flight alerts

> Review these points before starting. Gaps marked with ⚠️ block the associated task.

{{#each PREFLIGHT_ALERTS}}
- ⚠️ **{{this.gap}}** — blocks Task {{this.task_number}} ({{this.task_name}})
{{/each}}

{{#if NO_ALERTS}}
No critical gaps identified. Safe to start.
{{/if}}

---

## Tasks

### Task 01 — Database Schema
**Status:** pending
**Reads:** `_reversa_sdd/erd-complete.md`, `_reversa_sdd/data-dictionary.md`
**Builds:** migrations, schema, ORM models (according to the detected stack)
**Done when:** Every table in the ERD exists with the correct types, constraints and foreign keys

---

### Task 02 — Domain Entities
**Status:** pending
**Reads:** `_reversa_sdd/domain.md`, `_reversa_sdd/data-dictionary.md`
**Builds:** entities, value objects, domain validations
**Done when:** Every entity is implemented with the described business rules

---

### Task 03 — State Machines
**Status:** pending
**Reads:** `_reversa_sdd/state-machines.md`
**Builds:** implementation of each entity's state flows
**Done when:** Every documented state and transition is implemented
**Note:** Skip this task if `_reversa_sdd/state-machines.md` does not exist

---

<!-- COMPONENT_TASKS_START -->
<!-- The Reconstructor inserts one task per unit here, in the bottom-up order determined by dependencies.md -->
<!-- Example of a unit task: -->

### Task 04 — [Unit Name]
**Status:** pending
**Reads:** `_reversa_sdd/[unit]/requirements.md`, `_reversa_sdd/[unit]/design.md`, `_reversa_sdd/[unit]/tasks.md`, `_reversa_sdd/dependencies.md`
**Builds:** [module path according to the stack]
**Done when:** [acceptance criterion taken from requirements.md, the "Given/When/Then" field]
**Alert:** [if there is an associated gap, describe it here]

<!-- COMPONENT_TASKS_END -->

---

### Task {{API_N}} — API Layer
**Status:** pending
**Reads:** `_reversa_sdd/openapi/[list of files]`
**Builds:** endpoints, controllers, middleware, authentication
**Done when:** Every endpoint responds according to the OpenAPI contracts

---

### Task {{STORIES_N}} — User Flows
**Status:** pending
**Reads:** `_reversa_sdd/user-stories/[list of files]`
**Builds:** end-to-end integration, complete user flows
**Done when:** Every acceptance criterion of the user stories is satisfied
