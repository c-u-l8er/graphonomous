---
name: sync
description: Use when the user says "sync", "ingest files", "update memory from disk", "scan directory", "sync to graph", or after making significant filesystem changes. Batch-ingests changed files into Graphonomous, runs edge extraction, and optionally consolidates. Routes through `act`, `learn`, and `consolidate` machines.
argument-hint: [path] [--full] [--consolidate]
---

# Filesystem Sync — Batch Ingest to Graphonomous

Sync filesystem changes into the Graphonomous knowledge graph.

## Arguments

Optional path or flags: $ARGUMENTS

- No arguments: sync only files changed during this session (tracked by the PostToolUse hook)
- `<path>`: scan a specific directory (uses `scan_directory` for full traversal)
- `--full`: force full directory scan even if change tracking is available
- `--consolidate`: run consolidation after ingestion

## How It Works

This skill bridges the gap between AI-driven file editing and Graphonomous memory. When Claude writes or edits files, those changes should be reflected in the knowledge graph so that future retrieval includes the latest state.

### Mode 1: Tracked Changes (Default)

The PostToolUse hook on Write/Edit tools records changed file paths in a session file at `/tmp/graphonomous-changed-files.jsonl`. This skill reads that file and batch-ingests only the changed files.

**Steps:**

1. Read the change tracker file (`/tmp/graphonomous-changed-files.jsonl`)
2. For each changed file, call `act(action: "store_node", ...)` with:
   - `content`: first 16KB of file content
   - `node_type`: "episodic"
   - `source`: "filesystem_sync"
   - `confidence`: 0.65
   - `metadata`: `{"path": "<absolute_path>", "extension": "<ext>", "sync_reason": "file_changed"}`
3. After all nodes are stored, create edges between related files using `act(action: "store_edge", ...)`:
   - Files in the same directory get `related` edges (weight 0.4)
   - Files that import/reference each other get `derived_from` edges (weight 0.6)
4. Clear the change tracker file
5. Report: files synced, nodes created, edges created

**Example — sync tracked changes:**
```
/graphonomous:sync
```

### Mode 2: Directory Scan (with path argument)

When given a path, performs a full `scan_directory`-style ingestion.

**Steps:**

1. List files in the target directory (respecting .gitignore, max 1MB per file)
2. For each file matching supported extensions (.ex, .exs, .ts, .js, .tsx, .md, .html, .css, .json, .yml, .yaml, .toml, .svelte):
   - Read first 16KB
   - Call `act(action: "store_node", ...)` with file content and path metadata
3. Create inter-file edges based on import/reference patterns
4. Report ingestion stats

**Example — scan a specific directory:**
```
/graphonomous:sync graphonomous/lib/
```

**Example — full scan with consolidation:**
```
/graphonomous:sync graphonomous/ --full --consolidate
```

### Mode 3: Post-Consolidation

If `--consolidate` is passed, run consolidation after ingestion:
```
consolidate(action: "run")
```

## Deduplication

Before storing, check if a node with the same path already exists:
```
consolidate(action: "query", operation: "similarity_search", query: "<file path>", limit: 1)
```
If a high-similarity node exists (score > 0.9), update it via `learn(action: "from_feedback", feedback_type: "correction")` rather than creating a duplicate.

## Edge Extraction Patterns

After storing nodes, create edges for detected references:

- **Elixir**: `alias Foo.Bar` / `import Foo` / `use Foo` / `require Foo` -> `derived_from` edge
- **JS/TS**: `import ... from './foo'` / `require('./foo')` -> `derived_from` edge
- **Markdown**: backtick file paths, cross-project names -> `related` edge

```
act(action: "store_edge", source_id: "<importer_node>", target_id: "<imported_node>", edge_type: "derived_from", weight: 0.6)
```

## Anti-patterns to avoid

- Don't sync every tiny edit in real-time — batch at natural breakpoints
- Don't ingest binary files, node_modules, _build, deps, or .git directories
- Don't set confidence above 0.65 for file content (it's raw, not curated knowledge)
- Don't skip edge extraction — edges are what make the graph useful for retrieval
