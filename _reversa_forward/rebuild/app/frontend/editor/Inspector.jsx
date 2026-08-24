import { blockType } from "./blockTypes.js";

// The settings sidebar (Inspector controls). A small set of first-class controls for common
// attributes (heading level, text alignment) plus a generic key/value editor so any block's
// attributes remain fully editable — honest about the fact that the full @wordpress/*
// inspector-controls system is not reproduced (DEV-012), while keeping every attribute
// reachable.
export default function Inspector({ node, onAttrs, onClose }) {
  if (!node) {
    return <aside className="be-inspector"><div className="be-inspector-empty">No block selected.</div></aside>;
  }
  const type = blockType(node.name);
  const attrs = node.attrs || {};
  const set = (k, v) => onAttrs(node.clientId, { ...attrs, [k]: v });
  const unset = (k) => { const next = { ...attrs }; delete next[k]; onAttrs(node.clientId, next); };

  return (
    <aside className="be-inspector" aria-label="Block settings">
      <div className="be-inspector-head">
        <span>{type.icon} {type.title}</span>
        <button type="button" aria-label="Close settings" onClick={onClose}>✕</button>
      </div>

      {node.name === "core/heading" && (
        <div className="be-field">
          <label htmlFor="be-heading-level">Level</label>
          <select id="be-heading-level" value={Number(attrs.level) || 2} onChange={(e) => set("level", Number(e.target.value))}>
            {[1, 2, 3, 4, 5, 6].map((l) => <option key={l} value={l}>H{l}</option>)}
          </select>
        </div>
      )}

      {["core/paragraph", "core/heading", "core/image", "core/columns", "core/group", "core/button"].includes(node.name) && (
        <div className="be-field">
          <label htmlFor="be-align">Align</label>
          <select id="be-align" value={attrs.align || ""} onChange={(e) => (e.target.value ? set("align", e.target.value) : unset("align"))}>
            <option value="">None</option>
            <option value="left">Left</option>
            <option value="center">Center</option>
            <option value="right">Right</option>
            <option value="wide">Wide</option>
            <option value="full">Full</option>
          </select>
        </div>
      )}

      <details className="be-attrs">
        <summary>Attributes (JSON)</summary>
        <AttrsTable attrs={attrs} set={set} unset={unset} />
      </details>
    </aside>
  );
}

function AttrsTable({ attrs, set, unset }) {
  const keys = Object.keys(attrs);
  return (
    <div className="be-attrs-table">
      {keys.length === 0 && <div className="be-attrs-empty">No attributes.</div>}
      {keys.map((k) => (
        <div key={k} className="be-attr-row">
          <code>{k}</code>
          <input
            type="text"
            value={typeof attrs[k] === "string" ? attrs[k] : JSON.stringify(attrs[k])}
            onChange={(e) => {
              const raw = e.target.value;
              let v = raw;
              try { v = JSON.parse(raw); } catch { v = raw; }
              set(k, v);
            }}
          />
          <button type="button" aria-label={`Remove ${k}`} onClick={() => unset(k)}>✕</button>
        </div>
      ))}
    </div>
  );
}
