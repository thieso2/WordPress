# Schema — .reversa/state.json

This file persists the complete analysis state across sessions. Reversa reads from and writes to it.

## Full structure

```json
{
  "version": "1.0.0",
  "project": "project-name",
  "user_name": "User Name",
  "chat_language": "en",
  "doc_language": "English",
  "answer_mode": "chat",
  "doc_level": null,
  "output_folder": "_reversa_sdd",
  "phase": "recon",
  "completed": ["recon"],
  "pending": ["excavation", "interpretation", "generation", "review"],
  "engines": ["claude-code"],
  "agents": ["reversa", "reversa-scout", "reversa-archaeologist"],
  "skills_scope": "project",
  "skills_root": ".",
  "skills_flat": false,
  "checkpoints": {
    "scout": {
      "completed_at": "2026-04-26T10:00:00Z",
      "files": [
        "_reversa_sdd/inventory.md",
        "_reversa_sdd/dependencies.md",
        ".reversa/context/surface.json"
      ]
    },
    "archaeologist": {
      "completed_at": "2026-04-26T11:00:00Z",
      "modules_analyzed": ["auth", "orders", "payments"],
      "files": [
        "_reversa_sdd/code-analysis.md",
        "_reversa_sdd/data-dictionary.md",
        ".reversa/context/modules.json"
      ]
    }
  },
  "created_files": [
    "CLAUDE.md",
    ".agents/skills/reversa/SKILL.md",
    ".reversa/state.json",
    ".reversa/plan.md"
  ]
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Installed Reversa version |
| `project` | string | Name of the legacy project |
| `user_name` | string | User's name (for interactions) |
| `chat_language` | string | Language of the interactions (e.g. en, pt-br) |
| `doc_language` | string | Language of the generated specs (e.g. English, Português) |
| `answer_mode` | string | How the user answers gaps: `chat` or `file` |
| `doc_level` | string \| null | Volume of documentation generated: `essential`, `complete` or `detailed`. Starts as `null` — must be filled in from the user's choice after the Scout. |
| `output_folder` | string | Output folder for the specs (default: `_reversa_sdd`) |
| `phase` | string \| null | Current phase. `null` = not started |
| `completed` | string[] | Completed phases |
| `pending` | string[] | Pending phases |
| `checkpoints` | object | Completion record for each agent |
| `engines` | string[] | Configured engines (e.g. `["claude-code", "codex"]`) |
| `agents` | string[] | Installed agents |
| `skills_scope` | string | Where the skills were installed: `project` (default), `global` (`--global`, the user's home) or `env` (`REVERSA_SKILLS_DIR`) |
| `skills_root` | string | Folder the skill paths hang from. `.` for `project`, an absolute path otherwise |
| `skills_flat` | boolean | `true` when the agents sit directly in `skills_root` (`REVERSA_SKILLS_DIR`), `false` when the engine layout is kept (`.claude/skills/<agent>`) |
| `created_files` | string[] | Every file created by Reversa (for a safe uninstall). Skills installed outside the project are deliberately absent — they are shared with other projects |

## Valid phases

`recon` → `excavation` → `interpretation` → `generation` → `review`

## Rule when writing

Never remove existing fields. Only add or update.

## Where NOT to write

The spec organization decision (granularity, custom folders, the Scout's original suggestion, the timestamp of the choice) does **not** go in `state.json`. It is persisted in `.reversa/config.toml`, section `[specs]`, as described in `references/step-03-specs-organization.md`. `state.json` is runtime state; `config.toml` is a long-term decision.
