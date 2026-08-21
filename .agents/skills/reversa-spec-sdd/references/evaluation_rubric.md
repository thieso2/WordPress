# Spec Evaluation Rubric

Used by `scripts/spec_scorer.py` and as a manual review guide.

Total score: **0–100 points**

---

## Dimension 1: Completeness (30 points)

Assesses whether every essential section is present and filled in.

| Criterion | Points | How to check |
|-----------|--------|--------------|
| Sections 1–6 all present and filled in (not just headers) | 10 | Each section has ≥ 2 sentences or 1 list item |
| Functional requirements with IDs (FR-XX) | 8 | At least 3 numbered requirements |
| Acceptance criteria defined for every Must FR | 7 | The "Acceptance Criterion" column is filled in |
| Explicit Non-Goals (section 4) | 5 | At least 2 non-goals listed |

**Penalties:**
- A mandatory section completely missing: -5 per section
- A section with an unfilled placeholder (`[brackets]`): -2 per occurrence

---

## Dimension 2: Testability (25 points)

Assesses whether a QA can write tests from the spec without asking questions.

| Criterion | Points | How to check |
|-----------|--------|--------------|
| Requirements use concrete, measurable verbs | 10 | No "must be good", "must be fast", "must be intuitive" |
| The main flow (happy path) described step by step | 8 | Section 6.2 with ≥ 3 steps |
| Success metrics with numeric values | 7 | Section 3 has at least 1 metric with a numeric target |

**Penalties:**
- An untestable requirement ("the system must be easy to use"): -3 per occurrence
- Happy path missing: -8

---

## Dimension 3: Clarity (20 points)

Assesses whether the language is precise and unambiguous.

| Criterion | Points | How to check |
|-----------|--------|--------------|
| No vague terms without a definition | 8 | "quickly", "soon", "many", "some" with no value — -2 each |
| Open Questions flagged with ⚠️ or in section 14 | 6 | Ambiguities are explicit, not silent |
| A clear subject in every requirement ("the system", "the user") | 6 | There are no requirements without an identified subject |

**Penalties:**
- A contradiction between requirements: -5 per contradiction
- A technical term with no definition for a non-technical audience: -2 per occurrence

---

## Dimension 4: Scope (15 points)

Assesses whether the feature's boundaries are clear.

| Criterion | Points | How to check |
|-----------|--------|--------------|
| The Non-Goals section (4) is clear and useful | 7 | At least 2 non-goals that prevent real scope creep |
| Dependencies and integrations mapped (section 10) | 5 | Every external dependency is listed |
| Rollout / rollback plan present (section 13) | 3 | The strategy and how to revert are defined |

**Penalties:**
- Vague non-goals ("future features"): -2 per occurrence
- A critical dependency not mapped: -3

---

## Dimension 5: Edge Cases (10 points)

Assesses whether the hard cases were anticipated.

| Criterion | Points | How to check |
|-----------|--------|--------------|
| At least 3 edge cases listed (section 11) | 5 | A table with ≥ 3 filled rows |
| Error handling with a defined message/behavior | 3 | Every error has an expected behavior |
| External dependency failure cases covered | 2 | At least 1 EC for a timeout/outage |

**Penalties:**
- Zero edge cases: -10 (this dimension goes to zero)
- An edge case with no defined behavior: -1 per occurrence

---

## Classification by Score

| Score | Classification | Meaning |
|-------|----------------|---------|
| 90–100 | ⭐ Excellent | Ready for immediate implementation |
| 80–89 | ✅ Good | Ready with minor adjustments |
| 65–79 | ⚠️ Adequate | Implementable but risky |
| 50–64 | 🔶 Incomplete | Needs review before implementing |
| < 50 | ❌ Insufficient | Go back to the interview / draft |

---

## Quick Review Checklist

Before marking a spec as "Approved", confirm:

- [ ] Can any dev implement it without asking anything?
- [ ] Can any QA write tests without asking anything?
- [ ] Are the non-goals as clear as the goals?
- [ ] Does every error case have a defined behavior?
- [ ] Do all the requirements have traceable IDs?
- [ ] Are there no contradictions between requirements?
- [ ] Are the open questions documented (not silent)?
- [ ] Are the success metrics numeric and verifiable?
