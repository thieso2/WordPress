# Opportunity and transformation schema

Minimum contract for the artifacts the Code Quality team writes. YAML front matter + Markdown body. Atomic write (tempfile + rename, UTF-8 without BOM).

## opportunities/<id>.md

```yaml
---
schema_version: 1
id: OPP-<YYYYMMDD>-<suffix>          # suffix: 4 base32 chars from a hash of title+date
display_number: <n>                  # global human-friendly alias, largest existing + 1
context: <context-slug>
verb: restructure | modularize | decouple | optimize | simplify | standardize | prune
title: <short phrase>
target:
  files: [<path>, ...]
  symbol: <optional: function/class/module>
smell: <code smell or objective reason>
roi:
  confidence: green | yellow | red    # 🟢 covered and understood | 🟡 partial | 🔴 unproven
  impact: <why it is worth it: hot path, coupling, risk, clarity>
  cost: low | medium | high
  est_return: <expected return in one sentence>
state: proposed | approved | applied | reverted | declined
traceability:
  soul: [<locator in soul.md>, ...]   # soul rules/decisions that touch the target
  specs: [<path#anchor>, ...]         # related confirmed spec sections
---

<description of the opportunity, with the observed "before" and the proposed transformation>
```

## transformations/OPP-.../transformation.md

```yaml
---
schema_version: 1
id: OPP-<...>
verb: <same as the opportunity>
state: applied | reverted
safety_net:
  kind: existing | characterization | none
  green_before: true | false
  green_after: true | false
preservation:
  method: tests | equivalence-proof | death-proof | pattern-only
  evidence: [<relative path>, ...]
measurement:                          # mandatory for optimize/decouple/simplify
  before: <complexity/coupling/time before>
  after: <after>
change_set:
  - chg: CHG-001
    file: <path>
    purpose: <what changes>
approval:
  by: user
  at: <ISO 8601>
reversible_via: [CHG-001.diff, ...]
---

<what was done, step by step, with relative links to the evidence>
```

## Rules

- Confirmed `soul` and `specs` entries that touch the target are always consulted. A confirmed business rule is never violated nor treated as dead code.
- States are monotonic from an audit standpoint: `declined` and `reverted` preserve history, they never erase the record.
- `prune` may only set `state: applied` with `preservation.method: death-proof` and the proof attached. A suspected orphan stays `proposed` with `promoted_to: null`.
