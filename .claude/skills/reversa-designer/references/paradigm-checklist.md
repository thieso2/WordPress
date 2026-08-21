# Target-paradigm fidelity checklist

Quick checklist the Designer applies before finalizing `target_architecture.md` and `target_domain_model.md`.

## Event-driven

- [ ] Events are named in the past tense (`OrderCreated`, not `CreateOrder`).
- [ ] Every event has an explicit, versioned schema.
- [ ] Commands and events are distinct.
- [ ] Idempotency is guaranteed by construction (event ID, deduplication key).
- [ ] Message ordering is handled via a partitioning key.
- [ ] Saga / orchestrator for distributed transactions, with compensation.
- [ ] Outbox table for at-least-once guarantees between the DB and the queue.
- [ ] DLQ defined for terminal failures.

## OO with DI

- [ ] Explicit interfaces for external dependencies.
- [ ] Injection container configured per bounded context.
- [ ] Aggregates do not depend on infrastructure (no persistence inside the aggregate).
- [ ] Concrete repositories live in the infrastructure layer.
- [ ] Active Record explicitly forbidden.

## Functional

- [ ] Immutable types in the domain.
- [ ] Pure functions at the core; side effects at the edges.
- [ ] State is a sequence of transformations, not mutation.
- [ ] Composition used to build flows.
- [ ] Algebraic types (sum types) for disjoint states.

## Actor model

- [ ] Each actor has a mailbox and isolated state.
- [ ] Hierarchical supervision defined.
- [ ] Messages between actors are immutable.
- [ ] Persistence via event sourcing or snapshots.

## Procedural / dataflow

- [ ] The flow is expressed as a pipeline of transformations.
- [ ] No shared mutation.
- [ ] Stages are independent and testable in isolation.

## General (any paradigm)

- [ ] Every element points back to a legacy origin or to `discard_log.md`.
- [ ] Bounded contexts justified by cohesion, not by the legacy structure.
- [ ] The Mermaid diagram renders without errors.
- [ ] Architectural decisions documented in a condensed ADR format.
