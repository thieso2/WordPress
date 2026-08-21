---
schemaVersion: 1
generatedAt: <ISO-8601>
reversa:
  version: "x.y.z"
kind: topology_decision
producedBy: designer
hash: "sha256:<hash of the body below the front-matter>"
---

# Topology Decision

> A conscious decision about how to organize the new system: preserve the legacy topology, adopt a modern one, or apply a hybrid.
> This artifact is required reading for the Designer itself (to decompose bounded contexts) and for the coding agent (to create the folder tree).

## Detected legacy topology
- **Organizational pattern**: <package-by-layer | package-by-feature | feature-sliced | modules per domain | DDD with bounded contexts | monorepo | monolith with no clear boundaries | hybrid: ...>
- **Confidence**: 🟢 CONFIRMED | 🟡 INFERRED | 🔴 GAP | ⚠️ AMBIGUOUS
- **Evidence**:
  - <evidence 1, referencing an artifact in `_reversa_sdd/` (architecture.md, inventory.md, dependencies.md)>
  - <evidence 2>
- **Map of the legacy tree** (summarized):
  ```
  <a short tree with the main folders/modules>
  ```

## Structural diagnosis
- **Coupling**: <high | medium | low, with evidence>
- **Cohesion per module**: <high | medium | low, with evidence>
- **Orphaned / dead modules**: <list, or "none">
- **Redundant layers**: <list, or "none">
- **Boundary violations**: <list, or "none">
- **Mixed paradigms/styles**: <description, or "homogeneous">
- **Overall assessment**: <healthy | problematic | partially problematic>

## Proposed modern topology
- **Pattern**: <hexagonal | vertical slices | feature-sliced | DDD with bounded contexts | package-by-feature | modularization by capability | monorepo with pnpm/turborepo | ...>
- **Rationale**: <why this pattern fits the target stack, the domain, the team's size and the chosen migration strategy>
- **Concrete expected gains**:
  - <gain 1: e.g. isolated testability per feature>
  - <gain 2: e.g. independent deployment per bounded context>
  - <gain 3: e.g. faster onboarding>
- **Cost / risk**:
  - <cost 1: e.g. the team's learning curve>
  - <cost 2: e.g. the reorganization effort>
- **Sketch of the proposed tree**:
  ```
  <a short tree with the folders/modules in the modern pattern>
  ```

## Options presented to the user
1. **Preserve the legacy topology** (conservative)
   - Consequences: keeps the current team's mental map; perpetuates any structural debt; lowers migration risk.
2. **Adopt the proposed modern topology** (transformational)
   - Consequences: breaks with the structural debt; requires learning; maximizes the target stack's gains.
3. **Hybrid** (balanced)
   - Consequences: <describe which boundaries preserve the legacy one and which adopt the modern one, with a rationale per boundary>

## The user's decision
- **Choice**: <1 | 2 | 3>
- **The user's rationale**: <free text>
- **Decided at**: <ISO-8601>

## Legacy → new mapping
| Legacy module / folder | New bounded context | Type | Notes |
|---|---|---|---|
| <legacy A> | <new X> | preserved | <note> |
| <legacy B + C> | <new Y> | merged | <rationale> |
| <legacy D> | <new Y1, Y2> | split | <rationale> |
| (none) | <new Z> | new | <rationale> |
| <legacy E> | (discarded) | removed | see `discard_log.md` |

## Pending implications for the Designer's next steps
| Designer step | Implication | How to honor it |
|---|---|---|
| Bounded contexts | <implication> | <expected action> |
| target_architecture | <implication> | <expected action> |
| target_domain_model | <implication> | <expected action> |
| target_data_model | <implication> | <expected action> |

## Notes
<Any additional point the coding agent needs to know in order to create the folder tree and respect the chosen topology.>
