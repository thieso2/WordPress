# Code Quality Register (Reversa Refactor)

> GENERATED / MANAGED by Reversa's Code Quality team. This README holds the register's policies.
> The context folders and transformation artifacts are created on demand.

## Policies

- `control_mode`: gated
  - `gated` (default): reading, analysis, measurement and behavior proofs flow without approval. EVERY step that touches the project's code goes through a gate with an approved diff.
  - `supervised`: the agent may apply low-risk transformations that have already been proven, with a notice; high-risk ones still go through the gate.
  - `autonomous`: automatically applies whatever is 🟢 and proven. Even here some gates are mandatory: removing code, changing the effective spec, sending material to an external harness, any destructive operation.
- `safety_net_policy`: require-characterization
  - `require-characterization` (default): a transformation that changes structure or logic requires a safety net (existing tests + characterization tests) that is green before and after.
  - `allow-unproven`: allows a transformation without a safety net, always downgraded to 🔴 and marked in the register as having no mechanical proof.

## Register invariant

No transformation changes observable behavior. Anything that cannot prove preservation stops at the gate. Every applied transformation is revertible from the stored diff.

## Structure

```
_reversa_refactor/
  README.md                         (this file)
  <context>/                         (feature, module or use case)
    opportunities/                   (detected opportunities, one per file)
    transformations/
      OPP-<date>-<suffix>-<slug>/
        plan.html                    (visual report of the plan, before touching any file)
        safety-net/                  (characterization tests + green/red result)
        before-after/                (evidence: measurement, equivalence proof, deadness proof)
        CHG-NNN.diff                 (applied diffs, the source for reverting)
        transformation.md            (record following opportunity-schema.md)
    generated/                       (regenerable index and catalog, never hand-edited)
```
