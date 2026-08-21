> Local copy of the advisory catalog. The canonical source is `templates/migration/catalogs/migration_strategies.md`.

# Migration Strategies (local copy)

## Strategies

### Strangler Fig
- **When it applies**: system in production that cannot stop; need for incrementality; routing possible (proxy / API gateway).
- **Cost**: medium. **Risk**: low. **Time**: long.
- **Favored appetite**: conservative, balanced.

### Big Bang
- **When it applies**: small system; a tolerated downtime window; transformational appetite; few live integrations.
- **Cost**: low. **Risk**: high. **Time**: short.
- **Favored appetite**: transformational (on small systems).

### Parallel Run
- **When it applies**: critical logic (financial / fiscal / regulatory); needs proof of equivalence over a long period.
- **Cost**: high. **Risk**: medium. **Time**: medium.
- **Favored appetite**: balanced.

### Branch by Abstraction
- **When it applies**: internal migration (the language or framework changes, the domain stays); conservative appetite.
- **Cost**: low. **Risk**: low. **Time**: medium.
- **Favored appetite**: conservative.

## Recommendation rules

- `conservative` appetite → Branch by Abstraction + Strangler Fig.
- `balanced` appetite → Strangler Fig + Parallel Run.
- `transformational` appetite → Big Bang on small systems; Strangler Fig with deep boundaries on larger ones.
- large paradigm change + transformational appetite → recommend a Parallel Run to validate parity.
- system with regulatory integrations → never recommend Big Bang.

## Pseudo-procedure

1. Filter the applicable strategies based on the brief.
2. Score the remaining ones by fit with the appetite and the paradigm gap.
3. Select 2 to 3 candidates.
4. Mark one as recommended, with a rationale.
5. For each of the others, list the cons as the reason it was not recommended.
