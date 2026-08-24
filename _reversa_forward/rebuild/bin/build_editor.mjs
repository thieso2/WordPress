#!/usr/bin/env node
// Bundles the block editor React island (DEV-012, D-3) into app/assets/builds/editor.js.
// The rest of the rebuild is importmap/no-build; the editor is the single React surface the
// owner carved out. Output is a self-contained ESM module propshaft fingerprints and serves.
import * as esbuild from "esbuild";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const watch = process.argv.includes("--watch");

const options = {
  entryPoints: [
    { in: resolve(root, "app/frontend/site_editor_gb/index.jsx"), out: "site_editor" },
    { in: resolve(root, "app/frontend/gutenberg/index.jsx"), out: "gutenberg" }
  ],
  bundle: true,
  format: "esm",
  target: ["es2020"],
  jsx: "automatic",
  loader: { ".css": "css", ".svg": "dataurl", ".png": "dataurl", ".gif": "dataurl" },
  minify: !watch,
  sourcemap: true,
  outdir: resolve(root, "app/assets/builds"),
  define: { "process.env.NODE_ENV": watch ? '"development"' : '"production"' },
  logLevel: "info"
};

if (watch) {
  const ctx = await esbuild.context(options);
  await ctx.watch();
  console.log("[build_editor] watching…");
} else {
  await esbuild.build(options);
  console.log("[build_editor] built app/assets/builds/editor.js");
}
