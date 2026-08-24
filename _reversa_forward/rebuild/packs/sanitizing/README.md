# `sanitizing` — kses allowlist filtering + escaping and text transforms

> Legacy: `wp-includes/kses.php` (3,158 lines) and `wp-includes/formatting.php` (6,405 lines).
> `topology_decision.md` merges `kses-security` and `formatting-and-sanitization` because they
> call each other mutually and cannot be separated. Together they form **one leaf** with nothing
> depending inward, so the mutual recursion stops being a cycle.

**Pure Ruby. Zero dependencies. Not one `require`, not even from the stdlib** — enforced by
`spec/sanitizing/pack_purity_spec.rb` and by `bin/check_cycles`.

```
bundle exec rspec --pattern "packs/sanitizing/spec/**/*_spec.rb"
143 examples, 0 failures
```

---

## 1. Result of the differential fuzzing (RISK-005)

`handoff.md`, "Six things that will bite if you skip them", item 3 requires proving PCRE/Onigmo
equivalence by differential fuzzing before trusting the port. `spec/differential/` does that
against the live PHP oracle at `_reversa_forward/oracle/wordpress/`.

| | |
|---|---|
| corpus entries | **5,497** |
| functions compared | **30** |
| byte-for-byte comparisons per run | **164,910** |
| **pass rate** | **100.00 %** — with one documented divergence class (D‑1, below) |
| undocumented divergences | **0** |
| wall time | ~14 s (one PHP process for the whole batch) |

The corpus is: the four `CORPUS_*` constants copied verbatim from
`oracle/wordpress/tools/corpus.php`; ~50 hand-written scheme obfuscations; ~70 tag and attribute
shapes; ~40 text shapes; those crossed into `href`/`src`/`style` positions; NUL/control-character/
truncation/invalid-UTF‑8 mutations of each seed; **4,000 seeded recombinations** of 80 syntax
fragments; and **1,200 seeded byte mutations** (flip, delete, insert-newline, truncate, duplicate)
of the real payloads. `SEED = 20260822`, so a failure is reproducible on any machine.

The fuzzer was not decoration. It found, and forced fixes for, nine real defects that the
hand-written cases missed — the last two by an independent adversarial review pass that fuzzed the
same 30 subjects against a *differently generated* corpus:

| Found by | Defect |
|---|---|
| corpus | `&quot;`/`&apos;` were not decoded — the entity table had been generated with `ENT_HTML5` alone, which does not decode quotes. `title="a &quot;q&quot; t"` came out double-encoded. |
| corpus | `esc_textarea` passed invalid UTF‑8 through; PHP's `htmlspecialchars()` without `ENT_SUBSTITUTE` returns `''`. |
| corpus | `remove_accents()` has a **second, ISO‑8859‑1 branch** for input that is not valid UTF‑8. It was missing. |
| corpus | `strip_tags()` is not `<[^>]*>`. It is a byte state machine that keeps `<` before whitespace, tracks quotes inside tags, drops comments, and **deletes NUL bytes** — which shifts `utf8_uri_encode()`'s 200-byte budget and changed slugs. |
| byte-mutation fuzz | `wp_spaces_regexp`'s `\xC2\xA0` made every texturize pattern a **fixed-encoding UTF‑8 regexp**, which raises `Encoding::CompatibilityError` on any binary subject. Every regexp in the pack now goes through `Bytes.regexp`. |
| recombination fuzz | `strip_tags()` keeps a `depth` counter for nested `<` inside a tag, and has a literal `!DOCTYPE` exception that returns from the markup-declaration state to the tag state. |
| recombination fuzz | `esc_url()`'s bracket branch depends on `parse_url()` **failing** (returning `false`) for a malformed authority such as `//host:notaport/`, in which case the whole URL gets percent-encoded. The first port had no failure path. |
| review fuzz | `php_stripslashes()` kept a **lone trailing backslash**; PHP's `php_stripslashes()` consumes the slash and then finds nothing to preserve, so it drops it. `esc_js("a\\")` was `a\\\\`, PHP says `a`. Fixed; `'trailing backslash \\'` added to the corpus. |
| review fuzz | `htmlspecialchars(..., double_encode: false)` used the **HTML 4.01** entity table for every doctype. PHP takes the "already a valid reference" set from the doctype flag, and `ENT_XML1` knows `&apos;` while HTML 4.01 does not — so `_wp_specialchars("&apos;", ENT_XML1)` was `&amp;apos;` against PHP's `&apos;`. Fixed with `Tables::XML1_ENTITY_NAMES`; `&apos;` added to the corpus. |

