# Skill 14 — Filesystem Sync

Batch-ingest changed files into Graphonomous, extract edges, and optionally consolidate.

## When to Use

- After making significant filesystem changes (editing multiple files, creating new modules)
- At session start to catch up on changes made outside Graphonomous sessions
- After git operations (checkout, merge, rebase) that modify many files
- When the PostToolUse hook has tracked changes in `/tmp/graphonomous-changed-files.jsonl`

## Three Modes

### Mode 1: Tracked Changes (Default)
Reads the PostToolUse hook's change log (`/tmp/graphonomous-changed-files.jsonl`) and ingests only changed files.

### Mode 2: Directory Scan
Scans a specific directory with full traversal. Each file becomes an episodic node (first 16KB read, metadata: path, extension, size). Inter-file edges are extracted from import/reference patterns.

### Mode 3: Post-Consolidation
Optionally runs consolidation after ingestion to merge near-duplicates and update graph health.

## Deduplication
Before storing, checks for existing nodes with the same file path to avoid duplicates. Existing nodes are updated rather than recreated.

## Supported Extensions
`.ex`, `.exs`, `.ts`, `.js`, `.tsx`, `.md`, `.html`, `.css`, `.json`, `.yml`, `.yaml`, `.toml`, `.svelte`

## Edge Extraction Patterns
- **Elixir:** `alias`, `import`, `use`, `require` statements
- **JS/TS:** `import`, `require()` statements
- **Markdown:** Cross-project `[link](../other-project/)` references

## Example Workflow

1. Edit several files across `graphonomous/` and `WebHost.Systems/`
2. Run `/graphonomous:sync` to ingest changes
3. Graphonomous reads the change log, stores/updates nodes, extracts edges
4. Optionally consolidates to merge near-duplicate content

## Anti-Patterns

- Don't sync build artifacts (`_build/`, `node_modules/`, `deps/`)
- Don't sync binary files (images, compiled assets)
- Don't sync the same directory from multiple concurrent sessions
