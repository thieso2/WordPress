---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: paradigm_decision
producedBy: paradigm_advisor
hash: "sha256:<hash of the body below the front-matter>"
---

# Paradigm Decision

> A conscious decision about how to handle the change (or absence of change) of paradigm between the legacy system and the target stack.
> This artifact is required reading first for every downstream agent and for the coding agent.

## Detected legacy paradigm
- **Main paradigm**: <procedural | classic OO | OO with DI | functional | event-driven | actor model | dataflow | hybrid: ...>
- **Confidence**: 🟢 CONFIRMED | 🟡 INFERRED | 🔴 GAP | ⚠️ AMBIGUOUS
- **Evidence**:
  - <evidence 1, referencing an artifact in `_reversa_sdd/`>
  - <evidence 2>
- **Observed variations** (if hybrid):
  - <component A: paradigm X, evidence>
  - <component B: paradigm Y, evidence>

## Declared target stack
- Language: <from migration_brief.md>
- Framework: <from migration_brief.md>
- Infrastructure: <from migration_brief.md>

## Inferred natural paradigm
- **Paradigm**: <inferred via paradigm_catalog>
- **Rationale**: <why this stack has this natural paradigm>
- **Viable alternatives**: <e.g. OO with DI is also viable in Node, at cost X>

## Identified gap
- **Severity**: high | medium | low | none
- **Concrete implications** (not abstract; with an example from the legacy system itself):
  - <implication 1, citing the affected legacy rule/flow>
  - <implication 2>
  - <implication 3>
  - <implication 4>

## Options presented to the user
1. **Adopt the stack's natural paradigm** (transformational)
   - Consequences: <list>
2. **Force a paradigm similar to the legacy one** (conservative)
   - Consequences: <list>
3. **Hybrid** (balanced)
   - Consequences: <list>

## User decision
- **Choice**: <1 | 2 | 3>
- **User's rationale**: <free text>
- **Decided at**: <ISO-8601>

## Derived appetite
- `derived_appetite`: conservative | balanced | transformational

## Pending implications for the next agents
| Agent | Implication | How to honor it |
|---|---|---|
| Curator | <implication> | <expected action> |
| Strategist | <implication> | <expected action> |
| Designer | <implication> | <expected action> |
| Inspector | <implication> | <expected action> |

## Notes
<Any additional point the coding agent needs to know about the target paradigm.>
