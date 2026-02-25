# Graphonomous

Continual learning engine for AI agents, implemented as an Elixir OTP application with a durable SQLite-backed knowledge graph, confidence-updating learning loop, GoalGraph orchestration, and MCP tools/resources.

> **TL;DR**
> - Use Graphonomous as an MCP server over stdio.
> - Easiest onboarding is npm/npx.
> - OpenSentience is optional; you can start immediately with built-in MCP tools.

---

## For Users (npm-first)

### 1) Install and run

Use whichever fits your workflow.

#### Option A — One-off run with `npx` (no global install)

```/dev/null/shell.sh#L1-2
npx -y graphonomous --help
npx -y graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

#### Option B — Global install

```/dev/null/shell.sh#L1-3
npm i -g graphonomous
graphonomous --help
graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

---

### 2) First-time setup (2–5 minutes)

1. Create a data directory:
```/dev/null/shell.sh#L1-1
mkdir -p ~/.graphonomous
```

2. Run Graphonomous:
```/dev/null/shell.sh#L1-1
npx -y graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

3. Configure your MCP client to launch `graphonomous` (or `npx`) and pass the same args.

---

### 3) Zed setup (custom context server)

In Zed settings JSON, use either installed command, `npx`, or a local wrapper script (recommended for dev logging/debugging).

#### Installed command

```/dev/null/settings.json#L1-14
{
  "context_servers": {
    "graphonomous": {
      "command": "graphonomous",
      "args": ["--db", "./.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
      "env": {
        "GRAPHONOMOUS_EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2"
      }
    }
  }
}
```

#### `npx` command

```/dev/null/settings.json#L1-12
{
  "context_servers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "./.graphonomous/knowledge.db", "--embedder-backend", "fallback"],
      "env": {}
    }
  }
}
```

#### Local wrapper script (recommended for local dev + logs)

Use a wrapper that launches local source via `mix run` and writes stderr logs to `~/.graphonomous/logs`.

```/dev/null/settings.json#L1-12
{
  "context_servers": {
    "graphonomous": {
      "command": "/home/travis/ProjectAmp2/graphonomous/scripts/graphonomous_mcp_wrapper.sh",
      "args": [],
      "env": {}
    }
  }
}
```

After saving:
1. Open Zed Agent panel.
2. Confirm server is active.
3. Ask explicitly for Graphonomous tool usage (for example: “use `graphonomous` to retrieve context for …”).

### 4) Zed timeout troubleshooting

If Zed shows `context server request timeout`:

1. Confirm CLI works first:
```/dev/null/shell.sh#L1-2
graphonomous --version
graphonomous --help
```
2. Start with fallback embedder and a longer request timeout:
```/dev/null/shell.sh#L1-1
graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback --request-timeout 180000
```
3. Prefer local wrapper-script mode for debugging to capture server stderr logs:
```/dev/null/settings.json#L1-12
{
  "context_servers": {
    "graphonomous": {
      "command": "/home/travis/ProjectAmp2/graphonomous/scripts/graphonomous_mcp_wrapper.sh",
      "args": [],
      "env": {}
    }
  }
}
```
4. After reproducing once, inspect wrapper logs:
```/dev/null/shell.sh#L1-3
ls -lt ~/.graphonomous/logs | head
LATEST="$(ls -1t ~/.graphonomous/logs/zed-mcp-*.log | head -n1)"
tail -n 200 "$LATEST"
```
5. Fully restart Zed after changing MCP config.
6. Reinstall/upgrade your global package if needed:
```/dev/null/shell.sh#L1-2
npm uninstall -g graphonomous
npm i -g graphonomous
```

---

### 5) Core MCP tools you’ll use first

- `store_node`
- `retrieve_context`
- `learn_from_outcome`
- `query_graph`
- `manage_goal`
- `review_goal`
- `run_consolidation`

### MCP resources (read-only)

- `graphonomous://runtime/health`
- `graphonomous://goals/snapshot`

---

### 6) Recommended laptop setting

Use:

- `--embedder-backend fallback`

This avoids heavyweight backend friction and is the quickest reliable starting point on constrained machines.

---

### 7) Common CLI flags

- `--db PATH`
- `-v, --version`
- `--embedding-model MODEL`
- `--embedder-backend auto|fallback`
- `--sqlite-vec-extension-path PATH`
- `--consolidator-interval-ms MS`
- `--consolidator-decay-rate FLOAT`
- `--consolidator-prune-threshold FLOAT`
- `--consolidator-merge-similarity FLOAT`
- `--learning-rate FLOAT`
- `--log-level debug|info|warning|error`
- `--request-timeout MS`

Help:

```/dev/null/shell.sh#L1-2
graphonomous --version
graphonomous --help
```

