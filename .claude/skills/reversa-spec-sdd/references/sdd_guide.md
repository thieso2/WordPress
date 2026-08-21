# Methodology Guide — Spec-Driven Development

## What is SDD?

Spec-Driven Development is the practice of writing a detailed behavior specification **before** writing any code. The spec answers **what** the system must do — not **how** to implement it.

Not to be confused with:
- **TDD** (Test-Driven Development): writes tests before the code — complementary to SDD
- **DDD** (Domain-Driven Design): an architectural pattern — independent of SDD
- **BDD** (Behavior-Driven Development): focuses on behaviors with Gherkin — a subset of SDD

---

## Core Principles

### 1. Behavior, not Implementation

The spec describes observable behavior, not the internal implementation.

❌ Bad: "The system must use Redis to cache sessions"
✅ Good: "The system must keep the user's session active for 30 days on devices where they ticked 'remember me'"

The implementation (Redis, JWT, a database) is a technical decision for whoever implements it — not for the spec.

### 2. Ambiguity = a Future Bug

Every ambiguity in the spec becomes a bug, an alignment meeting or a PR argument later on. Make ambiguities explicit with `⚠️ OPEN:` — a visible open item beats a silent assumption.

### 3. Non-Goals matter as much as Goals

"What we are not going to do" prevents scope creep, aligns expectations and speeds up decisions. A feature with no non-goals tends to grow indefinitely.

### 4. The Spec is a Living Contract

The spec changes as understanding evolves — and that is healthy. What matters is that the changes are recorded (Decision Log) and that every stakeholder is aligned with the current version.

### 5. LLM-Readiness

A good modern spec must be readable by the LLMs that will help implement it. That means:
- Numbered requirements (traceable IDs)
- Explicit behaviors, not implicit ones
- Documented edge cases (LLMs do not guess extreme cases)
- Business context included (the "why" helps make good implementation decisions)

---

## The SDD Cycle

```
Idea/Problem
      ↓
  Interview  ←───────────────────────┐
      ↓                              │
  Spec draft                         │
      ↓                              │
  Evaluation (Score)                 │
      ↓                              │
  Score < 80? ──── Yes ──── Identify gaps
      ↓ No
  Spec approved
      ↓
  Implementation
      ↓
  Spec vs. Code (final validation)
```

---

## When to Write the Spec

| Feature size | Recommendation |
|--------------|----------------|
| Bug fix | No spec needed |
| Small improvement (< 1 dev day) | Minimal spec: goals + main requirements |
| New feature (1–5 days) | A complete but concise spec |
| Complex feature (> 5 days) | A complete spec + review by 2+ people |
| A new system | An architecture spec + a spec per feature |

---

## Requirement Priorities (MoSCoW)

| Priority | Meaning | Decision if it does not fit the deadline |
|----------|---------|------------------------------------------|
| **Must** | Mandatory — without it, no launch | Blocks the launch |
| **Should** | Important — but there is a workaround | Deferred to the next version |
| **Could** | Nice-to-have | Dropped if necessary |
| **Won't** | Consciously out of scope | Documented as a Non-Goal |

---

## Common Antipatterns

### "A spec like a big-company PRD"
50-page specs nobody reads. Prefer concise specs that cover the essentials clearly.

### "A spec as a list of technical tasks"
"Create the users table, add a POST /auth endpoint, integrate with OAuth..." — that is an implementation plan, not a spec. The spec speaks in terms of behavior.

### "A verbal / Slack spec"
Decisions made in conversation with no record get lost and cause conflict. Every spec must exist as a written document.

### "A spec that never changes"
Frozen specs that do not reflect the reality of what was implemented. The spec must be updated when the implementation deliberately diverges.

### "Silent Open Questions"
Assuming answers to unanswered questions. Always use `⚠️ OPEN:` and resolve it before implementing.

---

## SDD Vocabulary

| Term | Definition |
|------|------------|
| **Spec** | A document describing the expected behavior of a feature |
| **FR** | Functional Requirement — what the system must do |
| **NFR** | Non-Functional Requirement — how the system must behave (performance, security...) |
| **Goal** | An objective the feature must achieve |
| **Non-Goal** | What is explicitly out of scope |
| **Edge Case** | A boundary or non-obvious case the system must handle correctly |
| **Happy Path** | The main, most common flow of use |
| **Acceptance Criterion** | A verifiable condition that defines when a requirement is implemented |
| **Open Question** | An unresolved doubt that may affect the design |
| **Decision Log** | A record of important decisions and why they were made |
