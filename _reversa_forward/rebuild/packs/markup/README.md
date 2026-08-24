# `markup` — the WordPress `html-api` port

Pure-Ruby port of `wp-includes/html-api/` from WordPress 7.2-alpha-63330 onto Rails 8.1.

This pack has **zero dependencies**: no Rails, no ActiveSupport, no ActiveRecord, no other
pack, nothing but the Ruby standard library (`base64` and `open3` only in the specs).
`bin/check_cycles` enforces the declaration; `spec/pack_isolation_spec.rb` enforces that
the source honours it, including a run in a bare `ruby --disable-gems` process.

`spec-impact-matrix.md` (F-SIM-03) names `html-api` one of only two genuinely extractable
components in WordPress — zero internal dependencies, few dependents — and
`paradigm_decision.md` names it one of the two legacy modules already written in a modern
idiom. Both hold up: the legacy is object-oriented, dependency-free and filter-free, so
this port is close to a transliteration rather than a redesign.

| | |
|---|---|
| Legacy source | `wp-includes/html-api/` — 16,589 lines of PHP |
| Port | 7,068 lines of Ruby under `app/markup/`, of which 2,251 are the generated entity table |
| Specs | 190 examples, 0 failures |
| Differential corpus | 103 curated inputs × 11 compared fields, plus 150 in-suite fuzz documents |
| Additional fuzzing (offline) | ~5,100 randomised documents across 12 seeds, all matching |

---

## Rules implemented

All seven. Each is verified against the live PHP oracle, not only by hand-written
assertions.

### BR-MIGRATE-220 — no tree; modifications are byte-level and applied on `get_updated_html()`
`class-wp-html-tag-processor.php:4913` → `Markup::TagProcessor#get_updated_html`

`Markup::TagProcessor` holds the document as one binary string and records byte offsets —
`Markup::Span`, `Markup::AttributeToken` — for the token it is sitting on. Nothing is
materialised: `get_attribute` decodes on demand, `get_modifiable_text` decodes on demand.
`set_attribute`, `remove_attribute`, `add_class`, `remove_class` and `set_modifiable_text`
enqueue a `Markup::TextReplacement` and change nothing; `get_updated_html` sorts the queue
by start offset, splices it in one pass, shifts the cursor and every bookmark by the
accumulated deltas, and reparses the current token in place. Bytes the caller never asked
about come out exactly as they went in — original quoting, original whitespace, original
casing.

Because PHP's string functions are byte-oriented and Ruby's are not, the whole pack works
on `ASCII-8BIT` strings and `Markup::ByteScan` supplies `strspn`/`strcspn`. This is not a
stylistic choice: with astral-plane characters in the document (the migration brief's
`CORPUS_ASTRAL`), character offsets and byte offsets diverge and every splice would land in
the wrong place.

### BR-MIGRATE-221 — forward-only scanning; `set_bookmark()` and `seek()` are the only way back
`class-wp-html-tag-processor.php:1360` → `Markup::TagProcessor#set_bookmark`, `#seek`

There is no `previous_tag`. Bookmarks are stored as spans and are shifted as splices are
applied, so a bookmark keeps identifying the same *token* rather than the same *offset*; a
bookmark whose entire span is overwritten is released rather than left pointing at the
wrong bytes. `MAX_BOOKMARKS` (10) and `MAX_SEEK_OPS` (1000) are preserved verbatim, and
both limits are covered by specs.

`Markup::Processor#seek` is the harder case: the two tree-construction stacks *are* the
record of how the parser got where it is, so seeking backwards unwinds them, restores the
fragment's context (or byte zero for a whole document) and replays forward. The
differential suite compares a bookmark-and-return round trip for both parser kinds over
every corpus and fuzz input.

### BR-MIGRATE-222 — `get_attribute_names_with_prefix()` for attribute discovery
`class-wp-html-tag-processor.php:2971` → `Markup::TagProcessor#get_attribute_names_with_prefix`

Without a tree there is no `element.attributes` to walk, so consumers that need "every
`data-wp-*` attribute on this element" — the Interactivity API is the reason this exists —
ask by prefix. Names come back lowercased, matching is ASCII-case-insensitive, attributes
enqueued by `set_attribute` but not yet written are included, attributes enqueued for
removal are excluded, and pending `add_class`/`remove_class` are flushed first so that
`class` is discoverable. The differential suite calls it at every tag of every input, in
the middle of a mutation program, and compares the result.

