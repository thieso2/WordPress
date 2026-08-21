# Data extraction policy (Mapper)

Defines when to invoke the extraction scripts versus reusing the cache in `_reversa_docs/assets/data/`.

## Cache hit (reuse)

Use the existing JSON when **all** of the following are true:

1. The file exists at `_reversa_docs/assets/data/<name>.json`.
2. The JSON's `mtime` is newer than the maximum `mtime` across all relevant source files:
   - For `modules.json`: the largest `mtime` within the source code (excluding `.reversa/`, `_reversa_sdd/`, `node_modules/`, `.git/`).
   - For `deps.json`: the largest `mtime` of the source code AND of `modules.json`.
3. The JSON's `schemaVersion` is compatible with the current version (1).

## Cache miss (regenerate)

In any other case, invoke the matching Python script:

```bash
python templates/documentation/scripts/extract_modules.py \
    --root . \
    --out _reversa_docs/assets/data/modules.json

python templates/documentation/scripts/extract_deps.py \
    --modules _reversa_docs/assets/data/modules.json \
    --out _reversa_docs/assets/data/deps.json
```

## Python unavailable

Do the extraction inline in the AI engine:

1. Use Glob to list files by extension (`*.py`, `*.js`, `*.ts`, `*.go`, `*.java`).
2. Use Read to count the non-empty lines of each file.
3. Build a structure identical to the `modules.json` schema (see `specs/reversa-docs/design.md`).
4. For `deps.json`, without an AST parser, start with `nodes` populated and `edges: []`. Record in `.config.json.pagesPlanned` that dependencies were not extracted.

## Force regeneration

If the user passes `--force-extract` to `/reversa-docs-mapper`, ignore the cache and regenerate. Back up the previous JSON to `.backup-<timestamp>/assets/data/`.

## When the Analyst runs standalone

If the `Analyst` runs before the Mapper or in standalone mode and does not find `modules.json`/`deps.json`, it must invoke the **same scripts** following this same policy. The result is shared: a later Mapper run will use the cache.
