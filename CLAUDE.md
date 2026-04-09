# Graphonomous — CLAUDE Instructions

This file defines how Claude (and Claude-driven agents) must operate in this repository.

## Primary Directive

Use Graphonomous as an **always-on memory + learning loop** in every non-trivial chat.

Adopt this internal policy at session start:

**“Graphonomous-first memory loop is active.”**

---

## 1) Mandatory Skills Pack (Load First)

Skills live in the [ampersand-plugins](https://github.com/c-u-l8er/ampersand-plugins) repo as Claude Code skills. Reference docs are mirrored in `docs/skills/`.

Before doing meaningful work, load and follow these files:

1. `docs/skills/SKILLS.md` (index + machine architecture)
2. `docs/skills/bootstrap.md` (session initialization)
3. `docs/skills/retrieve.md` (foundational read/write loop)
4. `docs/skills/learn.md` (closed-loop learning)
5. `docs/skills/deliberate.md` (κ-aware routing)
6. `docs/skills/consolidate.md` (memory maintenance)
7. `docs/skills/goals.md` (durable intent tracking)
8. `docs/skills/attention.md` (autonomous focus)
9. `docs/skills/workflows.md` (end-to-end recipes)

Extended skills (load for complex sessions): `store.md`, `belief.md`, `forgetting.md`, `epistemic-frontier.md`, `trace-evidence-path.md`, `review.md`, `inspect.md`, `graph-health.md`, `sync.md`, `watch.md`

If some files are unavailable, proceed with best effort and explicitly lower certainty.

---

## 2) Always-On Default Loop

For non-trivial user requests, run the 5-machine loop:

1. **Retrieve** — `retrieve(action: "context", query: "...")` before reasoning/acting
2. **Route** — check `topology.routing`; if `"deliberate"`, run `route(action: "deliberate", ...)`
3. **Act** — `act(action: "store_node", ...)` to mutate the graph
4. **Learn** — `learn(action: "from_outcome", ...)` when outcome signal exists
5. **Consolidate** — `consolidate(action: "run")` periodically and at session end

Do not routinely skip retrieval on domain-heavy tasks.

---

## 3) Session Start Protocol (Every Chat)

At start of chat (or major topic switch):

1. Retrieve context for user topic/history
2. Check goals state (active/proposed/blocked as needed)
3. Optionally survey attention if multiple goals exist
4. Proceed grounded in retrieved memory

---

## 4) Node / Edge Discipline

- Prefer **atomic nodes** (one claim/procedure/event per node).
- Node types:
  - `semantic` = facts/architecture
  - `procedural` = workflows/how-to
  - `episodic` = observed events/outcomes
- Include `source` whenever possible.
- Confidence must reflect evidence quality (no blanket high confidence).
- Create edges only when they improve retrieval/provenance:
  `causal`, `supports`, `contradicts`, `related`, `derived_from`.

---

## 5) Outcome Learning Discipline

When action used retrieved context:

- Preserve retrieval causal IDs.
- Feed only true causal IDs into `learn_from_outcome`.
- Use status exactly: `success`, `partial_success`, `failure`, `timeout`.
- `timeout` is not `failure`.
- Include structured evidence when practical.

No fabricated outcome signals. No fabricated causal attribution.

---

## 6) Goal Discipline (Multi-Step Work)

For tasks spanning multiple turns:

- Create/manage goals
- Link supporting nodes to goals
- Update progress incrementally with evidence
- Review coverage at decision points (`review_goal`)
- Follow decision routing:
  - `act` -> continue execution
  - `learn` -> gather more context
  - `escalate` -> block/escalate appropriately

---

## 7) Topology / Deliberation Discipline

- Read topology signals on retrieval responses.
- If routing is deliberate (κ > 0), use `topology_analyze` / `deliberate` for high-stakes decisions.
- Avoid unnecessary deliberation when routing is fast.

---

## 8) Attention Discipline

When many goals are in flight:

- Use `attention_survey` (and optionally `attention_run_cycle`) to prioritize.
- Respect dispatch mode: `act`, `learn`, `escalate`, `idle`.
- Prefer observe/advise posture unless autonomous action is explicitly desired.

---

## 9) Consolidation Discipline

Trigger consolidation:

- At productive session boundaries
- Periodically during long iterative runs
- After heavy storage/learning bursts

Use status outputs to monitor memory quality trends.

---

## 10) Hard Prohibitions

Never:

- Skip retrieval habitually
- Skip outcome learning on consequential actions
- Inflate confidence indiscriminately
- Store kitchen-sink nodes
- Fabricate coverage signals/causal links
- Ignore repeated `learn` / `escalate` outcomes
- Create edge spaghetti
- Neglect consolidation indefinitely

---

## 11) Prompt Wiring Requirement (For Claude Runtimes)

Any Claude system/developer prompt for this repo should include:

- `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` (required)
- `docs/skills/SKILLS.md` (required)
- Relevant numbered skill files (or all for general-purpose use)

Minimum acceptable wiring: bootstrap prompt + skills index.

---

## 12) End-of-Session Behavior

Before ending a productive session:

1. Store key new facts/procedures/events
2. Report pending outcomes
3. Update goals/progress/state
4. Trigger consolidation (status when practical)

---

## 13) Project Constraints (Keep Intact)

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

## 14) Build and Run (Reference)

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

## 15) Core MCP Surface (Reference)

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
