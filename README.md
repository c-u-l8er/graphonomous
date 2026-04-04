# Graphonomous

Continual learning engine for AI agents, implemented as an Elixir OTP application with a durable SQLite-backed knowledge graph, confidence-updating learning loop, GoalGraph orchestration, κ-aware topology routing, and MCP tools/resources.

**v0.3.2** — Full spec compliance: 6 node types, 16 edge types, 8-stage consolidation pipeline, 28 MCP tools, 5 MCP resources. κ-aware topology routing, AGM-rational belief revision, intentional forgetting (soft/hard/cascade/GDPR), Wilson score epistemic frontier, Q-value outcome-weighted retrieval, and multi-agent scoping via `agent_id`. 309 tests, 0 failures.

> **TL;DR**
> - Install: `npm i -g graphonomous` or `npx -y graphonomous`
> - Use as an MCP server over stdio or HTTP
> - κ-aware topology routing ships out of the box — no configuration needed
> - 28 tools covering knowledge CRUD, retrieval, learning, belief revision, forgetting, goals, consolidation, and attention
> - Works with Claude Code, Zed, and any MCP-compatible client

---

## Always-On Agent Skills Wiring (Required)

To ensure Graphonomous MCP is used correctly **every chat**, this repo ships an always-on skills pack and bootstrap prompt.

### Skills pack location

- `docs/skills/SKILLS.md` (index)
- `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` (always-on bootstrap policy)
- `docs/skills/01_RETRIEVE_AND_REMEMBER.md`
- `docs/skills/02_LEARNING_LOOP.md`
- `docs/skills/03_GRAPH_INSPECTION.md`
- `docs/skills/04_GOAL_MANAGEMENT.md`
- `docs/skills/05_COVERAGE_AND_REVIEW.md`
- `docs/skills/06_TOPOLOGY_AND_DELIBERATION.md`
- `docs/skills/07_CONSOLIDATION.md`
- `docs/skills/08_ATTENTION.md`
- `docs/skills/09_WORKFLOWS.md`
- `docs/skills/10_ANTI_PATTERNS.md`

### Prompt injection guidance (system/developer context)

When configuring any agent/chat runtime, inject:

1. `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` (required)
2. `docs/skills/SKILLS.md` (required)
3. Relevant numbered skill files (or all files for general-purpose sessions)

Minimum acceptable wiring: bootstrap prompt + skills index.

### Repository wiring status

This repository already wires these policies into:

- `AGENTS.md`
- `CLAUDE.md`

That means local repo-aware agent sessions should default to a Graphonomous-first loop:
retrieve → reason/act → store → learn_from_outcome → consolidate.

## For Users (npm-first)

### 1) Install and run

Use whichever fits your workflow.

#### Option A — One-off run with `npx` (no global install)

```/dev/null/shell.sh#L1-5
npx -y graphonomous --help
npx -y graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
npx -y graphonomous scan ./docs --extensions .md,.txt
npx -y graphonomous watch ./docs --poll-interval-ms 1500 --ingest-on-start
```

#### Option B — Global install

