# Exploration Plan — WordPress

> Created by Reversa on 2026-08-21
> Mark each task with ✅ when it is done.
> You can edit this plan before starting: add, remove or reorder tasks as needed.

---

## Phase 1: Recon 🔍

- [x] ✅ **Scout** — Map the folder structure and technologies
- [x] ✅ **Scout** — Analyze dependencies and package managers
- [x] ✅ **Scout** — Identify entry points, CI/CD and configuration

> Artifacts: `_reversa_sdd/inventory.md`, `_reversa_sdd/dependencies.md`, `.reversa/context/surface.json`
> Result: 44 modules identified · PHP 1,900 files / ~670k LOC · 565 actions + 1,638 filters · no tests, no CI in this tree

## Spec organization decision 🗂️

- [x] ✅ Decided: **`module`** (Scout suggestion, accepted automatically per the interview's "Automatic" choice).
      Persisted in `.reversa/config.toml` → `[specs]`, `decided_at = 2026-08-21T12:56:33Z`.
      `scout_suggestion = "module"` is now immutable.

## Phase 2: Excavation 🏗️

> One Archaeologist task per module identified by the Scout (44 total).
> Vendored third-party libraries (`php-ai-client/`, `sodium_compat/`, `SimplePie/`, `Requests/`, `ID3/`,
> `PHPMailer/`, `IXR/`, `Text/`, `pomo/`, PclZip, phpass, Snoopy) are **documented as dependencies**
> in `dependencies.md`, not excavated as domain logic.

### Tier A — Core kernel (everything else depends on these)

- [x] ✅ **Archaeologist** — `bootstrap-and-load`
- [x] ✅ **Archaeologist** — `hooks-plugin-api`
- [x] ✅ **Archaeologist** — `database-wpdb`
- [x] ✅ **Archaeologist** — `options-and-transients`
- [x] ✅ **Archaeologist** — `cache-and-object-cache`
- [x] ✅ **Archaeologist** — `metadata`

### Tier B — Content domain

- [x] ✅ **Archaeologist** — `posts-and-post-types`
- [x] ✅ **Archaeologist** — `query-and-loop`
- [x] ✅ **Archaeologist** — `taxonomy-and-terms`
- [x] ✅ **Archaeologist** — `comments`
- [x] ✅ **Archaeologist** — `media-and-attachments`
- [x] ✅ **Archaeologist** — `embeds-oembed`

### Tier C — Identity & access

- [x] ✅ **Archaeologist** — `users-roles-capabilities`
- [x] ✅ **Archaeologist** — `authentication-and-sessions`

### Tier D — Presentation

- [x] ✅ **Archaeologist** — `themes-and-templates`
- [x] ✅ **Archaeologist** — `rewrite-and-permalinks`
- [x] ✅ **Archaeologist** — `script-modules-and-assets`
- [x] ✅ **Archaeologist** — `widgets-and-nav-menus`
- [x] ✅ **Archaeologist** — `customizer`

### Tier E — Block editor stack

- [x] ✅ **Archaeologist** — `block-editor`
- [x] ✅ **Archaeologist** — `blocks-library`
- [x] ✅ **Archaeologist** — `block-supports`
- [x] ✅ **Archaeologist** — `global-styles-theme-json`
- [x] ✅ **Archaeologist** — `style-engine`
- [x] ✅ **Archaeologist** — `html-api`
- [x] ✅ **Archaeologist** — `interactivity-api`

### Tier F — Interfaces & integration

- [x] ✅ **Archaeologist** — `rest-api`
- [x] ✅ **Archaeologist** — `http-api`
- [x] ✅ **Archaeologist** — `xmlrpc`
- [x] ✅ **Archaeologist** — `feeds`
- [x] ✅ **Archaeologist** — `sitemaps`
- [x] ✅ **Archaeologist** — `ai-abilities-connectors`

### Tier G — Platform services

- [x] ✅ **Archaeologist** — `cron`
- [x] ✅ **Archaeologist** — `internationalization`
- [x] ✅ **Archaeologist** — `formatting-and-sanitization`
- [x] ✅ **Archaeologist** — `kses-security`
- [x] ✅ **Archaeologist** — `error-handling-and-recovery-mode`
- [x] ✅ **Archaeologist** — `performance-speculation-view-transitions`

### Tier H — Administration & operations

- [x] ✅ **Archaeologist** — `admin-application`
- [x] ✅ **Archaeologist** — `filesystem-api`
- [x] ✅ **Archaeologist** — `updates-and-upgrader`
- [x] ✅ **Archaeologist** — `site-health`
- [x] ✅ **Archaeologist** — `multisite`

### Tier I — Compatibility

- [x] ✅ **Archaeologist** — `deprecated-compat`

## Phase 3: Interpretation 🧠

- [x] ✅ **Detective** — Git archaeology and retroactive ADRs
- [x] ✅ **Detective** — Implicit business rules and state machines
- [x] ✅ **Detective** — Permission matrix (RBAC/ACL)
- [x] ✅ **Architect** — C4 diagrams (Context, Containers, Components)
- [x] ✅ **Architect** — Complete ERD and external integrations
- [x] ✅ **Architect** — Spec Impact Matrix

## Phase 4: Generation 📝

- [x] ✅ **Writer** — SDD specs per component
- [x] ✅ **Writer** — OpenAPI (if applicable)
- [x] ✅ **Writer** — User Stories (if applicable)
- [x] ✅ **Writer** — Code/Spec Matrix

## Phase 5: Review ✅

- [x] ✅ **Reviewer** — Cross-review of the specs
- [x] ✅ **Reviewer** — Resolve gaps with the user
- [x] ✅ **Reviewer** — Final confidence report

---

## Standalone Agents

> Run these agents whenever the resources are available — they can run in any phase.

- [ ] **Visor** — Interface analysis via screenshots  ⚠️ blocked: no running WordPress instance or screenshots available
- [x] ✅ **Data Master** — Complete database analysis → `_reversa_sdd/database/` (5 files)
- [x] ✅ **Design System** — Extraction of design tokens → `_reversa_sdd/design-system.md`
- [ ] **Tracer** — Dynamic analysis  ⚠️ blocked: requires an accessible running system

---

## Next step

Once the Discovery Team has finished and `_reversa_sdd/` is populated, you can trigger one of the following workflows:

- `/reversa-migrate`: orchestrator of the **Migration Team** (Paradigm Advisor → Curator → Strategist → Designer → Screen Translator → Inspector). Generates the specs for the new system. Output in `_reversa_sdd/migration/` and `_reversa_sdd/screens/`.
- `/reversa-reconstructor`: generates a bottom-up plan to reimplement the software from the legacy specs (one task per session).
