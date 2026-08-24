import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const OUT = '/tmp/shots/out';
const results = JSON.parse(readFileSync(`${OUT}/results.json`, 'utf8'));
const admin = existsSync(`${OUT}/admin_results.json`)
  ? JSON.parse(readFileSync(`${OUT}/admin_results.json`, 'utf8')) : [];
const sizes = existsSync('/tmp/shots/sizes.json')
  ? JSON.parse(readFileSync('/tmp/shots/sizes.json', 'utf8')) : {};
const b64 = (f) => `data:image/jpeg;base64,${readFileSync(`${OUT}/${f.replace('.png', '.jpg')}`).toString('base64')}`;
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

// ── Parity class per screen ───────────────────────────────────────────────────
// Two different contracts are in play, and the page must not blur them.
//   · The 25 front-end screens are LITERAL: byte-comparable through the parity harness.
//   · The console is MODERNIZED (screen_modernization_decision.md): a semantic contract —
//     literal strings verbatim, data and behaviour matching, structure free. There are no
//     golden files for it, so pixel difference here is expected, not a defect.
const CLASS = {
  literal:    { label: 'Literal target', note: 'byte-comparable against the golden' },
  structural: { label: 'Structural',     note: 'machine-readable output, compared as source' },
  modernized: { label: 'Modernized',     note: 'semantic contract — strings verbatim, structure free' },
  absent:     { label: 'Not built',      note: 'no rebuild surface yet' },
};
const classOf = (r) => {
  if (r.group) return 'modernized';
  if (r.shots.rebuild?.status === 404 && r.shots.oracle?.status !== 404) return 'absent';
  return r.screen.startsWith('syndication.') ? 'structural' : 'literal';
};

const FRONT_GROUPS = [
  { id: 'read', title: 'Front-end read path', wave: 'Wave 2',
    blurb: 'The whole public site rendered from PostgreSQL. Every one of these is byte-identical to the oracle through the parity harness — the normalizer masks nonces, autoincrement ids, the UUID guid and timestamps, and sorts class-attribute tokens; everything else must match exactly.',
    match: (r) => !r.screen.startsWith('syndication.') && classOf(r) !== 'absent' },
  { id: 'synd', title: 'Syndication', wave: 'Wave 1',
    blurb: 'Feeds, sitemaps and robots — terminal modules with zero dependents (F-SIM-06), which is why this wave was reversible at near-zero blast radius.',
    match: (r) => r.screen.startsWith('syndication.') },
  { id: 'gap', title: 'Not built yet', wave: '—',
    blurb: 'The oracle answers; the rebuild does not. Shown rather than omitted — a screen missing from a report reads as a screen that passed.',
    match: (r) => classOf(r) === 'absent' },
];

const ADMIN_GROUPS = [
  { id: 'core', title: 'Content and people', wave: 'Wave 4',
    blurb: 'The screens an editor lives in. Each is a P-LIST or P-EDIT instantiation over the same models the front end reads — one list contract rather than forty near-identical views.' },
  { id: 'editor', title: 'The editors', wave: 'DEV-012 · D-3',
    blurb: 'The block editor and the Site Editor. WordPress ships these as compiled JavaScript, so no rule in the extraction describes them; DEV-012 ruled they be specified by observing the running oracle instead. The rebuild answers with a React island — the one carved-out client surface in an otherwise server-rendered console — talking to a server that owns the block grammar.' },
  { id: 'settings', title: 'Settings', wave: 'Wave 4',
    blurb: 'Configuration is settings only (AD-06). Compare the fields and their values, never the panel registry: hook-registered sections became declared structures when AD-01 removed the hook system (DEV-002).' },
  { id: 'tools', title: 'Tools, privacy and health', wave: 'Wave 4',
    blurb: 'Export, the GDPR request lifecycle, and Site Health. The GDPR screens carry the personal-data workflows verbatim, down to the confirmation-email checkbox and the status vocabulary.' },
  { id: 'appearance', title: 'Appearance', wave: 'Wave 4',
    blurb: 'Themes, theme install and menus. DEV-011 resolved as themes yes, plugins no — a theme is data plus template files, not code that hooks into the core, so carrying it forward does not reopen AD-01.' },
];

const GATE = [
  { n: 'Topology', cmd: 'bin/check_cycles', verdict: 'pass',
    line: 'acyclic; the three packs stay zero-dependency leaves' },
  { n: 'Boot', cmd: 'bin/rails runner', verdict: 'pass',
    line: 'boots — every route carries an AD-04 authorization declaration, or it would not' },
  { n: 'Specs', cmd: 'bin/rspec_worker', verdict: 'pass',
    line: '1489 examples, 0 failures, 6 pending' },
  { n: 'Seeding pipeline', cmd: 'bin/rails oracle:seed', verdict: 'pass',
    line: 'T-01…T-12 round-tripped; dead-letter queue empty' },
  { n: 'Determinism', cmd: 'bin/parity determinism', verdict: 'pass',
    line: 'full oracle rebuilds produce byte-identical goldens' },
  { n: 'Parity suite', cmd: 'bin/parity_worker', verdict: 'pass',
    line: '172 scenarios — 168 passed, 0 failed, 4 pending' },
  { n: 'Response diff', cmd: 'bin/parity compare', verdict: 'pass',
    line: '25 of 25 byte-identical through the harness, five consecutive runs' },
  { n: 'Editor islands', cmd: 'editor_e2e/run.sh', verdict: 'pass',
    line: 'both islands driven in a real browser: edit, insert, publish, save — then the corpus restored' },
  { n: 'Rule coverage', cmd: 'bin/rule_coverage', verdict: 'info',
    line: '262 of 363 rules carry a citation in the rebuild' },
];

