import { useState } from "react";

// Global Styles editor — the 'custom'/user origin of the theme.json four-origin cascade
// (BR-MIGRATE-208: one user layer per theme, persisted to themes.user_styles). A genuine,
// useful subset: background/text colour (with the theme's own palette as swatches),
// link colour, and base typography size/line-height. Everything writes into the
// theme.json v3 shape { version, styles: { color, typography, elements } } that the
// cascade already merges and renders.
export default function GlobalStylesPanel({ initial, palette, onSave, saving, notice }) {
  const [styles, setStyles] = useState(() => normalize(initial));

  const setPath = (path, value) => {
    setStyles((prev) => {
      const next = structuredClone(prev);
      let node = next;
      for (let i = 0; i < path.length - 1; i++) { node[path[i]] = node[path[i]] || {}; node = node[path[i]]; }
      if (value === "" || value == null) delete node[path[path.length - 1]];
      else node[path[path.length - 1]] = value;
      return next;
    });
  };

  const colorValue = (path) => path.reduce((o, k) => (o ? o[k] : undefined), styles.styles) || "";

  return (
    <div className="se-styles">
      <h2 className="se-styles-title">Styles</h2>
      {notice && <div className={`notice notice-${notice.kind === "error" ? "error" : "success"}`}><p>{notice.text}</p></div>}

      <section className="se-styles-group">
        <h3>Colors</h3>
        <ColorField label="Background" value={colorValue(["color", "background"])} palette={palette} onChange={(v) => setPath(["styles", "color", "background"], v)} />
        <ColorField label="Text" value={colorValue(["color", "text"])} palette={palette} onChange={(v) => setPath(["styles", "color", "text"], v)} />
        <ColorField label="Links" value={colorValue(["elements", "link", "color", "text"])} palette={palette} onChange={(v) => setPath(["styles", "elements", "link", "color", "text"], v)} />
      </section>

      <section className="se-styles-group">
        <h3>Typography</h3>
        <div className="be-field">
          <label htmlFor="se-fontsize">Base size</label>
          <input id="se-fontsize" type="text" placeholder="e.g. 1.125rem"
            value={(styles.styles.typography && styles.styles.typography.fontSize) || ""}
            onChange={(e) => setPath(["styles", "typography", "fontSize"], e.target.value)} />
        </div>
        <div className="be-field">
          <label htmlFor="se-lineheight">Line height</label>
          <input id="se-lineheight" type="text" placeholder="e.g. 1.6"
            value={(styles.styles.typography && styles.styles.typography.lineHeight) || ""}
            onChange={(e) => setPath(["styles", "typography", "lineHeight"], e.target.value)} />
        </div>
      </section>

      <button type="button" className="button button-primary" disabled={saving} onClick={() => onSave(styles)}>
        {saving ? "Saving…" : "Save styles"}
      </button>
    </div>
  );
}

function ColorField({ label, value, palette, onChange }) {
  return (
    <div className="se-color-field">
      <label>{label}</label>
      <div className="se-swatches">
        {(palette || []).map((c) => (
          <button key={c.slug} type="button" title={c.name || c.slug}
            className={`se-swatch${value === varRef(c.slug) || value === c.color ? " is-active" : ""}`}
            style={{ background: c.color }} onClick={() => onChange(varRef(c.slug))} aria-label={c.name || c.slug} />
        ))}
        <button type="button" className="se-swatch se-swatch-none" title="Clear" onClick={() => onChange("")}>✕</button>
      </div>
      <input type="text" className="se-color-input" value={value} placeholder="theme colour or #hex" onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

// A theme palette colour is referenced in theme.json as a CSS var preset, matching how
// WordPress stores palette selections: var(--wp--preset--color--<slug>).
function varRef(slug) { return `var(--wp--preset--color--${slug})`; }

function normalize(initial) {
  const s = initial && typeof initial === "object" ? structuredClone(initial) : {};
  if (!s.version) s.version = 3;
  if (!s.styles) s.styles = {};
  return s;
}