Two of those seven (`\xC2\xA0`, `strip_tags` NUL) are exactly the class of bug `handoff.md`
predicted: a pattern that behaves differently under Onigmo, and a byte-level PHP behaviour that
looks like an implementation detail until it changes a slug.

---

## 2. Rules implemented

### kses-security — BR-MIGRATE-298…307

| Rule | | Statement | Where |
|---|---|---|---|
| BR-MIGRATE-298 | BR-KSES-01 ⚠️ | KSES is an allowlist: anything not explicitly permitted is stripped, **implemented with regular expressions** | `Kses.wp_kses`, `wp_kses_split`, `wp_kses_split2`, `wp_kses_attr`, `wp_kses_hair`, `Css.safecss_filter_attr` |
| BR-MIGRATE-299 | BR-KSES-02 | 22 protocols allowed by default | `Tables::ALLOWED_PROTOCOLS` |
| BR-MIGRATE-300 | BR-KSES-03 | The protocol list is memoized and then frozen for the request | `Tables::ALLOWED_PROTOCOLS` is `frozen` — see §5 |
| BR-MIGRATE-301 | BR-KSES-04 ⚠️ | Scheme normalisation is exactly four steps: decode entities → strip whitespace → remove nulls → lowercase | `Kses.wp_kses_bad_protocol_once2` |
| BR-MIGRATE-302 | BR-KSES-05 ⚠️ | The colon is `:`, `&#58;`, `&#x3a;` **and** `&colon;` | `Kses::COLON_SPLIT` |
| BR-MIGRATE-303 | BR-KSES-06 ⚠️ | Truncated colon entities are repaired before splitting | `Kses::TRUNCATED_COLON` |
| BR-MIGRATE-304 | BR-KSES-07 ⚠️ | A `feed:` prefix is re-examined recursively, capped at two levels | `Kses.wp_kses_bad_protocol_once` |
| BR-MIGRATE-305 | BR-KSES-08 | A disallowed scheme yields an empty protocol string, leaving the URL schemeless | `Kses.wp_kses_bad_protocol_once2` |
| BR-MIGRATE-306 | BR-KSES-09 | Allowlists are context-specific: post, strip, data, entities, user_description, pre_user_description | `Kses.wp_kses_allowed_html` |
| BR-MIGRATE-307 | BR-KSES-10 | Entity normalization converts all `&` to `&amp;` then selectively restores valid references | `Kses.wp_kses_normalize_entities` |

### formatting — BR-MIGRATE-292…297

| Rule | | Statement | Where |
|---|---|---|---|
| BR-MIGRATE-292 | BR-FMT-01 | Escaping is applied at output and chosen by context; there is no universal escaper | `Formatting.esc_html/esc_attr/esc_textarea/esc_js/esc_url` |
| BR-MIGRATE-293 | BR-FMT-02 | `esc_url()` encodes `&` for markup; `esc_url_raw()` does not | `Formatting.esc_url`, `.esc_url_raw`, `.sanitize_url` |
| BR-MIGRATE-294 | BR-FMT-03 | `wpautop()`/`wptexturize()` run on output, not on stored content | `Formatting.wpautop`, `Texturize.wptexturize` — neither is called by `Kses` |
| BR-MIGRATE-295 | BR-FMT-04 ⚠️ | Both skip a maintained list of block-level and code tags, as regex transforms over rendered HTML | `Formatting::ALL_BLOCKS`, `Texturize::NO_TEXTURIZE_TAGS` |
| BR-MIGRATE-296 | BR-FMT-06 | `sanitize_title()` produces a URL-safe slug; `sanitize_key()` restricts to `[a-z0-9_-]` | `Formatting.sanitize_title`, `.sanitize_title_with_dashes`, `.sanitize_key` |
| BR-MIGRATE-297 | BR-FMT-07 | `sanitize_option()` dispatches per option name | `Options.sanitize_option` — **partial**, see §4 |

