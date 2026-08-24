<?php
/**
 * The oracle corpus definition — the adversarial text the handoff demands.
 *
 * handoff.md § "The one thing that can invalidate everything":
 *   "Seed it properly: ... 4-byte UTF-8, quote- and backslash-heavy text.
 *    An oracle seeded with three posts proves very little."
 *
 * Every string here exists to break something specific:
 *  - 4-byte UTF-8 exercises utf8mb4 -> PostgreSQL text (RISK-006).
 *  - Backslashes exercise T-08: the seeding pipeline must NOT unslash. Adding an
 *    unslash pass would corrupt every legitimate backslash in the corpus.
 *  - Quotes exercise wptexturize (BR-FMT-04) and KSES attribute parsing.
 *  - The KSES payloads exercise BR-KSES-01/04/05/06/07 — the owner-override rules
 *    that must be ported character-for-character (RISK-005).
 */

/** 4-byte UTF-8: emoji, astral-plane math, CJK extension B, and a ZWJ sequence. */
const CORPUS_ASTRAL = "Emoji 😀🧬🚀 · Math 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𝕬𝖑𝖌𝖊𝖇𝖗𝖆 · CJK-Ext-B 𠜎𠜱𠝹 · ZWJ 👨‍👩‍👧‍👦 · Flag 🇯🇵";

/** Backslashes that must survive verbatim. T-08. */
const CORPUS_BACKSLASH = 'Windows path C:\\Users\\thies\\file.txt — regex \\d+\\s*\\\\ — literal \\n not a newline — LaTeX \\frac{1}{2} — escaped quote \\" and \\\'';

/** Quote-heavy text: straight, curly, prime, guillemet, CJK corner brackets. */
const CORPUS_QUOTES = 'He said "it\'s a test" -- she replied \'"nested"\' ... 5\'9" tall, 3" wide « French » 「日本語」 ‘curly’ “already curly”';

/** KSES adversarial input. BR-KSES-04/05/06/07: colon recognised four ways. */
const CORPUS_KSES = <<<'HTML'
<p>Safe paragraph with <strong>bold</strong> and <em>emphasis</em>.</p>
<script>alert('xss')</script>
<a href="javascript:alert(1)">plain colon</a>
<a href="javascript&#58;alert(2)">numeric entity colon</a>
<a href="javascript&#x3a;alert(3)">hex entity colon</a>
<a href="javascript&colon;alert(4)">named entity colon</a>
<a href="javascript&#58alert(5)">truncated colon entity</a>
<a href="feed:javascript:alert(6)">feed prefix, one level</a>
<a href="feed:feed:javascript:alert(7)">feed prefix, two levels</a>
<a href="JaVaScRiPt:alert(8)">mixed case scheme</a>
<a href="  javascript:alert(9)">leading whitespace scheme</a>
<a href="java\0script:alert(10)">null byte in scheme</a>
<img src="x" onerror="alert(11)" />
<div style="background:url(javascript:alert(12))">style payload</div>
<a href="https://example.com/ok" title="a &quot;quoted&quot; title">legitimate link</a>
<iframe src="https://evil.example"></iframe>
<p>Unclosed tag <b>bold forever
<table><tr><td>cell</td></tr></table>
HTML;

/** Serialized payloads: nested arrays, objects, floats, booleans, NULs. RISK-006. */
function corpus_serialized_array() {
    return array(
        'string'  => 'plain',
        'astral'  => CORPUS_ASTRAL,
        'slash'   => CORPUS_BACKSLASH,
        'int'     => 42,
        'float'   => 3.14159265358979,
        'bool_t'  => true,
        'bool_f'  => false,
        'null'    => null,
        'nested'  => array( 'a' => array( 'b' => array( 'c' => 'deep' ) ), 'list' => array( 1, 2, 3 ) ),
        'empty'   => array(),
        'numeric_keys' => array( 0 => 'zero', 5 => 'five', '10' => 'ten' ),
    );
}

/** Post-shaped fixtures. One per status, plus the awkward ones. */
function corpus_articles() {
    return array(
        array( 'title' => 'Published article with '.CORPUS_QUOTES, 'status' => 'publish' ),
        array( 'title' => 'Draft carrying the zero date', 'status' => 'draft' ),
        array( 'title' => 'Pending review', 'status' => 'pending' ),
        array( 'title' => 'Private article', 'status' => 'private' ),
        array( 'title' => 'Scheduled for the future', 'status' => 'future' ),
        array( 'title' => 'Trashed article', 'status' => 'trash' ),
        array( 'title' => 'Password protected', 'status' => 'publish', 'password' => 'secret' ),
        array( 'title' => CORPUS_ASTRAL, 'status' => 'publish' ),
        array( 'title' => 'Backslash title '.CORPUS_BACKSLASH, 'status' => 'publish' ),
        array( 'title' => 'KSES payload carrier', 'status' => 'publish', 'content' => CORPUS_KSES ),
        array( 'title' => 'Sticky front-page article', 'status' => 'publish', 'sticky' => true ),
        // BR-MIGRATE-035: 200 bytes INCLUDING any numeric suffix.
        array( 'title' => str_repeat( 'long-slug-segment-', 20 ), 'status' => 'publish' ),
        // Three colliding titles: exercises wp_unique_post_slug()'s suffix loop (F-POST-03).
        array( 'title' => 'Duplicate slug candidate', 'status' => 'publish' ),
        array( 'title' => 'Duplicate slug candidate', 'status' => 'publish' ),
        array( 'title' => 'Duplicate slug candidate', 'status' => 'publish' ),
    );
}
