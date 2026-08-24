// Site Editor React island (DEV-012, D-3) entry. Mounts into #site-editor-root.
import "../editor/editor.css";
import "./site_editor.css";
import { createRoot } from "react-dom/client";
import SiteEditor from "./SiteEditor.jsx";

const el = document.getElementById("site-editor-root");
if (el) {
  const fallback = document.getElementById("site-editor-fallback");
  if (fallback) fallback.hidden = true;
  createRoot(el).render(<SiteEditor />);
}
