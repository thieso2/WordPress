# ADR-008 — Encode block structure in HTML comments

**Status:** Accepted · **Date:** 2018 (WordPress 5.0, Gutenberg) · **Confidence:** 🟢 CONFIRMED

## Context

The block editor needed structured, addressable content. But `post_content` already held twenty
years of HTML from the classic editor, was read directly by countless plugins, themes and export
tools, and had to keep rendering correctly on any site that disabled the new editor.

## Decision

Keep `post_content` as **valid HTML**, and encode block boundaries and attributes in **HTML
comments**.

```html
<!-- wp:paragraph {"align":"center"} --><p class="has-text-align-center">Hi</p><!-- /wp:paragraph -->
```

## Evidence

- The delimiter regex (`class-wp-block-parser.php:248`) with `closer`, `namespace`, `name`, `attrs`
  and `void` capture groups.
- `innerContent` mixes literal HTML strings with `null` placeholders marking child positions, which
  is what makes parse → serialize lossless (BR-BLK-06/07).
- The parser is a stack machine that **cannot fail**: unclosed blocks close implicitly, unrecognized
  text becomes `core/freeform` (BR-BLK-04/05).

## Alternatives considered 🟡

| Alternative | Why not |
|-------------|---------|
| A JSON column or a separate `post_blocks` table | Content would be invisible to every existing plugin, theme, feed reader and export tool. Disabling the editor would blank every post. |
| Custom XML/JSON in `post_content` | The field would no longer be renderable HTML; every classic theme and `the_content` filter would break. |
| Custom HTML elements (`<wp-paragraph>`) | Browsers would render them as unstyled inline elements; content would degrade *visibly*. Comments degrade *invisibly*. |
| Data attributes on real elements | Cannot express nesting boundaries or blocks without a wrapper element. |

## Consequences

**Positive**
- **Content degrades gracefully.** An install with the block editor disabled — or a feed reader, or
  an export — still renders every post correctly. This is the single best decision in the block
  system (F-BLK-01).
- Existing `the_content` filters keep working.
- Round-tripping is lossless.

**Negative**
- Content structure is parsed by **regular expression**, including a hand-rolled JSON brace matcher
  using a possessive quantifier (F-BLK-02). This bounds how complex attributes may become.
- The parser cannot fail, so there is no validation stage and no error signal for corrupt block
  markup (F-BLK-03).
- ~82% of core blocks turned out to be **dynamic**, so stored content is an incomplete description
  of the page anyway (F-BLK-06, F-BLIB-02) — partially undermining the "content is in the database"
  premise.
- Reading 115 `block.json` files per request was slow enough to require a 206 KB generated PHP
  manifest (F-BLIB-01).
