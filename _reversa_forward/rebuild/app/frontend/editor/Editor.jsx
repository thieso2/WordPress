import { useState, useEffect, useRef, useCallback } from "react";
import BlockView from "./BlockView.jsx";
import Inserter from "./Inserter.jsx";
import Inspector from "./Inspector.jsx";
import { decorateList, makeBlock, updateNode, removeNode, insertAfter, appendChild, moveNode, duplicateNode, findNode } from "./tree.js";
import { toPayload } from "./serialize.js";
import { blockType } from "./blockTypes.js";
import { loadBlocks, save as saveApi, refreshLock, autosave as autosaveApi } from "./api.js";

const DEFAULT_TEXT_HTML = { "core/paragraph": "", "core/heading": "", "core/list": "<li></li>", "core/code": "", "core/button": "" };

export default function Editor({ postId, isNew }) {
  const [blocks, setBlocks] = useState([]);
  const [title, setTitle] = useState("");
  const [excerpt, setExcerpt] = useState("");
  const [status, setStatus] = useState("");
  const [publishedAt, setPublishedAt] = useState("");
  const [selectedId, setSelectedId] = useState(null);
  const [inserterAfter, setInserterAfter] = useState(undefined); // undefined=closed, null=append end, id=after id
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState(null);
  const [errors, setErrors] = useState([]);
  const [autosaveNote, setAutosaveNote] = useState("");
  const [readOnly, setReadOnly] = useState(false);
  const [viewUrl, setViewUrl] = useState(null);

  // ── initial load ──────────────────────────────────────────────────────────────────
  useEffect(() => {
    let live = true;
    loadBlocks(postId).then((data) => {
      if (!live) return;
      setBlocks(decorateList(data.blocks));
      setTitle(data.title || "");
      setExcerpt(data.excerpt || "");
      setStatus(data.status || "");
      setPublishedAt(data.published_at || "");
      setViewUrl(data.status === "published" ? null : null);
      setLoading(false);
    }).catch((e) => { setErrors([String(e.message || e)]); setLoading(false); });
    return () => { live = false; };
  }, [postId]);

  // ── lock heartbeat (wp_refresh_post_lock): a takeover flips to read-only ────────────
  useEffect(() => {
    const t = setInterval(async () => {
      const r = await refreshLock(postId);
      if (r && r.lock_error) { setReadOnly(true); setNotice({ kind: "error", text: r.lock_error.text }); }
    }, 15000);
    return () => clearInterval(t);
  }, [postId]);

  // ── debounced autosave (the heartbeat's create-autosave tick) ───────────────────────
  const dirtyRef = useRef(false);
  useEffect(() => {
    const t = setInterval(async () => {
      if (!dirtyRef.current || readOnly) return;
      dirtyRef.current = false;
      const r = await autosaveApi(postId, { title, excerpt, blocks: toPayload(blocks) });
      if (r && r.message) setAutosaveNote(r.message);
    }, 20000);
    return () => clearInterval(t);
  }, [postId, title, excerpt, blocks, readOnly]);

  const touch = () => { dirtyRef.current = true; };

  // ── tree actions ────────────────────────────────────────────────────────────────────
  const onText = useCallback((id, html) => { setBlocks((b) => updateNode(b, id, { innerHTML: html })); touch(); }, []);
  const onAttrs = useCallback((id, attrs) => { setBlocks((b) => updateNode(b, id, { attrs })); touch(); }, []);
  const actions = {
    move: (id, d) => { setBlocks((b) => moveNode(b, id, d)); touch(); },
    duplicate: (id) => { setBlocks((b) => duplicateNode(b, id)); touch(); },
    remove: (id) => { setBlocks((b) => removeNode(b, id)); if (selectedId === id) setSelectedId(null); touch(); },
    openInserter: (id) => setInserterAfter(id)
  };

  const doInsert = (name) => {
    const html = DEFAULT_TEXT_HTML[name] !== undefined ? DEFAULT_TEXT_HTML[name] : "";
    const block = makeBlock(name, defaultAttrs(name), html);
    setBlocks((b) => {
      // If the anchor is a container, append inside it; else insert after it (or at end).
      const anchor = inserterAfter != null ? findNode(b, inserterAfter) : null;
      if (anchor && blockType(anchor.name).kind === "container") return appendChild(b, inserterAfter, block);
      return insertAfter(b, inserterAfter ?? null, block);
    });
    setSelectedId(block.clientId);
    setInserterAfter(undefined);
    touch();
  };

  // ── save (the control strip → Publishing::Post commands) ────────────────────────────
  const runSave = async (command) => {
    setSaving(true); setErrors([]); setNotice(null);
    const r = await saveApi(postId, { command, title, excerpt, publishedAt, blocks: toPayload(blocks) });
    setSaving(false);
    if (r.ok) {
      setStatus(r.status);
      setNotice({ kind: "success", text: r.notice });
      setViewUrl(r.view_url || null);
      dirtyRef.current = false;
    } else if (r.lock_error) {
      setReadOnly(true); setNotice({ kind: "error", text: r.lock_error.text });
    } else {
      setErrors(r.errors || ["Save failed."]);
    }
  };

  const selected = selectedId ? findNode(blocks, selectedId) : null;
  const renderChildren = (parent) => (
    <div className="be-children">
      {parent.innerBlocks.map((child) => (
        <BlockView key={child.clientId} node={child} depth={1} selectedId={selectedId}
          onSelect={setSelectedId} onText={onText} onAttrs={onAttrs} actions={actions}
          readOnly={readOnly} renderChildren={renderChildren} />
      ))}
      {!readOnly && (
        <button type="button" className="be-add-child" onClick={() => setInserterAfter(parent.innerBlocks.at(-1)?.clientId ?? parent.clientId)}>＋ Add block</button>
      )}
    </div>
  );

  if (loading) return <div className="be-loading">Loading the editor…</div>;

  const isPublished = status === "published";

  return (
    <div className={`be-app${readOnly ? " is-readonly" : ""}`} onMouseDown={() => setSelectedId(null)}>
      <header className="be-topbar" onMouseDown={(e) => e.stopPropagation()}>
        <div className="be-topbar-left">
          <button type="button" className="be-inserter-toggle" aria-label="Toggle block inserter"
            onClick={() => setInserterAfter(inserterAfter === undefined ? null : undefined)}>＋</button>
          <span className="be-status" aria-live="polite">
            {saving ? "Saving…" : autosaveNote || `Status: ${status}`}
          </span>
        </div>
        <div className="be-topbar-right">
          <button type="button" className="button" disabled={saving || readOnly} onClick={() => runSave("draft")}>
            {isPublished ? "Switch to draft" : "Save draft"}
          </button>
          {!isPublished && (
            <button type="button" className="button button-primary" disabled={saving || readOnly} onClick={() => runSave("publish")}>Publish</button>
          )}
          {isPublished && (
            <>
              <button type="button" className="button button-primary" disabled={saving || readOnly} onClick={() => runSave("draft")}>Update</button>
              {viewUrl && <a className="button button-link" href={viewUrl}>View Post</a>}
            </>
          )}
        </div>
      </header>

      {readOnly && <div className="notice notice-error be-lock-note">This block is now being edited by another user. Your changes are read-only.</div>}
      {notice && <div className={`notice notice-${notice.kind === "error" ? "error" : "success"}`}><p>{notice.text}</p></div>}
      {errors.length > 0 && <div className="notice notice-error"><ul>{errors.map((e, i) => <li key={i}>{e}</li>)}</ul></div>}

      <div className="be-body" onMouseDown={(e) => e.stopPropagation()}>
        <main className="be-canvas" aria-label="Editor canvas">
          <input className="be-title" placeholder="Add title" aria-label="Add title" value={title}
            disabled={readOnly} onChange={(e) => { setTitle(e.target.value); touch(); }} />

          {blocks.length === 0 && <p className="be-empty-hint">Type / to choose a block, or press ＋ to add one.</p>}
          {blocks.map((node) => (
            <BlockView key={node.clientId} node={node} depth={0} selectedId={selectedId}
              onSelect={setSelectedId} onText={onText} onAttrs={onAttrs} actions={actions}
              readOnly={readOnly} renderChildren={renderChildren} />
          ))}

          {!readOnly && (
            <button type="button" className="be-append" onClick={() => setInserterAfter(null)}>＋ Add block</button>
          )}

          <details className="be-excerpt">
            <summary>Excerpt</summary>
            <textarea rows={2} value={excerpt} disabled={readOnly} onChange={(e) => { setExcerpt(e.target.value); touch(); }} aria-label="Excerpt" />
          </details>

          {!isPublished && (
            <div className="be-schedule">
              <label htmlFor="be-published-at">Publish on (leave blank to publish immediately)</label>
              <input id="be-published-at" type="datetime-local" value={toLocalInput(publishedAt)} disabled={readOnly}
                onChange={(e) => setPublishedAt(e.target.value ? new Date(e.target.value).toISOString() : "")} />
              <button type="button" className="button" disabled={saving || readOnly} onClick={() => runSave("schedule")}>Schedule</button>
              <button type="button" className="button" disabled={saving || readOnly} onClick={() => runSave("pending")}>Pending Review</button>
            </div>
          )}
        </main>

        <Inspector node={selected} onAttrs={onAttrs} onClose={() => setSelectedId(null)} />
      </div>

      {inserterAfter !== undefined && (
        <div className="be-inserter-layer" onMouseDown={(e) => { if (e.target === e.currentTarget) setInserterAfter(undefined); }}>
          <Inserter onInsert={doInsert} onClose={() => setInserterAfter(undefined)} />
        </div>
      )}
    </div>
  );
}

function defaultAttrs(name) {
  if (name === "core/heading") return { level: 2 };
  return {};
}

function toLocalInput(iso) {
  if (!iso) return "";
  try { const d = new Date(iso); const p = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
  } catch { return ""; }
}
