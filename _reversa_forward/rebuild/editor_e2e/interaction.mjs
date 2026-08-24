// Behavioural proof of the block editor React island (DEV-012, D-3). DEV-012 rules that
// editor parity is verified by OBSERVATION against a running instance, not by an extracted
// rule. This drives the real island in Chromium against the live rebuild: it signs in,
// waits for the island to mount (the noscript fallback hidden), edits the title and a
// paragraph, inserts a Heading through the inserter, publishes, and then reads the blocks
// API back to assert the tree the server serialized and stored.
import { chromium } from "playwright";

const BASE = process.env.BASE || "http://127.0.0.1:3100";
const POST = process.env.POST_ID;
const USER = "island_e2e";
const PW = "island-pw-1";

function assert(cond, msg) { if (!cond) { console.error("FAIL:", msg); process.exitCode = 1; throw new Error(msg); } else { console.log("ok:", msg); } }

const browser = await chromium.launch();
const ctx = await browser.newContext({ baseURL: BASE });
const page = await ctx.newPage();

// 1) Sign in over the real login surface (sets the session cookie).
await page.goto("/login");
await page.fill('input[name="log"]', USER);
await page.fill('input[name="pwd"]', PW);
await page.check('input[name="testcookie"]').catch(() => {});
await Promise.all([page.waitForLoadState("networkidle"), page.click('button[type="submit"], input[type="submit"]')]);

// 2) Open the editor and wait for the island to take over.
await page.goto(`/console/posts/${POST}/edit`);
await page.waitForSelector("#editor-root .be-app", { timeout: 15000 });
assert(await page.isHidden("#editor-fallback"), "noscript fallback is hidden once the island mounts");
assert(await page.locator(".be-title").inputValue() === "E2E seed title", "title loaded from the server");
assert((await page.locator('.be-editable').first().innerText()).includes("Original body"), "paragraph content loaded");

// 3) Edit the title and the paragraph text.
await page.fill(".be-title", "E2E edited title");
const para = page.locator('.be-block[data-block="core/paragraph"] .be-editable').first();
await para.click();
await para.selectText().catch(() => {});
await para.press("Control+A");
await para.type("Rewritten body");

// 4) Insert a Heading via the inserter palette.
await page.click(".be-inserter-toggle");
await page.waitForSelector(".be-inserter");
await page.click('.be-inserter-item:has-text("Heading")');
const heading = page.locator('.be-block[data-block="core/heading"] .be-editable').first();
await heading.click();
await heading.type("Inserted heading");

// 5) Publish.
await Promise.all([
  page.waitForResponse((r) => r.url().endsWith(`/console/posts/${POST}`) && r.request().method() === "PATCH"),
  page.click('button:has-text("Publish")')
]);
await page.waitForSelector(".notice-success", { timeout: 8000 });
console.log("publish notice:", (await page.locator(".notice-success").innerText()).trim());

// 6) Read the blocks API back through the same session and assert the stored tree.
const data = await page.evaluate(async (id) => {
  const res = await fetch(`/console/posts/${id}/blocks`, { headers: { Accept: "application/json" }, credentials: "same-origin" });
  return res.json();
}, POST);

assert(data.title === "E2E edited title", "title persisted");
assert(data.status === "published", "status is published");
const names = data.blocks.map((b) => b.name);
assert(names.includes("core/paragraph") && names.includes("core/heading"), `both blocks persisted (${names.join(", ")})`);
const paraNode = data.blocks.find((b) => b.name === "core/paragraph");
assert(/Rewritten body/.test(paraNode.innerHTML), "edited paragraph text serialized into stored markup");
const headNode = data.blocks.find((b) => b.name === "core/heading");
assert(/Inserted heading/.test(headNode.innerHTML), "inserted heading serialized into stored markup");
assert(Number(headNode.attrs.level) === 2, "inserted heading carries its level attribute");

console.log("\nISLAND_E2E_PASS");
await browser.close();
