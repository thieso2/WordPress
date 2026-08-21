# [Unit Name], Technical Design

> Template for the `design.md` file. Focuses on HOW the unit is built, based on the legacy code that was read.

## Interface
[Inputs, outputs, parameters, data types]

For HTTP endpoints:

| Method | Path | Input | Output | Status codes |
|--------|------|-------|--------|--------------|
| GET | `/resource/:id` | `id: string` | `Resource` | 200, 404 |
| POST | `/resource` | `ResourceCreate` | `Resource` | 201, 400, 409 |

For classes/functions:

| Symbol | Signature | Returns | Note |
|--------|-----------|---------|------|
| `ClassName.method` | `(arg1: T, arg2: U)` | `V` | [Relevant detail] |

## Main Flow
1. [Step 1, referencing the legacy file where applicable]
2. [Step 2]
3. [Step N]

## Alternative Flows
- **[Special condition]:** [behavior]
- **[Error case]:** [behavior]

## Dependencies
- [Component X], [why, how it is used]
- [Service Y], [why, how it is used]

## Identified Design Decisions

| Decision | Evidence in the code | Confidence |
|----------|----------------------|------------|
| [e.g. persistence via Prisma with soft-delete] | `prisma/schema.prisma:42` | 🟢 |
| [e.g. in-memory cache with a 5min TTL] | `cache/store.ts:18` | 🟡 |

## Internal State
[If the unit keeps state, describe which fields, where they are stored, how they evolve]

## Observability
[Logs, metrics, traces emitted by the unit, referencing the code]

## Risks and Gaps
- 🔴 [Behavior that could not be inferred from the code, needs human validation]
- 🟡 [Assumption that may be wrong]