### BR-MIGRATE-223 — HTML5 tree construction, stack of open elements, active formatting elements
`class-wp-html-processor.php` → `Markup::Processor`, `Markup::OpenElements`, `Markup::ActiveFormattingElements`

Twenty insertion modes are ported: initial, before html, before head, in head, in head
noscript, after head, in body, in table, in table text, in caption, in column group, in
table body, in row, in cell, in template, after body, in frameset, after frameset, after
after body, after after frameset, plus foreign content. With them come the scope
predicates (`in scope`, `list item scope`, `button scope`, `table scope`), implied end
tags (both kinds), `reset the insertion mode appropriately`, `close the cell`, the
MathML/HTML integration-point tests, and the adoption agency algorithm as far as a
forward-only processor can take it.

Elements the algorithm implies but the document never wrote — `HTML`, `HEAD`, `BODY`,
`TBODY`, `TR`, `COLGROUP` — are reported as *virtual* tokens through `Markup::StackEvent`,
which is how a caller sees tree shape without a tree.

### BR-MIGRATE-224 — fragment parsing requires a context element, defaulting to `<body>`
`class-wp-html-processor.php:300` → `Markup::Processor.create_fragment`

The context is what makes the difference between `<td>x</td>` losing its cell (BODY
context) and producing `TBODY > TR > TD` (TABLE context). `create_fragment` establishes the
context the way the legacy does — by running a full parser over `<!DOCTYPE html><body>` and
creating the fragment at the node it lands on — which is why `HTML` and `BODY` lead every
breadcrumb path from the first token. As in the legacy, `<body>` is the *only* context this
entry point accepts and `UTF-8` the only encoding: anything else returns `nil` rather than
guessing.

### BR-MIGRATE-225 — unsupported constructs raise rather than produce incorrect output
`class-wp-html-unsupported-exception.php` → `Markup::UnsupportedException`, `Markup::Processor#bail`

This is the rule that defines the module's character, and it is preserved exactly. Every
`bail()` site in the legacy is a `bail` site here, with the message string byte-identical:

- `Cannot reconstruct active formatting elements when advancing and rewinding is required.`
- `Cannot extract common ancestor in adoption agency algorithm.`
- `Cannot run adoption agency when "any other end tag" is required.`
- `Cannot run adoption agency when looping required.`
- `Foster parenting is not supported.`
- `Cannot process PLAINTEXT elements.`
- `Cannot process an IMAGE tag. (Don't ask.)`
- `Cannot process non-ignored FRAMESET tags.`
- `Cannot close a FORM when other elements remain open as this would throw off the breadcrumbs for the following tokens.`
- `Cannot process elements after HEAD which reopen the HEAD element.`
- `Cannot yet process META tags with charset to determine encoding.`
- `Cannot yet process META tags with http-equiv Content-Type to determine encoding.`
- `Content outside of BODY is unsupported.` / `Content outside of HTML is unsupported.`
- `Non-whitespace characters cannot be handled in frameset.` / `… in after frameset` / `… in after after frameset.`
- `No support for parsing in the insertion-mode-in-table-text state.`
- `Unaware of the requested parsing mode: '…'.`
- `Should not have been able to reach end of "any other end tag" IN BODY processing. Check HTML API code.`
- `Should not have reached end of HTML Integration Point detection: check HTML API code.`

Two further `bail()` calls in the legacy — `Should not have been able to reach end of IN
BODY processing.` (`:3369`) and `Should not have been able to reach end of IN FOREIGN
CONTENT processing.` (`:5100`) — are dead code: every path above them returns
unconditionally. They are not reproduced, and no input can reach them in either
implementation.

The exception carries the token name, the byte offset, the raw token text, and both stacks
— everything needed to reconstruct the failure. The exception is caught inside `step` and
surfaced as `get_last_error == "unsupported"` plus `get_unsupported_exception`, exactly as
in PHP: callers see a clean `false`, never a stack trace, and the processor then refuses to
continue rather than limping on. Five distinct abort paths are reached by the corpus and
compared message-for-message against the oracle.

