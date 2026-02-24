# Graphonomous

Continual learning engine for AI agents, implemented as an Elixir OTP application with a durable SQLite-backed knowledge graph, confidence-updating learning loop, GoalGraph orchestration, and MCP tools/resources.

## Status

- **Phase:** Foundation + Core CL Engine + GoalGraph/Coverage + MCP resources + grounding fidelity + migration/versioning hardening
- **Build/Test:** ✅ Compiling and testable
- **Current test suite:** ✅ `31 tests, 0 failures`

---

## What Graphonomous Does

Graphonomous provides a closed-loop memory and learning system:

1. **Store knowledge** as graph nodes/edges.
2. **Retrieve context** by semantic similarity + graph neighborhood expansion.
3. **Execute actions externally** (via your agent/client).
4. **Learn from outcomes** by updating confidence of causal nodes.
5. **Persist intent** with durable goals (GoalGraph).
6. **Review epistemic coverage** (`act | learn | escalate`) before action.
7. **Consolidate memories** on schedule or on demand.

---

## Architecture

### Supervised Runtime Services

- `Graphonomous.Store` — SQLite schema/bootstrap, persistence, ETS hot cache, cache rebuild
- `Graphonomous.Embedder` — embedding backend orchestration
- `Graphonomous.Graph` — node/edge operations, graph query surface
- `Graphonomous.Retriever` — ranked retrieval + neighborhood expansion
- `Graphonomous.Learner` — outcome ingestion, confidence updates, grounding trace handling
- `Graphonomous.GoalGraph` — durable goal lifecycle + linked nodes + review metadata
- `Graphonomous.Consolidator` — decay/prune/merge cycle runner

### Data Model (Implemented)

- **Nodes**: `episodic | semantic | procedural` (current typed set)
- **Edges**: typed relationships with weights
- **Outcomes**: status, confidence, causal node ids, evidence, and grounding trace fields
- **Goals**: durable lifecycle state, priority, timescale, progress, linkage, metadata

### Storage

- SQLite tables: `nodes`, `edges`, `outcomes`, `goals`
- Migration tracking table: `schema_migrations`
- Startup cache warm/rebuild from SQLite into ETS for fast reads + restart consistency
- Core writes and delete paths use prepared/parameterized SQL execution

---

## MCP Surface

### Tools

- `store_node`
- `retrieve_context`
- `learn_from_outcome`
- `query_graph`
- `manage_goal`
- `review_goal`
- `run_consolidation`

### Resources (read-only)

- `graphonomous://runtime/health`
- `graphonomous://goals/snapshot`

---

## Public API

The `Graphonomous` module is the primary API entrypoint for direct calls and MCP tool delegation.

Key functions include:

- Node graph:
  - `store_node/1`
  - `get_node/1`
  - `list_nodes/1`
  - `update_node/2`
  - `delete_node/1`
  - `link_nodes/3`
  - `query_graph/1`
- Retrieval + learning:
  - `retrieve_context/2`
  - `learn_from_outcome/1`
- GoalGraph:
  - `create_goal/1`
  - `get_goal/1`
  - `list_goals/1`
  - `update_goal/2`
  - `delete_goal/1`
  - `transition_goal/3`
  - `link_goal_nodes/2`
  - `unlink_goal_nodes/2`
  - `set_goal_progress/2`
  - `review_goal/3`
- Coverage + operations:
  - `evaluate_coverage/2`
  - `decide_coverage/2`
  - `run_consolidation_now/0`
  - `rebuild_cache/0`
  - `consolidator_info/0`
  - `health/0`

---

## Project Structure

- `lib/graphonomous/`
  - `application.ex` (supervision tree)
  - `store.ex` (SQLite + cache + migrations)
  - `graph.ex`, `retriever.ex`, `learner.ex`, `goal_graph.ex`, `consolidator.ex`, `coverage.ex`
  - `mcp/` (server, tools, resources)
  - `types/` (`node`, `edge`, `outcome`, `goal`)
- `config/`
  - `config.exs`, `dev.exs`, `test.exs`, `prod.exs`, `runtime.exs`
- `test/`
  - store/graph/retriever/learner/goal/coverage/MCP integration tests
- `docs/`
  - `BOOTSTRAP.md` (reproducible local bootstrap + verification)
- `.github/workflows/`
  - `ci.yml` (format + compile + test)

---

## Quick Start

From `ProjectAmp2/graphonomous`:

    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test

Expected: all checks pass.

---

## Runtime Configuration

Environment-driven runtime settings are handled in `config/runtime.exs`.

### Core env vars

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

    export GRAPHONOMOUS_DB_PATH="tmp/graphonomous_local.db"
    export GRAPHONOMOUS_EMBEDDER_BACKEND="fallback"
    export LOG_LEVEL="debug"

---

## Verification

### Fast local verification

    MIX_ENV=test mix deps.get
    MIX_ENV=test mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    MIX_ENV=test mix test --color

### Store/migration verification

    mix test test/store_test.exs

Includes assertions for:
- persistence flows
- cache rebuild
- grounding trace persistence
- migration bookkeeping in `schema_migrations`

---

## CI

GitHub Actions workflow (`.github/workflows/ci.yml`) runs:

1. `mix deps.get`
2. `mix format --check-formatted`
3. `mix compile --warnings-as-errors`
4. `mix test --color`

---

## Notes

- EXLA is intentionally optional right now to avoid environment-level NIF/CUDA mismatch issues.
- sqlite-vec extension loading is optional and can be configured via environment variable.
- For deeper setup and reproducible bootstrap steps, use `docs/BOOTSTRAP.md`.

---

## License

Internal project (no public license declared in this repository yet).