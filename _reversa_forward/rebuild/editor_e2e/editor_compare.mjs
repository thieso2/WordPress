import { chromium } from "playwright";
const b = await chromium.launch();
async function go(base, isOracle) {
  const c = await b.newContext({ baseURL: base, viewport:{width:1440,height:1000}, deviceScaleFactor:1 });
  const p = await c.newPage();
  if (isOracle) { await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
    await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]); }
  else { await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
    await p.check('input[name="testcookie"]').catch(()=>{});
    await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]); }
  return p;
}
// find "Hello world!" on each side so both editors open the SAME content
const o = await go("http://127.0.0.1:8099", true);
await o.goto("http://127.0.0.1:8099/wp-admin/edit.php", {waitUntil:'domcontentloaded'});
const oHref = await o.locator('a.row-title', { hasText: 'Hello world' }).first().getAttribute('href');
const oId = oHref.match(/post=(\d+)/)[1];
await o.goto(`http://127.0.0.1:8099/wp-admin/post.php?post=${oId}&action=edit`, {waitUntil:'domcontentloaded'});
await o.waitForTimeout(6000);
await o.keyboard.press('Escape').catch(()=>{});
await o.waitForTimeout(1000);
await o.screenshot({ path: "/tmp/ed_oracle.png" });
console.log("oracle editor captured, post", oId);

const r = await go("http://127.0.0.1:3100", false);
await r.goto("http://127.0.0.1:3100/console/posts", {waitUntil:'domcontentloaded'});
const rHref = await r.locator('a.row-title', { hasText: 'Hello world' }).first().getAttribute('href');
const rId = rHref.match(/posts\/(\d+)\/edit/)[1];
await r.goto(`http://127.0.0.1:3100/console/posts/${rId}/edit`, {waitUntil:'domcontentloaded'});
await r.waitForSelector('#editor-root .be-app', {timeout:15000});
await r.waitForTimeout(1200);
await r.screenshot({ path: "/tmp/ed_rebuild.png" });
console.log("rebuild editor captured, post", rId);
await b.close();
