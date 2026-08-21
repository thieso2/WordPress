# Step 4 — Semantic regression check

> This step only runs on **re-extractions**, that is, when a reverse pipeline runs on a project that has already been through at least one `/reversa-coding` cycle. In projects with no `_reversa_forward/` or no `regression-watch.md`, the regression check is silently skipped (the "Addendum reconciliation" at the end is still checked).

## Why it exists

Reversa is not just one-shot extraction. Every `/reversa-coding` leaves in `_reversa_forward/<feature>/regression-watch.md` a list of rules that must remain true in the next extraction. When the reverse pipeline runs again, it has a duty to check those rules against the current code and report regressions. This is Reversa's competitive edge over pure forward frameworks.

## When to run

After the **last agent in the plan** finishes, before the final "extraction complete" message. The trigger is position (the last item in `.reversa/plan.md`), not the agent's name, because the last agent varies with the optional teams chosen at install time (the Reviewer may be absent, for example). Run the checks in this order:

1. Check whether `_reversa_forward/` exists at the project root. If it does not, jump straight to the "Addendum reconciliation" section.
2. List every subfolder of `_reversa_forward/` that contains a `regression-watch.md`.
3. If the list is empty, jump straight to the "Addendum reconciliation" section.
4. Otherwise, follow the procedure below, one feature at a time.

## Procedure per feature

For each `_reversa_forward/<feature>/regression-watch.md`:

1. Load the file. Identify the main watch-item table (columns `ID | Source | Expected rule after change | Verification type | Violation signal`).
2. For each watch item in the main table (not the archived ones):
   2.1. Identify the `Verification type`; possible values: `presence`, `absence`, `wording`, `confidence`.
   2.2. Apply the matching check against the freshly generated artifacts in `_reversa_sdd/`:
        - `presence`: the rule must be present in `_reversa_sdd/domain.md` (or in the file named by the Source column) with the same semantic essence.
        - `absence`: the original rule must NOT appear in the SDD any more.
        - `wording`: the text was deliberately changed; verify the new version matches the expectation.
        - `confidence`: the rule is still present, but its confidence (🟢, 🟡, 🔴) must be equal to or higher than expected.
   2.3. Assign a verdict:
        - 🟢 **green**, the expectation matched in full.
        - 🟡 **yellow**, there is semantic equivalence but the text differs, or the evidence is partial. This is the default verdict when there is ambiguity. Awaits human judgement.
        - 🔴 **red**, the expectation did NOT match. A previously confirmed rule has become a violated rule.
3. After evaluating every watch item, update the `## Re-extraction history` section of that same `regression-watch.md`, adding a dated block:

```
### Re-extraction YYYY-MM-DD HH:MM

| ID | Verdict | Note |
|----|---------|------|
| W001 | 🟢 green | rule preserved in _reversa_sdd/domain.md#rule-X |
| W005 | 🔴 red | rule removed from the current code; unintended change |
| W010 | 🟡 yellow | equivalent text but differs literally; awaiting judgement |
```

4. Do NOT alter the main watch-item table. Do NOT recycle IDs. Do NOT move watch items to "Archived" automatically.

5. For each watch item with three consecutive green verdicts in the history, and provided `setup.json#watch.archive-after` allows it, move the item from the main table to the `## Archived` section at the end of the file. Keep the original ID.

## Write policy

- Atomic write (tempfile plus rename) to `regression-watch.md`.
- Never rewrite or delete entries in the re-extraction history.
- The new re-extraction block always goes at the top of the `## Re-extraction history` section (descending order).

## Report to the user

After going through every feature, present:

1. Total features checked
2. Total watch items checked
3. Breakdown by verdict: green, yellow, red
4. Detailed list of the reds (ID, feature, rule, reason for the divergence)
5. Detailed list of the yellows that need human judgement

If there is at least one red, show a highlighted warning:

> 🔴 **Attention** — **N semantic regressions** were detected in previously coded features. Review before continuing.

If `setup.json#watch.block-on-red` is `true`, suggest the user **not** proceed with new `/reversa-requirements` until every red has been triaged. Reversa only warns; it never automatically blocks the user's flow.

## Addendum reconciliation

After going through the features (or even if none had a `regression-watch.md`), check whether `_reversa_sdd/addenda/` exists with `.md` files created by `/reversa-sync`. If it does:

1. For each addendum whose `## Validity` section does NOT contain a `Superseded by the re-extraction of ...` line, append this line to the end of that section:

   ```
   Superseded by the re-extraction of YYYY-MM-DD.
   ```

2. Never delete the addendum, never rewrite earlier lines of the Validity section, never touch the other sections. Append-only, atomic write.
3. Addenda already superseded in earlier re-extractions stay as they are (they are history).
4. Include in the report how many addenda were marked as superseded in this re-extraction.

The reasoning: addenda are bridges between a forward delivery and the re-extraction. Once the extraction is regenerated from the current code, the deltas described in the addenda are already absorbed into the main artifacts, and consumers (for example `/reversa-requirements` and `/reversa-plan`) should only consider addenda that are still in effect.

## Special case, no `_reversa_sdd/`

If during the procedure `_reversa_sdd/` does not have the expected files (because the re-extraction was partial or the documentation level was lowered), record a 🟡 yellow verdict with the note `evidence missing, _reversa_sdd/<file> was not generated in this extraction` and move on.

## Known gap

Semantic equivalence between the expected rule and the extracted rule is a subjective judgement. When in doubt, prefer a yellow verdict. A red verdict should be reserved for cases where the rule simply vanished or was explicitly contradicted.
