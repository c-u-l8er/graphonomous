# Graphonomous

Continual learning engine for AI agents. Elixir/OTP application with SQLite-backed knowledge graph, confidence-updating learning loop, GoalGraph orchestration, and MCP server over stdio.

## Source-of-truth spec

The authoritative spec for this codebase lives outside this directory:
- `../graphonomous.com/project_spec/README.md` — full technical spec (architecture, schema, MCP design, learning pipeline, etc.)
- `../AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md` — autonomous traversal prompt for Graphonomous MCP
- `PROGRESS.md` — implementation progress tracker with traceability map (spec section -> status)

When implementing new features or fixing gaps, check the spec first. PROGRESS.md tracks which spec sections are implemented vs pending.

## Build and verify

```
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

31 tests, 0 failures as of last known state.

## Run locally

```
# MCP server over stdio (fallback embedder for dev)
mix run --no-halt -- --db ~/.graphonomous/knowledge.db --embedder-backend fallback

# Or via escript
mix escript.build
./graphonomous --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

## Release and publish

```
# Build OTP release
MIX_ENV=prod mix release --overwrite

# npm publish (see BUILD.md for full runbook)
cd npm && npm publish
```

Version must match in: `mix.exs`, `npm/package.json`, and git tag `vX.Y.Z`.

## Architecture

OTP supervision tree with these GenServers:
- `Store` — SQLite persistence + ETS hot cache + schema migrations
- `Embedder` — local embeddings via Bumblebee (sentence-transformers/all-MiniLM-L6-v2)
- `Graph` — similarity retrieval, node/edge operations
- `Retriever` — confidence-weighted ranking + neighborhood expansion
- `Learner` — outcome-driven confidence updates with grounding traces
- `GoalGraph` — durable goal lifecycle with dependency tracking
- `Consolidator` — periodic decay + prune + merge (sleep-cycle inspired)

Storage: SQLite tables `nodes`, `edges`, `outcomes`, `goals`, `schema_migrations`. ETS cache rebuilt from SQLite on startup.

## MCP tools

`store_node`, `retrieve_context`, `learn_from_outcome`, `query_graph`, `manage_goal`, `review_goal`, `run_consolidation`

MCP resources: `graphonomous://runtime/health`, `graphonomous://goals/snapshot`

## Key decisions

- EXLA intentionally excluded — NIF/CUDA mismatch blocks boot on some machines
- MCP uses vendored `vendor/anubis_mcp` with patched stdio transport — do not replace with upstream
- Raw SQL via `exqlite` (no Ecto) — matches edge-first SQLite design
- ETS-first read path for fast local operations

## File layout

- `lib/graphonomous/` — all modules (store, graph, learner, embedder, etc.)
- `lib/graphonomous/mcp/` — MCP server + tool handlers
- `lib/graphonomous/types/` — Node, Edge, Outcome, Goal structs
- `vendor/anubis_mcp/` — vendored MCP dependency
- `npm/` — npm wrapper package for global distribution
- `scripts/` — helper scripts (MCP wrapper for Zed)
- `docs/` — BOOTSTRAP.md, ZED.md, NPM_PUBLISH.md