⚠️ = one of the nine owner-override rules. Question Q5 proposed migrating KSES off regular
expressions and rewriting `wpautop`/`wptexturize`; the owner **overruled it**. Finding `F-KSES-05`
(KSES parses HTML with regular expressions) is knowingly carried into the greenfield system, and
because there is no hook system (AD‑01) it is **permanent — there is no filter to correct it
later**. `spec/sanitizing/kses_spec.rb` asserts that the implementation is regex-based, so
replacing it with a real parser has to be a deliberate, visible act.

Plus the one guarantee the target **adds**: `SafeHtml` (parity_tests/05, `@invariant`
"Sanitized markup is a distinct type"). `architecture.md` §4 records the legacy's escaping as
"convention only, no type system" (F‑FMT‑02); here, rendering code that is handed a bare `String`
gets a `TypeError` instead of an XSS.

---

## 3. PCRE vs Onigmo — the analysis `handoff.md` demanded

Every pattern below was copied from the PHP source body-first, then each engine difference was
reasoned about explicitly. **No regex was tidied.**

### 3.1 `^` and `$` — the one most likely to ship a hole

PCRE's `$` without `/m` matches at end-of-subject **or immediately before a subject-final
newline**. Ruby's `$` is a **line** anchor and matches before *every* newline; `\z` is stricter
than PCRE and forbids the trailing newline. Neither is a drop-in.

`Bytes::PCRE_EOS = '(?=\n?\z)'` is the exact equivalent, and `Bytes::PCRE_BOS = '\A'` replaces `^`.

Concretely, if `wp_kses_split`'s token pattern kept Ruby's `$`, the input

```
<!--\nfoo-->
```

would tokenize as `<!--` + `$` at the end of line 1 — a *closed* comment token where PCRE sees an
unterminated one that the next alternative swallows whole. That is not a formatting difference;
it changes which bytes reach `wp_kses_split2` and therefore what the allowlist inspects.
Every anchor in this pack is translated:

| Site | Legacy | Here |
|---|---|---|
| `Kses::SPLIT_PATTERN` (`kses.php:1288`) | `(-->|$)`, `(>|$)` | `(-->|(?=\n?\z))`, `(>|(?=\n?\z))` |
| `Kses::BOGUS_COMMENT` (`kses.php:1428`) | `^(?:…)$` | `\A(?:…)(?=\n?\z)` |
| `Kses::ELEMENT_PATTERN` (`kses.php:1459`) | `^<\s*…>?$` | `\A<\s*…>?(?=\n?\z)` |
| `Kses::TRAILING_DASH` (`kses.php:2113`) | `/-$/` | `-(?=\n?\z)` |
| `Kses::XHTML_SLASH` (`kses.php:1528`) | `%\s*/\s*$%` | `\s*/\s*(?=\n?\z)` |
| `Kses::DATA_ATTRIBUTE` (`kses.php:1635`) | `/^data-[a-z0-9_-]+$/` | `\Adata-[a-z0-9_-]+(?=\n?\z)` |
| `Kses::NUMERIC_VALUE` (`kses.php:1906`) | `/^\s{0,6}[0-9]{1,6}\s{0,6}$/` | `\A…(?=\n?\z)` |
| `Kses::HTML_ERROR` (`kses.php:2083`) | `/^(…|$)…/` | `\A(…|(?=\n?\z))…` |
| `Css::URL_PIECES` (`kses.php:2977`) | `/^url\(…\)$/` | `\Aurl\(…\)(?=\n?\z)` |
| `Css::CUSTOM_PROPERTY` (`kses.php:2919`) | `/^--[…]+$/` | `\A--[…]+(?=\n?\z)` |
| `Texturize::DASH_PATTERNS` (`formatting.php:200-204`) | `(?<=^\|…)--(?=$\|…)` | `(?<=\A\|…)--(?=(?=\n?\z)\|…)` |
| `Formatting` `wpautop` tail (`formatting.php:589`) | `\|\n</p>$\|` | `\n</p>(?=\n?\z)` |

Note that `\Z` needed **no** translation: PCRE's `\Z` and Ruby's `\Z` mean the same thing, and
`wptexturize`'s quote patterns use `\Z` rather than `$`. Translating it anyway would have been a
change of meaning, so it was left alone.

