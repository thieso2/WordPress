// The block editor React island (DEV-012, D-3). Mounts into #editor-root, which the
import "./editor.css";
// EditorLayout renders with the post's id. Progressive enhancement: when this script runs
// it replaces the noscript <form> fallback with the live canvas; without JS, that form
// still edits raw block markup and saves through the same command path.
import { createRoot } from "react-dom/client";
import Editor from "./Editor.jsx";

const el = document.getElementById("editor-root");
if (el) {
  const postId = el.getAttribute("data-post-id");
  const isNew = el.getAttribute("data-post-new") === "true";
  // Hide the noscript fallback form once the island takes over.
  const fallback = document.getElementById("editor-fallback");
  if (fallback) fallback.hidden = true;
  createRoot(el).render(<Editor postId={postId} isNew={isNew} />);
}
