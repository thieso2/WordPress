import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL: "http://127.0.0.1:3100", viewport: { width: 1280, height: 900 } });
const p = await c.newPage();
await p.goto("/login"); await p.fill('input[name="log"]',"oracle_admin"); await p.fill('input[name="pwd"]',"oracle-admin-pw");
await p.check('input[name="testcookie"]').catch(()=>{});
await Promise.all([p.waitForLoadState("networkidle"), p.click('button[type=submit],input[type=submit]')]);
for (const [name,url] of [["import","/console/tools/import"],["about","/console/about"],["freedoms","/console/freedoms"],["posts","/console/posts"]]) {
  const r = await p.goto(url, { waitUntil: "domcontentloaded" });
  const h1 = await p.locator("h1").first().textContent().catch(()=>null);
  console.log(`${name.padEnd(9)} ${r.status()}  h1="${(h1||'').trim().slice(0,40)}"`);
  await p.waitForTimeout(300);
  await p.screenshot({ path: `/tmp/new_${name}.png` });
}
// Tools menu should now list Import
await p.goto("/console/tools");
const subs = await p.locator('.adminmenu .sub a').allTextContents();
console.log("Tools submenu:", JSON.stringify(subs.map(t=>t.trim())));
await b.close();
