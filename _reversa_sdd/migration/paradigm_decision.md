---
schemaVersion: 1
generatedAt: 2026-08-21T00:00:00Z
reversa:
  version: "1.2.58"
kind: paradigm_decision
producedBy: paradigm_advisor
hash: "sha256:304c8eeb6cbcbbdf91b5de96060d78f7b2d1640754542b5716386137b022824f"
---

# Paradigm Decision

> A conscious decision about how to handle the change (or absence of change) of paradigm between the legacy system and the target stack.
> This artifact is required reading first for every downstream agent and for the coding agent.

## Detected legacy paradigm

- **Main paradigm**: **hybrid** - dominantly **procedural**, with a synchronous **observer** layer and isolated **classic OO** islands.
- **Confidence**: 🟢 CONFIRMED

- **Evidence**:
  - Global functions over process-wide globals. `$wpdb`, `$wp_object_cache`, `$wp_the_query`, `$wp_query`, `$wp_rewrite`, `$wp`, `$wp_widget_factory`, `$wp_roles`, `$wp_locale`, `$wp_locale_switcher` are all instantiated at fixed line numbers during boot. Source: `domain.md` DR-06, `architecture.md` section 3.2, `bootstrap-and-load/design.md`.
  - No dependency-injection container, no aggregates, no repositories anywhere in 44 modules. Source: `dependencies.md` section 7 ("what is absent"), which records the absence of an autoloader, a DI container, an ORM and a query builder.
  - Domain logic lives in free functions, not objects. `wp-includes/post.php` is 298 KB of top-level functions serving 16 unrelated post types through one code path. Source: F-POST-01, F-POST-07.
  - No transactions anywhere. `wpdb` exposes no `begin`/`commit`/`rollback`, so multi-table operations use compensating logic. Source: F-DB-06, `domain.md` DR-07.

- **Observed variations** (hybrid):
  - **Observer / event layer**: 565 unique actions and 1,638 unique filters across 3,371 dispatch sites. `do_action()` is `apply_filters()` with the return discarded, so both are one mechanism. Synchronous, in-process, not message-based. Source: F-HOOK-01, `hooks-plugin-api/design.md`.
  - **Classic OO islands**: `WP_Query` (4,900 lines), `wpdb` (4,230 lines), `WP_Customize_Manager` (198 KB), `WP_Theme_JSON` (216 KB). These are god-objects and data holders rather than domain models with invariants. Source: F-QUERY-07, F-DB-01, F-CUST-03.
  - **One genuinely declarative subsystem**: `theme.json` and the four-origin cascade, the only data-compiled-to-CSS design in core. Source: F-GS-01.
  - **Two rigorous, well-factored modules**: `html-api` (HTML5 tree construction) and `style-engine` (single responsibility per class, no globals, no hooks in the hot path). Source: F-HTML-01, F-SE-01.

## Declared target stack

- Language: Ruby (modern, 3.3+)
- Framework: Ruby on Rails (modern, 7.1+)
- Infrastructure: not specified in the brief. PostgreSQL is the declared database.

## Inferred natural paradigm

- **Paradigm**: **classic OO (Active Record)**
- **Rationale**: `references/paradigm-catalog.md` maps "Modern Ruby (Rails 7, Hanami)" to classic OO for Rails specifically, noting "Rails dictates Active Record". Rails is convention-over-configuration: models own their data and their invariants, persistence is inherited rather than injected, and the framework supplies transactions, validations, callbacks and a query builder as first-class idiom.
- **Viable alternatives**:
  - **OO with DI (Hanami)**, at the cost of leaving the Rails ecosystem and its conventions. Would suit the repository pattern better but loses ActiveRecord's migration, validation and association machinery.
  - **Light functional (dry-rb)** layered on Rails, at the cost of fighting the framework's defaults in every model.

## Identified gap

- **Severity**: **HIGH**

