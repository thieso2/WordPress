import { readFileSync, writeFileSync } from 'node:fs';
const OUT = '/tmp/shots/out';
const results = JSON.parse(readFileSync(`${OUT}/results.json`, 'utf8'));
const sizes   = JSON.parse(readFileSync('/tmp/shots/sizes.json', 'utf8'));
const stage = (n) => { try { return readFileSync(`/tmp/shots/stage_${n}.txt`, 'utf8').trim(); } catch { return ''; } };
const b64 = (f) => `data:image/jpeg;base64,${readFileSync(`${OUT}/${f.replace('.png', '.jpg')}`).toString('base64')}`;
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

// ── Parity class per screen ───────────────────────────────────────────────────
// screen_modernization_decision.md makes the 18 web.* screens LITERAL — byte-comparable
// against a golden file. Nothing here meets that yet, and the page says so rather than
// grading on a curve.
const CLASS = {
  literal:   { label: 'Literal target',   note: 'byte-comparable against the golden' },
  structural:{ label: 'Structural',       note: 'machine-readable output, compared as source' },
  absent:    { label: 'Not built',        note: 'no rebuild surface yet' },
};
const classOf = (r) => {
  if (r.shots.rebuild?.status === 404 && r.shots.oracle?.status !== 404) return 'absent';
  return r.screen.startsWith('syndication.') ? 'structural' : 'literal';
};

const GROUPS = [
  { id: 'read',  title: 'Front-end read path', wave: 'Wave 2',
    blurb: 'The whole public site rendered from PostgreSQL. In the strategy this is the largest diff-heavy wave and still carries no write risk.',
    match: (r) => !r.screen.startsWith('syndication.') && classOf(r) !== 'absent' },
  { id: 'synd',  title: 'Syndication', wave: 'Wave 1',
    blurb: 'Feeds, sitemaps and robots — terminal modules with zero dependents (F-SIM-06). No write path, which is why this wave is reversible at near-zero blast radius.',
    match: (r) => r.screen.startsWith('syndication.') },
  { id: 'gap',   title: 'Not built yet', wave: '—',
    blurb: 'The oracle answers; the rebuild does not. Shown rather than omitted — a screen missing from a report reads as a screen that passed.',
    match: (r) => classOf(r) === 'absent' },
];

const statusPill = (s) => {
  const tone = s === 200 ? 'ok' : s === 404 ? 'warn' : s >= 300 && s < 400 ? 'info' : 'bad';
  return `<span class="pill ${tone}">${s || '—'}</span>`;
};

const pane = (r, side) => {
  const shot = r.shots[side];
  if (!shot || !shot.file) return `<figure class="pane"><div class="missing">no capture<br><small>${esc(shot?.error || 'unavailable')}</small></div></figure>`;
  return `<figure class="pane">
    <img src="${b64(shot.file)}" alt="${esc(r.screen)} rendered by the ${side}" loading="lazy" width="1180" height="820">
  </figure>`;
};

const row = (r) => {
  const k = classOf(r);
  const sz = sizes[r.screen];
  return `<article class="screen" id="s-${r.screen.replace(/\./g, '-')}">
    <header class="screen-head">
      <div class="screen-id">
        <h3>${esc(r.screen)}</h3>
        <code class="path">${esc(r.path)}</code>
      </div>
      <div class="screen-meta">
        <span class="cls cls-${k}">${CLASS[k].label}</span>
        <span class="verdict ${r.statusMatch ? 'ok' : 'bad'}">${r.statusMatch ? 'status matches' : 'status differs'}</span>
        ${sz ? `<span class="bytes" title="normalized response size">${(sz.oracle_bytes / 1024).toFixed(0)} KB vs ${(sz.rebuild_bytes / 1024).toFixed(0)} KB</span>` : ''}
      </div>
    </header>
    <div class="diptych">
      <div class="side">
        <p class="side-label oracle">Oracle · WordPress 7.2-alpha-63330 ${statusPill(r.shots.oracle?.status)}</p>
        ${pane(r, 'oracle')}
      </div>
      <div class="side">
        <p class="side-label rebuild">Rebuild · Rails 8.1 + PostgreSQL ${statusPill(r.shots.rebuild?.status)}</p>
        ${pane(r, 'rebuild')}
      </div>
    </div>
  </article>`;
};

