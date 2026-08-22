---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: screen_modernization_decision
producedBy: screen-translator
decidedBy: thies
decidedAt: 2026-08-21T00:00:00Z
mode: hybrid
sourcePlatform: php-server-rendered
targetPlatform: rails-hotwire
hash: "sha256:c343683f661784f93b72de9a331f8e2d4021f54a00f287f1876991b81deefc6d"
---

# Screen Modernization Decision

> A conscious decision about how to translate the legacy system's screens: byte-for-byte observable
> parity, an idiomatic redesign for the target platform, or a screen-by-screen combination.
> Required reading for the Screen Translator's Phase 2, for the Inspector (to build parity tests
> suited to the mode) and for the coding agent.

## Context

- **Detected source platform**: **`php-server-rendered`**
- **Confidence**: 🟢 CONFIRMED — 1,900 PHP files with inline HTML; `wp-admin/` is a front controller
  per URL (95 root files, 30 network, 10 user), and filenames are public API (ADR-002,
  `inventory.md` §3).
- ⚠️ **A second source platform exists and is opaque.** The block editor and the Site Editor are a
  **React SPA** whose source is not in this tree — `wp-includes/js/dist/` ships compiled
  `@wordpress/*` packages only (TD-19, Q6, `dependencies.md` §4). It is *detected* but not
  *readable*. Every screen it owns is specifiable only at the shell level.
- **Target platform**: **`rails-hotwire`** — Rails server-rendered HTML with Turbo and Stimulus.
- **Screens inventoried**: **144** (141 in scope, 3 excluded)
- **Inventory source**: `_reversa_sdd/screens/inventory.json`.
  ⚠️ `_reversa_sdd/ui/inventory.md` is **absent** — `reversa-visor` has not run (EC-18). The FR-05
  divergence check could not be applied, so this inventory is unverified against a second reading.
- **Adapter applied**: `php__spa`, spec format **`route-component`** (`references/adapter-pairs.md`).
  The catalogued pair is `php-server-rendered` → `web-spa`; the chosen target is server-rendered
  Rails, which is a **closer** idiom than the catalogued one. `route-component` still applies —
  `spec.route` and `spec.layout` map onto Rails routes and layouts directly — but note the pair is
  being used one step conservatively, in the target's favour.

### Inventory breakdown

| Group | Screens | Legacy origin |
|---|---:|---|
| `console.*` | 113 | `wp-admin/*.php` (77), `wp-admin/network/*.php` (28), `wp-admin/user/*.php` (8) — includes `console.authorize-application` |
| `web.*` | 18 | the template hierarchy resolved by `wp-includes/template-loader.php` |
| `auth.*` | 8 | `wp-login.php` action dispatch |
| `tenancy.*` | 5 | `wp-signup.php` (3), `wp-activate.php` (2) |
| **Total** | **144** | 27 marked critical |
| *excluded* | 3 | `link-manager`, `link-add`, `link` — the target drops `wp_links` (F-DD-07, `target_data_model.md`) |

## Modes evaluated

### Mode: literal
- **Definition**: byte-for-byte or pixel-equivalent observable parity between the legacy system and
  the new one.
- **Trade-offs**:
  - Implementation cost: **high**
  - Visual fidelity: **high** where achievable
  - Feasibility of constructive parity tests: **no**, as a global mode — see below
  - Expected end-user acceptance: **high** (nothing changes)
  - Future technical debt: **high** — it imports the legacy's UI decisions wholesale
- **Recommended**: **no — ruled out as a global mode, on two independent grounds.**
- **Rationale**:

  1. **FR-13 and this agent's absolute rules refuse it.** Literal mode with a graphical target and
     no legacy screenshot must block. `_reversa_sdd/ui/screens/` does not exist and
     `_reversa_sdd/ui/inventory.md` is absent (EC-18), so there is nothing to be faithful *to*.
  2. **The component library is unrecoverable.** F-DS-07 states it plainly: `@wordpress/components`
     ships only as build output, so component names, variants and props cannot be read from this
     checkout. Literal fidelity for the 113 console screens would mean reproducing a component
     library that no one can inspect. This ground does not go away even if screenshots appear.

  ✅ **But ground 2 does not apply to the front end.** `theme.json` is fully readable and 🟢
  CONFIRMED — 12 colour presets, gradients, duotones, a formula-generated spacing scale, four font
  sizes — and every preset emits both a CSS custom property and a utility class (BR-GS-07). And
  ground 1 is **removable**: AD-08 already commits to a running reference WordPress instance, which
  can capture golden HTML+CSS for those screens. This asymmetry is what makes hybrid viable.

