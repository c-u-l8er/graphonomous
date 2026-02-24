# Graphonomous Local Bootstrap & Verification Guide

This guide gives you a reproducible way to bootstrap, run, and verify `graphonomous` on a local machine.

---

## 1) Prerequisites

Use the same toolchain as CI for consistency:

- **Erlang/OTP**: `27.1`
- **Elixir**: `1.17.3`
- **Mix**: comes with Elixir
- **OS**: Linux/macOS (Windows via WSL recommended)

Optional but useful:

- `git`
- `sqlite3` CLI (for inspecting DB files manually)

---

## 2) Quick Start (5-minute path)

From the `ProjectAmp2` root:

    cd graphonomous
    mix deps.get
    mix format
    mix compile --warnings-as-errors
    mix test
    MIX_ENV=prod mix escript.build

Expected result:

- Compile succeeds
- Test suite passes (currently `31 tests, 0 failures`)
- Executable `./graphonomous` is generated for standard MCP client launch

---

## 3) Clean Reproducible Bootstrap (from scratch)

If you want a deterministic “fresh machine” style run:

    cd graphonomous
    rm -rf _build deps
    rm -f tmp/graphonomous_test.db
    rm -f priv/graphonomous_dev.db
    mix local.hex --force
    mix local.rebar --force
    mix deps.get
    MIX_ENV=test mix compile --warnings-as-errors
    MIX_ENV=test mix test

Why this works:
- Removes compiled artifacts and dependency cache
- Rebuilds from declared dependencies in `mix.exs` + `mix.lock`
- Verifies code quality and runtime behavior in test mode

---

## 4) Runtime Configuration Matrix

Runtime config is controlled via environment variables in `config/runtime.exs`.

### Core variables

- `GRAPHONOMOUS_DB_PATH`  
  Default: `priv/graphonomous.db`
- `GRAPHONOMOUS_EMBEDDING_MODEL`  
  Default: `sentence-transformers/all-MiniLM-L6-v2`
- `GRAPHONOMOUS_EMBEDDER_BACKEND`  
  Allowed: `auto | fallback`  
  Default: `auto`
- `GRAPHONOMOUS_SQLITE_VEC_EXTENSION_PATH`  
  Optional path to sqlite-vec extension
- `GRAPHONOMOUS_CONSOLIDATOR_INTERVAL_MS`  
  Default: `300000`
- `GRAPHONOMOUS_CONSOLIDATOR_DECAY_RATE`  
  Default: `0.02`
- `GRAPHONOMOUS_CONSOLIDATOR_PRUNE_THRESHOLD`  
  Default: `0.1`
- `GRAPHONOMOUS_CONSOLIDATOR_MERGE_SIMILARITY`  
  Default: `0.95`
- `GRAPHONOMOUS_LEARNING_RATE`  
  Default: `0.2`
- `LOG_LEVEL`  
  Allowed: `debug | info | warning | error`  
  Default: `info`

### Example (safe local dev profile)

    export GRAPHONOMOUS_DB_PATH="tmp/graphonomous_local.db"
    export GRAPHONOMOUS_EMBEDDER_BACKEND="fallback"
    export LOG_LEVEL="debug"

### MCP Executable Build + Standard Client Command Configuration

Build the executable command once:

    MIX_ENV=prod mix escript.build

Run directly (STDIO transport):

    ./graphonomous --db ~/.graphonomous/knowledge.db

If you install/copy it onto PATH, use:

    graphonomous --db ~/.graphonomous/knowledge.db

Standard MCP client configuration shape:

    {
      "mcpServers": {
        "graphonomous": {
          "command": "graphonomous",
          "args": ["--db", "~/.graphonomous/knowledge.db"],
          "env": {
            "GRAPHONOMOUS_EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2"
          }
        }
      }
    }

---

## 5) Functional Verification in IEx

Start the app:

    iex -S mix

Run these checks in IEx:

    Graphonomous.health()
    Graphonomous.store_node(%{
      content: "Hydraulic pressure error E-47 often indicates seal wear.",
      node_type: "semantic",
      confidence: 0.82,
      source: "bootstrap_manual"
    })
    Graphonomous.retrieve_context("What causes E-47 hydraulic pressure faults?", limit: 3)

What to verify:

- `Graphonomous.health/0` reports services as `:up`
- `store_node/1` returns a node struct/map with an `id`
- `retrieve_context/2` returns relevant node results

---

## 6) Store & Migration Verification

The store auto-creates schema and applies tracked migrations at startup.

To verify via tests:

    mix test test/store_test.exs

Coverage includes:
- node/edge/outcome persistence
- cache rebuild from SQLite
- grounding trace persistence
- migration bookkeeping (`schema_migrations` records applied IDs)

---

## 7) CI Parity Commands (run exactly what CI expects)

    MIX_ENV=test mix deps.get
    MIX_ENV=test mix format --check-formatted
    MIX_ENV=test mix compile --warnings-as-errors
    MIX_ENV=test mix test --color

If all pass locally, your branch should be CI-ready.

---

## 8) Common Issues & Fixes

### A) `sqlite_vec` / extension loading issues
If vector extension loading fails, keep going with:
- `GRAPHONOMOUS_EMBEDDER_BACKEND=fallback`
- omit `GRAPHONOMOUS_SQLITE_VEC_EXTENSION_PATH` unless you have a valid extension binary

### B) Embedding model download/runtime constraints
If model/NIF/runtime setup is constrained:
- set `GRAPHONOMOUS_EMBEDDER_BACKEND=fallback`
- rerun compile/test

### C) Logger warning about session store adapter during tests
A warning like session-store adapter availability may appear in test output; tests can still pass. Treat as non-blocking unless behavior fails.

### D) Stale local DB state causing confusing results
Reset local state:

    rm -f tmp/graphonomous_test.db priv/graphonomous_dev.db priv/graphonomous.db
    mix test

---

## 9) Release-Hardening Checklist (Local)

Before merging/releasing, verify:

- [ ] `mix format --check-formatted` passes
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes
- [ ] runtime env vars documented for your deployment
- [ ] DB path is explicit for your environment
- [ ] fallback embedder behavior understood for constrained runtimes
- [ ] migration table (`schema_migrations`) present after boot

---

## 10) One-Command Local Verification Script (optional)

You can use this command sequence for a quick confidence run (including MCP executable build):

    rm -rf _build deps &&
    rm -f tmp/graphonomous_test.db &&
    mix deps.get &&
    MIX_ENV=test mix format --check-formatted &&
    MIX_ENV=test mix compile --warnings-as-errors &&
    MIX_ENV=test mix test &&
    MIX_ENV=prod mix escript.build

If this completes successfully, your local environment is reproducible, verified, and ready for standard MCP command launch via `./graphonomous`.