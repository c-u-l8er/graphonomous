# Graphonomous

Continual learning engine for AI agents, implemented as an Elixir/OTP application with a durable SQLite-backed knowledge graph, confidence-updating learning loop, GoalGraph orchestration, κ-aware topology routing, and an MCP server exposing 5 loop-phase machines.

**v0.4.0** — Dual-loop machine architecture: 29 actions grouped into 5 machines (retrieve, route, act, learn, consolidate). κ-aware topology routing, AGM-rational belief revision, intentional forgetting (soft/hard/cascade/GDPR), Wilson score epistemic frontier, Q-value outcome-weighted retrieval, multi-agent scoping via `agent_id`, nomic-embed-text-v2-moe 768D embedder, and graph algorithm suite (Dijkstra, toposort, Louvain, Hopcroft-Karp, incremental SCC, triangle counting). LongMemEval: 92.6% QA proxy, 98.7% session hit rate. 455+ tests, 0 failures.

> **TL;DR**
> - Install: `npm i -g graphonomous` or `npx -y graphonomous`
> - MCP server over stdio or HTTP — works with Claude Code, Codex, Cursor, Zed, and any MCP client
> - 5 machines with 29 actions (not 29 flat tools) — better tool selection accuracy
> - κ-aware topology routing ships out of the box — no configuration needed
> - Data stays local: SQLite at `~/.graphonomous/knowledge.db`

---

## Quick Start (60 seconds)

### 1) Install

```sh
# Option A — One-off (no global install)
npx -y graphonomous --help

# Option B — Global install
npm i -g graphonomous
graphonomous --help
```

**Requirements:** Node.js >= 18 · macOS or Linux · x64 or arm64

### 2) Add to your MCP config

Add to `~/.mcp.json` or your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db"]
    }
  }
}
```

Restart your agent. Graphonomous is now your memory layer.

### 3) Start a memory session

Copy this into Claude Code, Codex, or any MCP-capable agent:

```
Start a Graphonomous memory session for this repo.
1. retrieve(action: "context", query: "session context")
2. Check active goals: act(action: "manage_goal", goal_operation: "list_goals")
3. Survey attention: route(action: "attention_survey")
Then proceed with my task, storing durable knowledge as we go.
```

Every session follows the closed loop: **retrieve → route → act → learn → consolidate**.

---

## Machine Architecture (v0.4)

Tool selection accuracy degrades past ~30 tools. Instead of 29 individual tools, Graphonomous v0.4 exposes **5 loop-phase machines** — one per phase of the closed memory loop. Each machine dispatches via an `action` parameter.

```
retrieve → route → act → learn → consolidate
"What do I know?" → "What should I do?" → "Do it" → "Did it work?" → "Clean up"
```

| Machine | Actions | Description |
|---|---|---|
| **retrieve** | `context`, `episodic`, `procedural`, `coverage`, `trace_evidence`, `frontier` | κ-aware ranked retrieval, time-filtered episodes, procedural search, epistemic coverage, Dijkstra evidence paths, Wilson interval uncertainty |
| **route** | `topology`, `deliberate`, `attention_survey`, `attention_cycle`, `review_goal` | SCC/κ analysis, κ-driven deliberation, priority survey, triage → dispatch, coverage-driven gate |
| **act** | `store_node`, `store_edge`, `delete_node`, `manage_edge`, `manage_goal`, `belief_revise`, `forget_node`, `forget_policy`, `gdpr_erase` | All graph mutations: node/edge CRUD, goal lifecycle, AGM belief revision, soft/hard/cascade forgetting, GDPR erasure |
| **learn** | `from_outcome`, `from_feedback`, `detect_novelty`, `from_interaction`, `contradictions` | Causal confidence updates, feedback processing, novelty scoring, full ingestion pipeline, contradiction detection |
| **consolidate** | `run`, `stats`, `query`, `traverse` | 8-stage consolidation, aggregate statistics, operation-based inspection, BFS traversal |

### Backward compatibility

All 29 legacy tools (`store_node`, `retrieve_context`, `learn_from_outcome`, etc.) remain available. Machines delegate to them internally, so existing integrations continue to work.

### MCP resources (5 read-only)

- `graphonomous://runtime/health` — runtime health + service status
- `graphonomous://goals/snapshot` — goal totals, status breakdown
- `graphonomous://graph/node/{id}` — individual node details + edges
- `graphonomous://graph/recent` — recently accessed/modified nodes
- `graphonomous://consolidation/log` — consolidator state + orchestrator plasticity metrics

### Dual-loop architecture (PRISM)

When PRISM (OS-009) benchmarks Graphonomous, both closed loops interlock:

