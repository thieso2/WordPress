#!/usr/bin/env bash
# Runs both editor island e2e suites against the live rebuild on :3100.
# Self-provisioning: re-creates its fixtures first, so it works after any oracle:seed.
set -e
cd "$(dirname "$0")/.."
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
POST_ID=$(RAILS_ENV=development bin/rails runner editor_e2e/setup.rb 2>/dev/null | grep -oE 'POST_ID=[0-9]+' | cut -d= -f2)
[ -z "$POST_ID" ] && { echo "e2e setup failed"; exit 1; }
echo "fixture post: $POST_ID"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # absolute: the trap runs after we have cd'd away
cleanup() { (cd "$ROOT" && RAILS_ENV=development bin/rails runner editor_e2e/teardown.rb >/dev/null 2>&1); }
trap cleanup EXIT   # the corpus must be exactly as seeded when we leave, pass or fail
cd editor_e2e
POST_ID="$POST_ID" node interaction.mjs
node site_editor.mjs