### 3.2 Conditional groups — a genuine capability gap

PCRE supports both `(?(1)yes|no)` (numbered) and `(?(?=…)yes|no)` (assertion). **Onigmo supports
only the numbered form**; the assertion form raises `RegexpError: invalid conditional pattern`.
Three legacy patterns use the assertion form:

| Legacy | Rewrite here | Why it is equivalent |
|---|---|---|
| `get_html_split_regex()` `(?(?=!-)$comments\|$cdata)` (`formatting.php:653`) | `(?:(?=!-)COMMENT\|(?!!-)CDATA)` | `(?(?=X)A\|B)` ≡ `(?:(?=X)A\|(?!X)B)`. The branches are mutually exclusive on every input, which is exactly what the conditional made them. |
| `_get_wptexturize_split_regex()` `(?(?=!--)$comment\|[^>]*>?)` (`formatting.php:702`) | same shape | idem |
| `wptexturize`'s times pattern `(?(?<=0)[\d.,]+\|[\d.,]*)` (`formatting.php:290`) | `(?:(?<=0)[\d.,]+\|(?<!0)[\d.,]*)` | idem, with a lookbehind condition |

`esc_js`'s `&#(x)?0*(?(1)27|39);?` (`formatting.php:4728`) is a **numbered** conditional, so it is
ported **character-for-character**. All four are covered by the differential harness.

### 3.3 Character classes

Onigmo implements character-class set operations, so a bare `[` **inside** a class starts a nested
class; PCRE treats it as a literal. Two patterns needed the `[` escaped — and nothing else
changed:

* `(?<=\A|[([{"\-]|&lt;|SPACES)'` → `(?<=\A|[(\[{"\-]|&lt;|SPACES)'`
* `(?<=\A|[([{\-]|&lt;|SPACES)"` → `(?<=\A|[(\[{\-]|&lt;|SPACES)"`

Left uncorrected, Ruby raises `premature end of char-class` at load — a loud failure rather than a
silent bypass, but a failure nonetheless.

### 3.4 Modifiers

| PCRE | Ruby | Used at |
|---|---|---|
| `/x` | `Regexp::EXTENDED` | `Kses::SPLIT_PATTERN` (`kses.php:1288`) |
| `/i` | `Regexp::IGNORECASE` | `TRUNCATED_COLON`, `COLON_SPLIT`, `ESC_JS_QUOTE`, `esc_url`'s filter |
| `/s` | **`/m`** — not Ruby's `/s`, which does not exist | `wpautop`'s `<(script\|style\|svg\|math).*?</\1>` (`formatting.php:576`) |
| `/u` | not used — see §3.6 | — |
| `/m` | `Regexp::MULTILINE` — a *different* meaning from PCRE's `/m` | not used |

### 3.5 Possessive quantifiers and atomic groups

`get_html_split_regex()` uses `[^\-]*+`, `)*+` and `[^\]]*+`. Onigmo has possessive quantifiers
and they mean the same thing — no backtracking into the group — so they are **kept verbatim**.
The one place where the engines genuinely differ is `Css::CSS_FUNCTIONS` (`kses.php:3013`), which
uses PCRE's **recursive subpattern** `(?1)`, spelled `\g<1>` in Onigmo. Both recurse into group 1,
but PCRE has a backtrack/recursion limit and Onigmo does not: on a pathological nested-parenthesis
value PHP's `preg_replace()` returns `null` and the legacy `continue`s (dropping the declaration),
whereas Ruby keeps matching and the declaration may survive. This is recorded as **divergence D‑2**
below — it is a *liveness* difference, not an allowlist difference, and it fails **open** for CSS
only, never for a URL scheme.

### 3.6 Capture-group semantics and byte-vs-character matching

* **Non-participating groups.** `preg_replace_callback` gives `''`, Ruby gives `nil`. Every use of
  a possibly-absent group in this pack goes through `.to_s` — see `Kses.wp_kses_split2`, where
  `matches[1]` (the closing slash) is absent for opening tags.
