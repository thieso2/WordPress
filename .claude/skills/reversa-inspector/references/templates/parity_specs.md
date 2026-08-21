---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: parity_specs
producedBy: inspector
hash: "sha256:<hash of the body below the front-matter>"
---

# Parity Specs

> Strategy for validating behavioral equivalence between the legacy system and the new one, adapted to the paradigm chosen in `paradigm_decision.md`.

## General strategy
- **Applicable validation modes** (tick the ones used):
  - [ ] Shadow mode (traffic mirroring with asynchronous comparison)
  - [ ] Characterization tests (suite derived from the legacy system's current behavior)
  - [ ] Contract tests (external interfaces)
  - [ ] Data parity (snapshots and checksums)
  - [ ] Other: <specify>

## "Parity accepted" criteria
- **Primary metric**: <e.g. functional divergence rate < 0.01% over N consecutive days>
- **Observation window**: <evaluation period>
- **Blocking criterion**: <when insufficient parity blocks the cutover>

## Coverage adapted to the paradigm

> This section changes according to the target paradigm confirmed in `paradigm_decision.md`.

### No paradigm change
- Standard functional equivalence: same input → same output → same observable side effect.

### Synchronous → event-driven change
- **Message ordering**: <acceptance criterion per channel / partition>
- **Idempotency**: <proof that reprocessing does not duplicate the effect>
- **Eventual consistency**: <maximum accepted propagation window>
- **Behavior under queue failure**: <retry, DLQ, replay>

### Procedural → OO change
- **Aggregate invariants**: <set to validate>
- **Validation in factories / constructors**: <critical cases>

### OO → functional change
- **Immutability**: <critical points to observe>
- **Absence of expected side effects**: <where the legacy system had an implicit side effect>
- **Equivalence under composition**: <composed functions are equivalent to the legacy flow>

## Test types to apply
- **Functional**: <description, tooling>
- **Contract**: <description, tooling>
- **Load / performance**: <description, targets>
- **Resilience** (if applicable): <queue failure, external dependency unavailable>

## Reuse of characterization_specs from the discovery team
- **Source**: `_reversa_sdd/characterization_specs/` or an equivalent that is available.
- **Adaptations needed for the new system**: <text>

## Outputs
- `parity_tests/*.feature`: Gherkin scenarios for the critical flows.

## Notes
<Additional observations.>
