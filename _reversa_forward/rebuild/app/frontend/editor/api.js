// The island's talk to the server half (DEV-012, D-3). GET .../blocks loads the parsed
// tree; PATCH .../:id saves a serialized tree through the same command path the noscript
// form uses. The CSRF token rides from the page's <meta name="csrf-token">, exactly as
// Rails' own fetch helpers expect.
function csrfToken() {
  const el = document.querySelector('meta[name="csrf-token"]');
  return el ? el.getAttribute("content") : "";
}

export async function loadBlocks(postId) {
  const res = await fetch(`/console/posts/${postId}/blocks`, {
    headers: { Accept: "application/json" },
    credentials: "same-origin"
  });
  if (!res.ok) throw new Error(`load failed: ${res.status}`);
  return res.json();
}

// command: "draft" | "publish" | "schedule" | "pending". Returns {ok, status, notice,
// view_url} or {ok:false, errors|lock_error}.
export async function save(postId, { command, title, excerpt, publishedAt, blocks }) {
  const res = await fetch(`/console/posts/${postId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    credentials: "same-origin",
    body: JSON.stringify({ command, title, excerpt, published_at: publishedAt, blocks })
  });
  const data = await res.json().catch(() => ({ ok: false, errors: [`save failed: ${res.status}`] }));
  return { httpStatus: res.status, ...data };
}

// The heartbeat lock tick (wp_refresh_post_lock) — keeps the editor's lock live and
// surfaces a takeover. Fire-and-forget; a takeover flips the UI to read-only.
export async function refreshLock(postId) {
  const res = await fetch(`/console/posts/${postId}/lock`, {
    method: "POST",
    headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    credentials: "same-origin"
  });
  return res.ok ? res.json() : null;
}

export async function autosave(postId, { title, excerpt, content }) {
  const res = await fetch(`/console/posts/${postId}/autosave`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken() },
    credentials: "same-origin",
    body: JSON.stringify({ title, excerpt, content })
  });
  return res.ok ? res.json() : null;
}
