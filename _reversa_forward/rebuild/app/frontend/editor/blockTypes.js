// The block registry — the observable core-block set the oracle's inserter offers
// (DEV-012, D-3: specified by observation, not by an extracted rule; there is no
// BR-MIGRATE-* behind the editor). Each entry declares HOW the block edits:
//
//   kind: "text"      — a single contenteditable region; `tag` is the element whose
//                       innerHTML is the block's editable content.
//   kind: "container" — renders innerBlocks recursively inside a wrapper.
//   kind: "dynamic"   — server-rendered on the front end; the editor shows an honest
//                       labelled preview (as Gutenberg shows a server preview), never a
//                       fake render. Attributes are still editable via the inspector.
//   kind: "void"      — a structural block with no editable content (separator, spacer).
//
// `level`-bearing text blocks (heading) pick their tag from the attr at render time.
export const BLOCK_TYPES = {
  "core/paragraph":     { title: "Paragraph", kind: "text", tag: "p", icon: "¶" },
  "core/heading":       { title: "Heading", kind: "text", tag: "h2", icon: "H", levelAttr: "level" },
  "core/list":          { title: "List", kind: "text", tag: "ul", icon: "•" },
  "core/list-item":     { title: "List item", kind: "text", tag: "li", icon: "•" },
  "core/quote":         { title: "Quote", kind: "container", wrapperTag: "blockquote", icon: "❝" },
  "core/pullquote":     { title: "Pullquote", kind: "container", wrapperTag: "figure", icon: "❝" },
  "core/code":          { title: "Code", kind: "text", tag: "code", pre: true, icon: "</>" },
  "core/preformatted":  { title: "Preformatted", kind: "text", tag: "pre", pre: true, icon: "Pre" },
  "core/verse":         { title: "Verse", kind: "text", tag: "pre", pre: true, icon: "Ⓥ" },

  "core/group":         { title: "Group", kind: "container", wrapperTag: "div", icon: "⯐" },
  "core/columns":       { title: "Columns", kind: "container", wrapperTag: "div", icon: "▚" },
  "core/column":        { title: "Column", kind: "container", wrapperTag: "div", icon: "▎" },
  "core/buttons":       { title: "Buttons", kind: "container", wrapperTag: "div", icon: "⬚" },
  "core/button":        { title: "Button", kind: "text", tag: "a", icon: "⬚" },

  "core/image":         { title: "Image", kind: "dynamic", icon: "🖼", previewAttrs: ["url", "alt"] },
  "core/cover":         { title: "Cover", kind: "dynamic", icon: "▨", previewAttrs: ["url"] },
  "core/gallery":       { title: "Gallery", kind: "dynamic", icon: "▦" },
  "core/audio":         { title: "Audio", kind: "dynamic", icon: "♪", previewAttrs: ["src"] },
  "core/video":         { title: "Video", kind: "dynamic", icon: "▶", previewAttrs: ["src"] },
  "core/file":          { title: "File", kind: "dynamic", icon: "▤", previewAttrs: ["href"] },
  "core/html":          { title: "Custom HTML", kind: "text", tag: "div", raw: true, icon: "</>" },
  "core/shortcode":     { title: "Shortcode", kind: "text", tag: "div", raw: true, icon: "[ ]" },

  "core/separator":     { title: "Separator", kind: "void", icon: "―" },
  "core/spacer":        { title: "Spacer", kind: "void", icon: "↕", previewAttrs: ["height"] },
  "core/more":          { title: "More", kind: "void", icon: "…" },

  // Dynamic site/query blocks — front-end server-rendered (Composition renderers already
  // exist). The editor shows a labelled placeholder, honest about what mounts on render.
  "core/site-logo":     { title: "Site Logo", kind: "dynamic", icon: "◆" },
  "core/site-title":    { title: "Site Title", kind: "dynamic", icon: "T" },
  "core/site-tagline":  { title: "Site Tagline", kind: "dynamic", icon: "t" },
  "core/navigation":    { title: "Navigation", kind: "dynamic", icon: "☰" },
  "core/page-list":     { title: "Page List", kind: "dynamic", icon: "☰" },
  "core/template-part": { title: "Template Part", kind: "dynamic", icon: "⧉", previewAttrs: ["slug"] },
  "core/post-content":  { title: "Post Content", kind: "dynamic", icon: "¶" },
  "core/post-title":    { title: "Post Title", kind: "dynamic", icon: "T" },
  "core/query":         { title: "Query Loop", kind: "container", wrapperTag: "div", icon: "⟳" },
  "core/post-template": { title: "Post Template", kind: "container", wrapperTag: "div", icon: "⟳" },
  "core/latest-posts":  { title: "Latest Posts", kind: "dynamic", icon: "≣" },
  "core/search":        { title: "Search", kind: "dynamic", icon: "⌕" },
  "core/social-links":  { title: "Social Icons", kind: "dynamic", icon: "◍" }
};

// The inserter palette — the readable, commonly-inserted set, grouped as the oracle groups
// them. Order and grouping are observational, not rule-bound.
export const INSERTER_GROUPS = [
  { label: "Text", names: ["core/paragraph", "core/heading", "core/list", "core/quote", "core/code", "core/preformatted", "core/verse"] },
  { label: "Media", names: ["core/image", "core/gallery", "core/audio", "core/video", "core/file", "core/cover"] },
  { label: "Design", names: ["core/group", "core/columns", "core/buttons", "core/separator", "core/spacer", "core/html"] },
  { label: "Widgets", names: ["core/shortcode", "core/social-links", "core/search", "core/latest-posts"] },
  { label: "Theme", names: ["core/site-logo", "core/site-title", "core/navigation", "core/template-part", "core/post-title", "core/post-content"] }
];

export function blockType(name) {
  return BLOCK_TYPES[name] || { title: name || "Classic", kind: name ? "dynamic" : "freeform", icon: "▦" };
}

// The tag a text block renders into — heading resolves h1..h6 from its level attr.
export function textTag(node) {
  const t = blockType(node.name);
  if (t.levelAttr) {
    const level = Number(node.attrs?.[t.levelAttr]) || 2;
    return `h${Math.min(6, Math.max(1, level))}`;
  }
  return t.tag || "p";
}
