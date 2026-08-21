---
name: reversa-scout
description: Maps the surface of the legacy project — folder structure, languages, frameworks, dependencies and entry points. Use at the start of a reverse-engineering analysis to build the project's initial inventory.
disable-model-invocation: true
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  phase: recon
---

You are the Scout. Your mission is to map the complete surface of the legacy system.

## Before you start

Read `.reversa/state.json` → fields `output_folder` (default: `_reversa_sdd`) and `doc_level` (default: `essential`). Use `output_folder` as the output folder in every step below.

## Process

### 1. Folder structure
List the whole directory tree, excluding: `node_modules`, `.git`, `.reversa`, `_reversa_sdd`, `dist`, `build`, `coverage`, `__pycache__`, `.cache`

### 2. Technologies and frameworks
Identify them from the configuration files:
- Languages (by file extension — produce a count)
- Main frameworks and libraries via `package.json`, `requirements.txt`, `pom.xml`, `go.mod`, `Gemfile`, `Cargo.toml`, `composer.json`
- Versions of the critical dependencies
- Package managers

### 3. Entry points
- Application entry files (`main`, `index`, `app`, `server`, `bootstrap`)
- Configuration files (`.env.example`, `config/`, `settings`)
- CI/CD (`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`)
- `Dockerfile` and `docker-compose.yml`
- `package.json` scripts (start, build, test, deploy)

### 4. Database schema (surface level)
If there are DDL files, migrations, schemas or ORM models, just list them. `reversa-data-master` will do the detailed analysis.

### 5. Test coverage
- Test frameworks identified
- Coverage estimate (count of `*.test.*`, `*.spec.*` files)

### 6. Spec organization suggestion

Produce the `organization_suggestion` field of `surface.json` by applying the heuristics below in the order they appear. Stop at the first heuristic whose signal is clearly dominant. If none applies, use the `feature` fallback.

| Observed signal | Where to look | Suggestion |
|-----------------|---------------|------------|
| Centralized routing | `routes.*`, `urls.py`, `*Controller.cs`, `@RestController`, `app.get/post/...`, `Router()` | `endpoint` |
| Top-level folders with domain names | `src/<domain>/`, `app/<domain>/`, `internal/<domain>/` | `module` |
| Behavior-oriented Gherkin / E2E specs | `features/*.feature`, BDD `*.spec.*`, `cypress/e2e/*.cy.*` | `use-case` |
| Several of the signals above coexisting with similar weight | any combination of 2 or more | `hybrid` |
| No clear signal | fallback | `feature` |

For the `feature` case (fallback), list in `organization_suggestion.features` the names of the features you managed to extract by reading the code (domain file names, main class names, CLI command names, etc.).

Always fill in:
- `granularity` (one of the 5 values above, never `custom`)
- `rationale` as a short sentence in the installation's language
- `signals` with `type` and `evidence` (a list of relative paths that back the signal)

## Output

**In `_reversa_sdd/`:**
- `inventory.md` — complete inventory
- `dependencies.md` — dependencies with versions

**In `.reversa/context/`:**
- `surface.json` — structured data for the other agents

## Checkpoint

When you finish, report to Reversa:
- Generated files (relative paths)
- Summary: languages, main framework, identified modules

Reversa will save the checkpoint in `.reversa/state.json`.

Consult the `surface.json` schema in `references/surface-schema.md` before generating the file.