- **Concrete implications** (each citing the affected legacy rule or flow):

  - **Implication 1: global mutable state has no Rails analogue.**
    In the legacy system, `switch_to_blog()` mutates `$wpdb`'s table prefix, the object cache's `blog_prefix` and several globals at once, and must be unwound manually by `restore_current_blog()`. An unbalanced switch corrupts every subsequent query in the request (`multisite/design.md`, F-MS-02). Rails has no process-wide request state of this kind. Per-request context lives in controller instances or `ActiveSupport::CurrentAttributes`, and multi-tenancy is expressed through scoping or schema switching rather than by mutating a global connection object.

  - **Implication 2: the hook system disappears, so the documented default becomes final.**
    In the legacy system, 1,638 filters mean no core function's return value can be specified without also specifying its filters, and `apply_filters('query', $sql)` lets any plugin rewrite every SQL statement in the system (F-HOOK-06, BR-DB-05). With no compatibility burden, the rebuild does not reproduce this. **The consequence is precise and load-bearing: every one of the 431 extracted rules describes WordPress's unfiltered default, and in the target that default becomes the permanent, only behaviour.** Nothing can change it at runtime. This is what makes behavioural parity checkable at all.

  - **Implication 3: every compensating transaction can be deleted.**
    The legacy has no transactions, so uniqueness is enforced by check-then-act or insert-then-detect loops: `wp_insert_term()` inserts rows, queries for an older duplicate, then deletes its own rows (F-TAX-02); `add_metadata()` runs `SELECT COUNT(*)` then `INSERT` with no unique index behind it (F-META-02); `wp_unique_post_slug()` loops with one query per attempt (F-POST-03). In Rails each collapses into a database unique index plus a single transaction. **Three business rules become zero rules and one migration.**

  - **Implication 4: derived state moves from inline procedure into the model.**
    In the legacy system, post status is computed from `post_date_gmt` inside `wp_insert_post()` with a 60-second threshold, so a caller cannot set status independently of date (BR-POST-01/02). Hierarchical term counts are padded at read time by `_pad_term_counts()`, which joins `term_relationships` to `posts` filtered to `post_status = 'publish'` on every render (BR-TAX-11, F-TAX-05). In Rails these become a `before_save` callback or a state machine on `Post`, and a counter cache or materialized count on `Term`.

  - **Implication 5: sixteen post types in one table forces an explicit modelling fork.**
    `wp_posts` holds posts, pages, attachments, revisions, nav menu items, Customizer changesets, oEmbed cache, block templates, global styles and font faces, distinguished only by a `post_type` column (F-POST-01). Rails offers single-table inheritance, which is closest to the legacy and keeps the two composite indexes meaningful, or separate models and tables, which is cleaner but abandons the "everything is a post" generality that ADR-004 records as a deliberate decision. **This is a genuine design fork and belongs to the Designer, not to this agent.**

  - **Implication 6: the slashing convention vanishes.**
    `wp_magic_quotes()` re-slashes every superglobal during boot, so all WordPress input arrives slashed and `wp_unslash()` is required before use, enforced by nothing (DR-02, F-FMT-05). Rails params are never slashed. A whole class of double-escaping bugs disappears, but **every extracted rule that assumes slashed input must be re-read before being ported**, notably BR-META-02 and the `formatting-and-sanitization` module.

## Options presented to the user

1. **Adopt the stack's natural paradigm** (transformational)
   - ActiveRecord models own their invariants; validations and DB constraints replace check-then-act loops.
   - `map_meta_cap()`'s 870-line switch becomes policy objects (Pundit or ActionPolicy), fail-closed by default, which also discharges the Q4 decision.
   - Compensating transactions become real transactions.
   - Derived state becomes callbacks, state machines and counter caches.
   - The hook system is not reproduced; behaviour becomes final.
   - Highest per-rule translation risk, lowest long-term debt. Breaks the 23-module cycle by construction.

2. **Force a paradigm similar to the legacy one** (conservative)
   - Recreate a hook registry, global service locators and procedural module functions in Ruby.
   - Rules port almost literally, so parity risk is lowest.
   - Inherits the 23-module cycle, the global-state coupling and the five conflicting authorization defaults.
   - Rails supplies nothing: no ActiveRecord, no policies, no transaction idiom. The team reimplements the framework's stack.

3. **Hybrid** (balanced)
   - Rails idiom for the data core (posts, taxonomy, users, comments, media, options, metadata).
   - An explicit extension-point registry retained only where the extraction shows behaviour genuinely must vary (block rendering, template resolution, content filters).
   - Requires drawing and defending a boundary, which the Designer would have to make concrete in `topology_decision.md`.

## User decision

- **Choice**: **1**
- **User's rationale**: Adopt the Rails idiom. Selected with the transformation preview showing `wp_insert_term()` collapsing to `Term.create!` plus a unique index, `map_meta_cap()` becoming a policy object, the boot globals disappearing, and the hook system deliberately not reproduced so that behaviour becomes final rather than negotiable.
- **Decided at**: 2026-08-21T00:00:00Z

## Derived appetite

- `derived_appetite`: **transformational**

## Pending implications for the next agents

