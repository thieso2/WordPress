# Architecture Decision Records — WordPress (retroactive)

> Reconstructed by the **Detective** (Reversa) from 53,163 commits (2003-04-01 → 2026-08-21),
> the code itself, and the Archaeologist's 44-module analysis.
>
> **These ADRs were never written at the time.** They are inferred from evidence: commit messages,
> code structure, comments, and the shape of the compatibility surface. Each records its evidence
> and marks its confidence.
>
> Confidence: 🟢 CONFIRMED (decision explicit in code or commit) · 🟡 INFERRED (deduced from
> structure) · 🔴 GAP (rationale unknown)

| # | Decision | Date | Confidence |
|---|----------|------|-----------|
| [001](001-hooks-as-the-extension-mechanism.md) | Hooks as the universal extension mechanism | ~2003–2004 | 🟢 |
| [002](002-never-break-backward-compatibility.md) | Never break backward compatibility | ongoing | 🟢 |
| [003](003-no-orm-hand-rolled-wpdb.md) | No ORM: a hand-rolled `wpdb` with `prepare()` | 2003 | 🟢 |
| [004](004-post-types-as-generic-storage.md) | Post types as generic object storage | 2010 (3.0) | 🟢 |
| [005](005-pluggable-security-functions.md) | Make the security core pluggable | ~2004 | 🟢 |
| [006](006-cron-without-a-daemon.md) | Cron without a daemon | ~2006 | 🟢 |
| [007](007-permissive-mysql-sql-mode.md) | Run MySQL in permissive SQL mode | 2014 (4.1) | 🟢 |
| [008](008-blocks-in-html-comments.md) | Encode block structure in HTML comments | 2018 (5.0) | 🟢 |
| [009](009-html-api-replaces-regex.md) | Build a spec-compliant HTML parser in PHP | 2023 (6.2) | 🟢 |
| [010](010-bcrypt-with-prehashing.md) | Move to bcrypt with HMAC-SHA-384 pre-hashing | 2025 (6.8) | 🟢 |
| [011](011-recovery-mode-over-white-screen.md) | Degrade instead of failing: recovery mode | 2019 (5.2) | 🟢 |
| [012](012-abilities-api-inverts-defaults.md) | Invert core's defaults for the Abilities API | 2025 (6.9) | 🟢 |
