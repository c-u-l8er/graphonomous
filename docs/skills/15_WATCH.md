# 15. Filesystem Watch

Continuous polling-based filesystem monitoring that syncs changes to Graphonomous in real-time.

## When to Use

- During active development sessions where you want live sync
- When monitoring a directory for external changes (CI artifacts, generated files)
- For long-running sessions where periodic sync is preferred over manual triggers

## How It Works

Uses snapshot diffing (file size + mtime + content SHA256) to detect changes at configurable intervals:

- **Added files** → create new episodic nodes with content + metadata
- **Modified files** → update existing nodes with new content
- **Removed files** → mark node confidence to 0.0 (soft delete)

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| Path | (required) | Directory to watch |
| Poll interval | 5000 ms | How often to check for changes |
| Extensions | .ex, .exs, .ts, .js, .tsx, .md, .html, .css, .json, .yml, .yaml, .toml, .svelte | File types to track |
| Max file size | 1 MB | Skip files larger than this |
| Recursive | true | Watch subdirectories |
| Respect .gitignore | true | Skip gitignored files |

## Session vs Background Watching

- **In-session**: The `/graphonomous:watch` skill runs within the conversation, polling at intervals
- **Background**: Use `graphonomous watch <path>` CLI command for persistent background watching outside Claude sessions

## Anti-Patterns

- Don't set poll interval below 1000 ms (excessive I/O)
- Don't watch `_build/`, `node_modules/`, `deps/`, `.git/` directories
- Don't run overlapping watchers on the same directory
- Don't use watch for one-time bulk ingestion — use `/graphonomous:sync` instead
