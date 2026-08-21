# Reversa

> Reverse Engineering framework installed in this project.

## How to use

Use the appropriate workflow in the chat:

- `/reversa` — discover and document an existing system
- `/reversa-new` — create a PRD and specs for a new project
- `/reversa-forward` — implement or evolve code from the specs
- `/reversa-migrate` — plan the migration of a legacy system
- `/reversa-docs` — generate the visual documentation mini-site
- `/reversa-agents-help` — browse the full agent catalog

## Behavior on activation

When the user types `/reversa` or the word `reversa` alone in a message:

1. Activate the `reversa` skill available at `.claude/skills/reversa/SKILL.md`
2. If not found in `.claude/skills/`, try `.agents/skills/reversa/SKILL.md`
3. Read the SKILL.md in full and follow Reversa's instructions exactly

## Non-negotiable rule

Never delete, modify or overwrite pre-existing files of the legacy project.
Reversa writes only to `.reversa/`, `_reversa_sdd/`, `_reversa_docs/` and `_reversa_forward/`.
