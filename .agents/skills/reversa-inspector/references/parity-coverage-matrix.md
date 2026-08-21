# Parity coverage matrix

Reference table for defining the minimum set of `.feature` scenarios per flow, according to the paradigm transition.

## Coverage per transition

| Transition | Minimum scenarios per flow |
|---|---|
| no change | `@parity` (input → expected output) |
| procedural → OO | `@parity` + `@invariant` (aggregate invariant validated) |
| procedural → event-driven | `@parity` + `@idempotency` + `@ordering` + `@dlq` (behavior under queue failure) |
| classic OO → OO with DI | `@parity` + `@composition` (no Active Record dependency) |
| classic OO → event-driven | `@parity` + `@idempotency` + `@ordering` + `@saga` (compensation on failure) |
| classic OO → functional | `@parity` + `@immutability` + `@composition` |
| OO with DI → event-driven | `@parity` + `@idempotency` + `@ordering` |
| functional → event-driven | `@parity` + `@idempotency` + `@ordering` |
| any → actor model | `@parity` + `@supervision` (recovery after a failure) |

## Agreed tags

- `@parity`: always present; the main equivalence check.
- `@critical`: critical flow (regulatory, financial, sensitive data).
- `@regulatory`: when there is a formal external requirement.
- `@idempotency`: reprocessing does not duplicate the effect.
- `@ordering`: ordering per key is respected.
- `@dlq`: behavior when a message reaches the dead letter queue.
- `@saga`: compensation in a distributed transaction.
- `@invariant`: aggregate invariant validated.
- `@composition`: equivalent behavior under functional composition.
- `@immutability`: there is no shared mutation.
- `@supervision`: the supervisor recovers a failed actor.

## Typical "parity accepted" criteria

| System type | Primary metric |
|---|---|
| Web app without strong regulation | functional divergence < 1% over 7 days |
| Public API | functional divergence < 0.1% over 30 days + zero divergence on public contracts |
| Fiscal / regulatory system | functional divergence < 0.01% over 60 days + zero divergence on regulated fields |
| Financial system | financial divergence by monetary value < 0.001% + zero divergence on totals |
| Low-criticality internal system | functional divergence < 5% over 7 days |

## Reuse of characterization_specs

When `_reversa_sdd/characterization_specs/` exists:

1. For each spec → derive the matching `.feature`, adapting inputs/outputs to the new system.
2. Keep the original `spec-id` in the traceability.
3. Add extra scenarios per the "Minimum scenarios per flow" table.

When it does not exist:

1. Infer the critical flows from `code-analysis.md` + `sequences/` + `BR-MIGRATE` rules marked as critical.
2. Document the gap in `parity_specs.md § Reuse of characterization_specs`.