### BR-MIGRATE-226 — `get_breadcrumbs()` / `matches_breadcrumbs()` without a DOM or XPath
`class-wp-html-processor.php:1202` → `Markup::Processor#get_breadcrumbs`, `#matches_breadcrumbs`

Breadcrumbs are maintained incrementally as stack events are visited, so reading them is
free. `matches_breadcrumbs` walks the path from the matched element upward, one crumb per
ancestor, with `*` matching exactly one element. There is deliberately no `**`: it would
require backtracking, and a query costing more than the current depth is the thing this API
exists to avoid. `next_tag(breadcrumbs: [...])` and `match_offset` are ported too.

---

## Deliberately not ported

Nothing here was dropped silently.

| Legacy | Why not |
|---|---|
| `esc_url()` on URI attributes in `set_attribute()` (`class-wp-html-tag-processor.php:4646`) | `esc_url()` and `wp_kses_uri_attributes()` live in the sanitizing pack; `topology_decision.md` option 3 forbids the dependency. **This is a behavioural divergence, not just an omission** — see below. |
| `set_modifiable_text()` for SCRIPT / STYLE / TEXTAREA / TITLE / RAWTEXT contents (`:4230`–`:4585`) | Requires `get_script_content_type()` and `escape_javascript_script_contents()` — ~500 lines of JavaScript/JSON-aware escaping serving no rule in this pack's set. Text nodes, HTML comments and processing instructions **are** supported; the other contexts return `false`, which is a documented legacy return value for content that cannot be safely represented. |
| `WP_HTML_Processor::normalize()`, `serialize()`, `serialize_token()`, `escape_text_for_serialization()` (`:1272`–`:1567`) | Re-serialisation, not parsing. No rule in the assigned set names it and nothing in this pack consumes it. |
| `_doing_it_wrong()` notices | `paradigm_decision.md` option 1: no hook system, and `_doing_it_wrong` is a hook (`doing_it_wrong_run`, `doing_it_wrong_trigger_error`). Invalid usage returns the same `false`/`nil` the legacy returns; only the notice is gone. |
| The Noah's Ark clause in the list of active formatting elements (`class-wp-html-active-formatting-elements.php:114`) | **The legacy does not implement it either** — it carries an explicit `@todo`. Implementing it here would be a behaviour change, not a port. |
| `has_element_in_select_scope()` (`class-wp-html-open-elements.php:483`) | Deprecated in 7.1.0; the legacy body is `_deprecated_function(); return false;`. Nothing calls it. |
| `WP_Token_Map`'s precomputed group/bucket layout (`class-wp-token-map.php`) | A PHP-specific memory optimisation. The *semantics* it provides — longest match wins, case-sensitive, semicolon significant — are what the parser depends on, and those are ported. All 2,231 entries were exported from the oracle with `WP_Token_Map::to_array()`, so the table itself is complete and verbatim; see below. |
| Serialization guards (`__wakeup` throwing `LogicException`) | Guards against PHP's `unserialize()`. Ruby's `Marshal` is not used anywhere in this pack. |
| Encodings other than UTF-8 | Same as the legacy: `create_fragment` / `create_full_parser` return `nil` for anything else. |

### Named character references: what is covered

The brief allowed "enough of the table to be correct on the common cases". That turned out
to be unnecessary: `WP_Token_Map::to_array()` on the oracle exports the whole set, so
`app/markup/named_character_references.rb` is **complete — all 2,231 entries**,
semicolon-terminated and legacy semicolon-less forms alike, values stored as raw UTF-8 byte
escapes. The HTML5 specification freezes this list, so it will never need regenerating.
`spec/decoder_spec.rb` decodes a systematic sample of the table (every 7th entry, ~320
references) in both contexts on both sides and compares.

What is ported from `WP_HTML_Decoder` in full: numeric references decimal and hex, leading
zeros, the digit-count caps, the Windows-1252 remap of the C1 range, U+FFFD substitution
for surrogates and out-of-range code points, the ambiguous-ampersand rule that makes
`&ampx` literal in an attribute but `&x` in a text node, `decode_text_node`,
`decode_attribute` and `attribute_starts_with`.

---