const GATE = [
  { n: 'Topology', cmd: 'bin/check_cycles', verdict: 'pass',
    line: 'acyclic; every pack a leaf',
    body: stage('topology').split('\n').filter((l) => /->|packs checked|OK —/.test(l)).join('\n') },
  { n: 'Specs', cmd: 'bundle exec rspec', verdict: 'pass',
    line: '476 examples, 0 failures', body: stage('specs') },
  { n: 'Seeding pipeline', cmd: 'bin/rails oracle:seed', verdict: 'pass',
    line: '13/13 validations, dead-letter empty', body: stage('seed') },
  { n: 'Golden capture', cmd: 'bin/parity capture', verdict: 'pass',
    line: '25 requests captured from the oracle', body: stage('capture') },
  { n: 'Determinism', cmd: 'bin/parity determinism', verdict: 'pass',
    line: 'full rebuilds are byte-identical', body: stage('determinism') },
  { n: 'Parity suite', cmd: 'bin/parity_worker', verdict: 'pass',
    line: '87 passed, 0 failed, 85 undefined', body: stage('parity') },
  { n: 'Rule coverage', cmd: 'bin/rule_coverage', verdict: 'info',
    line: '183 of 363 rules carry a citation', body: stage('rules') },
  { n: 'Response diff', cmd: 'bin/parity compare', verdict: 'fail',
    line: '0 of 25 byte-match — literal parity not met',
    body: stage('compare').split('\n').slice(-3).join('\n') },
];

const matched = results.filter((r) => r.statusMatch).length;

