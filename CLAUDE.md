# Graphonomous — CLAUDE Instructions

This file defines how Claude (and Claude-driven agents) must operate in this repository.

## Status — read first (2026-09-27)

This repository holds three things. Know which one you are touching.

| Path | What | State |
|---|---|---|
| `lib/`, `mix.exs`, `npm/`, `docs/spec/README.md` | **v1** — the Elixir/OTP memory engine + MCP server + npm package, v0.4.3 | **LEGACY.** Its plugin is disabled; do not run its memory loop |
| `v2/` | **v2** — the certified semantic/evidence graph (G0/G1) | the active lane; read `v2/handoff/STATUS.md` first, then `v2/handoff/ROADMAP.md` |
| `docs/spec/v3/README.md` | **Graphonomous v3** — the proposal for a carried memory built on v2 | **CLOSED 2026-09-28 (D-078): there is no Graphonomous v3.** Tested by V3-1 (`v3-bench/`) and not justified; a record, not a direction. Its survivors are in `v2/handoff/ROADMAP.md` |

**D-078 (Travis, 2026-09-28):** Graphonomous stays v2 — *a derived semantic graph over sources it does not
own*. It gains the memory folder and the ruling register as sources, and only authored relations. When a
relation is uncertain, it abstains or queues the pair for review. Recall is BM25 (`scripts/memory-search.py`
in the root repository), outside Graphonomous. Do not build any of the following:
- a Graphonomous memory store;
- a recall daemon;
- a journal;
- model-mediated recall;
- a model in the relation-emission path.

Do not renumber v2 as v3 for gaining features.

**D-079 (Travis, 2026-09-28) — the source boundary. Read it before writing any adapter:**
- **This repository is PUBLIC.** Anything derived from a private source goes in `~/.graphonomous/v2/`, never
  here (SB-1). That covers projections, indexes, evidence, review candidates, UI payloads and quoting
  receipts.
- **Authority is per record**, never per family and never by ingestion order (SB-2).
- **A model's or reviewer's relation is a candidate** until an authorized source records it (SB-3).
- **Secret-shaped text is refused at intake** (SB-4).
- **Source order:** WRL → ruling register → memory folder.

**The "Graphonomous-first memory loop" is OFF — ruled by Travis 2026-09-27.** This file's Primary
Directive and its sections 1–12 used to tell every session to run retrieve → route → act → learn →
consolidate through this engine's MCP server. Do not restore them, and do not call
`mcp__plugin_graphonomous_graphonomous__*`. The retired text is `git show 61adec2d:CLAUDE.md`; the skills it
loaded are still in `docs/skills/`.

**Why:** the v1 engine was deleting everything it stored. The consolidator (`config/config.exs`,
`lib/graphonomous/consolidator.ex`) runs every 5 minutes, decays every node's confidence by 2 % and
hard-deletes below 0.1, so a node stored at 0.5 is gone in about 7 hours; `~/.graphonomous/knowledge.db`
held **0 nodes** on 2026-09-27. The plugin also started one server per open session (29 at once, ≈ 1.6 GB),
each loading its own cache and running its own consolidator. The measurements and the direction are in
`docs/spec/v3/README.md` §1.1 and §6.

**Name trap:** section 3's "v2 Machine Surface" and "v1 Legacy Surface" are two generations of the **v1
engine's** MCP tool surface — not Graphonomous v2 (`v2/`), and neither is Graphonomous v3.

**Two disciplines survive the old policy:** never fabricate provenance, outcomes, causal links or coverage
signals; never state confidence the evidence does not carry.

---

## 1) Project Constraints (v1 — keep intact while v1 is maintained)

- Source of truth:
  - `docs/spec/README.md`
  - `../AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md`
- Keep vendored MCP dependency approach in `vendor/anubis_mcp`
- EXLA is now included for fast neural embeddings (~87ms vs 20s on BinaryBackend)
  - Requires `LD_LIBRARY_PATH=/opt/cuda/lib64` at runtime (see `.envrc`)
  - If EXLA fails to load, embedder gracefully falls back to deterministic hashing
  - Set `GRAPHONOMOUS_EMBEDDER_BACKEND=fallback` to skip EXLA entirely
- Keep raw SQL + parameterized writes model
- Keep version synchronization across:
  - `mix.exs`
  - `npm/package.json`
  - git tag `vX.Y.Z`

---

## 2) Build and Run (v1 reference)

```sh
source .envrc  # sets LD_LIBRARY_PATH for CUDA/EXLA
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
# Neural embeddings (default, requires EXLA):
mix run --no-halt -- --db ~/.graphonomous/knowledge.db
# Fallback mode (no EXLA needed):
mix run --no-halt -- --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

---

## 3) Core MCP Surface (v1 reference)

### v2 Machine Surface (Production Default — 5 tools)

The v2 server groups 29 tools into 5 loop-phase machines. Each accepts an `action` parameter.

**`retrieve`** — "What do I know?"
- `context` (κ-aware ranked retrieval), `episodic`, `procedural`, `coverage`, `trace_evidence`, `frontier`

**`route`** — "What should I do?"
- `topology` (SCC/κ analysis), `deliberate`, `attention_survey`, `attention_cycle`, `review_goal`

**`act`** — "Do it"
- `store_node`, `store_edge`, `delete_node`, `manage_edge`, `manage_goal`, `belief_revise`, `forget_node`, `forget_policy`, `gdpr_erase`

**`learn`** — "Did it work?"
- `from_outcome`, `from_feedback`, `detect_novelty`, `from_interaction`, `contradictions`

**`consolidate`** — "Clean up"
- `run`, `stats`, `query`, `traverse`

### v1 Legacy Surface (29 individual tools)

The v1 tools remain available for backward compatibility. Machines delegate to them internally.

Knowledge graph write: `store_node`, `store_edge`, `delete_node`, `manage_edge`
Graph read/query: `retrieve_context`, `query_graph`, `topology_analyze`, `graph_traverse`, `graph_stats`
Specialized retrieval: `retrieve_episodic`, `retrieve_procedural`, `coverage_query`
Graph algorithms: `trace_evidence_path`, `epistemic_frontier`
Learning: `learn_from_outcome`, `learn_from_feedback`, `learn_detect_novelty`, `learn_from_interaction`
Belief: `belief_revise`, `belief_contradictions`
Deliberation: `deliberate`
Goals: `manage_goal`, `review_goal`
Attention: `attention_survey`, `attention_run_cycle`
Forgetting: `forget_node`, `forget_by_policy`, `gdpr_erase`
Maintenance: `run_consolidation`

### Resources (shared across v1/v2)

- `graphonomous://runtime/health`
- `graphonomous://goals/snapshot`
- `graphonomous://graph/node/{id}` — individual node details + edges
- `graphonomous://graph/recent` — recently accessed nodes
- `graphonomous://consolidation/log` — consolidator state + orchestrator metrics

### Dual-Loop Architecture

When PRISM benchmarks Graphonomous, the loops interlock (5 + 6 = 11 tools total, down from 76):

```
PRISM: compose → interact → observe → reflect → diagnose  (+ config)
                     │
                     ▼
Graphonomous: retrieve → route → act → learn → consolidate
```

See `AmpersandBoxDesign/prompts/DUAL_LOOP_MACHINES.md` for the full architecture.