### Mode: modernized
- **Definition**: an idiomatic redesign for the target platform, preserving the information and the
  flow but re-expressing the hierarchy and the interaction.
- **Trade-offs**:
  - Implementation cost: **medium**
  - Visual fidelity: **low** — deliberately
  - Feasibility of constructive parity tests: **partial** — semantic contract only (events,
    transitions, textual content, the four states); no byte comparison
  - Expected end-user acceptance: **medium** — there are no existing users to disrupt, since there
    is no live deployment
  - Future technical debt: **low**
- **Recommended**: **yes, for the console, auth and tenancy screens.**
- **Rationale**: for 126 of the 144 screens the legacy source is either opaque (the editor) or
  already slated for reduction. `target_architecture.md` BC-11 merges the **four overlapping
  settings surfaces** — Customizer, widgets, nav menus, Site Editor — that TD-10 and F-CUST-04
  record as redundant. Literal fidelity would contradict a reduction already approved in the
  architecture. Modernizing is not a preference here; it is the consequence of a decision already
  taken.

### Mode: hybrid
- **Definition**: some screens literal, some modernized, with explicit lists.
- **Trade-offs**:
  - Implementation cost: **medium-high** — one extra mechanism (golden capture) for 18 screens
  - Mixed visual fidelity: **high on the front end, redesigned in the console.** This matches where
    fidelity is worth paying for: the front end is what readers see and what themes render; the
    console is staff-facing and already being consolidated.
  - Feasibility of parity tests: **byte-comparable** for the 18 `web.*` screens once golden files
    exist; **semantic contract** for the other 126. The Inspector declares the strategy per screen.
  - Cost of maintaining the split: **low** — the split follows an existing architectural boundary
    (`Web` vs `Console` surfaces in `target_architecture.md`), not an arbitrary line.
- **Recommended**: **yes.**
- **Rationale**: it puts literal fidelity exactly where the evidence supports it — the surface whose
  design tokens are 🟢 CONFIRMED and whose oracle output can be captured — and modernization exactly
  where the source is unreadable and the architecture has already chosen to consolidate.

## Decision

- **Chosen mode**: **hybrid**
- **The human's rationale**: accepted the recommendation as presented — literal for the 18
  front-end templates, unblocked by capturing golden HTML+CSS from the Wave 0 oracle; modernized for
  the 126 console, auth and tenancy screens.
- **Rejected alternatives**:
  - *Literal everywhere* — refused by this agent on the two grounds above, not by the owner.
  - *Modernized everywhere* — viable and unblocked today, rejected because it would put the front
    end permanently out of visual parity scope and turn every theme-output diff into an accepted
    deviation, discarding the one surface where the token system makes fidelity cheap.
- **Decided at**: 2026-08-21
- **Decided by**: thies (owner)

### In hybrid mode, the explicit lists (mandatory)

**Screens in literal mode (18)** — all `web.*`, resolved by `wp-includes/template-loader.php`:

`web.index` · `web.front_page` · `web.home` · `web.singular` · `web.single` · `web.page` ·
`web.archive` · `web.category` · `web.tag` · `web.taxonomy` · `web.author` · `web.date` ·
`web.search` · `web.not_found_404` · `web.attachment` · `web.embed` · `web.privacy_policy` ·
`web.comments`

> ⚠️ **These 18 are BLOCKED until golden files exist.** FR-13 stands: literal mode may not be
> generated without a legacy capture. Phase 2 emits `_reversa_sdd/screens/golden/manifest.yaml` with
> a suggested capture command per screen; automated capture is OQ-02 and out of scope for v1. Until
> the manifest is run against the oracle, these screens carry a **pending** deviation and the
> handoff to the Inspector is blocked for them.

**Screens in modernized mode (123 in scope, 126 inventoried)**:

- **`console.*` (113, of which 3 excluded)** — the whole administration surface, including
  `console.site-editor`, `console.customize`, `console.widgets`, `console.nav-menus`, which
  `target_architecture.md` BC-11 consolidates.
- **`auth.*` (8)** — `auth.login`, `auth.logout`, `auth.lostpassword`, `auth.retrievepassword`,
  `auth.resetpass`, `auth.register`, `auth.confirmaction`, `auth.checkemail`.
  (`console.authorize-application` sits in the console group, since it is an admin route.)
- **`tenancy.*` (5)** — the multisite signup and activation flows. ⚠️ Wave 5; these are specified now
  but built last (RISK-009).

Both lists are non-empty; EC-12 satisfied.

## Pending implications for Phase 2