---

### 8) Runtime environment variables

- `GRAPHONOMOUS_DB_PATH` (default: `priv/graphonomous.db`)
- `GRAPHONOMOUS_EMBEDDING_MODEL` (default: `sentence-transformers/all-MiniLM-L6-v2`)
- `GRAPHONOMOUS_EMBEDDER_BACKEND` (`auto | fallback`)
- `GRAPHONOMOUS_SQLITE_VEC_EXTENSION_PATH` (optional)
- `GRAPHONOMOUS_CONSOLIDATOR_INTERVAL_MS`
- `GRAPHONOMOUS_CONSOLIDATOR_DECAY_RATE`
- `GRAPHONOMOUS_CONSOLIDATOR_PRUNE_THRESHOLD`
- `GRAPHONOMOUS_CONSOLIDATOR_MERGE_SIMILARITY`
- `GRAPHONOMOUS_LEARNING_RATE`
- `LOG_LEVEL` (`debug | info | warning | error`)

Example:

```/dev/null/shell.sh#L1-3
export GRAPHONOMOUS_DB_PATH="$HOME/.graphonomous/knowledge.db"
export GRAPHONOMOUS_EMBEDDER_BACKEND="fallback"
export LOG_LEVEL="info"
```

---

## For Maintainers

### Local development verification

```/dev/null/shell.sh#L1-4
MIX_ENV=test mix deps.get
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test --color
```

---

### Source fallback run (no npm)

```/dev/null/shell.sh#L1-6
cd ProjectAmp2/graphonomous
mix deps.get
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix release --overwrite
_build/prod/rel/graphonomous/bin/graphonomous eval "Graphonomous.CLI.main(System.argv())" --help
```

---

### npm package pre-publish smoke test

```/dev/null/shell.sh#L1-6
cd ProjectAmp2/graphonomous/npm
npm pack
mkdir -p /tmp/graphonomous-npm-smoke && cd /tmp/graphonomous-npm-smoke
npm init -y
npm i /home/travis/ProjectAmp2/graphonomous/npm/graphonomous-0.1.1.tgz
npx graphonomous --help
```

---

### Release + publish flow (high level, manual-first)

1. Ensure versions align (`mix.exs`, `npm/package.json`, git tag `vX.Y.Z`).
2. Build release assets locally and upload them to GitHub Release `vX.Y.Z`.
3. Run `npm publish` locally from `ProjectAmp2/graphonomous/npm`.
4. Verify with `npm view graphonomous version` and `npx -y graphonomous --help`.

See full operational runbook:
- `docs/NPM_PUBLISH.md` (manual publish path; no CI token dependency required)

---

### Architecture snapshot

Supervised services:
- `Graphonomous.Store`
- `Graphonomous.Embedder`
- `Graphonomous.Graph`
- `Graphonomous.Retriever`
- `Graphonomous.Learner`
- `Graphonomous.GoalGraph`
- `Graphonomous.Consolidator`

Storage:
- SQLite tables: `nodes`, `edges`, `outcomes`, `goals`
- migration tracking: `schema_migrations`
- ETS hot cache with startup rebuild

---

### Public API (direct module usage)

Primary module: `Graphonomous`

- Node graph: `store_node/1`, `get_node/1`, `list_nodes/1`, `update_node/2`, `delete_node/1`, `link_nodes/3`, `query_graph/1`
- Retrieval + learning: `retrieve_context/2`, `learn_from_outcome/1`
- GoalGraph: `create_goal/1`, `get_goal/1`, `list_goals/1`, `update_goal/2`, `delete_goal/1`, `transition_goal/3`, `link_goal_nodes/2`, `unlink_goal_nodes/2`, `set_goal_progress/2`, `review_goal/3`
- Coverage + ops: `evaluate_coverage/2`, `decide_coverage/2`, `run_consolidation_now/0`, `rebuild_cache/0`, `consolidator_info/0`, `health/0`

---

### Documentation map

- `docs/BOOTSTRAP.md` — bootstrap + verification
- `docs/ZED.md` — Zed integration details
- `docs/NPM_PUBLISH.md` — npm publishing and maintenance runbook
- `npm/README.md` — npm wrapper package usage and overrides

---

## Notes

- EXLA is currently optional to avoid environment-level NIF/CUDA mismatch issues.
- sqlite-vec extension loading is optional.
- OpenSentience integration is **not required** to start using Graphonomous.
- MCP stdio reliability is currently ensured by a vendored `anubis_mcp` dependency patch (`vendor/anubis_mcp`) that fixes decoded message list handling and request-response writes in the STDIO transport path.

---

## License

Internal project (no public license declared in this repository yet).
