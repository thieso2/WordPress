import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL:"http://127.0.0.1:3100" });
const p = await c.newPage();
await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
await p.check('input[name="testcookie"]').catch(()=>{});
await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]);
await p.goto("/console/posts/1/edit", {waitUntil:'domcontentloaded'});
const nonce = await p.evaluate(()=> (window.wpApiSettings||{}).nonce);
const root  = await p.evaluate(()=> (window.wpApiSettings||{}).root);
console.log("wpApiSettings.root:", root, " nonce:", nonce ? nonce.slice(0,16)+"…" : null);
// with the nonce header
const withN = await p.evaluate(async (n) => {
  const r = await fetch("/wp-json/wp/v2/users/me", { headers: { "X-WP-Nonce": n, Accept:"application/json" }, credentials:"same-origin" });
  return { status: r.status, body: (await r.text()).slice(0,220) };
}, nonce);
console.log("\nWITH nonce  ->", withN.status, withN.body);
// without
const noN = await p.evaluate(async () => {
  const r = await fetch("/wp-json/wp/v2/users/me", { headers:{Accept:"application/json"}, credentials:"same-origin" });
  return { status: r.status, body: (await r.text()).slice(0,200) };
});
console.log("WITHOUT     ->", noN.status, noN.body);
await b.close();