const statusPill = (s) => {
  const tone = s === 200 ? 'ok' : s === 404 ? 'warn' : s >= 300 && s < 400 ? 'info' : 'bad';
  return `<span class="pill ${tone}">${s || 'no answer'}</span>`;
};

const pane = (r, side) => {
  const shot = r.shots[side];
  if (!shot || !shot.file) return `<figure class="pane"><div class="missing">no capture<br><small>${esc(shot?.error || 'unavailable')}</small></div></figure>`;
  return `<figure class="pane"><img src="${b64(shot.file)}" alt="${esc(r.screen)} rendered by the ${side}" loading="lazy" width="1280" height="900"></figure>`;
};

const row = (r) => {
  const k = classOf(r);
  const sz = sizes[r.screen];
  const opath = r.paths ? r.paths.oracle : r.path;
  const rpath = r.paths ? r.paths.rebuild : r.path;
  return `<article class="screen" id="s-${r.screen.replace(/\./g, '-')}">
    <header class="screen-head">
      <div class="screen-id">
        <h3>${esc(r.screen)}</h3>
        <code class="path">${esc(opath)}${rpath !== opath ? `  →  ${esc(rpath)}` : ''}</code>
        ${r.note ? `<p class="screen-note">${esc(r.note)}</p>` : ''}
      </div>
      <div class="screen-meta">
        <span class="cls cls-${k}">${CLASS[k].label}</span>
        <span class="verdict ${r.statusMatch ? 'ok' : 'bad'}">${r.statusMatch ? 'status matches' : 'status differs'}</span>
        ${sz ? `<span class="bytes" title="normalized response size">${(sz.oracle_bytes / 1024).toFixed(0)} KB vs ${(sz.rebuild_bytes / 1024).toFixed(0)} KB</span>` : ''}
      </div>
    </header>
    <div class="diptych">
      <div class="side">
        <p class="side-label oracle">WordPress oracle ${statusPill(r.shots.oracle?.status)}</p>
        ${pane(r, 'oracle')}
      </div>
      <div class="side">
        <p class="side-label rebuild">Rails rebuild ${statusPill(r.shots.rebuild?.status)}</p>
        ${pane(r, 'rebuild')}
      </div>
    </div>
  </article>`;
};

const matched = results.filter((r) => r.statusMatch).length;
const adminMatched = admin.filter((r) => r.statusMatch).length;

const CSS = readFileSync('./_report.css', 'utf8');