```
PRISM:        compose → interact → observe → reflect → diagnose  (+ config)
                            │
                            ▼
Graphonomous: retrieve → route → act → learn → consolidate
```

5 + 6 = **11 tools** in a shared session, down from 76. The outer loop improves the benchmark. The inner loop improves the memory. Each makes the other sharper.

---

## Client Setup

### Claude Code

Add to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "graphonomous": {
      "command": "npx",
      "args": ["-y", "graphonomous", "--db", "./.graphonomous/knowledge.db", "--embedder-backend", "fallback"]
    }
  }
}
```

Or if installed globally:

```json
{
  "mcpServers": {
    "graphonomous": {
      "command": "graphonomous",
      "args": ["--db", "./.graphonomous/knowledge.db", "--embedder-backend", "fallback"]
    }
  }
}
```

### Zed (custom context server)

#### Installed command

```json
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

```json
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

```json
{
  "context_servers": {
    "graphonomous": {
      "command": "/path/to/graphonomous/scripts/graphonomous_mcp_wrapper.sh",
      "args": [],
      "env": {}
    }
  }
}
```

After saving:
1. Open Zed Agent panel.
2. Confirm server is active.
3. Ask explicitly for Graphonomous tool usage (e.g., "use `graphonomous` to retrieve context for …").

### Zed timeout troubleshooting

If Zed shows `context server request timeout`:

1. Confirm CLI works: `graphonomous --version && graphonomous --help`
2. Start with fallback embedder and longer timeout: `graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback --request-timeout 180000`
3. Use the local wrapper script for debugging (captures stderr logs).
4. Inspect logs: `ls -lt ~/.graphonomous/logs | head`
5. Fully restart Zed after changing MCP config.
6. Reinstall if needed: `npm uninstall -g graphonomous && npm i -g graphonomous`

---

## Agent Skills (Claude Code Plugin)

Graphonomous skills for Claude Code live in the **[ampersand-plugins](https://github.com/c-u-l8er/ampersand-plugins)** repository. Install the plugin to get 18 skills that wire the Graphonomous memory loop into every session automatically.

### Installing the plugin

```sh
claude plugin add c-u-l8er/ampersand-plugins
```

This registers the `graphonomous` plugin (18 skills) plus `prism` (8 skills), `spec-driven-dev` (3 skills), and `ampersand-protocol` (2 skills).

### Graphonomous skills (18)

| Skill | Description |
|---|---|
| `/graphonomous:bootstrap` | Initialize session — retrieve context, check goals, survey attention |
| `/graphonomous:retrieve` | Query knowledge graph by natural language (κ-aware ranked retrieval) |
| `/graphonomous:store` | Save knowledge — atomic nodes with confidence calibration |
| `/graphonomous:learn` | Close feedback loop — outcome, feedback, novelty, contradictions |
| `/graphonomous:deliberate` | Topology analysis and κ-driven cyclic reasoning |
| `/graphonomous:consolidate` | Graph maintenance — 7-stage pipeline, stats, query, traverse |
| `/graphonomous:goals` | Durable intent tracking across sessions |
| `/graphonomous:belief` | AGM-style belief revision — expand, revise, contract |
| `/graphonomous:forgetting` | Structured removal — soft, hard, cascade, GDPR, policy pruning |
| `/graphonomous:epistemic-frontier` | Wilson score uncertainty analysis + information gain ranking |
| `/graphonomous:trace-evidence-path` | Weighted Dijkstra provenance paths between nodes |
| `/graphonomous:attention` | Autonomous focus — survey, triage, dispatch |
| `/graphonomous:review` | Coverage evaluation — act/learn/escalate routing |
| `/graphonomous:inspect` | Read-only graph browsing — list, get, edges, search, traverse |
| `/graphonomous:graph-health` | Combined diagnostics — weak nodes, orphans, staleness |
| `/graphonomous:workflows` | End-to-end recipes — cold start, debug, Ralph loop, handoff |
| `/graphonomous:sync` | Batch filesystem ingest to knowledge graph |
| `/graphonomous:watch` | Continuous filesystem monitoring with change detection |

### PRISM skills (8)

| Skill | Description |
|---|---|
| `/prism:bootstrap` | Initialize PRISM evaluation engine |
| `/prism:compose` | Build/validate/manage test scenarios |
| `/prism:interact` | Execute scenarios against memory systems |
| `/prism:observe` | 3-layer judging across 9 CL dimensions |
| `/prism:reflect` | Gap analysis, IRT recalibration, scenario evolution |
| `/prism:diagnose` | Reports, failure patterns, leaderboards, fix suggestions |
| `/prism:configure` | Register systems, set weights, create profiles |
| `/prism:benchmark` | Full cycle orchestrator (compose → interact → observe → reflect → diagnose) |

### Skills reference docs

This repo also ships reference documentation in `docs/skills/` mirroring the plugin skills — useful for non-Claude-Code agents, manual prompt injection, or understanding the skill internals.

- `docs/skills/SKILLS.md` — index and quick orientation
- One file per skill matching the plugin names above

---

## CLI Reference

### Command modes

```sh
graphonomous                                                    # MCP server over stdio (default)
graphonomous --transport streamable_http --port 4100            # MCP server over HTTP
graphonomous scan <directory>                                   # One-shot traversal
graphonomous watch <directory>                                  # Continuous change detection + traversal
```

### Global options

| Flag | Description |
|---|---|
| `--db PATH` | SQLite database path |
| `-v, --version` | Print version |
| `--embedding-model MODEL` | Embedding model name |
| `--embedder-backend auto\|fallback` | Embedding backend (`fallback` skips EXLA) |
| `--sqlite-vec-extension-path PATH` | Custom sqlite-vec path |
| `--consolidator-interval-ms MS` | Consolidation interval |
| `--consolidator-decay-rate FLOAT` | Consolidation decay rate |
| `--consolidator-prune-threshold FLOAT` | Pruning threshold |
| `--consolidator-merge-similarity FLOAT` | Merge similarity threshold |
| `--learning-rate FLOAT` | Learning rate |
| `--log-level debug\|info\|warning\|error` | Log level |
| `--request-timeout MS` | Request timeout |

### Filesystem traversal options (`scan` / `watch`)

`--recursive`, `--include-hidden`, `--follow-symlinks`, `--extensions .ex,.md,.txt`, `--poll-interval-ms MS`, `--ingest-on-start`, `--max-file-size-bytes N`, `--max-read-bytes N`

### Environment variables

| Variable | Default |
|---|---|
| `GRAPHONOMOUS_DB_PATH` | `priv/graphonomous.db` |
| `GRAPHONOMOUS_EMBEDDING_MODEL` | `sentence-transformers/all-MiniLM-L6-v2` |
| `GRAPHONOMOUS_EMBEDDER_BACKEND` | `auto` (options: `auto`, `fallback`) |
| `GRAPHONOMOUS_SQLITE_VEC_EXTENSION_PATH` | (optional) |
| `GRAPHONOMOUS_CONSOLIDATOR_INTERVAL_MS` | — |
| `GRAPHONOMOUS_CONSOLIDATOR_DECAY_RATE` | — |
| `GRAPHONOMOUS_CONSOLIDATOR_PRUNE_THRESHOLD` | — |
| `GRAPHONOMOUS_CONSOLIDATOR_MERGE_SIMILARITY` | — |
| `GRAPHONOMOUS_LEARNING_RATE` | — |
| `LOG_LEVEL` | `info` (options: `debug`, `info`, `warning`, `error`) |

**Recommended laptop setting:** Use `--embedder-backend fallback` to avoid heavyweight EXLA/CUDA friction on constrained machines.

---

## Key Features

- **κ-Routing** — Tarjan SCC analysis detects circular dependencies; κ=0 regions get fast single-pass retrieval, κ>0 regions trigger deliberation with configurable budgets
- **Belief Revision** — AGM-rational expand/revise/contract with automatic contradiction detection during consolidation
- **Intentional Forgetting** — soft (hidden, reversible), hard (delete), cascade (delete + orphans), GDPR Article 17 compliant erase with audit
- **Epistemic Frontier** — Wilson score confidence intervals at 95%, information-gain ranking for uncertainty-driven exploration
- **Attention Engine** — proactive survey/triage/dispatch with autonomy override for multi-goal prioritization
- **Q-Value Retrieval** — outcome-weighted ranking; nodes that led to successful actions rank higher
- **Goal Graph** — durable intent tracking with status/progress lifecycle, coverage-driven routing (act/learn/escalate)
- **Graph Algorithms** — Dijkstra shortest path, DAG detection + toposort, Hopcroft-Karp bipartite matching, Louvain community detection, incremental SCC, triangle counting + clustering coefficient
- **Multi-Timescale Memory** — 4-tier decay (fast/medium/slow/glacial) with access-frequency promotion
- **8-Stage Consolidation** — prune weak edges, strengthen co-activated, merge similar, promote timescale, generate abstractions, detect contradictions
- **768D Neural Embeddings** — nomic-embed-text-v2-moe (500M params) with cross-encoder reranking, BM25+neural hybrid retrieval
- **Multi-Agent Scoping** — `agent_id` metadata for per-agent attribution with cross-agent discovery

---

## For Maintainers

### Local development

```sh
source .envrc  # sets LD_LIBRARY_PATH for CUDA/EXLA
MIX_ENV=test mix deps.get
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix test --color
```

### Source fallback run (no npm)

```sh
cd graphonomous
mix deps.get
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix release --overwrite
_build/prod/rel/graphonomous/bin/graphonomous eval "Graphonomous.CLI.main(System.argv())" --help
```

### npm package pre-publish smoke test

```sh
cd graphonomous/npm
npm pack
mkdir -p /tmp/graphonomous-npm-smoke && cd /tmp/graphonomous-npm-smoke
npm init -y
npm i /path/to/graphonomous/npm/graphonomous-0.4.0.tgz
npx graphonomous --help
```

### Release + publish flow

1. Ensure versions align (`mix.exs`, `npm/package.json`, git tag `vX.Y.Z`).
2. Build release assets locally and upload to GitHub Release `vX.Y.Z`.
3. Run `npm publish` from `graphonomous/npm`.
4. Verify: `npm view graphonomous version` and `npx -y graphonomous --help`.

See `docs/NPM_PUBLISH.md` for the full operational runbook.

---

## Architecture

### Supervised OTP services

- `Graphonomous.Store` — SQLite persistence
- `Graphonomous.Embedder` — neural embedding (EXLA/ONNX/fallback)
- `Graphonomous.Graph` — knowledge graph operations
- `Graphonomous.Retriever` — κ-aware retrieval with cross-encoder reranking
- `Graphonomous.Orchestrator` — stability-plasticity monitoring, adaptive learning rates
- `Graphonomous.Learner` — outcome and feedback processing
- `Graphonomous.GoalGraph` — durable intent lifecycle
- `Graphonomous.Consolidator` — 8-stage idle-time memory maintenance

### MCP server

- **Transport:** stdio (default) or streamable HTTP (`--transport streamable_http --port 4100`)
- **v2 surface (default):** 5 machines in `lib/graphonomous/mcp/machines/` — each is an `Anubis.Server.Component` with `schema do` parameter validation and `execute/2` dispatch
- **v1 surface (backward compat):** 29 individual tools in `lib/graphonomous/mcp/`
- **Resources:** 5 read-only resources in `lib/graphonomous/mcp/resources/`

### Storage

- SQLite tables: `nodes`, `edges`, `outcomes`, `goals`
- Migration tracking: `schema_migrations`
- ETS hot cache with startup rebuild
- HNSW vector index for embedding similarity search

### Public API (direct module usage)

Primary module: `Graphonomous`

- Node graph: `store_node/1`, `get_node/1`, `list_nodes/1`, `update_node/2`, `delete_node/1`, `link_nodes/3`, `query_graph/1`
- Retrieval + learning: `retrieve_context/2`, `learn_from_outcome/1`
- GoalGraph: `create_goal/1`, `get_goal/1`, `list_goals/1`, `update_goal/2`, `delete_goal/1`, `transition_goal/3`, `link_goal_nodes/2`, `unlink_goal_nodes/2`, `set_goal_progress/2`, `review_goal/3`
- Coverage + ops: `evaluate_coverage/2`, `decide_coverage/2`, `run_consolidation_now/0`, `rebuild_cache/0`, `consolidator_info/0`, `health/0`
- Orchestrator: `orchestrator_info/0`, `current_learning_rate/0`, `recommend_timescale/1`

---

## Documentation

- `docs/index.md` — landing/navigation
- `docs/quickstart.md` — 2–5 minute setup
- `docs/architecture.md` — internals, OTP supervision, data model
- `docs/mcp-tools.md` — complete tool/parameter reference
- `docs/operations.md` — maintenance, consolidation, release workflow
- `docs/runtime-walkthrough.md` — retrieve → act → store → learn loop walkthrough
- `docs/BOOTSTRAP.md` — bootstrap + verification
- `docs/TECHNICAL_DOCUMENTATION.md` — deep-dive internals
- `docs/ZED.md` — Zed integration details
- `docs/NPM_PUBLISH.md` — npm publishing runbook
- `docs/skills/` — agent skills reference (18 files mirroring ampersand-plugins + SKILLS.md index)
- `docs/spec/README.md` — technical specification

Online: [docs.graphonomous.com](https://docs.graphonomous.com)

---

## Notes

- EXLA is optional — avoids environment-level NIF/CUDA mismatch issues. Use `--embedder-backend fallback` to skip entirely.
- sqlite-vec extension loading is optional.
- OpenSentience integration is **not required** to start using Graphonomous.
- MCP stdio reliability is ensured by a vendored `anubis_mcp` patch (`vendor/anubis_mcp`) that fixes STDIO transport handling.

---

## License

Apache-2.0
