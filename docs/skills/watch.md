---
name: watch
description: Use when the user says "watch directory", "monitor files", "start watching", "live sync", "auto-ingest", or wants continuous filesystem monitoring synced to Graphonomous. Starts a polling loop that detects file changes and ingests them automatically. Uses `act` machine for storage.
argument-hint: <path> [--interval <ms>] [--extensions <list>]
---

# Watch Directory — Continuous Filesystem Sync

Start a polling loop that detects filesystem changes and ingests them into Graphonomous.

## Arguments

Required path and optional flags: $ARGUMENTS

- `<path>`: directory to watch (required)
- `--interval <ms>`: poll interval in milliseconds (default: 5000)
- `--extensions <list>`: comma-separated extensions to watch (default: .ex,.exs,.ts,.js,.tsx,.md,.html,.css,.json,.svelte)

## How It Works

Graphonomous has a built-in `watch_directory` feature that polls for file changes using snapshot diffing (size + mtime + content SHA256). This skill wires that into the Claude Code session.

### Starting the Watcher

1. Note the target directory and configuration
2. Inform the user that watching is active
3. On each detected change, use `/graphonomous:sync <changed_file_path>` to ingest

**Example — watch the graphonomous lib directory:**
```
/graphonomous:watch graphonomous/lib/ --interval 3000
```

**Example — watch with specific extensions:**
```
/graphonomous:watch WebHost.Systems/src/ --extensions .ts,.tsx,.js
```

### What Gets Watched

The watcher tracks:
- **Added files**: new files matching the extension filter -> `act(action: "store_node", ...)`
- **Modified files**: changed content (SHA256 differs) -> update existing node or store new
- **Removed files**: deleted files -> optionally mark node confidence to 0.0

### Watcher Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `path` | (required) | Root directory to watch |
| `interval` | 5000ms | How often to check for changes |
| `extensions` | .ex,.exs,.ts,.js,.tsx,.md,.html,.css,.json,.svelte | File types to include |
| `recursive` | true | Watch subdirectories |
| `respect_gitignore` | true | Skip .gitignore'd files |
| `max_file_size` | 1MB | Skip files larger than this |

### Important Notes

- The watcher runs as a **conceptual loop within the conversation** — Claude checks for changes when prompted or between tasks
- For true background watching, use Graphonomous's native CLI: `graphonomous watch <path>`
- The watcher does NOT automatically run edge extraction (use `/graphonomous:sync --full` periodically for that)
- Stop watching by saying "stop watching" or ending the session

## Native CLI Alternative

For continuous background watching outside of Claude Code sessions:

```bash
cd graphonomous
mix run --no-halt -- watch /home/travis/ProjectAmp2 \
  --poll-interval-ms 5000 \
  --extensions .ex,.exs,.ts,.js,.tsx,.md,.html,.css,.json,.svelte \
  --ingest-on-start \
  --consolidation-cadence 100
```

This runs as a persistent process and is the recommended approach for always-on filesystem sync.

## Anti-patterns to avoid

- Don't set poll interval below 1000ms — excessive polling wastes resources
- Don't watch node_modules, _build, deps, or .git directories
- Don't expect real-time sub-second latency — this is polling-based, not inotify
- Don't run multiple watchers on overlapping directories — you'll get duplicate nodes