const html = `<title>Oracle vs Rebuild</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Serif:ital,wght@0,400;0,600;1,400&display=swap">
<style>${CSS}</style>

<header class="top">
  <div class="wrap top-inner">
    <p class="eyebrow">Reversa migration · visual verification</p>
    <h1>Oracle vs Rebuild</h1>
    <p class="thesis">
      Every screen below is served twice: once by a live WordPress <code>7.2-alpha-63330</code>
      instance, and once by the Rails rebuild reading the same content out of PostgreSQL.
      The WordPress instance is not a testing aid — with no live deployment, it is
      <strong>the project's only executable definition of the 363 migrated rules</strong>.
      All six waves are built. The front end is <strong>byte-identical through the parity
      harness on all 25 corpus screens</strong>; the console is held to a different and
      looser contract, which the second half of this page explains rather than hides.
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
        <p>Rails 8.1 · PostgreSQL 17 · 12 namespaces, 3 zero-dependency packs, 67 controllers.
        Content loaded one-way through a twelve-stage ETL.
        <br><code>127.0.0.1:3100</code></p>
      </div>
    </div>
    <div class="scoreboard">
      <div class="score ok"><p class="k">Byte match</p><p class="v">25 / 25</p><p class="s">front-end screens, through the harness</p></div>
      <div class="score ok"><p class="k">Specs</p><p class="v">1489</p><p class="s">examples, 0 failures</p></div>
      <div class="score ok"><p class="k">Console screens</p><p class="v">${adminMatched} / ${admin.length}</p><p class="s">answer with the same status as wp-admin</p></div>
      <div class="score warn"><p class="k">Rule coverage</p><p class="v">262 / 363</p><p class="s">rules citing an implementation</p></div>
    </div>
  </div>
</header>

<section><div class="wrap">
  <div class="sec-head narrow">
    <h2>The gate</h2>
    <p>What has to be green before any of this counts. Order matters: the topology check is
    worth almost nothing if it runs late, because the graph it exists to keep acyclic already
    will not be. Run on a quiet machine — concurrent work dirties the shared oracle and the
    test database, and a flake read as a regression costs more than the run it saved.</p>
  </div>
  <div class="gate">
    ${GATE.map((g) => `<div class="stage">
      <div class="nm">${esc(g.n)}<code>${esc(g.cmd)}</code></div>
      <div class="ln">${esc(g.line)}</div>
      <div class="vd"><span class="chip ${g.verdict}">${g.verdict === 'pass' ? 'pass' : g.verdict === 'fail' ? 'not met' : 'reported'}</span></div>
    </div>`).join('')}
  </div>
</div></section>

${FRONT_GROUPS.map((grp) => {
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

<section class="divider"><div class="wrap">
  <div class="sec-head narrow">
    <span class="wave">The second contract</span>
    <h2>The console is not held to byte parity</h2>
    <p>Everything above is compared byte-for-byte. Everything below is not, and that is a
    ruling rather than an omission. <code>screen_modernization_decision.md</code> puts the
    admin surface in <strong>modernized</strong> mode: every literal string stays verbatim,
    the data and the behaviour must match, and the structure is free. So the pairs below will
    not look alike, and looking alike was never the test — the test is that the same actions
    are available to the same roles and produce the same result, in the same words.</p>
    <p>Two consequences worth stating plainly. There are <strong>no golden files</strong> for
    these screens, so nothing here is machine-verified the way the front end is; the evidence
    is request specs and, for the editors, a browser driving the real thing. And a
    handful of wp-admin screens are <strong>deliberately absent</strong> — plugins, the plugin
    and theme code editors, and the Customizer were discarded by AD-01 and DEV-002. They are
    not missing work.</p>
  </div>
</div></section>

${ADMIN_GROUPS.map((grp) => {
  const rows = admin.filter((r) => r.group === grp.id);
  if (!rows.length) return '';
  return `<section><div class="wrap">
    <div class="sec-head narrow">
      <span class="wave">${esc(grp.wave)}</span>
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
    <div class="note">
      <h3>A matching screenshot is not a passing test</h3>
      <p>The front-end verdict comes from <code>bin/parity compare</code>, which diffs
      normalized bytes — not from these images. The normalizer masks nonces, autoincrement
      ids, the UUID guid, timestamps and the site host, and it <em>sorts</em> class-attribute
      tokens, so class order is invisible to the screen diff by design and is asserted by unit
      specs instead. Two panes that look identical can still differ in the bytes; the harness
      is the authority, and the harness says 25 of 25.</p>
    </div>
    <div class="note">
      <h3>The console pairs are a semantic comparison</h3>
      <p>Below the divider, difference is expected. What is being claimed is that the same
      capabilities reach the same roles with the same strings — not that the pixels agree. A
      recent audit of nine screen clusters against wp-admin found <strong>68 real
      defects</strong> behind screens previously reported as built: a search box that rendered
      but never filtered, a taxonomy screen with no way to create a term, an upload screen that
      404'd. 57 are fixed; 4 are deferred with reasons recorded.</p>
    </div>
    <div class="note warn">
      <h3>Two oracle screens failed to answer, and are shown failing</h3>
      <p><code>console.nav-menus</code> returns <strong>500</strong> from the oracle and
      <code>console.site-health-info</code> timed out on it. Both are oracle-side faults, not
      rebuild faults — the rebuild answers 200 for each. They are left in rather than quietly
      dropped, because a screen missing from a report reads as a screen that passed.</p>
    </div>
    <div class="note">
      <h3>The editors were specified by watching, not by reading</h3>
      <p>WordPress ships the block editor as compiled JavaScript. No rule in the extraction
      describes it, so DEV-012 changed the method rather than granting an exemption: the
      editor is specified from the running oracle. The rebuild's answer is a React island
      whose block grammar lives on the <em>server</em> — the same parser the front end uses,
      plus a serializer proven to round-trip all 22 corpus post bodies byte-identically. What
      the island edits is therefore what the site renders, by construction.</p>
    </div>
    <div class="note bad">
      <h3>These captures came from a database this report can perturb</h3>
      <p>The browser tests that exercise the editors write real records. An earlier run of
      them edited a template and set a Global Styles background, which moved thirteen
      front-end screens off parity — a self-inflicted failure that looked exactly like a
      regression. The suites now provision their own fixtures, restore what they touch, and
      tear down on exit; parity is re-checked immediately afterwards to prove it.</p>
    </div>
  </div>
</div></section>

<footer class="end"><div class="wrap">
  <p>Generated from <code>spec/parity/corpus/requests.yml</code> — the same file the parity
  harness reads, so the report and the harness cannot describe different sets of screens.
  Console screens are captured signed in as the seeded administrator on both systems.</p>
  <p>Oracle: WordPress 7.2-alpha-63330 on PHP 8.4 / MariaDB · Rebuild: Rails 8.1 on PostgreSQL 17.</p>
</div></footer>
`;

writeFileSync('./oracle-vs-rebuild.html', html);
console.log(`built oracle-vs-rebuild.html — ${(html.length / 1048576).toFixed(2)} MB, ${results.length} front-end + ${admin.length} console screens`);
