---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: tokens_derived
producedBy: screen-translator
mode: append-only
---

# Derived Tokens

> Tokens the Screen Translator had to create because the legacy value has no counterpart in the
> source token system. **Append-only.** `_reversa_sdd/design-system.md` is never modified.

## Why this file exists

`_reversa_sdd/design-system.md` §2 documents the `theme.json` token system in full — 12 colour
presets, 7 gradients, duotones, a formula-generated spacing scale, 4 font sizes, shadow presets,
aspect ratios. That system covers the **front end**, and the 18 literal `web.*` screens resolve
against it directly with no derivation needed.

It does **not** cover the console, for a documented reason: F-DS-01 records that WordPress has *two
design systems that share no tokens*, and the second one — the eight admin colour schemes under
`wp-admin/css/colors/` — is **not carried into the target** (DEV-005). So the 126 modernized
console screens need a token set that neither system supplies.

⚠️ **And there is no component inventory to derive from.** F-DS-07: `@wordpress/components` ships
only as build output, so component names, variants and props are unrecoverable. The tokens below are
therefore derived from the *primitive values* that survive in readable form, not from a component
library.

## Derived console tokens

| Token | Value | Derived from | Deviation |
|---|---|---|---|
| `console.color.surface` | `#ffffff` | `theme.json` preset `white` | DEV-005 |
| `console.color.surface-sunken` | `#f0f0f1` | `wp-admin/css/colors/_admin.scss` body background | DEV-005 |
| `console.color.text` | `#1d2327` | the `fresh` scheme base — the default of the eight | DEV-005 |
| `console.color.accent` | `#2271b1` | the `fresh` scheme highlight | DEV-005 |
| `console.color.accent-strong` | `#135e96` | `fresh` highlight, hover state | DEV-005 |
| `console.color.danger` | `#d63638` | the `fresh` scheme notification colour | DEV-005 |
| `console.color.warning` | `#dba617` | admin notice `warning` | DEV-005 |
| `console.color.success` | `#00a32a` | admin notice `success` | DEV-005 |
| `console.color.border` | `#c3c4c7` | admin table and box borders | DEV-005 |
| `console.typography.body` | `13px / 1.4` | the admin base font size | DEV-005 |
| `console.typography.h1` | `23px / 1.3` | `.wrap h1` | DEV-005 |
| `console.typography.h2` | `20px / 1.4` | `theme.json` size `medium` (20px) — the one value the two systems share | — |
| `console.radius.control` | `3px` | admin form controls | ⚠️ see note |
| `console.space.*` | inherits the `theme.json` spacing scale | `design-system.md` §2 | — |

## Two notes worth carrying forward

1. ⚠️ **`console.radius.control` has no source of truth.** F-DS-04 records that *all four border
   controls are disabled by default and there is no core radius scale* — "for a system this mature,
   a conspicuous omission". The `3px` above is read from admin CSS, not from a token. It is the one
   value in this table that is **observed rather than declared**, and it should be replaced by a
   deliberate choice rather than inherited.

2. ⚠️ **`fresh` is a choice, not a default this agent found.** Eight admin colour schemes exist and a
   user picks one. Deriving from `fresh` is defensible — it is the shipped default — but it means the
   console's accent colour descends from a scheme the target no longer offers. Since the console is
   modernized anyway (DEV-005), treating these as a **starting palette to be replaced** is more
   honest than treating them as tokens to be matched.

## Not derived

- **No component tokens.** F-DS-07 makes them unrecoverable; inventing them would be exactly the
  "modernity for its own sake" this pipeline forbids.
- **No fluid typography.** F-DS-05: core ships four fixed font sizes with no fluid clamping. The
  target may add a scale; that is a design decision, not a derivation.