* **`preg_split` capture semantics.** Ruby's `String#split` *includes* capture groups in the
  output. `Kses::COLON_SPLIT` therefore wraps the legacy's `:|&#0*58;|&#x0*3a;|&colon;` in a
  **non-capturing** group. Same language, same split points, no injected fields.
* **Bytes.** None of the ported patterns carries `/u`, so in PHP every one of them runs over
  *bytes*. Ruby regexps run over characters and raise `ArgumentError` the moment the subject is
  invalid in its declared encoding — which is exactly the input KSES exists for. The whole pack
  therefore works in `ASCII-8BIT` (`Sanitizing::Bytes`) and re-tags UTF‑8 on the way out. This
  reproduces PCRE's byte semantics including `\s`, `[a-z]` and `/i` being ASCII-only, and it makes
  malformed input inert rather than fatal (`Kses.wp_kses_post("bad \xC3 byte")` returns a string;
  it does not 500).
* **Fixed-encoding regexps.** A Ruby regexp whose *source* is a UTF‑8 string containing a `\xNN`
  escape above `0x7F` becomes a fixed-encoding UTF‑8 regexp and raises
  `Encoding::CompatibilityError` against a binary subject. `wp_spaces_regexp()`
  (`formatting.php:5960`) contains precisely that — `\xC2\xA0` — and it is interpolated into eight
  `wptexturize` patterns. `Bytes.regexp` forces every source to `ASCII-8BIT`. This was found by
  the fuzzer, not by inspection.

---

## 4. Not ported, and why

Nothing was silently omitted. Each of these is a deliberate decision with its reason.

1. **The hook system, in every form.** `paradigm_decision.md` option 1 / AD‑01. `pre_kses`,
   `wp_kses_allowed_html`, `wp_kses_uri_attributes`, `safe_style_css`,
   `safecss_filter_attr_allow_css`, `clean_url`, `esc_html`, `attribute_escape`, `js_escape`,
   `esc_textarea`, `sanitize_key`, `sanitize_title`, `run_wptexturize`, `no_texturize_tags`,
   `no_texturize_shortcodes`, `wp_spaces_regexp`, `sanitize_option_{$option}` and
   `$wp_cockneyreplace` have **no analogue**. What the unfiltered legacy produces is what this
   pack produces, permanently.
   *One deliberate exception, applied consistently:* where **WordPress core itself** registers the
   default listener in `wp-includes/default-filters.php`, that is core behaviour rather than
   third-party extension, and it is inlined as a fixed pipeline step. That covers
   `wp_pre_kses_less_than` (`default-filters.php:307`, inlined into `Kses.wp_kses_hook`) and
   `sanitize_title_with_dashes` (`default-filters.php:309`, inlined into `Formatting.sanitize_title`
   — without which BR‑FMT‑06 would not hold at all).
2. **`wp_pre_kses_block_attributes`** (`default-filters.php:308`). It calls
   `filter_block_content()`, i.e. the block parser, which is not in this pack and cannot be
   reached from it without a dependency. See divergence **D‑1**.
3. **`_wp_kses_allow_note_mention_span`** (`kses.php:1157`). A core default filter, but it only
   fires for the `pre_comment_content` context, which is not one of the six contexts BR‑KSES‑09
   enumerates. Its companion `_wp_kses_sanitize_note_mention_classes` needs `WP_HTML_Tag_Processor`
   (the `markup` pack) and `wp_slash`/`wp_unslash`, both out of scope.
4. **`value_callback` attribute checks** (`kses.php:1954`). The only core use is
   `_wp_kses_allow_pdf_objects()` on `<object data>`, which calls `wp_upload_dir()` — site state a
   zero-dependency leaf cannot see. `Kses.wp_kses_check_attr_val` therefore returns **false** for
   `value_callback`, i.e. `<object>` loses its `data`/`type` attributes and, because both are
   `required`, the whole tag is stripped to `<object>`. **Failing closed** was the deliberate
   choice. The callback needs to be reinjected by the caller when `wp_upload_dir()`'s equivalent
   exists; until then this is stricter than the legacy, never looser.
5. **The shortcode stack in `wptexturize`** (`formatting.php:230`). There is no shortcode registry
   in this pack, so `found_shortcodes` is permanently false and `no_texturize_shortcodes`
   (`[code]`) never engages. Inputs containing registered shortcode tags will texturize where the
   legacy would have skipped them. This is a scope boundary, not an oversight; it is listed here
   rather than papered over.
