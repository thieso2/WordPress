# ADR-009 — Build a spec-compliant HTML parser in PHP

**Status:** Accepted · **Date:** 2023 (WordPress 6.2) · **Confidence:** 🟢 CONFIRMED

## Context

For two decades WordPress modified HTML with regular expressions: adding `srcset` to `<img>` tags,
injecting classes, filtering attributes, stripping tags. This produced a long tail of correctness
bugs and security issues, because HTML is not a regular language.

## Decision

Write two purpose-built parsers in PHP: a **streaming tag-level editor** for the common case, and a
**full HTML5 tree-construction parser** for cases needing real structure.

## Evidence

- Introduced `be73904dc7 Introduce HTML API with HTML Tag Processor` (2023-02-03), followed
  immediately by bookmark invalidation, RCData/Script closer handling and self-closing-flag support
  — the commit sequence of people finding real HTML edge cases.
- `class-wp-html-tag-processor.php` (175 KB) — forward-only, byte-level edits applied on
  `get_updated_html()`, with `set_bookmark()`/`seek()` for non-linear access.
- `class-wp-html-processor.php` (209 KB) — insertion modes, stack of open elements, active
  formatting elements, adoption agency algorithm.
- `WP_HTML_Unsupported_Exception` — fails **loudly** on constructs it cannot handle correctly.
- 220 `HTML API:` commits.

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| `DOMDocument` | Requires `ext-dom` (not universally available), mangles HTML5, cannot round-trip source formatting, and loads the whole document into a node graph. |
| A third-party HTML5 parser (e.g. Masterminds/HTML5) | Would be a vendored dependency in the hot path of every rendered post; performance and memory unacceptable for `wp_filter_content_tags()`. |
| Better regular expressions | The approach being replaced. HTML is not regular; each fix creates the next edge case. |

## Consequences

**Positive**
- The most rigorous code in WordPress: a genuine HTML5 tree-construction implementation (F-HTML-01).
- Memory stays proportional to the document, not to a node graph — necessary for a parser that runs
  on every post (F-HTML-03).
- Enabled the Interactivity API, which depends entirely on `get_attribute_names_with_prefix()`
  (F-INT-02).
- Failing loudly on unsupported constructs is the correct choice for a correctness-critical parser
  (F-HTML-02).

**Negative**
- 384 KB of parser code to maintain against a living specification.
- Callers must drive the cursor themselves; there is no simple "modify this HTML" helper, which
  keeps it fast and makes it easy to misuse (F-HTML-04).
- **The migration is incomplete.** `wpautop()`, `wptexturize()` and all of KSES still parse HTML with
  regular expressions, and KSES is the higher-risk of the two (F-KSES-05, F-FMT-04).
