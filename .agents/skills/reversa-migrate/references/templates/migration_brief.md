---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: migration_brief
producedBy: orchestrator
hash: "sha256:<hash of the body below the front-matter>"
---

# Migration Brief

> Migration criteria document collected in an interview at the start of `/reversa-migrate`.
> Consumed by all six agents of the Migration Team. It does not ask about the paradigm (the Paradigm Advisor's responsibility) nor the appetite (derived in `paradigm_decision.md`).

## Migration goal
<Why does this migration exist? What changes for the business whether it happens or not.>

## Success metrics
- <metric 1, with a clear numeric or qualitative target>
- <metric 2>
- <metric 3>

## Constraints
- **Deadline**: <date or window>
- **Budget**: <range, team, hiring involved>
- **Technical**: <external APIs that cannot change, contracts, regulatory rules>
- **Operational**: <maintenance windows, SLAs during the migration>

## Known risk factors
- <risk 1: short description>
- <risk 2>

## Stakeholders
| Name / role | Responsibility in the migration |
|---|---|
| <name> | <responsibility> |

## Target stack
- **Language**: <e.g. Node.js 20>
- **Framework**: <e.g. Fastify>
- **Database**: <e.g. PostgreSQL 16>
- **Messaging** (if any): <e.g. SQS, Kafka, none>
- **Infrastructure**: <e.g. AWS Lambda, Kubernetes, on-premise>
- **Other relevant components**: <cache, observability, gateway>

## Declared scope
- **Included**: <legacy modules that are in scope>
- **Excluded**: <modules left out or to be decommissioned>

## Free-form notes
<Any context the user wants on record for the agents to read.>
