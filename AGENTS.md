# Graphonomous

Elixir/OTP continual learning engine with MCP server. SQLite-backed knowledge graph with confidence-updating learning loop and GoalGraph orchestration.

## Source-of-truth spec

- `../graphonomous.com/project_spec/README.md` — authoritative technical spec for this engine
- `../AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md` — autonomous traversal prompt
- `PROGRESS.md` — tracks spec section implementation status

Always check the spec before implementing new features or fixing gaps.

## Build and test

```
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

## Run MCP server locally

```
mix run --no-halt -- --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

## Key constraints

- Elixir ~> 1.17 required
- EXLA is intentionally excluded (NIF/CUDA issues) — do not add it
- MCP dependency is vendored at `vendor/anubis_mcp` with stdio transport patches — do not replace with upstream anubis_mcp
- Raw SQL via `exqlite`, no Ecto — this is intentional for the edge-first SQLite design
- All SQL writes use parameterized prepared statements (security requirement)
- Version must stay in sync across `mix.exs`, `npm/package.json`, and git tags

## Architecture

OTP supervision tree: Store, Embedder, Graph, Retriever, Learner, GoalGraph, Consolidator.

Storage: SQLite (`nodes`, `edges`, `outcomes`, `goals`, `schema_migrations`) + ETS hot cache.

MCP tools: `store_node`, `retrieve_context`, `learn_from_outcome`, `query_graph`, `manage_goal`, `review_goal`, `run_consolidation`

## File layout

- `lib/graphonomous/` — core modules
- `lib/graphonomous/mcp/` — MCP server and tool handlers
- `lib/graphonomous/types/` — domain structs
- `vendor/anubis_mcp/` — vendored MCP (do not delete)
- `npm/` — npm wrapper package
- `docs/` — operational docs (BOOTSTRAP, ZED, NPM_PUBLISH)
