// The REAL WordPress Site Editor (@wordpress/edit-site), mounted against this rebuild's own
// wp/v2 API — the companion to DEV-015, which replaced the post editor the same way.
//
// It supersedes the hand-built Site Editor island: that one browsed templates and edited them
// with our own block components, and had a Global Styles panel covering colour and two
// typography fields. This is Gutenberg's own — the template and template-part browser, the
// block canvas, style variations, and the full Global Styles UI over the theme.json cascade.
//
// Everything here is wiring; the editor is upstream. initializeEditor(id, settings) is called
// exactly as wp-admin/site-editor.php calls it.
import domReady from "@wordpress/dom-ready";
import apiFetch from "@wordpress/api-fetch";
import { initializeEditor } from "@wordpress/edit-site";

import "@wordpress/components/build-style/style.css";
import "@wordpress/block-editor/build-style/style.css";
import "@wordpress/block-library/build-style/style.css";
import "@wordpress/block-library/build-style/editor.css";
// These packages do not list ./build-style in their exports map, so they import by path.
import "../../../node_modules/@wordpress/editor/build-style/style.css";
import "../../../node_modules/@wordpress/edit-site/build-style/style.css";
import "../../../node_modules/@wordpress/format-library/build-style/style.css";
import "./site_editor.css";

domReady(() => {
  const el = document.getElementById("site-editor-root");
  if (!el) return;

  // The console layout prints `window.wpApiSettings` exactly as wp-admin does. The root is
  // RELATIVE on purpose: this corpus is seeded from the oracle, so the `siteurl` setting holds
  // the oracle's host — printing it would aim every request at WordPress instead of at us.
  const wpApi = window.wpApiSettings || {};
  apiFetch.use(apiFetch.createRootURLMiddleware(wpApi.root || "/wp-json/"));
  if (wpApi.nonce) apiFetch.use(apiFetch.createNonceMiddleware(wpApi.nonce));
  apiFetch.use((options, next) => next({ credentials: "same-origin", ...options }));

  const settings = JSON.parse(el.dataset.settings || "{}");
  initializeEditor("site-editor-root", settings);
});