6. **Localization.** `wptexturize` reads its quote characters and its cockney list through `_x()`.
   Wave 0 is single-locale (en_US) so the English values are inlined as constants. A locale with
   different quote conventions would need them back.
7. **Locale-specific `remove_accents` branches** (`formatting.php:1960-1992`): the `de*`,
   `da_DK`, `ca`, `sr_RS` and `bs_BA` overrides need `get_locale()`. The base UTF‑8 table and the
   ISO‑8859‑1 fallback branch are both ported.
8. **`sanitize_option()` is partial by construction.** The legacy switch mixes pure string work
   with `$wpdb->strip_invalid_text_for_column()`, `get_option()`, `get_role()`,
   `get_available_languages()`, `is_email()` and PHP's timezone database. Fifteen branches are
   ported in full; the five that need site state (`admin_email`, `new_admin_email`, `WPLANG`,
   `timezone_string`, `default_role`) return an `Options::Deferred` naming the option and the
   reason, so the caller resolves them **explicitly** instead of the pack faking a value.
   The `$wpdb->strip_invalid_text_for_column()` calls are dropped throughout: they exist to
   survive MySQL's `utf8` vs `utf8mb4` truncation, and PostgreSQL `text` has no such failure mode
   (RISK‑006, `data_migration_plan.md`).
9. **`_wp_specialchars`'s `'single'`/`'double'` back-compat quote styles** (`formatting.php:1004`).
   Deprecated spellings that no core caller uses. `ENT_NOQUOTES`, `ENT_COMPAT`, `ENT_QUOTES` and
   `ENT_XML1` are all ported.
10. **`esc_xml`** (`formatting.php:4831`). Its CDATA-aware pattern is only reachable from the
    feed/sitemap subsystems, which are not in Wave 0. `_wp_specialchars(..., :ent_xml1)` — the
    part that does the escaping — **is** ported, so adding `esc_xml` later is a wrapper.
11. **`WP_HTML_Tag_Processor` itself.** `wp_kses_hair()` (`kses.php:1708`) builds `"<wp {$attr}>"`
    and reads the attributes back through the HTML API, which lives in the `markup` pack.
    `topology_decision.md` option 3 forbids that dependency, so
    `Sanitizing::AttributeParser` reimplements exactly the subset KSES exercises:
    `parse_next_attribute()` (`class-wp-html-tag-processor.php:2213`) plus the incomplete-input
    rule at `:1016` — including the consequence that a tag which does not close before the end of
    the document loses **every** attribute, and that a repeated attribute keeps only its first
    declaration. Verified byte-for-byte by the harness.
12. **The full HTML5 named character reference table** (2,231 names). `Sanitizing::HtmlDecoder`
    carries only the 253 names in `$allowedentitynames` plus the 5 XML ones. This is sound
    *within* `wp_kses()`: `wp_kses_normalize_entities()` runs first and turns every `&` into
    `&amp;`, restoring only numeric references and names from that list, so nothing else can
    reach the decoder. Numeric references are ported in full, including the Windows‑1252 C1
    remapping and the surrogate/out-of-range → U+FFFD rules. The **legacy no-semicolon forms**
    (`&copy` without `;`) are not decoded; they are unreachable through `wp_kses()` for the same
    reason. Calling `HtmlDecoder.decode_attribute` on un-normalized text is outside its contract.

---

## 5. Known divergences from PHP

Two, both understood, both narrow. `spec/differential/known_divergences.rb` encodes **D‑1** as a
predicate tight enough that any *other* difference still fails the build. **D‑2** has not been
observed on any corpus entry.

**D‑1 — the block-attribute pre-filter rewrites comment tokens.**
`wp_pre_kses_block_attributes` (`default-filters.php:308`) runs `filter_block_content()` before
kses sees the content, and the block parser rewrites HTML comments because `<!-- wp:… -->` *is*
the block delimiter syntax. Not porting it (item 2 above) means the port differs on inputs whose
**comment tokens** the block parser would rewrite, and only there. Observed instance:
`wp_kses_post("<!------>")` returns `""` in PHP and `"<!---->"` here. Nothing outside a comment
token differs — the accepting predicate asserts exactly that, by stripping comment tokens from
both outputs and requiring equality. **Security impact: none** — the divergence preserves a
comment that PHP deletes; comments are inert, and their contents are still recursively
kses-filtered.