```/dev/null/shell.sh#L1-6
npm i -g graphonomous
graphonomous --help
graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
graphonomous scan ./docs --extensions .md,.txt
graphonomous watch ./docs --poll-interval-ms 1500 --ingest-on-start
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

### 3b) Claude Code setup

Add to your project's `.mcp.json`:

```json
{
  “mcpServers”: {
    “graphonomous”: {
      “command”: “npx”,
      “args”: [“-y”, “graphonomous”, “--db”, “./.graphonomous/knowledge.db”, “--embedder-backend”, “fallback”]
    }
  }
}
```

Or if installed globally:

```json
{
  “mcpServers”: {
    “graphonomous”: {
      “command”: “graphonomous”,
      “args”: [“--db”, “./.graphonomous/knowledge.db”, “--embedder-backend”, “fallback”]
    }
  }
}
```

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

### 5) MCP tools (28 total)

**Knowledge graph write:**
- `store_node`, `store_edge`, `delete_node`, `manage_edge`

**Knowledge graph read/query:**
- `retrieve_context` — κ-aware ranked retrieval with topology annotations
- `query_graph` — operation-based graph inspection
- `topology_analyze` — SCC/κ analysis with routing recommendation
- `graph_traverse` — BFS walk with depth/relationship filters
- `graph_stats` — aggregate counts, distributions, confidence stats, orphan detection

**Specialized retrieval:**
- `retrieve_episodic` — time-range filtered episodic nodes
- `retrieve_procedural` — semantic search scoped to procedural nodes
- `coverage_query` — standalone epistemic coverage (act/learn/escalate)

**Belief revision (v0.3):**
- `belief_revise` — AGM-rational expand/revise/contract with contradiction detection
- `belief_contradictions` — find contradicting nodes by embedding similarity

**Intentional forgetting (v0.3):**
- `forget_node` — soft/hard/cascade forgetting modes
- `forget_by_policy` — budget-aware hybrid priority pruning with dry-run
- `gdpr_erase` — GDPR Article 17 compliant permanent deletion with audit

**Uncertainty quantification (v0.3):**
- `epistemic_frontier` — Wilson score intervals, information gain ranking

**Learning loop:**
- `learn_from_outcome` — causal confidence + Q-value updates
- `learn_from_feedback` — positive/negative/correction feedback
- `learn_detect_novelty` — similarity-based novelty scoring
- `learn_from_interaction` — full pipeline (novelty → store → extract → link)
- `deliberate` — κ-driven deliberation over cyclic regions

**Goal orchestration:**
- `manage_goal`, `review_goal`

**Maintenance & autonomy:**
- `run_consolidation`, `attention_survey`, `attention_run_cycle`

### MCP resources (5 read-only)

- `graphonomous://runtime/health` — runtime health + service status
- `graphonomous://goals/snapshot` — goal totals, status breakdown
- `graphonomous://graph/node/{id}` — individual node details + edges
- `graphonomous://graph/recent` — recently accessed/modified nodes
- `graphonomous://consolidation/log` — consolidator state + orchestrator plasticity metrics

---

### 6) Recommended laptop setting

Use:

- `--embedder-backend fallback`

This avoids heavyweight backend friction and is the quickest reliable starting point on constrained machines.

---

### 7) Common CLI flags

Command modes:

- `graphonomous` (start MCP server over stdio)
- `graphonomous --transport streamable_http --port 4100` (start MCP server over HTTP)
- `graphonomous scan <directory>` (one-shot traversal from scratch)
- `graphonomous watch <directory>` (continuous change detection + traversal)

Global options:

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

Filesystem traversal options (`scan` / `watch`):

- `--recursive`
- `--include-hidden`
- `--follow-symlinks`
- `--extensions .ex,.md,.txt`
- `--poll-interval-ms MS`
- `--ingest-on-start`
- `--max-file-size-bytes N`
- `--max-read-bytes N`

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
npm i /home/travis/ProjectAmp2/graphonomous/npm/graphonomous-0.3.2.tgz
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
- `Graphonomous.Orchestrator` — stability-plasticity monitoring, adaptive learning rates
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
- Orchestrator: `orchestrator_info/0`, `current_learning_rate/0`, `recommend_timescale/1`

---

### Documentation map

- `docs/BOOTSTRAP.md` — bootstrap + verification
- `docs/ZED.md` — Zed integration details
- `docs/NPM_PUBLISH.md` — npm publishing and maintenance runbook
- `docs/skills/` — always-on Graphonomous agent skills pack and bootstrap prompt
- `npm/README.md` — npm wrapper package usage and overrides

---

## Notes

- EXLA is currently optional to avoid environment-level NIF/CUDA mismatch issues.
- sqlite-vec extension loading is optional.
- OpenSentience integration is **not required** to start using Graphonomous.
- MCP stdio reliability is currently ensured by a vendored `anubis_mcp` dependency patch (`vendor/anubis_mcp`) that fixes decoded message list handling and request-response writes in the STDIO transport path.

---

## License

Apache-2.0
