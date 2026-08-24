import { chromium } from "playwright";
const b = await chromium.launch();
async function tabs(base, isOracle, url) {
  const c = await b.newContext({ baseURL: base, viewport:{width:1280,height:900} });
  const p = await c.newPage();
  if (isOracle) { await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
    await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]); }
  else { await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
    await p.check('input[name="testcookie"]').catch(()=>{});
    await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]); }
  await p.goto(base+url, {waitUntil:'domcontentloaded'});
  const t = await p.locator('.subsubsub li').allTextContents();
  await c.close();
  return t.map(x=>x.replace(/\s+/g,' ').replace(/\s*\|\s*$/,'').trim());
}
const o = await tabs("http://127.0.0.1:8099", true, "/wp-admin/edit.php");
const r = await tabs("http://127.0.0.1:3100", false, "/console/posts");
console.log("oracle :", JSON.stringify(o));
console.log("rebuild:", JSON.stringify(r));
console.log(JSON.stringify(o)===JSON.stringify(r) ? "TABS MATCH" : "TABS DIFFER");
await b.close();