**D‑2 — PCRE's backtrack limit in `safecss_filter_attr`.**
See §3.5. On a CSS value with pathologically nested parentheses PHP's `preg_replace()` hits
`pcre.backtrack_limit`, returns `null`, and the legacy drops the declaration; Onigmo has no such
limit and completes the match, so the declaration may be kept. This affects only which
*declarations* survive inside `style=""`, never which *URL schemes* do — `url()` values still go
through `wp_kses_bad_protocol` before this point. It fails open for CSS and closed for schemes.
No corpus entry triggers it; it is recorded because the mechanism is real, not because it was
observed.

**Not a divergence, but worth stating: BR‑KSES‑03 changes shape.** The legacy memoizes the
protocol list in a static and lets a filter change it *until `wp_loaded`*, freezing it for the
rest of the request. With no hook system the "filterable before `wp_loaded`" half has no meaning,
so the list is simply a frozen constant. The observable behaviour — one immutable list for the
whole request — is identical, and stricter.

---

## 6. Slashing (RISK-008, implication 6) — read before using this pack

`wp_magic_quotes()` slashed every superglobal at request time, so **all** legacy input arrived
slashed and `wp_kses()`'s docblock ("expects unslashed data") describes a caller contract that the
request lifecycle had already broken in the other direction. **Rails params are never slashed.**

Consequences, applied throughout:

* **This pack receives raw, unslashed strings and adds no unslash pass.** A backslash a caller
  sends is a backslash. `Kses.wp_kses_post('C:\Users\thies')` returns `C:\Users\thies`.
* `wp_filter_kses`/`wp_filter_post_kses`/`wp_filter_nohtml_kses` in the legacy are
  `addslashes(wp_kses(stripslashes($data), …))`. Only the middle step is meaningful here, so
  `Kses.wp_filter_nohtml_kses` is `wp_kses(data, 'strip')` and the slash/unslash bookends are gone.
* **`wp_kses_stripslashes()` is kept anyway, and it is not an unslash pass.** It changes `\"` to
  `"` and nothing else — a leftover of `preg_replace(//e)` (`kses.php:2036`). It runs inside
  `wp_kses_split2()` on every token in the legacy whether the input was slashed or not, so
  removing it would be a genuine behavioural change. Ported as-is, and pinned by a spec.
* `sanitize_option`'s `blog_charset` and `gmt_offset` branches carry legacy comments reading
  "Strips slashes"; that was a side effect of their character filters on slashed input. The
  filters are ported; the comment's premise is gone.

---

## 7. Layout

```
packs/sanitizing/
  package.yml                     zero declared dependencies
  app/sanitizing/
    bytes.rb                      the byte discipline + Bytes.regexp + PCRE_EOS
    tables.rb                     $allowedposttags, $allowedtags, entity names, protocols,
                                  safe_style_css, the HTML 4.01 table (mechanically extracted
                                  from the running oracle, not retyped)
    accents.rb                    remove_accents()'s 311-entry table, likewise extracted
    html_decoder.rb               character references, attribute context
    attribute_parser.rb           the HTML API subset wp_kses_hair() needs
    kses.rb                       BR-MIGRATE-298…307
    css.rb                        safecss_filter_attr()
    formatting.rb                 BR-MIGRATE-292…296
    texturize.rb                  wptexturize() + primes + pushpop
    options.rb                    BR-MIGRATE-297 (partial — §4.8)
    safe_html.rb                  the invariant the target adds
  spec/
    pack_helper.rb                loads the pack with no Rails and no stdlib requires
    sanitizing/*_spec.rb          107 examples, one describe block per rule id
    differential/
      corpus.rb                   5,490 entries: corpus.php + hand-written + seeded fuzz
      oracle.rb                   batches the whole corpus through ONE php process
      php/oracle.php              the oracle side
      known_divergences.rb        D-1, as a predicate
      differential_spec.rb        fails on any difference, printing both outputs
```

Every public method cites its rule id and the legacy `file:line` it came from.
