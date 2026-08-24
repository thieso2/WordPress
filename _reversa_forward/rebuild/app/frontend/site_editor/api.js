// The Site Editor island's server calls (DEV-012, D-3). Templates and Global Styles live
// under /console/site-editor/*. CSRF rides from the page meta, as Rails expects.
function csrf() { const el = document.querySelector('meta[name="csrf-token"]'); return el ? el.getAttribute("content") : ""; }
const j = (extra = {}) => ({ Accept: "application/json", "X-CSRF-Token": csrf(), ...extra });

export async function loadIndex() {
  const r = await fetch("/console/site-editor/templates", { headers: j(), credentials: "same-origin" });
  if (!r.ok) throw new Error(`templates ${r.status}`);
  return r.json();
}
export async function loadTemplate(id) {
  const r = await fetch(`/console/site-editor/templates/${id}/blocks`, { headers: j(), credentials: "same-origin" });
  if (!r.ok) throw new Error(`template ${r.status}`);
  return r.json();
}
export async function saveTemplate(id, { title, blocks }) {
  const r = await fetch(`/console/site-editor/templates/${id}`, {
    method: "PATCH", credentials: "same-origin",
    headers: j({ "Content-Type": "application/json" }), body: JSON.stringify({ title, blocks })
  });
  return r.json().catch(() => ({ ok: false, errors: [`save ${r.status}`] }));
}
export async function loadStyles() {
  const r = await fetch("/console/site-editor/styles", { headers: j(), credentials: "same-origin" });
  if (!r.ok) throw new Error(`styles ${r.status}`);
  return r.json();
}
export async function saveStyles(userStyles) {
  const r = await fetch("/console/site-editor/styles", {
    method: "PATCH", credentials: "same-origin",
    headers: j({ "Content-Type": "application/json" }), body: JSON.stringify({ user_styles: userStyles })
  });
  return r.json().catch(() => ({ ok: false, errors: [`save ${r.status}`] }));
}
