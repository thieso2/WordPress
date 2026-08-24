import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL:"http://127.0.0.1:8099", viewport:{width:1440,height:1000} });
const p = await c.newPage();
await p.goto("/wp-login.php"); await p.fill('#user_login','oracle_admin'); await p.fill('#user_pass','oracle-admin-pw');
await Promise.all([p.waitForLoadState('networkidle'), p.click('#wp-submit')]);
const html = await (await p.goto("/wp-admin/post.php?post=1&action=edit", {waitUntil:'domcontentloaded'})).text();
// createPreloadingMiddleware( {...} ) — the keys are the REST paths preloaded into the page
const m = html.match(/createPreloadingMiddleware\(\s*(\{[\s\S]*?\})\s*\)/);
if (m) {
  const keys = [...m[1].matchAll(/"([^"]*\/wp\/v2[^"]*|\/[^"]*)"\s*:/g)].map(x=>x[1]);
  console.log("PRELOADED REST paths (" + keys.length + "):");
  keys.forEach(k=>console.log("   " + decodeURIComponent(k)));
} else { console.log("no preloading middleware found"); }
// what the save (POST) does
await p.waitForTimeout(8000);
const posted = [];
p.on('request', r => { if (r.url().includes('/wp-json/') && r.method()!=='GET') posted.push(r.method()+' '+decodeURIComponent(r.url().replace(/^https?:\/\/[^/]+/,'').split('?')[0])); });
try { await p.keyboard.press('Escape'); await p.click('.editor-post-title__input',{timeout:3000}); await p.keyboard.type(' edit');
      await p.click('.editor-post-publish-button__button, button.editor-post-publish-button',{timeout:4000}); await p.waitForTimeout(5000); } catch(e){}
console.log("\nWRITE calls observed on save:", posted.length ? posted.join(", ") : "(none captured)");
await b.close();
