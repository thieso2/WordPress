// Drives the Gutenberg WRITE paths that nothing has ever exercised through the actual editor:
// media upload, creating a term from the Post sidebar, autosave, revisions, and trash.
// Each endpoint has request specs, but every bug found in this project so far came from
// driving the real client, not from the specs.
//
// ⚠️ NON-DESTRUCTIVE. It works on a fixture post it creates and deletes, and it restores or
// removes everything else it makes. The corpus is live parity data.
import { chromium } from "playwright";

const BASE = "http://127.0.0.1:3100";
let pass = 0, fail = 0;
const ok  = (m) => { pass++; console.log("  ok:", m); };
const bad = (m, extra) => { fail++; console.log("  FAIL:", m, extra ? "\n        " + String(extra).slice(0, 300) : ""); };

const b = await chromium.launch();
const c = await b.newContext({ baseURL: BASE, viewport: { width: 1440, height: 1000 } });
const p = await c.newPage();
p.on("pageerror", (e) => console.log("  [pageerror]", String(e).split("\n")[0].slice(0, 140)));

await p.goto("/login");
await p.fill('input[name="log"]', "oracle_admin");
await p.fill('input[name="pwd"]', "oracle-admin-pw");
await p.check('input[name="testcookie"]').catch(() => {});
await Promise.all([p.waitForLoadState("networkidle"), p.click('button[type=submit],input[type=submit]')]);

// A helper that runs inside the page, so every call carries the session cookie + nonce.
const api = (path, options = {}) =>
  p.evaluate(async ([path, options]) => {
    const res = await fetch(path, {
      ...options,
      credentials: "same-origin",
      headers: { Accept: "application/json", "Content-Type": "application/json",
                 "X-WP-Nonce": (window.wpApiSettings || {}).nonce, ...(options.headers || {}) }
    });
    let body = null; try { body = await res.json(); } catch {}
    return { status: res.status, body };
  }, [path, options]);

// Land on an editor page first so window.wpApiSettings exists.
await p.goto("/console/posts", { waitUntil: "domcontentloaded" });
const href = await p.locator('a[href*="/console/posts/"][href$="/edit"]').first().getAttribute("href");
await p.goto(href, { waitUntil: "domcontentloaded" });
await p.waitForTimeout(9000);
await p.click('.components-modal__header button[aria-label="Close"]', { timeout: 4000 }).catch(() => {});

console.log("\n── 1. create a fixture post through the API (the editor's own create path) ──");
const created = await api("/wp-json/wp/v2/posts", { method: "POST",
  body: JSON.stringify({ title: "GB path fixture", content: "<!-- wp:paragraph --><p>seed</p><!-- /wp:paragraph -->", status: "draft" }) });
created.status === 201 ? ok(`created (201), id ${created.body?.id}`) : bad(`create returned ${created.status}`, JSON.stringify(created.body));
const postId = created.body?.id;

console.log("\n── 2. autosave ──");
if (postId) {
  const as = await api(`/wp-json/wp/v2/posts/${postId}/autosaves`, { method: "POST",
    body: JSON.stringify({ id: postId, title: "GB path fixture autosaved", content: "<!-- wp:paragraph --><p>autosaved</p><!-- /wp:paragraph -->" }) });
  [200, 201].includes(as.status) ? ok(`autosave accepted (${as.status})`) : bad(`autosave returned ${as.status}`, JSON.stringify(as.body));
  const list = await api(`/wp-json/wp/v2/posts/${postId}/autosaves`);
  list.status === 200 ? ok(`autosave list readable (${Array.isArray(list.body) ? list.body.length : "?"} entries)`) : bad(`autosave list ${list.status}`);
}

console.log("\n── 3. revisions ──");
if (postId) {
  await api(`/wp-json/wp/v2/posts/${postId}`, { method: "POST", body: JSON.stringify({ content: "<!-- wp:paragraph --><p>v2</p><!-- /wp:paragraph -->" }) });
  const revs = await api(`/wp-json/wp/v2/posts/${postId}/revisions`);
  revs.status === 200 ? ok(`revisions readable (${Array.isArray(revs.body) ? revs.body.length : "?"})`)
                      : bad(`revisions returned ${revs.status}`, JSON.stringify(revs.body));
}

console.log("\n── 4. create a term (what the Post sidebar's category box does) ──");
const term = await api("/wp-json/wp/v2/categories", { method: "POST", body: JSON.stringify({ name: "GB Path Category" }) });
term.status === 201 ? ok(`category created (201), id ${term.body?.id}`) : bad(`category create returned ${term.status}`, JSON.stringify(term.body));
const termId = term.body?.id;
if (postId && termId) {
  const assign = await api(`/wp-json/wp/v2/posts/${postId}`, { method: "POST", body: JSON.stringify({ categories: [termId] }) });
  assign.status === 200 ? ok("category assigned to the post") : bad(`assign returned ${assign.status}`);
  const check = await api(`/wp-json/wp/v2/posts/${postId}?context=edit`);
  (check.body?.categories || []).includes(termId)
    ? ok("assignment reads back")
    : bad("assignment did NOT read back", JSON.stringify(check.body?.categories));
}

console.log("\n── 5. media upload (the editor's media library path) ──");
const upload = await p.evaluate(async () => {
  // a 1x1 PNG, built in the page so no file system is involved
  const b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
  const bin = Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
  const res = await fetch("/wp-json/wp/v2/media", {
    method: "POST", credentials: "same-origin",
    headers: { "Content-Type": "image/png", "Content-Disposition": 'attachment; filename="gb-path-test.png"',
               "X-WP-Nonce": (window.wpApiSettings || {}).nonce, Accept: "application/json" },
    body: bin
  });
  let body = null; try { body = await res.json(); } catch {}
  return { status: res.status, body };
});
[200, 201].includes(upload.status) ? ok(`media uploaded (${upload.status}), id ${upload.body?.id}`)
                                   : bad(`media upload returned ${upload.status}`, JSON.stringify(upload.body));
const mediaId = upload.body?.id;

console.log("\n── 6. trash + restore ──");
if (postId) {
  const trashed = await api(`/wp-json/wp/v2/posts/${postId}`, { method: "DELETE" });
  trashed.status === 200 && trashed.body?.status === "trash"
    ? ok("post trashed (status 'trash', not deleted)")
    : bad(`trash returned ${trashed.status}`, JSON.stringify(trashed.body).slice(0, 160));
  const restored = await api(`/wp-json/wp/v2/posts/${postId}`, { method: "POST", body: JSON.stringify({ status: "draft" }) });
  restored.status === 200 && restored.body?.status === "draft" ? ok("post restored to draft") : bad(`restore returned ${restored.status}`);
}

console.log("\n── teardown ──");
if (postId)  { const r = await api(`/wp-json/wp/v2/posts/${postId}?force=true`,  { method: "DELETE" }); [200,410].includes(r.status) ? ok("fixture post removed") : bad(`post force-delete ${r.status}`); }
if (termId)  { const r = await api(`/wp-json/wp/v2/categories/${termId}?force=true`, { method: "DELETE" }); [200,410].includes(r.status) ? ok("fixture category removed") : bad(`category delete ${r.status}`); }
if (mediaId) { const r = await api(`/wp-json/wp/v2/media/${mediaId}?force=true`, { method: "DELETE" }); [200,410].includes(r.status) ? ok("fixture media removed") : bad(`media delete ${r.status}`); }

console.log(`\nRESULT: ${pass} ok, ${fail} failed`);
await b.close();
process.exit(fail ? 1 : 0);