## Known divergences from PHP

Five, all deliberate, none silent.

1. **URI attributes are not URL-escaped.** `set_attribute('href', …)` runs the same
   character escaping as any other attribute instead of `esc_url()`. A value that
   `esc_url()` would reject (a `javascript:` URL, say) is written escaped-but-present. Any
   caller in the target that writes URLs through this API must sanitize first. Re-injecting
   `esc_url` through a callback would be a hook, which `paradigm_decision.md` option 1
   rules out, so this stays a divergence until the sanitizing capability is reachable some
   other way. Marked in the source at `tag_processor.rb#set_attribute`.

2. **Internal bookmarks are never released.** PHP's `WP_HTML_Token::__destruct` releases a
   token's bookmark when the token becomes unreachable; Ruby has no deterministic
   destruction. `MAX_BOOKMARKS` (10,000 for the tree processor) is preserved and enforced,
   so a document with more than ~10,000 tokens reports
   `get_last_error == "exceeded-max-bookmarks"` where PHP would keep going. The corpus
   documents are far below that; a full-length WordPress post is not. This is the one
   divergence that would bite in production and it is the first thing to fix if this pack
   is pointed at real content — refcounting a token across the two stacks, the event queue
   and `state.current_token` is the work involved.

3. **`Markup::Processor#seek` returns `false` for an unknown bookmark.** The legacy indexes
   `$this->bookmarks` directly and would emit a PHP warning. Returning `false` matches the
   Tag Processor's own contract.

4. **Public decoder methods return UTF-8-tagged strings.** `decode_text_node` and
   `decode_attribute` return `Encoding::UTF_8`; the internal `decode(context, text)`
   returns binary, because decoding happens mid-scan and the surrounding byte offsets still
   have to line up. PHP has no such distinction to preserve.

5. **Ruby predicate naming on methods no rule names.** `is_tag_closer()` → `tag_closer?`,
   `has_class()` → `has_class?`, `has_self_closing_flag()` → `has_self_closing_flag?`,
   `has_bookmark()` → `has_bookmark?`, `paused_at_incomplete_token()` →
   `paused_at_incomplete_token?`, `is_special()` → `special?`, `is_void()` → `void?`.
   Every method a rule names keeps its exact legacy name: `get_attribute_names_with_prefix`,
   `set_bookmark`, `seek`, `get_updated_html`, `get_breadcrumbs`, `matches_breadcrumbs`,
   `create_fragment`. Query hashes take symbol keys (`next_tag(tag_name: "DIV")`).

Everything else — every functional string, every error message, every constant value
(`STATE_MATCHED_TAG`, `COMMENT_AS_CDATA_LOOKALIKE`, `insertion-mode-in-body`, `unsupported`,
`no-quirks-mode`, …) — is preserved verbatim. No copy editing.

### Two findings about the legacy, not the port

- The `+IMAGE` bail (`Cannot process an IMAGE tag. (Don't ask.)`) is **unreachable**.
  `WP_HTML_Processor::get_tag()` rewrites `IMAGE` to `IMG` before the operation sigil is
  built, so the `case '+IMAGE'` arm never matches. The port reproduces this faithfully.
- The two META encoding bails are unreachable through `create_full_parser`, which sets
  `encoding_confidence` to `certain`, and through `create_fragment`, which sets it to
  `irrelevant`. Only the `tentative` default reaches them, and no public constructor
  leaves it there.

---

## PCRE vs Onigmo

The legacy `html-api` is almost regex-free by design — it scans with `strspn`, `strcspn`,
`strpos` and `substr` — so there was very little to translate. The complete inventory:

