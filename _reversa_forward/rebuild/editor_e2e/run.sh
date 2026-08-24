#!/usr/bin/env bash
# Drives the REAL editors (DEV-015) in a browser against the live rebuild on :3100.
# Self-provisioning and non-destructive: it restores every record it edits, because these
# posts are the parity corpus and an edited one puts front-end screens off parity.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/editor_e2e"
echo "── post editor ──";  node gb_boot.mjs
echo "── save round trip ──"; node gb_save.mjs
echo "── site editor ──";  node se_boot.mjs
