import { chromium } from "playwright";
const b = await chromium.launch(); const c = await b.newContext({ baseURL: "http://127.0.0.1:3100", viewport: { width: 1280, height: 900 } });
const p = await c.newPage();
await p.goto("/login"); await p.fill('input[name="log"]',"island_e2e"); await p.fill('input[name="pwd"]',"island-pw-1");
await p.check('input[name="testcookie"]').catch(()=>{}); await Promise.all([p.waitForLoadState("networkidle"), p.click('button[type=submit],input[type=submit]')]);
await p.goto("/console/posts/26/edit"); await p.waitForSelector("#editor-root .be-app",{timeout:15000});
await p.locator('.be-block[data-block="core/heading"]').first().click(); await p.waitForTimeout(400);
await p.screenshot({ path: "/tmp/island.png", fullPage: true });
console.log("SHOT_OK"); await b.close();
