---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: target_architecture
producedBy: designer
hash: "sha256:<hash of the body below the front-matter>"
---

# Target Architecture

> Target architecture of the new system, respecting the paradigm chosen in `paradigm_decision.md` and the strategy confirmed in `migration_strategy.md`.

## Overview
<Summary in 3 to 6 lines: what the new system is, which paradigm it follows, which boundaries it has with the legacy system during the migration.>

## Diagram (Mermaid)

```mermaid
flowchart LR
    %% Replace with the real diagram
    Client -->|HTTP| API
    API --> Service
    Service --> Database[(DB)]
    Service -.events.-> Queue[[Messaging]]
```

## Components

| Component | Type | Responsibility | Origin (legacy / new / merged) |
|---|---|---|---|
| <name> | API / Service / Worker / DB / Queue | <text> | <ref to legacy or "new"> |

## Bounded contexts

### BC-01: <name>
- **Responsibility**: <text>
- **Rationale for the grouping / separation**: <why this context was not decomposed 1-to-1 from the legacy system>
- **Internal components**: <list>
- **Published events** (if the paradigm is event-driven): <list>
- **Consumed events**: <list>

<repeat per context>

## Architectural decisions (condensed ADR style)

### AD-01: <title>
- **Decision**: <text>
- **Rejected alternatives**: <list>
- **Rationale**: <text, tying back to the paradigm, strategy and appetite>
- **Traceability**: <reference to the legacy system or to the discard_log>

## Fidelity to the chosen paradigm

> Mandatory section when there is a paradigm change. Demonstrates that the architecture honors the decision in `paradigm_decision.md`.

- **Target paradigm**: <from `paradigm_decision.md`>
- **How the architecture honors that paradigm**:
  - <e.g. event-driven → explicit events, message schemas, eventual-consistency strategy>
  - <e.g. OO with DI → interfaces, injection container, clear boundaries between layers>
  - <e.g. functional → immutable types, composition, no side effects in the domain>

## Boundaries with the legacy system during the migration
- <e.g. during the Strangler Fig, the new API reroutes calls from legacy X until phase Y>

## Notes
<Additional design observations.>
