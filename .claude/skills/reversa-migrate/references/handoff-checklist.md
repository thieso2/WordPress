# `handoff.md` checklist

Before closing the pipeline, the orchestrator validates that `handoff.md` satisfies every item.

## Mandatory checklist

- [ ] `paradigm_decision.md` appears as the **first item** of the "Required reading" section and of the "Recommended reading order".
- [ ] `topology_decision.md` appears as the **second item** of the "Required reading" section.
- [ ] `screen_modernization_decision.md` appears as the **third item** when there is a UI; on a legacy system with no UI (Screen Translator skipped), the entry is omitted with an explicit note "Screen Translator skipped, legacy system has no UI".
- [ ] The list of produced artifacts is complete and reflects the real `_reversa_sdd/migration/` and `_reversa_sdd/screens/`.
- [ ] Pending deviations in `screen_deviation_log.md` appear as blockers; approved deviations are reflected in `parity_specs.md § Exceptions`.
- [ ] Items DEFERRED TO CODING from `ambiguity_log.md` appear in a dedicated section of `handoff.md`.
- [ ] Blockers are listed, or the line "no blockers, proceed".
- [ ] Next steps for the coding agent are specific and actionable (not generic).
- [ ] With `--auto`: auto-decided items are listed explicitly.
- [ ] The style is consistent with the installed engine (adapted format, e.g. compatible front-matter).

## Minimum structure

1. Banner of required reading for `paradigm_decision.md`, `topology_decision.md` and (if there is a UI) `screen_modernization_decision.md`.
2. Recommended reading order.
3. List of artifacts.
4. Blockers.
5. Next steps for the coding agent.
6. Auto-decided items (only with `--auto`).
7. Closing notes.

## Strong signal to the coding agent

The first sentence of `handoff.md` must convey immediate clarity. Suggested pattern:

> "New system to be built in paradigm <X>, topology <Y>, screens in <Z> mode. Before writing a single line of code, read `paradigm_decision.md`, `topology_decision.md` and `screen_modernization_decision.md`."

On a legacy system with no UI (Screen Translator skipped), replace the screens clause with: "screens: none (system has no UI)".
