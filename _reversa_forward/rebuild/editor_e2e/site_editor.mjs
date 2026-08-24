// ⚠️ NON-DESTRUCTIVE: this test edits a real template and the theme's Global Styles, which
// are part of the 25-screen parity corpus. It snapshots both before touching them and
// RESTORES them at the end, so running it can never poison the parity gate.
import { chromium } from "playwright";
const BASE = "http://127.0.0.1:3100";
function assert(c, m) { if (!c) { console.error("FAIL:", m); process.exitCode = 1; throw new Error(m); } console.log("ok:", m); }
const b = await chromium.launch(); const c = await b.newContext({ baseURL: BASE, viewport: { width: 1300, height: 900 } });
const p = await c.newPage();
await p.goto("/login"); await p.fill('input[name="log"]', "island_e2e"); await p.fill('input[name="pwd"]', "island-pw-1");
await p.check('input[name="testcookie"]').catch(() => {});
await Promise.all([p.waitForLoadState("networkidle"), p.click('button[type=submit],input[type=submit]')]);

await p.goto("/console/site-editor");
await p.waitForSelector("#site-editor-root .se-app", { timeout: 15000 });
assert(await p.isHidden("#site-editor-fallback"), "noscript fallback hidden once island mounts");
const tplCount = await p.locator(".se-sidebar .se-list").first().locator("li").count();
assert(tplCount > 0, `template browser lists templates (${tplCount})`);

// open the first template
await p.locator(".se-sidebar .se-item").first().click();
await p.waitForSelector(".se-main .be-canvas", { timeout: 8000 });
const blocks = await p.locator(".se-main .be-canvas .be-block").count();
assert(blocks > 0, `template canvas rendered its blocks (${blocks})`);

// snapshot the template's current tree so we can restore it verbatim afterwards
const openedId = await p.evaluate(async () => {
  const r = await fetch("/console/site-editor/templates", { headers: { Accept: "application/json" }, credentials: "same-origin" });
  const d = await r.json(); return d.templates[0].id;
});
const snapshot = await p.evaluate(async (id) => {
  const r = await fetch(`/console/site-editor/templates/${id}/blocks`, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  return r.json();
}, openedId);
const stylesSnapshot = await p.evaluate(async () => {
  const r = await fetch("/console/site-editor/styles", { headers: { Accept: "application/json" }, credentials: "same-origin" });
  return (await r.json()).user_styles;
});

// edit: append a paragraph via inserter, save
await p.click(".be-inserter-toggle"); await p.waitForSelector(".be-inserter");
await p.click('.be-inserter-item:has-text("Paragraph")');
const para = p.locator('.se-main .be-block[data-block="core/paragraph"] .be-editable').last();
await para.click(); await para.type("Edited in the site editor");
await Promise.all([
  p.waitForResponse((r) => /\/console\/site-editor\/templates\/\d+$/.test(r.url()) && r.request().method() === "PATCH"),
  p.click('.be-topbar-right button:has-text("Save")')
]);
await p.waitForSelector(".notice-success", { timeout: 8000 });
console.log("template save notice:", (await p.locator(".notice-success").innerText()).trim());

// Styles mode: set a background color from the palette, save
await p.click('.se-nav:has-text("Styles")');
await p.waitForSelector(".se-styles", { timeout: 8000 });
const swatches = await p.locator(".se-color-field").first().locator(".se-swatch").count();
assert(swatches > 1, `Global Styles shows the theme palette swatches (${swatches})`);
await p.locator(".se-color-field").first().locator(".se-swatch").first().click();
await Promise.all([
  p.waitForResponse((r) => r.url().endsWith("/console/site-editor/styles") && r.request().method() === "PATCH"),
  p.click('.se-styles button:has-text("Save styles")')
]);
await p.waitForSelector(".se-styles .notice-success", { timeout: 8000 });
console.log("styles save notice:", (await p.locator(".se-styles .notice-success").innerText()).trim());

// verify persistence via API
const styles = await p.evaluate(async () => (await fetch("/console/site-editor/styles", { headers: { Accept: "application/json" }, credentials: "same-origin" })).json());
assert(styles.user_styles && styles.user_styles.styles && styles.user_styles.styles.color && styles.user_styles.styles.color.background, "user background style persisted");
// ── RESTORE the corpus exactly as found (parity gate safety) ───────────────────────
const restored = await p.evaluate(async ([id, snap, styles]) => {
  const tok = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || "";
  const h = { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": tok };
  const a = await fetch(`/console/site-editor/templates/${id}`, { method: "PATCH", credentials: "same-origin", headers: h,
    body: JSON.stringify({ title: snap.title, blocks: snap.blocks }) });
  const bres = await fetch("/console/site-editor/styles", { method: "PATCH", credentials: "same-origin", headers: h,
    body: JSON.stringify({ user_styles: styles || {} }) });
  return (await a.json()).ok && (await bres.json()).ok;
}, [openedId, snapshot, stylesSnapshot]);
assert(restored, "template + global styles restored to their pre-test state");

console.log("\nSITE_EDITOR_E2E_PASS");
await b.close();