| Agent | Implication | How to honor it |
|---|---|---|
| **Curator** | Implication 2. Every rule describes the unfiltered default, and filters are out of parity scope. | When classifying the 431 rules, mark any rule whose statement is *about* the hook mechanism itself (BR-HOOK-01 to 12, BR-DB-05, the `user_has_cap` override) as DISCARD with the reason "extension mechanism not reproduced, see paradigm_decision option 1". Do not carry them into `target_business_rules.md` as behaviour to implement. |
| **Curator** | Implication 3. Compensating-transaction rules describe a workaround, not a requirement. | BR-TAX-05, BR-META-03, BR-POST-06 and BR-POST-03 describe *how* the legacy achieves uniqueness without transactions. Carry forward the **invariant** (a term is unique per slug, parent and taxonomy) and discard the **mechanism**. Record each in `discard_log.md` with the invariant that replaces it. |
| **Curator** | Implication 6. Slashing-dependent rules need re-reading. | Flag BR-META-02 and every `formatting-and-sanitization` rule that mentions `wp_unslash` or `wp_slash` as HUMAN DECISION: confirm the underlying intent before porting. |
| **Strategist** | Implication 1 and the primary risk in the brief. | The 23-module cycle exists partly *because* of global state and the hook system. Adopting option 1 dissolves much of it, so the strategy may sequence by data dependency rather than by the legacy cycle. State explicitly in `migration_strategy.md` whether the cycle still binds the sequencing after the paradigm change. |
| **Designer** | Implication 5. | `topology_decision.md` must decide single-table inheritance versus separate models for the 16 post types, and defend it. This is the single largest modelling decision in the rebuild. |
| **Designer** | Implications 3 and 4. | `target_data_model.md` must express as database constraints every invariant the legacy enforced in PHP: unique indexes on term slug/parent/taxonomy and on post slug per type, foreign keys for all 18 relationships that currently have none (F-DD-01), and a decision on counter caches for term and comment counts. |
| **Designer** | ~~The Q4 decision, carried from `questions.md`.~~ **AMENDED 2026-08-21.** | ⚠️ **The owner overrode question Q4 at the post-Curator pause and reaffirmed it when the conflict was put to them.** Authorization defaults are **reproduced as in the legacy**, including the permissive ones: a route with no policy is public (`BR-REST-05`), a policy emitting no capabilities allows (`BR-CAP-05`), and an ungated endpoint class exists (`BR-ADM-07`). Finding `F-DOM-02` is knowingly carried forward. See `target_business_rules.md`, Owner overrides. |
| **Inspector** | Implication 2. | Parity specs assert the unfiltered default only. Any legacy behaviour that requires a filter to observe is out of scope; note it in `parity_specs.md` rather than writing a test that cannot pass. |
| **Inspector** | Implication 4. | Write parity tests for derived state as behaviour, not as implementation: assert that publishing with a date 90 seconds ahead yields a scheduled record, without asserting how the model computes it. |

## Notes

**The tension recorded in the brief resolves here.** The success metric is behavioural parity while
the constraint is no compatibility burden. Under option 1 these are consistent, because parity is
owed to the **documented default behaviour** and not to the **extension contract**. Implication 2
states this precisely, and the Curator and Inspector rows above make it operational.

**What the coding agent must understand before writing any Ruby.** WordPress's 431 rules were
extracted from a system where almost every value passes through a filter before use. In the target
there are no filters. A rule that reads "X happens unless a plugin changes it" becomes simply
"X happens". That is a simplification, and it is also the reason the rebuild can be tested at all.

**Two legacy modules are worth reading before designing their replacements**, because they are the
only parts of WordPress already written in a modern idiom: `html-api` (a genuine HTML5
tree-construction parser that fails loudly on unsupported input) and `style-engine` (single
responsibility per class, no globals, no hooks in the hot path). Sources: F-HTML-01, F-HTML-02,
F-SE-01.

**Amendment, 2026-08-21.** Two contract rows above were reversed by owner ruling at the
post-Curator pause: authorization defaults are reproduced rather than made fail-closed, and the
KSES regex implementation is reproduced rather than replaced. Both were reaffirmed after the
conflict with questions Q4 and Q5 was put directly to the owner. The rest of option 1 stands
unchanged: no hook system, real transactions, ActiveRecord models, no global mutable state.

**Excluded from scope by the brief**: `deprecated-compat` and `xmlrpc`. Under option 1 both
exclusions are reinforced rather than merely permitted, since neither has a target-paradigm
equivalent worth building.
