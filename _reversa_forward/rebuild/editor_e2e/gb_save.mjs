// ⚠️ NON-DESTRUCTIVE: this edits and SAVES a real corpus post, which is exactly what put 11
// front-end screens off parity the first time it ran. It snapshots the post's content before
// touching it and restores it through the same API afterwards.
import { chromium } from "playwright";
const b = await chromium.launch();
const c = await b.newContext({ baseURL:"http://127.0.0.1:3100", viewport:{width:1440,height:1000} });
const p = await c.newPage();
const writes = [];
p.on('response', r => { const m=r.request().method(); if (r.url().includes('/wp-json/') && m!=='GET' && m!=='OPTIONS')
  writes.push(`${r.status()} ${m} ${decodeURIComponent(r.url().replace(/^https?:\/\/[^/]+/,'').split('?')[0])}`); });
await p.goto("/login"); await p.fill('input[name="log"]','oracle_admin'); await p.fill('input[name="pwd"]','oracle-admin-pw');
await p.check('input[name="testcookie"]').catch(()=>{});
await Promise.all([p.waitForLoadState('networkidle'), p.click('button[type=submit],input[type=submit]')]);
await p.goto("/console/posts/1/edit", {waitUntil:'domcontentloaded'});
await p.waitForTimeout(12000);
// dismiss the welcome guide
try { await p.click('.components-modal__header button[aria-label="Close"]', {timeout:4000}); } catch {}
await p.waitForTimeout(1500);
// Modern Gutenberg renders the canvas inside an iframe; query that frame, not the page.
const canvas = p.frameLocator('iframe[name="editor-canvas"]');
const useFrame = await p.locator('iframe[name="editor-canvas"]').count() > 0;
const scope = useFrame ? canvas : p;
console.log("canvas is iframed:", useFrame);
const blocks = await scope.locator('.block-editor-block-list__block').count();
const names = await (useFrame
  ? p.frame({name:'editor-canvas'}).evaluate(()=>[...document.querySelectorAll('.block-editor-block-list__block[data-type]')].map(e=>e.dataset.type))
  : p.evaluate(()=>[...document.querySelectorAll('.block-editor-block-list__block[data-type]')].map(e=>e.dataset.type)));
console.log("blocks rendered:", blocks, JSON.stringify(names));
console.log("title:", (await scope.locator('.editor-post-title__input, .wp-block-post-title').first().textContent().catch(()=>null))?.trim());
// snapshot first, so the corpus can be put back exactly as found
const before = await p.evaluate(async () => (await (await fetch("/wp-json/wp/v2/posts/1?context=edit",{headers:{Accept:"application/json","X-WP-Nonce":(window.wpApiSettings||{}).nonce},credentials:"same-origin"})).json())?.content?.raw);

// EDIT: append text to the paragraph
const para = scope.locator('.block-editor-block-list__block[data-type="core/paragraph"]').first();
await para.click(); await p.waitForTimeout(400);
await p.keyboard.press('End');
await p.keyboard.type(' EDITED-BY-GUTENBERG');
await p.waitForTimeout(800);
// SAVE
await p.click('.editor-post-publish-button, button.editor-post-publish-button__button, .editor-header__settings button:has-text("Save")').catch(()=>{});
await p.waitForTimeout(6000);
console.log("\nwrite calls:", writes.length ? writes.join(" | ") : "(none)");
// verify persisted through OUR api
const check = await p.evaluate(async () => (await (await fetch("/wp-json/wp/v2/posts/1?context=edit",{headers:{Accept:"application/json","X-WP-Nonce":(window.wpApiSettings||{}).nonce},credentials:"same-origin"})).json()));
console.log("stored content now contains EDITED-BY-GUTENBERG:", JSON.stringify(check?.content?.raw||"").includes("EDITED-BY-GUTENBERG"));
console.log("stored raw (first 200):", (check?.content?.raw||"").slice(0,200));
await p.screenshot({path:"/tmp/gb_saved.png"});

// ── RESTORE (parity-gate safety) ───────────────────────────────────────────────────
const restored = await p.evaluate(async (raw) => {
  const r = await fetch("/wp-json/wp/v2/posts/1", {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type":"application/json", Accept:"application/json", "X-WP-Nonce":(window.wpApiSettings||{}).nonce },
    body: JSON.stringify({ content: raw })
  });
  return r.ok;
}, before);
console.log("corpus restored:", restored);
await b.close();
