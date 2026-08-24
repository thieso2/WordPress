// The REAL WordPress block editor (DEV-015), mounted against this rebuild's own wp/v2 API.
//
// This replaces the hand-built island that lived in app/frontend/editor/. That island was a
// working block editor but not THE block editor: no Post sidebar, no undo/redo, no list view,
// no preview, no per-block toolbars. DEV-012 requires the editing experience to reach parity
// and records that its specification does not exist inside this checkout — so the honest
// resolution is to run the upstream packages instead of approximating them forever.
//
// Everything here is wiring. The editor is @wordpress/edit-post's own initializeEditor, called
// exactly as wp-admin calls it; what this file adds is pointing @wordpress/api-fetch at our
// REST surface and handing it the nonce the console minted.
import domReady from "@wordpress/dom-ready";
import apiFetch from "@wordpress/api-fetch";
import { initializeEditor } from "@wordpress/edit-post";

import "@wordpress/components/build-style/style.css";
import "@wordpress/block-editor/build-style/style.css";
import "@wordpress/block-library/build-style/style.css";
import "@wordpress/block-library/build-style/editor.css";
// These three packages do not list ./build-style in their exports map, so they are imported
// by path. The stylesheets are shipped in the published package either way.
import "../../../node_modules/@wordpress/editor/build-style/style.css";
import "../../../node_modules/@wordpress/edit-post/build-style/style.css";
import "../../../node_modules/@wordpress/format-library/build-style/style.css";
import "./editor.css";

domReady(() => {
  const el = document.getElementById("gutenberg-root");
  if (!el) return;

  const { postId, postType } = el.dataset;

  // The console layout prints `window.wpApiSettings` exactly as wp-admin does, so this reads
  // the same globals @wordpress/api-fetch expects. The root middleware maps `/wp/v2/...` onto
  // our `/wp-json/` mount; the nonce middleware supplies the `X-WP-Nonce` header our write
  // endpoints verify (the equivalent of rest_cookie_check_errors' `wp_rest` nonce).
  const wpApi = window.wpApiSettings || {};
  apiFetch.use(apiFetch.createRootURLMiddleware(wpApi.root || "/wp-json/"));
  if (wpApi.nonce) apiFetch.use(apiFetch.createNonceMiddleware(wpApi.nonce));
  // Same-origin cookies carry the session; without this every request reads as anonymous.
  apiFetch.use((options, next) => next({ credentials: "same-origin", ...options }));

  // Whatever the server could not supply is simply absent — the editor degrades by hiding the
  // feature rather than by inventing one.
  const settings = JSON.parse(el.dataset.settings || "{}");

  initializeEditor("gutenberg-root", postType || "post", Number(postId), settings);
});
