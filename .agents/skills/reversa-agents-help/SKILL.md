---
name: reversa-agents-help
description: Explains with analogies what each Reversa agent does and when to use it. Activate it with /reversa-agents-help.
license: MIT
compatibility: Claude Code, Codex, Cursor, Gemini CLI and other agents compatible with Agent Skills.
metadata:
  author: sandeco
  version: "1.0.0"
  framework: reversa
  role: help
---

Present exactly the text below, unaltered, without summarizing.

---

# Reversa agents — a guide with analogies

Reversa is a team of specialists. Each agent does one thing — and does it well.

---

## Main menu

| What do you want to do? | Command | Team |
|---|---|---|
| Discover and document a legacy system | `/reversa` | Reversa Agents Core |
| Clarify the idea before any code | `/reversa-brainstorm` | Ideation Agents |
| Create a new project from an idea | `/reversa-new` | Code New Project Agents |
| Implement or evolve code from the specs | `/reversa-forward` | Code Forward Agents |
| Plan the migration of a legacy system | `/reversa-migrate` | Migration Agents |
| Generate a visual documentation mini-site | `/reversa-docs` | Documentation Agents |
| Figure out which agent to use | `/reversa-agents-help` | Agent guide |

The Pricing and Translators teams have specialized commands. Use `/reversa-pricing-profile`, `/reversa-pricing-size`, `/reversa-pricing-estimate` or `/reversa-n8n` as needed.

---

## 💡 Reversa Brainstorm, the table before the building site
**Command:** `/reversa-brainstorm`

Before the bricklayer raises a wall, someone sits at a table and asks what the house is for: who will live in it, what hurts about living the way things are today, which paths are possible, what could go wrong. Nobody draws a floor plan at that table. It only decides what is worth building.

> Use Reversa Brainstorm when the idea is still raw, in a new project or in a legacy one. It runs `Framer → Explorer → Challenger → Arbiter → Pre-Spec` and hands the result to `/reversa-new` (greenfield) or `/reversa-requirements` (legacy).

**The five at the table:**

| Agent | Analogy | Command |
|---|---|---|
| **Framer** | The doctor who won't accept "I want drug X" and asks where it hurts | `/reversa-framer` |
| **Explorer** | The guide who shows every trail, including the one where you don't climb the mountain | `/reversa-explorer` |
| **Challenger** | The devil's advocate who has seen this project fail before | `/reversa-challenger` |
| **Arbiter** | The judge who gives a verdict and owns what it costs, though you are the one who decides | `/reversa-arbiter` |
| **Pre-Spec** | The scribe who hands over the minimum needed to start building, and nothing more | `/reversa-pre-spec` |

---

## 🆕 Reversa New — the product founder
**Command:** `/reversa-new`

The founder starts with a still-raw idea, investigates the problem, works out who the product exists for, consolidates a PRD and turns it all into specifications ready for implementation.

> Use Reversa New for greenfield projects. It runs `Ideator → Researcher → Drafter → Spec SDD` and hands the result to `/reversa-forward`.

---

## 🎼 Reversa — the central orchestrator
**Command:** `/reversa`

An orchestra conductor plays no instrument. They know the whole score and say who comes in when, in what order, at what tempo. Without them, every musician would play their part without connecting to the others.

> Use Reversa to start or resume the full analysis. It handles the sequence for you.

---

## 🗺️ Scout — the estate agent
**Command:** `/reversa-scout`

The estate agent gives the first tour of the property. They don't open drawers, don't read documents, don't touch anything. They just map it out: how many rooms, which neighborhood, what fixtures exist, the general condition.

> Use the Scout at the start. It produces the project's inventory — languages, frameworks, modules, dependencies — without going into the code.

---

## 🧬 Soul Extractor: the express biographer
**Command:** `/reversa-extract-soul`

The express biographer visits the subject, reads the estate agent's notes (the Scout), quickly leafs through a few family albums and the letter archive (git log), and produces a one-page biography: who they are, what they do, and the founding decisions that shaped a whole life. It is not the full story; it is the distilled soul.

> Use the Soul Extractor right after the Scout, when you want an executive synthesis of the system (purpose, core entities and founding decisions) in a single Spec, without waiting for the whole pipeline. It does not replace the Archaeologist or the Detective.

---

## ⛏️ Archaeologist — the excavator
**Command:** `/reversa-archaeologist`

The archaeologist digs through the ground patiently, layer by layer. They catalog each artifact found: size, material, location, shape. They do not interpret the civilization; they just describe precisely what is there.

> Use the Archaeologist to analyze the code module by module. It extracts functions, algorithms, data structures and control flows. **Run one module per session** to save tokens.

---

## 🔍 Detective — the Sherlock Holmes
**Command:** `/reversa-detective`

Sherlock Holmes arrives after the archaeologist. He looks at the catalogued artifacts and asks: *"But why is this here? Who put it there? What does it reveal about whoever lived here?"* He does not dig. He interprets.

> Use the Detective after the Archaeologist. It extracts implicit business rules, reads the git history like a diary and reconstructs decisions nobody documented.

---

## 📐 Architect — the cartographer
**Command:** `/reversa-architect`

The cartographer visits a territory and produces formal maps: a floor plan, an elevation map, a structural plan. Someone who has never set foot there can understand everything by looking at the maps.

> Use the Architect after the Detective. It synthesizes everything into C4 diagrams, a complete ERD and an integration map.

---

## 📝 Writer — the notary
**Command:** `/reversa-writer`

The notary turns what was discovered into formal, precise and traceable contracts. Every clause has a declared degree of certainty. The document works as a contract: an AI agent can reimplement the system from it.

> Use the Writer after the Architect. It generates the SDD specs, OpenAPI and user stories with code traceability.

---

## ⚖️ Reviewer — the spec reviewer
**Command:** `/reversa-reviewer`

The Reviewer takes the Writer's contracts and tries to poke holes: *"That's a contradiction. This point has no proof. This rule disappears if the user does X."* It doesn't want to destroy; it wants whatever is left standing to be solid.

> Use the Reviewer after the Writer. It critically reviews the specs, reclassifies confidence and raises questions for human validation.

---

## 🖼️ Visor — the forensic illustrator
**Command:** `/reversa-visor`

The forensic illustrator works only from images. They receive screenshots of the system and faithfully reconstruct the interface: screens, forms, navigation flows. The system doesn't need to be running — just the photos.

> Use the Visor when you have screenshots available. It documents the UI without needing access to the system.

---

## 🗄️ Data Master — the geologist
**Command:** `/reversa-data-master`

The geologist maps the subsurface — the layer nobody sees but that holds everything up. Tables, relationships, constraints, triggers, procedures. The invisible foundation the application is built on.

> Use the Data Master when there is DDL, migrations or ORM models available. It documents the database completely.

---

## 🎨 Design System — the stylist
**Command:** `/reversa-design-system`

The stylist catalogs the wardrobe: color palette, typography, spacing, design tokens. The "fashion rules" that govern the system's appearance — what can and cannot be combined.

> Use the Design System when there are CSS files, themes or interface screenshots. It extracts the project's visual tokens.

---

## Recommended sequence

```
Legacy project: /reversa → discovery and specifications
New project:    /reversa-new → PRD and specs → /reversa-forward
Migration:      /reversa → /reversa-migrate → /reversa-forward

Manual legacy pipeline:
Scout → Archaeologist (N sessions) → Detective → Architect → Writer → Reviewer

Optional at any phase:
Soul Extractor · Visor · Data Master · Design System · Reversa Docs
```