| Step | Implication | How to honor it |
|---|---|---|
| Generating `target_screens.md` | Two spec kinds in one document. | Modernized screens use `spec.kind: route-component` with `spec.route`, `spec.layout` and the **four states** (idle, loading, error, success) declared explicitly. Literal screens use `spec.kind: route-component` with a `golden_ref` and **no invented states** — principle 6 forbids inventing states the legacy does not have. |
| Generating `target_screens.md` | ⚠️ The editor screens have no readable source. | `console.post-new`, `console.post`, `console.site-editor` are specifiable **only at the shell level** — route, layout, chrome, entry and exit transitions. The editing canvas itself is `raw-prose` with a recorded deviation, because TD-19 leaves nothing to translate. Do not invent a component tree for it. |
| Capturing golden files | Literal mode is blocked without them. | Emit `manifest.yaml` listing one `.html` + `.css` capture per `web.*` screen, with a deterministic capture recipe: fixed clock, fixed seed, a seeded corpus, `admin_color` irrelevant (front end). Mark all 18 `pending` in the deviation log. |
| Design-system tokens | ⚠️ `_reversa_sdd/design-system/` does not exist; the artifact is `_reversa_sdd/design-system.md` at the root (EC-17 near-miss). | Read tokens from `design-system.md` §2. Any legacy value without a matching token gets a derived token in `_reversa_sdd/design-system/tokens-derived.md` (append-only, never modifying the source) and a `DEV-` entry. |
| Design-system tokens | **There are two token systems that share nothing** (F-DS-01): `theme.json` for the front end, eight SCSS colour schemes for the admin. | Literal `web.*` screens resolve against `theme.json` tokens. Modernized `console.*` screens must **not** inherit the eight admin colour schemes — reproducing `admin_color` is a preference feature the rebuild has no reason to carry. Record as a deviation. |
| Textual content | Preserve it literally unless copy editing is explicitly approved. | **No copy editing is approved.** All labels, prompts, validation messages and error strings are copied byte-for-byte, including any legacy typo (EC-11: in modernized mode a typo *may* be fixed with `type=fix`, but that requires a per-string decision, not a blanket licence). |
| i18n | Strings live in gettext catalogues (`wp-includes/pomo/`, `l10n/`), not in the templates. | EC-05 applies: keep `{{i18n.<key>}}` references rather than inlining English literals. The source English string **is** the key (F-I18N-02), which is a legacy property the target inherits unless `Localization` decides otherwise. |

## Implications for the Inspector

- **Parity strategy — mixed, declared per screen in `parity_specs.md`:**
  - **The 18 `web.*` screens → observable parity** against golden HTML+CSS, once captured. ⚠️ If the
    capture never happens, these fall back to semantic contract and the fallback must be **recorded
    as a deviation**, not assumed.
  - **The 123 in-scope modernized screens → semantic contract only**: events, transitions, textual
    content, and the four declared states. **No byte-for-byte or visual comparison.** A visual diff
    on a console screen is not a parity failure and must not be reported as one.
- **Textual content is in parity scope for every screen, in both modes.** Labels and messages are
  preserved literally, so a string diff is a real failure regardless of mode.
- ⚠️ **`web.*` literal parity is HTML parity, not behavioural parity.** It sits alongside, not
  instead of, the 363 rule-level parity specs. A page can render byte-identically and still have the
  wrong publish state behind it.
- **Known deviations to propagate**: see `screen_deviation_log.md`; approved entries flow into
  `parity_specs.md § Exceptions`.

## Notes

**Four things the coder and the Inspector need to know:**

1. **The split follows an architectural boundary, not a taste judgement.** Literal = the `Web`
   surface; modernized = the `Console`, auth and tenancy surfaces. Those are already distinct
   controller groups in `target_architecture.md`, so the mode is derivable from where a screen lives
   rather than from a list someone has to remember.

2. **The 18 literal screens are blocked, and that is the intended state.** They are not "to do
   later" — they are specified as *pending a capture that Wave 0 makes possible anyway*. The oracle
   is being built regardless (AD-08); the manifest just tells it what to photograph while it is up.

3. **No copy editing is approved.** Every string is preserved. If a legacy label is wrong, fixing it
   is a per-string decision recorded as `type=fix`, not a licence to rewrite the interface.

4. ⚠️ **`reversa-visor` never ran, so this inventory has not been cross-checked.** 144 screens were
   derived from the file tree by this agent alone. The FR-05 rule — stop if the two inventories
   diverge by more than 10% — could not be applied. The count is defensible (one screen per admin
   route, one per template-hierarchy branch, one per `wp-login.php` action) but it is **one
   reading, not two**. Recorded in `ambiguity_log.md`.
