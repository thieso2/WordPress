// Captures the SAME screen from both systems for side-by-side skin comparison.
import { chromium } from "playwright";
const b = await chromium.launch();
async function sess(base, isOracle) {
  const c = await b.newContext({ baseURL: base, viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
  const p = await c.newPage();
  if (isOracle) {
    await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
    await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]);
  } else {
    await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
    await p.check('input[name="testcookie"]').catch(()=>{});
    await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]);
  }
  return p;
}
const o = await sess("http://127.0.0.1:8099", true);
const r = await sess("http://127.0.0.1:3100", false);
const PAIRS = [["posts","/wp-admin/edit.php","/console/posts"],["settings","/wp-admin/options-general.php","/console/settings/general"]];
for (const [name, op, rp] of PAIRS) {
  await o.goto("http://127.0.0.1:8099"+op, {waitUntil:'domcontentloaded'}); await o.waitForTimeout(600);
  await o.screenshot({ path:`/tmp/skin_${name}_oracle.png` });
  await r.goto("http://127.0.0.1:3100"+rp, {waitUntil:'domcontentloaded'}); await r.waitForTimeout(600);
  await r.screenshot({ path:`/tmp/skin_${name}_rebuild.png` });
  console.log("captured", name);
}
await b.close();
