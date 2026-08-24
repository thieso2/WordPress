import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL: "http://127.0.0.1:3100", viewport: { width: 1280, height: 900 } });
const p = await c.newPage();
p.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0,200)));
await p.goto("/login");
await p.fill('input[name="log"]', "oracle_admin"); await p.fill('input[name="pwd"]', "oracle-admin-pw");
await p.check('input[name="testcookie"]').catch(()=>{});
await Promise.all([p.waitForLoadState("networkidle"), p.click('button[type=submit],input[type=submit]')]);
for (const [name, url] of [["dash","/console"],["posts","/console/posts"],["settings","/console/settings/general"]]) {
  const r = await p.goto(url, { waitUntil: "domcontentloaded" });
  console.log(name, r.status());
  await p.waitForTimeout(400);
  await p.screenshot({ path: `/tmp/nav_${name}.png` });
}
const items = await p.locator('.adminmenu > ul > li > a').allTextContents();
console.log("menu items:", JSON.stringify(items.map(t=>t.trim().replace(/\s+/g,' '))));
const subs = await p.locator('.adminmenu .sub a').allTextContents();
console.log("open submenu:", JSON.stringify(subs.map(t=>t.trim())));
await b.close();
