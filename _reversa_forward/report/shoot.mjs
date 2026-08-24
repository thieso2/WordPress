import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const ORACLE  = 'http://127.0.0.1:8099';
const REBUILD = 'http://127.0.0.1:3100';
const OUT = '/tmp/shots/out';
mkdirSync(OUT, { recursive: true });

// The corpus is the SAME file the parity harness uses — spec/parity/corpus/requests.yml.
// Reading it here rather than re-listing the screens keeps the visual report and the
// harness describing one set: add a screen to the corpus and it appears in both.
const yml = readFileSync('/workspace/WordPress/_reversa_forward/rebuild/spec/parity/corpus/requests.yml', 'utf8');
const requests = [];
let cur = null;
for (const line of yml.split('\n')) {
  const s = line.match(/^\s*- screen:\s*(\S+)/);
  if (s) { cur = { screen: s[1] }; requests.push(cur); continue; }
  if (!cur) continue;
  const p  = line.match(/^\s{4}path:\s*(.+)$/);          if (p)  cur.path = p[1].trim();
  const st = line.match(/^\s{4}expect_status:\s*(\d+)/);  if (st) cur.expect = Number(st[1]);
  const ct = line.match(/^\s{4}content_type:\s*(\S+)/);   if (ct) cur.contentType = ct[1];
}

const esc = (t) => t.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

// Chromium treats application/xml as a DOWNLOAD, so navigating to a feed or a sitemap
// hangs on a save dialog that never appears. Fetch the bytes and render them as source —
// which is what a reader comparing two feeds actually wants to look at anyway.
const sourceView = (path, body) => `<!doctype html><meta charset="utf-8"><style>
  body{margin:0;background:#fbfcfd;color:#16181d;font:12.5px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace}
  .bar{background:#eef1f5;border-bottom:1px solid #dfe3e8;padding:9px 14px;font:600 12px/1 ui-sans-serif,system-ui;color:#5b6472}
  pre{margin:0;padding:14px 16px;white-space:pre-wrap;word-break:break-word}
</style><div class="bar">${esc(path)}</div><pre>${esc(body.slice(0, 5200))}</pre>`;

const browser = await chromium.launch();
const results = [];

for (const req of requests) {
  const row = { ...req, shots: {} };
  for (const [side, base] of [['oracle', ORACLE], ['rebuild', REBUILD]]) {
    const ctx = await browser.newContext({
      viewport: { width: 1180, height: 820 },
      deviceScaleFactor: 1, colorScheme: 'light', reducedMotion: 'reduce',
    });
    const page = await ctx.newPage();
    const file = `${row.screen.replace(/\./g, '-')}--${side}.jpg`;
    try {
      let status;
      if (req.contentType === 'xml' || req.contentType === 'text') {
        const r = await ctx.request.get(base + req.path, { timeout: 15000 });
        status = r.status();
        await page.setContent(sourceView(req.path, await r.text()), { waitUntil: 'domcontentloaded' });
      } else {
        const resp = await page.goto(base + req.path, { waitUntil: 'domcontentloaded', timeout: 15000 });
        status = resp ? resp.status() : 0;
        await page.waitForTimeout(500);
      }
      // Freeze anything that renders motion so two captures of one state match.
      await page.addStyleTag({ content: '*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}' });
      await page.screenshot({ path: `${OUT}/${file}`, fullPage: false, type: 'jpeg', quality: 62 });
      row.shots[side] = { file, status, title: await page.title() };
    } catch (err) {
      row.shots[side] = { file: null, status: 0, error: String(err).split('\n')[0] };
    }
    await ctx.close();
  }
  const o = row.shots.oracle?.status, r = row.shots.rebuild?.status;
  row.statusMatch = o === r;
  console.log(`${row.statusMatch ? '  ' : '!!'} ${row.screen.padEnd(28)} oracle=${o} rebuild=${r}`);
  results.push(row);
}

await browser.close();
writeFileSync(`${OUT}/results.json`, JSON.stringify(results, null, 2));
console.log(`\n${results.length} screens captured, ${results.filter((r) => r.statusMatch).length} status-matched`);
