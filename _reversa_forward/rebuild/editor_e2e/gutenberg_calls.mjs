// Records every REST call the REAL Gutenberg makes while opening and using the editor.
// This is the definitive contract a backend must satisfy to host it (DEV-012's method:
// specify by observing the running oracle).
import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL:"http://127.0.0.1:8099", viewport:{width:1440,height:1000} });
const p = await c.newPage();
const calls = new Map();
p.on('request', req => {
  const u = req.url();
  if (!u.includes('/wp-json/') && !u.includes('rest_route')) return;
  const path = decodeURIComponent(u.replace(/^https?:\/\/[^/]+/,'').split('?')[0]);
  const key = `${req.method()} ${path.replace(/\/\d+$/,'/:id')}`;
  calls.set(key, (calls.get(key)||0)+1);
});
await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]);
await p.goto("/wp-admin/post.php?post=1&action=edit", {waitUntil:'domcontentloaded'});
await p.waitForTimeout(9000);
// exercise it: type, open the inserter, open list view
await p.keyboard.press('Escape').catch(()=>{});
try {
  await p.click('.editor-post-title__input, [aria-label="Add title"]', {timeout:3000});
  await p.keyboard.type('x');
} catch {}
try { await p.click('button[aria-label*="Block Inserter"], .editor-document-tools__inserter-toggle', {timeout:3000}); await p.waitForTimeout(2500); } catch {}
await p.waitForTimeout(2000);
console.log("REST endpoints Gutenberg touched:\n");
[...calls.entries()].sort().forEach(([k,n]) => console.log(`  ${String(n).padStart(3)}x  ${k}`));
console.log(`\ntotal distinct endpoints: ${calls.size}`);
await b.close();
