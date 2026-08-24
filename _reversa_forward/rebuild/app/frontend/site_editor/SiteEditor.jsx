import { useState, useEffect, useCallback } from "react";
import BlockView from "../editor/BlockView.jsx";
import Inserter from "../editor/Inserter.jsx";
import Inspector from "../editor/Inspector.jsx";
import { decorateList, makeBlock, updateNode, removeNode, insertAfter, appendChild, moveNode, duplicateNode, findNode } from "../editor/tree.js";
import { toPayload } from "../editor/serialize.js";
import { blockType } from "../editor/blockTypes.js";
import GlobalStylesPanel from "./GlobalStylesPanel.jsx";
import { loadIndex, loadTemplate, saveTemplate, loadStyles, saveStyles } from "./api.js";

// The Site Editor (wp-admin/site-editor.php) as a React island: a template/part browser, a
// template block canvas that reuses the post editor's block components verbatim (a template
// IS a document of block markup), and a Global Styles panel over the theme.json cascade.
export default function SiteEditor() {
  const [mode, setMode] = useState("templates"); // templates | styles
  const [index, setIndex] = useState({ templates: [], parts: [], active_theme: "" });
  const [openId, setOpenId] = useState(null);
  const [doc, setDoc] = useState(null); // { id, title, blocks(decorated) }
  const [selectedId, setSelectedId] = useState(null);
  const [inserterAfter, setInserterAfter] = useState(undefined);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState(null);
  const [styles, setStyles] = useState(null); // { user_styles, settings }
  const [stylesNotice, setStylesNotice] = useState(null);

  useEffect(() => { loadIndex().then(setIndex).catch((e) => setNotice({ kind: "error", text: String(e.message || e) })); }, []);

  const open = async (id) => {
    setNotice(null);
    const data = await loadTemplate(id);
    setDoc({ id: data.id, title: data.title, slug: data.slug, area: data.area, kind: data.kind, blocks: decorateList(data.blocks) });
    setOpenId(id); setSelectedId(null); setMode("templates");
  };

  const enterStyles = async () => {
    setMode("styles");
    if (!styles) { try { setStyles(await loadStyles()); } catch (e) { setStylesNotice({ kind: "error", text: String(e.message || e) }); } }
  };

  // ── canvas actions (shared shape with the post editor) ───────────────────────────
  const setBlocks = (fn) => setDoc((d) => ({ ...d, blocks: fn(d.blocks) }));
  const onText = useCallback((id, html) => setBlocks((b) => updateNode(b, id, { innerHTML: html })), []);
  const onAttrs = useCallback((id, attrs) => setBlocks((b) => updateNode(b, id, { attrs })), []);
  const actions = {
    move: (id, d) => setBlocks((b) => moveNode(b, id, d)),
    duplicate: (id) => setBlocks((b) => duplicateNode(b, id)),
    remove: (id) => { setBlocks((b) => removeNode(b, id)); if (selectedId === id) setSelectedId(null); },
    openInserter: (id) => setInserterAfter(id)
  };
  const doInsert = (name) => {
    const block = makeBlock(name, name === "core/heading" ? { level: 2 } : {}, "");
    setBlocks((b) => {
      const anchor = inserterAfter != null ? findNode(b, inserterAfter) : null;
      if (anchor && blockType(anchor.name).kind === "container") return appendChild(b, inserterAfter, block);
      return insertAfter(b, inserterAfter ?? null, block);
    });
    setSelectedId(block.clientId); setInserterAfter(undefined);
  };
  const renderChildren = (parent) => (
    <div className="be-children">
      {parent.innerBlocks.map((child) => (
        <BlockView key={child.clientId} node={child} depth={1} selectedId={selectedId}
          onSelect={setSelectedId} onText={onText} onAttrs={onAttrs} actions={actions} readOnly={false} renderChildren={renderChildren} />
      ))}
      <button type="button" className="be-add-child" onClick={() => setInserterAfter(parent.innerBlocks.at(-1)?.clientId ?? parent.clientId)}>＋ Add block</button>
    </div>
  );

  const saveDoc = async () => {
    setSaving(true); setNotice(null);
    const r = await saveTemplate(doc.id, { title: doc.title, blocks: toPayload(doc.blocks) });
    setSaving(false);
    if (r.ok) { setNotice({ kind: "success", text: r.notice || "Template saved." }); loadIndex().then(setIndex).catch(() => {}); }
    else setNotice({ kind: "error", text: (r.errors || ["Save failed."]).join(", ") });
  };

  const persistStyles = async (userStyles) => {
    setSaving(true); setStylesNotice(null);
    const r = await saveStyles(userStyles);
    setSaving(false);
    setStylesNotice(r.ok ? { kind: "success", text: r.notice || "Styles saved." } : { kind: "error", text: (r.errors || ["Save failed."]).join(", ") });
    if (r.ok) setStyles((s) => ({ ...s, user_styles: userStyles }));
  };

  const selected = doc && selectedId ? findNode(doc.blocks, selectedId) : null;
  const palette = (styles && styles.settings && styles.settings.color_palette) || [];

  return (
    <div className="se-app">
      <nav className="se-sidebar" aria-label="Site editor navigation">
        <div className="se-brand">Editor <span className="se-theme">{index.active_theme}</span></div>
        <button type="button" className={`se-nav${mode === "styles" ? " is-active" : ""}`} onClick={enterStyles}>Styles</button>
        <div className="se-nav-section">Templates</div>
        <ul className="se-list">
          {index.templates.map((t) => (
            <li key={t.id}><button type="button" className={`se-item${openId === t.id && mode === "templates" ? " is-active" : ""}`} onClick={() => open(t.id)}>{t.title}</button></li>
          ))}
        </ul>
        <div className="se-nav-section">Template Parts</div>
        <ul className="se-list">
          {index.parts.map((t) => (
            <li key={t.id}><button type="button" className={`se-item${openId === t.id && mode === "templates" ? " is-active" : ""}`} onClick={() => open(t.id)}>{t.title}</button></li>
          ))}
        </ul>
      </nav>

      <div className="se-main">
        {mode === "styles" ? (
          styles ? <GlobalStylesPanel initial={styles.user_styles} palette={palette} onSave={persistStyles} saving={saving} notice={stylesNotice} />
                 : <div className="be-loading">Loading styles…</div>
        ) : !doc ? (
          <div className="se-placeholder"><p>Select a template or template part to edit, or choose <strong>Styles</strong>.</p></div>
        ) : (
          <div className="be-app">
            <header className="be-topbar" onMouseDown={(e) => e.stopPropagation()}>
              <div className="be-topbar-left">
                <button type="button" className="be-inserter-toggle" aria-label="Add block" onClick={() => setInserterAfter(inserterAfter === undefined ? null : undefined)}>＋</button>
                <span className="be-status">{doc.kind === "part" ? "Template Part" : "Template"}: {doc.title}</span>
              </div>
              <div className="be-topbar-right">
                <button type="button" className="button button-primary" disabled={saving} onClick={saveDoc}>{saving ? "Saving…" : "Save"}</button>
              </div>
            </header>
            {notice && <div className={`notice notice-${notice.kind === "error" ? "error" : "success"}`}><p>{notice.text}</p></div>}
            <div className="be-body" onMouseDown={(e) => { e.stopPropagation(); setSelectedId(null); }}>
              <main className="be-canvas" onMouseDown={(e) => e.stopPropagation()}>
                {doc.blocks.length === 0 && <p className="be-empty-hint">Empty template — press ＋ to add a block.</p>}
                {doc.blocks.map((node) => (
                  <BlockView key={node.clientId} node={node} depth={0} selectedId={selectedId}
                    onSelect={setSelectedId} onText={onText} onAttrs={onAttrs} actions={actions} readOnly={false} renderChildren={renderChildren} />
                ))}
                <button type="button" className="be-append" onClick={() => setInserterAfter(null)}>＋ Add block</button>
              </main>
              <Inspector node={selected} onAttrs={onAttrs} onClose={() => setSelectedId(null)} />
            </div>
            {inserterAfter !== undefined && (
              <div className="be-inserter-layer" onMouseDown={(e) => { if (e.target === e.currentTarget) setInserterAfter(undefined); }}>
                <Inserter onInsert={doInsert} onClose={() => setInserterAfter(undefined)} />
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