const html = `<title>Oracle vs Rebuild</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Serif:ital,wght@0,400;0,600;1,400&display=swap">
<style>
:root{
  --ground:#fafbfc; --panel:#ffffff; --sunk:#f2f4f7;
  --ink:#14171c; --muted:#5f6877; --faint:#8b94a3; --rule:#e0e4ea;
  --accent:#2f4bc8;
  --oracle:#26697f; --rebuild:#a9392f;
  --ok:#2c7355; --warn:#8a6512; --bad:#9c3a3a; --info:#2f4bc8;
  --ok-bg:#e8f2ed; --warn-bg:#f7f0e0; --bad-bg:#f8eaea; --info-bg:#e9edfb;
  --shadow:0 1px 2px rgba(20,23,28,.05),0 8px 24px -12px rgba(20,23,28,.18);
}
@media (prefers-color-scheme:dark){ :root:not([data-theme="light"]){
  --ground:#0f1114; --panel:#161a1f; --sunk:#1b2027;
  --ink:#e6e9ee; --muted:#98a2b1; --faint:#6c7686; --rule:#252b33;
  --accent:#8ba3ff;
  --oracle:#63b3cd; --rebuild:#e08476;
  --ok:#6fc39b; --warn:#d9ac5c; --bad:#e08585; --info:#8ba3ff;
  --ok-bg:#16261f; --warn-bg:#2a2318; --bad-bg:#2b1a1a; --info-bg:#1a1f33;
  --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 28px -14px rgba(0,0,0,.7);
}}
:root[data-theme="dark"]{
  --ground:#0f1114; --panel:#161a1f; --sunk:#1b2027;
  --ink:#e6e9ee; --muted:#98a2b1; --faint:#6c7686; --rule:#252b33;
  --accent:#8ba3ff;
  --oracle:#63b3cd; --rebuild:#e08476;
  --ok:#6fc39b; --warn:#d9ac5c; --bad:#e08585; --info:#8ba3ff;
  --ok-bg:#16261f; --warn-bg:#2a2318; --bad-bg:#2b1a1a; --info-bg:#1a1f33;
  --shadow:0 1px 2px rgba(0,0,0,.5),0 10px 28px -14px rgba(0,0,0,.7);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font:400 16px/1.6 "IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  -webkit-font-smoothing:antialiased}
.wrap{max-width:1240px;margin:0 auto;padding-inline:32px}
@media(max-width:600px){.wrap{padding-inline:20px}}
.narrow{max-width:660px}
code,.mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace}

/* ── masthead ─────────────────────────────────────────────── */
header.top{border-bottom:1px solid var(--rule);background:var(--panel)}
.top-inner{padding-block:56px 40px;display:grid;gap:28px}
.eyebrow{margin:0;font:600 11.5px/1 "IBM Plex Mono",monospace;letter-spacing:.16em;
  text-transform:uppercase;color:var(--faint)}
h1{margin:0;font:600 clamp(2rem,4.4vw,3.1rem)/1.06 "IBM Plex Serif",Georgia,serif;
  letter-spacing:-.02em;text-wrap:balance;max-width:16ch}
.thesis{margin:0;max-width:60ch;color:var(--muted);font:400 17.5px/1.66 "IBM Plex Serif",Georgia,serif}
.thesis strong{color:var(--ink);font-weight:600}

.systems{display:grid;grid-template-columns:1fr auto 1fr;gap:24px;align-items:stretch;
  margin-top:8px}
.sys{border:1px solid var(--rule);border-radius:10px;padding:18px 20px;background:var(--ground)}
.sys h2{margin:0 0 4px;font:600 14px/1.3 "IBM Plex Sans";letter-spacing:.01em}
.sys .who{font:600 11px/1 "IBM Plex Mono",monospace;letter-spacing:.12em;text-transform:uppercase;
  display:block;margin-bottom:9px}
.sys.o .who{color:var(--oracle)} .sys.r .who{color:var(--rebuild)}
.sys p{margin:0;color:var(--muted);font-size:13.5px;line-height:1.55}
.sys code{font-size:12px;color:var(--faint)}
.vs{align-self:center;font:600 11px/1 "IBM Plex Mono",monospace;color:var(--faint);
  letter-spacing:.14em}
@media(max-width:760px){.systems{grid-template-columns:1fr}.vs{display:none}}

/* ── headline numbers ─────────────────────────────────────── */
.scoreboard{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));
  gap:1px;background:var(--rule);border:1px solid var(--rule);border-radius:10px;
  overflow:hidden;margin-top:8px}
.score{background:var(--panel);padding:18px 20px}
.score .k{margin:0;font:600 10.5px/1 "IBM Plex Mono",monospace;letter-spacing:.13em;
  text-transform:uppercase;color:var(--faint)}
.score .v{margin:9px 0 3px;font:600 27px/1 "IBM Plex Sans";letter-spacing:-.02em;
  font-variant-numeric:tabular-nums}
.score .s{margin:0;font-size:12.5px;color:var(--muted);line-height:1.45}
.score.ok .v{color:var(--ok)} .score.bad .v{color:var(--bad)} .score.warn .v{color:var(--warn)}

/* ── sections ─────────────────────────────────────────────── */
section{padding-block:64px}
section + section{border-top:1px solid var(--rule)}
.sec-head{margin-bottom:36px}
.sec-head h2{margin:0 0 10px;font:600 26px/1.15 "IBM Plex Serif",Georgia,serif;letter-spacing:-.015em}
.sec-head .wave{display:inline-block;margin-bottom:12px;font:600 10.5px/1 "IBM Plex Mono",monospace;
  letter-spacing:.13em;text-transform:uppercase;color:var(--accent);
  background:var(--info-bg);padding:5px 9px;border-radius:4px}
.sec-head p{margin:0;max-width:64ch;color:var(--muted);font-size:15px}

/* ── gate ─────────────────────────────────────────────────── */
.gate{display:grid;gap:1px;background:var(--rule);border:1px solid var(--rule);border-radius:10px;overflow:hidden}
.stage{background:var(--panel);display:grid;grid-template-columns:minmax(150px,190px) 1fr minmax(96px,auto);
  gap:20px;padding:16px 20px;align-items:start}
.stage .nm{font-weight:600;font-size:14.5px}
.stage .nm code{display:block;margin-top:4px;font-size:11.5px;color:var(--faint);font-weight:400}
.stage .ln{color:var(--muted);font-size:13.5px;padding-top:1px}
.stage .ln pre{margin:8px 0 0;background:var(--sunk);border-radius:6px;padding:10px 12px;
  font-family:"IBM Plex Mono",monospace;font-size:11.5px;line-height:1.5;color:var(--muted);
  overflow-x:auto;white-space:pre;max-height:180px}
.stage .vd{justify-self:end}
@media(max-width:720px){.stage{grid-template-columns:1fr}.stage .vd{justify-self:start}}

.chip{display:inline-block;font:600 10.5px/1 "IBM Plex Mono",monospace;letter-spacing:.09em;
  text-transform:uppercase;padding:5px 9px;border-radius:4px;white-space:nowrap}
.chip.pass{background:var(--ok-bg);color:var(--ok)}
.chip.fail{background:var(--bad-bg);color:var(--bad)}
.chip.info{background:var(--info-bg);color:var(--info)}

/* ── screens ──────────────────────────────────────────────── */
.screen{margin-bottom:44px;background:var(--panel);border:1px solid var(--rule);
  border-radius:12px;overflow:hidden;box-shadow:var(--shadow)}
.screen-head{display:flex;justify-content:space-between;align-items:center;gap:20px;
  flex-wrap:wrap;padding:16px 20px;border-bottom:1px solid var(--rule);background:var(--panel)}
.screen-id h3{margin:0;font:600 15.5px/1.2 "IBM Plex Mono",monospace;letter-spacing:-.01em}
.screen-id .path{display:block;margin-top:5px;font-size:11.5px;color:var(--faint);
  word-break:break-all;max-width:66ch}
.screen-meta{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.cls{font:600 10.5px/1 "IBM Plex Mono",monospace;letter-spacing:.09em;text-transform:uppercase;
  padding:5px 9px;border-radius:4px;border:1px solid var(--rule);color:var(--muted)}
.cls-literal{border-color:var(--accent);color:var(--accent)}
.cls-absent{background:var(--bad-bg);color:var(--bad);border-color:transparent}
.verdict{font:600 10.5px/1 "IBM Plex Mono",monospace;letter-spacing:.09em;text-transform:uppercase;
  padding:5px 9px;border-radius:4px}
.verdict.ok{background:var(--ok-bg);color:var(--ok)}
.verdict.bad{background:var(--bad-bg);color:var(--bad)}
.bytes{font:400 11.5px/1 "IBM Plex Mono",monospace;color:var(--faint);
  font-variant-numeric:tabular-nums}

.diptych{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--rule)}
@media(max-width:880px){.diptych{grid-template-columns:1fr}}
.side{background:var(--panel);padding:14px 14px 16px;display:flex;flex-direction:column;gap:11px}
.side-label{margin:0;font:600 10.5px/1.4 "IBM Plex Mono",monospace;letter-spacing:.07em;
  text-transform:uppercase;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.side-label.oracle{color:var(--oracle)}
.side-label.rebuild{color:var(--rebuild)}
.pill{font:600 10px/1 "IBM Plex Mono",monospace;padding:4px 7px;border-radius:3px;letter-spacing:.05em}
.pill.ok{background:var(--ok-bg);color:var(--ok)}
.pill.warn{background:var(--warn-bg);color:var(--warn)}
.pill.info{background:var(--info-bg);color:var(--info)}
.pill.bad{background:var(--bad-bg);color:var(--bad)}
.pane{margin:0;border:1px solid var(--rule);border-radius:8px;overflow:hidden;background:var(--sunk);
  aspect-ratio:1180/820}
.pane img{display:block;width:100%;height:100%;object-fit:cover;object-position:top center}
.missing{height:100%;display:grid;place-content:center;text-align:center;color:var(--faint);
  font:600 11px/1.6 "IBM Plex Mono",monospace;letter-spacing:.08em;text-transform:uppercase}
.missing small{font-weight:400;letter-spacing:0;text-transform:none;font-size:10.5px}

/* ── notes ────────────────────────────────────────────────── */
.notes{display:grid;gap:20px;max-width:72ch}
.note{border-left:2px solid var(--rule);padding:2px 0 2px 20px}
.note.warn{border-left-color:var(--warn)}
.note.bad{border-left-color:var(--bad)}
.note h3{margin:0 0 7px;font:600 15px/1.35 "IBM Plex Sans"}
.note p{margin:0 0 8px;color:var(--muted);font-size:14.5px;line-height:1.62}
.note p:last-child{margin-bottom:0}
.note code{font-size:12.5px;background:var(--sunk);padding:1.5px 5px;border-radius:3px}

footer.end{border-top:1px solid var(--rule);padding:36px 0 60px;color:var(--faint);font-size:13px}
footer.end p{margin:0 0 5px;max-width:70ch}
a{color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:3px;border-radius:3px}
@media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
</style>

<header class="top">
  <div class="wrap top-inner">
    <p class="eyebrow">Reversa migration · visual verification</p>
    <h1>Oracle vs Rebuild</h1>
    <p class="thesis">
      Every screen below is served twice: once by a live WordPress <code>7.2-alpha-63330</code>
      instance, and once by the Rails rebuild reading the same content out of PostgreSQL.
      The WordPress instance is not a testing aid — with no live deployment, it is
      <strong>the project's only executable definition of the 363 migrated rules</strong>.
      Wave 0 is complete and its gate passes. The read path is new and
      <strong>does not yet match byte-for-byte</strong>, which is what the last column says.
    </p>
    <div class="systems">
      <div class="sys o">
        <span class="who">Left pane</span>
        <h2>The oracle</h2>
        <p>WordPress 7.2-alpha-63330 · PHP 8.4 · MariaDB. Seeded with all 16 post types,
        threaded comments, every role, zero-dates, 4-byte UTF-8 and backslash-heavy text.
        <br><code>127.0.0.1:8099</code></p>
      </div>
      <span class="vs">VS</span>
      <div class="sys r">
        <span class="who">Right pane</span>
        <h2>The rebuild</h2>
        <p>Rails 8.1 · PostgreSQL 17 · 26 tables, 12 namespaces, 3 zero-dependency packs.
        Content loaded one-way through Active Record.
        <br><code>127.0.0.1:3100</code></p>
      </div>
    </div>
    <div class="scoreboard">
      <div class="score ok"><p class="k">Wave 0 gate</p><p class="v">PASS</p><p class="s">7 of 8 checks green</p></div>
      <div class="score ok"><p class="k">Status match</p><p class="v">${matched} / ${results.length}</p><p class="s">same HTTP status, both systems</p></div>
      <div class="score bad"><p class="k">Byte match</p><p class="v">0 / 25</p><p class="s">literal parity not met yet</p></div>
      <div class="score warn"><p class="k">Rule coverage</p><p class="v">183 / 363</p><p class="s">rules citing an implementation</p></div>
    </div>
  </div>
</header>

<section><div class="wrap">
  <div class="sec-head narrow">
    <h2>The gate</h2>
    <p>What <code>bin/ci</code> checks before Wave 0 counts as done. Order matters: the
    topology check is worth almost nothing if it runs late, because the graph it exists to
    keep acyclic already will not be.</p>
  </div>
  <div class="gate">
    ${GATE.map((g) => `<div class="stage">
      <div class="nm">${esc(g.n)}<code>${esc(g.cmd)}</code></div>
      <div class="ln">${esc(g.line)}${g.body ? `<pre>${esc(g.body)}</pre>` : ''}</div>
      <div class="vd"><span class="chip ${g.verdict}">${g.verdict === 'pass' ? 'pass' : g.verdict === 'fail' ? 'not met' : 'reported'}</span></div>
    </div>`).join('')}
  </div>
</div></section>

${GROUPS.map((grp) => {
  const rows = results.filter(grp.match);
  if (!rows.length) return '';
  return `<section><div class="wrap">
    <div class="sec-head narrow">
      ${grp.wave !== '—' ? `<span class="wave">${esc(grp.wave)}</span>` : ''}
      <h2>${esc(grp.title)}</h2>
      <p>${grp.blurb}</p>
    </div>
    ${rows.map(row).join('')}
  </div></section>`;
}).join('')}

<section><div class="wrap">
  <div class="sec-head narrow"><h2>What these pictures do not show</h2>
  <p>Read this before drawing conclusions from the pairs above.</p></div>
  <div class="notes">
    <div class="note bad">
      <h3>No screen matches byte-for-byte, and eighteen of them are supposed to</h3>
      <p><code>screen_modernization_decision.md</code> classes the eighteen <code>web.*</code>
      screens as <strong>literal</strong> — byte-comparable against a golden file. The rebuild
      renders its own markup, so <code>bin/parity compare</code> reports 25 divergences out of 25.
      Matching HTTP status and comparable content is <em>not</em> parity; it is the point from
      which parity work starts.</p>
      <p>The two systems are also not the same distance apart everywhere: the oracle's front
      page normalizes to about 90 KB of block-theme output against roughly 3 KB from the
      rebuild. Closing that is the block renderer and the theme layer, neither of which exists.</p>
    </div>
    <div class="note warn">
      <h3>Two screens have no rebuild at all</h3>
      <p><code>web.attachment</code> and <code>web.embed</code> return 404 from the rebuild.
      They are shown rather than dropped, because a screen missing from a report reads as a
      screen that passed.</p>
      <p><code>web.attachment</code> carries a second finding: on a default WordPress 7.2
      install it does not render either. <code>wp_attachment_pages_enabled</code> is
      <code>'0'</code> and <code>canonical.php:553</code> 301-redirects every attachment URL to
      the file. It is listed among the eighteen literal screens, so the inventory and the
      running software disagree.</p>
    </div>
    <div class="note warn">
      <h3>The first diff caught a real bug, which is the argument for looking</h3>
      <p>The rebuild was rendering its own site title as
      <code>Reversa Oracle &amp;quot;7.2&amp;quot;</code> — entities visible on screen. WordPress
      runs <code>sanitize_option()</code> on every option write (BR-MIGRATE-014), so
      <code>blogname</code> is <em>already HTML-escaped at rest</em>; the oracle's own row
      literally contains <code>&amp;quot;</code>. WordPress prints it raw. Rails escaped it a
      second time.</p>
      <p>Fixed as a named exception for the two option names WordPress escapes on write, not
      a blanket <code>raw</code> — the practical stand-in for the <code>SafeHtml</code> value
      object until that type is wired through the surfaces. No test caught this; a picture
      did.</p>
    </div>
    <div class="note">
      <h3>The pictures are reproducible; that took work</h3>
      <p>Three separate sources of drift had to be removed before two captures of the same
      corpus agreed: <code>wp_install()</code> stamps its seed content with the real clock,
      every seeded post shared one date and WordPress orders archives by date with no
      tiebreak, and the embed screen carries a per-request token. <code>bin/parity
      determinism 5</code> now rebuilds the oracle from scratch five times and gets
      byte-identical captures.</p>
      <p>That is a precondition, not a nicety: the parity gate is defined as five consecutive
      clean runs, which is unmeetable if the corpus moves underneath it.</p>
    </div>
    <div class="note">
      <h3>What the left pane proves that the right one cannot</h3>
      <p>The oracle is seeded adversarially on purpose — all 16 post types, a three-deep
      category tree, four-level comment threads, drafts carrying
      <code>0000-00-00 00:00:00</code>, serialized metadata, emoji and Windows paths full of
      backslashes. An oracle seeded with three posts proves very little.</p>
      <p>That corpus round-trips into PostgreSQL through Active Record with an empty
      dead-letter queue and all 13 quality validations green, including the two that are
      easiest to get backwards: byte-identical text (which is what catches an accidental
      unslashing pass) and terms counted against <code>wp_term_taxonomy</code> rather than
      <code>wp_terms</code>.</p>
    </div>
  </div>
</div></section>

<footer class="end">
  <div class="wrap">
    <p>Captured with Playwright at 1180×820, both systems running locally, same corpus, same
    moment. Screens are ordered as they appear in
    <code>spec/parity/corpus/requests.yml</code> — the same file the parity harness reads, so
    the report and the harness cannot drift apart.</p>
    <p>Waves 3–5 are not started: there is no write path, no admin console and no editor.</p>
  </div>
</footer>`;

writeFileSync('/tmp/claude-2000/-workspace-WordPress/a9276f37-3abf-4b95-b39b-2ff9c8569c81/scratchpad/oracle-vs-rebuild.html', html);
console.log('bytes:', (html.length / 1048576).toFixed(2), 'MB');
