import { chromium } from "playwright";
const b = await chromium.launch(); const c = await b.newContext({ baseURL:"http://127.0.0.1:3100" });
const p = await c.newPage();
await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
await p.check('input[name="testcookie"]').catch(()=>{});
await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]);
for (const u of ["/console/media/new","/console/tools/import"]) {
  const r = await p.goto(u, {waitUntil:'domcontentloaded'});
  console.log(u, "->", r.status());
}
await b.close();
