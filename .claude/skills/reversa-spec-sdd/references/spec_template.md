# Spec Template — Pragmatic RFC

> Usage instructions: replace all text between `[brackets]` with real content.
> Remove the italic instructions when you finish.
> Mark open items with `⚠️ OPEN:` so you don't forget to resolve them.

---

# Spec: [Feature Name]

**Version:** 1.0
**Status:** Draft | In Review | Approved | Implemented
**Author:** [Name]
**Date:** [YYYY-MM-DD]
**Reviewers:** [Names or "N/A"]

---

## 1. Summary

> *1–3 sentences. What is this feature and why does it exist? Read this and you should already grasp the goal.*

[A concise description of the feature and its purpose.]

---

## 2. Context and Motivation

> *Why are we building this now? What problem or opportunity drove the decision?*

**Problem:**
[Describe the problem that exists today. Be specific — include real examples if possible.]

**Evidence:**
[Data, feedback, metrics or observations that justify the priority.]

**Why now:**
[What changed that makes this urgent or timely.]

---

## 3. Goals

> *What must this feature deliver to count as a success?*
> *Every goal must be verifiable — if you cannot measure it, rewrite it.*

- [ ] G-01: [Goal 1]
- [ ] G-02: [Goal 2]
- [ ] G-03: [Goal 3]

**Success metrics:**
| Metric | Current baseline | Target | Deadline |
|--------|------------------|--------|----------|
| [e.g. Conversion rate] | [X%] | [Y%] | [date] |

---

## 4. Non-Goals (Out of Scope)

> *Explicit beats implicit. Say what will NOT be done in this version.*
> *This prevents scope creep and aligns expectations.*

- NG-01: [What will not be done]
- NG-02: [What will not be done]
- NG-03: [Future versions may include X, but not now]

---

## 5. Users and Personas

> *Who will use this? What is their context?*

**Primary user:** [Description — e.g. "A logged-in user on the Pro plan, familiar with the platform"]
**Secondary user:** [If any — e.g. "An admin who configures the permissions"]

**Current journey (without the feature):**
[Describe in 2–4 steps what the user does today to solve the same problem, or why they can't.]

**Future journey (with the feature):**
[Describe in 2–4 steps what the user will do once the feature exists.]

---

## 6. Functional Requirements

> *The heart of the spec. Every requirement must be atomic, testable and unambiguous.*
> *Format: FR-XX — [The system / user] must [concrete verb] [complement].*

### 6.1 Main requirements

| ID | Requirement | Priority | Acceptance criterion |
|----|-------------|----------|----------------------|
| FR-01 | [The system must...] | Must | [How to test that it works] |
| FR-02 | [The user must be able to...] | Must | [A verifiable condition] |
| FR-03 | [The system must...] | Should | [A verifiable condition] |
| FR-04 | [The system must...] | Could | [A verifiable condition] |

> Priorities: **Must** (mandatory in the MVP) / **Should** (important, but negotiable) / **Could** (nice-to-have)

### 6.2 Main flow (Happy Path)

> *Describe the most common flow, step by step.*

1. The user [action 1]
2. The system [response 1]
3. The user [action 2]
4. The system [response 2]
5. Result: [final state]

### 6.3 Alternative flows

> *Variations of the main flow that must also work.*

**Alternative Flow A — [Name]:**
1. [The step that diverges from the main flow]
2. [The specific behavior]

---

## 7. Non-Functional Requirements

| ID | Requirement | Target value | Note |
|----|-------------|--------------|------|
| NFR-01 | Performance | [e.g. P95 < 300ms] | [context] |
| NFR-02 | Availability | [e.g. 99.9% uptime] | [context] |
| NFR-03 | Security | [e.g. authentication required] | [context] |
| NFR-04 | Accessibility | [e.g. WCAG 2.1 AA] | [context] |

---

## 8. Design and Interface

> *Describe the UI/UX behavior, not the visuals. Wireframes can be referenced.*

**Affected components:** [A list of the screens, components or endpoints touched]

**Expected behavior:**
[Describe what the user sees and how the elements respond to their actions.]

**UI states:**
- Empty state: [what to show when there is no data]
- Loading state: [what to show while processing]
- Error state: [what to show on failure]
- Success state: [what to show after completion]

---

## 9. Data Model

> *Only if the feature creates or modifies persisted data.*

**New or modified entities:**

```
[EntityName] {
  field_1: type        // description
  field_2: type        // description
}
```

**Migrations needed:** [Yes / No — if yes, describe the impact]

---

## 10. Integrations and Dependencies

| Dependency | Type | Impact if unavailable |
|------------|------|-----------------------|
| [External API / Service / Library] | [Required / Optional] | [Fallback behavior] |

---

## 11. Edge Cases and Error Handling

> *This is the section where specs usually fail. Think about the hard cases.*

| Scenario | Trigger | Expected behavior |
|----------|---------|-------------------|
| EC-01: [Edge case name] | [What causes this scenario] | [What the system must do] |
| EC-02: [Invalid input] | [Condition] | [Error message / fallback] |
| EC-03: [Timeout / external failure] | [Condition] | [Retry / degradation / a clear error] |
| EC-04: [Rate/quota limit reached] | [Condition] | [Behavior] |

---

## 12. Security and Privacy

- **Authentication:** [Who can access this feature?]
- **Authorization:** [Which permissions are required?]
- **Sensitive data:** [Does the feature process PII, financial or confidential data? How is it protected?]
- **Auditing:** [Is an audit log needed? What must be logged?]

---

## 13. Rollout Plan

- **Strategy:** [Big bang / Feature flag / Gradual rollout / Canary]
- **How to roll back:** [Steps to undo it if something goes wrong]
- **Post-deploy monitoring:** [What to watch in the first 24–48h]

---

## 14. Open Questions

> *Unresolved doubts that may affect the design. Every item must have an owner and a deadline.*

| # | Question | Impact | Owner | Deadline |
|---|----------|--------|-------|----------|
| OQ-01 | [Open question] | [High/Medium/Low] | [Name] | [date] |

---

## 15. Decisions Made (Decision Log)

> *Record the important decisions and the rationale — useful for future reviews.*

| Decision | Alternatives considered | Rationale |
|----------|-------------------------|-----------|
| [What was decided] | [What was rejected] | [Why this option] |

---

## Appendix

### References
- [Links to docs, tickets, designs, related research]

### Revision History
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | [date] | [author] | Initial creation |