| Where | Pattern | Analysis |
|---|---|---|
| `utf8.rb` — `Utf8.noncharacters?` (from `wp-includes/utf8.php:158`) | `\xEF(?:\xB7[\x90-\xAF]\|\xBF[\xBE\xBF])\|(?:\xF0[\x9F\xAF\xBF]\|[\xF1-\xF3][\x8F\x9F\xAF\xBF]\|\xF4\x8F)\xBF[\xBE\xBF]` with `/x` | Ported verbatim. The legacy matches **raw UTF-8 byte sequences** rather than using PCRE's `/u` mode, precisely so malformed UTF-8 elsewhere in the subject cannot make the match fail — and that decision is what makes it portable. Three adaptations: (a) the `n` flag, so Onigmo treats the pattern as ASCII-8BIT and `\xEF` stays a byte rather than becoming an invalid character in a UTF-8 pattern; (b) matching against `String#b`, since an `/n` regex containing high bytes against a non-ASCII UTF-8 subject raises `Encoding::CompatibilityError`; (c) PHP used `~…~x` delimiters, so its free-spacing comment `# U+nFFFE/U+nFFFF` contained a `/` — in a Ruby `/…/x` literal that `/` terminates the regex even inside a comment, so the comment was reworded. |
| `tag_processor.rb` — `set_modifiable_text` comment guard | `/--!?>/n` | Identical semantics in PCRE and Onigmo. `/n` for byte matching. |
| `tag_processor.rb` — `escape_attribute_value` | `/[<>&"']/n` | Not a regex in the legacy — PHP uses `strtr()` with a five-entry map. `gsub` with a character class is the Ruby equivalent; `/n` keeps it byte-oriented so the subject's encoding is irrelevant. |
| `tag_processor.rb` — processing-instruction target start | `/[a-zA-Z_]/n` | Replaces a PHP range comparison on a single byte. |
| `open_elements.rb` — `current_node_is?("#tag")` | `/\A[A-Z]+\z/` | Replaces PHP's `ctype_upper()`. **The one real trap**: Ruby's `^`/`$` are *line* anchors, not string anchors, so `/^[A-Z]+$/` would happily match `"DIV\nx"` where `ctype_upper` returns false. `\A`/`\z` are required. `[[:upper:]]` was also avoided, since Onigmo's POSIX classes are Unicode-aware on a UTF-8 string while `ctype_upper` is ASCII-only. |

Two non-regex traps handled the same way: PHP 8's `strtolower`/`strtoupper` are ASCII-only,
while Ruby's `String#downcase`/`#upcase` are Unicode-aware on a UTF-8 string — the port
keeps those strings binary, where Ruby's case methods are ASCII-only by definition. And
PHP arrays are values while Ruby hashes are references, so the legacy's plain assignment
that snapshots `$this->attributes` before scanning a SCRIPT body had to become an explicit
`dup`; without it, the closer's bytes leak in as attributes. That one was found by the
differential suite, not by reading.

---

## Verification

```
# `.rspec` sets `--pattern "{spec,packs/*/spec}/**/*_spec.rb"`, which a path argument does
# not override, so pass the pattern to run this pack alone.
bundle exec rspec --pattern "packs/markup/spec/**/*_spec.rb"   # 190 examples, 0 failures
./bin/check_cycles                      # markup is a leaf, zero dependencies
bin/rails zeitwerk:check                # eager-loads cleanly under Rails
```

`spec/differential_spec.rb` runs the real `WP_HTML_Tag_Processor` and `WP_HTML_Processor`
under PHP 8.4 against the seeded oracle (`spec/support/dump_tokens.php`) and compares
eleven fields per input: the whole token stream (type, name, closer and self-closing flags,
comment type, namespace, modifiable text, full comment text, class list, `has_class`,
DOCTYPE details, every attribute name with its decoded value); the incomplete-input signal;
the document after a deterministic mutation program with a bookmark-and-seek; prefix
discovery at every tag; the fragment parser's token stream with full breadcrumbs and depth;
the whole-document parser's token stream; a bookmark round trip through both parsers; and
which inputs abort with which verbatim message.

The corpus (`spec/fixtures/corpus.json`, 103 inputs) includes `CORPUS_KSES`,
`CORPUS_ASTRAL`, `CORPUS_QUOTES` and `CORPUS_BACKSLASH` from the oracle's `corpus.php`,
plus unclosed tags, nested and misnested formatting, misnested tables, foster-parenting
triggers, truncated tags and comments, NULL bytes, funky comments, presumptuous tags,
CDATA lookalikes, processing instructions, SVG and MathML, quirks-mode DOCTYPEs, and 30
levels of nesting. `spec/fuzz_spec.rb` adds 150 randomly assembled documents from fixed
seeds; another ~5,100 were run offline across twelve seeds while porting, all matching.
