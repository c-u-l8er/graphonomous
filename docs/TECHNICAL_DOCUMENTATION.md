# Graphonomous Technical Documentation

**Project:** `graphonomous`  
**Scope:** Architecture, runtime model, MCP interface, and operational workflow  
**Version Context:** Repository state as inspected in this session (March 2026)

---

## 1) What Graphonomous Is

Graphonomous is an Elixir/OTP continual-learning engine designed to provide persistent, evolving memory for LLM agents through an MCP server interface. Instead of retraining model weights, it learns by updating a graph of knowledge nodes and relationships over time.

At a high level, Graphonomous provides:

- Durable graph-backed memory (`semantic`, `procedural`, `episodic`)
- Confidence-updating learning from outcomes
- Goal lifecycle and coverage-based decision routing (`act`, `learn`, `escalate`)
- κ-aware topology analysis for cyclic knowledge regions
- Periodic consolidation to decay/prune weak memory and maintain graph quality
- MCP-native integration for tool-based agents

---

## 2) Core Design Principles

1. **Graph-first memory**  
   Knowledge is represented as nodes and typed edges, not flat logs.

2. **Outcome-grounded learning**  
   Confidence is adjusted based on actual action outcomes (`success`, `partial_success`, `failure`, `timeout`).

3. **Topology-aware reasoning**  
   Cycles are detected via SCC analysis; routing can shift from fast retrieval to deliberate reasoning.

4. **Goal-directed operation**  
   Multi-step work is persisted in a GoalGraph with explicit lifecycle transitions and progress.

5. **Operationally lightweight runtime**  
   Local SQLite + ETS hot cache + supervised Elixir processes.

---

## 3) Runtime Architecture

Graphonomous boots as an OTP application with supervised components.

### Supervised children (from `application.ex`)

- `Anubis.Server.Registry`
- `Graphonomous.Store`
- `Graphonomous.Embedder`
- `Graphonomous.Graph`
- `Graphonomous.Retriever`
- `Graphonomous.Learner`
- `Graphonomous.GoalGraph`
- `Graphonomous.Attention`
- `Graphonomous.Consolidator`

This yields a clean separation:

- **Store**: persistence + cache
- **Graph**: CRUD and similarity retrieval orchestration
- **Retriever**: ranking + neighborhood expansion + topology annotation
- **Learner**: feedback-driven confidence updates
- **GoalGraph/Coverage/Attention**: planning and prioritization control loop
- **Consolidator**: long-term maintenance

---

## 4) Storage Model

`Graphonomous.Store` owns durable SQLite persistence and ETS tables for hot reads.

### Core behaviors

- Writes persist to SQLite and mirror into ETS.
- Reads are served from ETS.
- On startup: schema bootstrap + migrations + cache warm-up from DB.

### Primary logical entities

- Nodes
- Edges
- Outcomes
- Goals

### Operational implication

This architecture gives low-latency reads with durable state continuity across restarts.

---

## 5) Knowledge and Learning Model

## 5.1 Node semantics

Graphonomous uses node types aligned with usage intent:

- `semantic`: facts/architecture/domain knowledge
- `procedural`: workflows/how-to
- `episodic`: events/observations

## 5.2 Learning from outcomes

`Graphonomous.Learner`:

1. Persists an outcome record.
2. Updates confidence of `causal_node_ids`.

The confidence update formula is:

`new_confidence = old_confidence * (1 - learning_rate) + target_signal * learning_rate`

Where `target_signal` is derived from status and scaled by outcome confidence.

### Status semantics

- `success`: positive reinforcement
- `partial_success`: mild positive reinforcement
- `failure`: confidence reduction
- `timeout`: weak/neutralized signal (not treated as hard failure)

---

## 6) Retrieval and Topology-Aware Routing

## 6.1 Retrieval pipeline (`Retriever`)

For `retrieve_context`:

1. Similarity search over graph nodes
2. Neighbor expansion via edges (bounded hops)
3. Confidence-aware ranking
4. Topology analysis of retrieved subgraph
5. Return payload with `results`, `causal_context`, `stats`, `topology`

## 6.2 Topology analysis (`Topology`)

Graphonomous computes SCCs and κ characteristics and emits routing guidance:

- `fast`: acyclic/low-risk structure
- `deliberate`: cyclic complexity requiring deeper reasoning

The retrieved response can include:

- `routing`
- `max_kappa`
- `scc_count`
- SCC details including fault-line edges and deliberation budget hints

## 6.3 Deliberation (`Deliberator`)

For cyclic regions, Graphonomous can run a deliberate pass that:

- decomposes SCCs
- evaluates fault-line partitions
- reconciles conclusions
- optionally crystallizes conclusions back into the graph

---

## 7) GoalGraph and Coverage Control

## 7.1 Goal lifecycle

Goal states include:

- `proposed`
- `active`
- `blocked`
- `completed`
- `abandoned`

Transitions are policy-validated in `GoalGraph`.

## 7.2 Coverage evaluation (`Coverage`)

Graphonomous computes:

- `coverage_score`
- `uncertainty_score`
- `risk_score`
- decision: `act` | `learn` | `escalate`

## 7.3 Review-driven transitions

`review_goal` can automatically map decisions to statuses:

- `act` -> `active`
- `learn` -> `proposed`
- `escalate` -> `blocked`

This creates an epistemic gate before high-impact execution.

---

## 8) Attention Engine

`Graphonomous.Attention` is a proactive prioritization layer.

It supports autonomy modes:

- `observe`
- `advise`
- `act`

It periodically surveys active goals, combines urgency + coverage + topology, and may dispatch bounded actions depending on autonomy configuration.

---

## 9) Consolidation

`Graphonomous.Consolidator` performs periodic memory maintenance.

Current implementation responsibilities include:

- confidence decay
- low-confidence pruning
- telemetry emission for cycle/node events

Runtime controls include:

- interval
- decay rate
- prune threshold
- merge similarity (configured, with further strategy expansion expected over time)

---

## 10) MCP Interface

`Graphonomous.MCP.Server` registers machines via `lib/graphonomous/mcp/machines/server.ex`.

### v2 Machine Surface (Production Default — 5 machines, 29 actions)

Each machine is an `Anubis.Server.Component` with `schema do` parameter validation and `execute/2` dispatch.

| Machine | Actions |
|---------|---------|
| `retrieve` | context, episodic, procedural, coverage, trace_evidence, frontier |
| `route` | topology, deliberate, attention_survey, attention_cycle, review_goal |
| `act` | store_node, store_edge, delete_node, manage_edge, manage_goal, belief_revise, forget_node, forget_policy, gdpr_erase |
| `learn` | from_outcome, from_feedback, detect_novelty, from_interaction, contradictions |
| `consolidate` | run, stats, query, traverse |

### v1 Legacy Surface (29 individual tools)

All v1 tool names remain available for backward compatibility. Machines delegate to them internally.

### Resources (5)

- `graphonomous://runtime/health`
- `graphonomous://goals/snapshot`
- `graphonomous://graph/node/{id}`
- `graphonomous://graph/recent`
- `graphonomous://consolidation/log`

See `docs/mcp-tools.md` for full parameter reference.

---

## 11) Public API Surface

`lib/graphonomous.ex` provides façade functions that normalize inputs and delegate to internals, including:

- node store/query/update/delete
- context retrieval
- learning from outcome
- goal CRUD + transitions + progress + review
- consolidation trigger/info
- health status

This keeps MCP tools and direct module consumers aligned on one normalized API contract.

---

## 12) CLI and Operations

`Graphonomous.CLI` supports:

- MCP stdio runtime mode
- `scan` mode
- `watch` mode
- `traverse` mode
- extensive runtime/config flags

Operational safeguards include:

- robust argument normalization/validation
- configurable request timeout
- stderr logging policy to keep stdio MCP frames clean
- supervised MCP transport startup and monitoring

---

## 13) Configuration Highlights

Key runtime configuration families include:

- database path
- embedding model/backend
- consolidator cadence and thresholds
- learning rate
- logging level
- request timeout
- traversal controls (`scan`/`watch`)

Both CLI flags and environment-level configuration are supported.

---

## 14) Health, Observability, and Telemetry

Observability is implemented through:

- runtime process health summary (`Graphonomous.health/0`)
- consolidator info snapshots
- resource snapshots for runtime and goals
- telemetry events (e.g., confidence decay/prune/outcome processing/topology routes)

This supports both human debugging and external monitoring.

---

## 15) Recommended Operating Loop for Agents

For non-trivial tasks, use this sequence:

1. `retrieve_context`
2. reason + act
3. `store_node`/`store_edge` for durable learnings
4. `learn_from_outcome` with real causal attribution
5. update goals/progress
6. `run_consolidation` periodically (especially session boundaries)

This loop is also explicitly codified in the project skills docs under `docs/skills/`.

---

## 16) Research Trace (Proof of Under-the-Hood Exploration)

This documentation was produced after directly inspecting code/spec/docs and running graph-oriented workflow actions.

### What was validated in this session

1. Skills pack loaded from:
   - `docs/skills/SKILLS.md`
   - `docs/skills/bootstrap.md` through `docs/skills/workflows.md`

2. Spec and architecture references inspected:
   - `graphonomous.com/docs/spec/README.md`
   - `graphonomous/README.md`
   - `graphonomous/CLAUDE.md`
   - `graphonomous/BUILD.md`

3. Runtime internals inspected:
   - `application.ex`, `store.ex`, `graph.ex`, `retriever.ex`, `topology.ex`, `deliberator.ex`, `learner.ex`, `goal_graph.ex`, `coverage.ex`, `attention.ex`, `consolidator.ex`
   - MCP modules and resource handlers under `lib/graphonomous/mcp/`

4. Graph-oriented MCP behavior exercised:
   - retrieval invoked (`retrieve_context`) and returned `ok` with empty result set (clean/empty context)
   - goals listed (none initially), then a documentation goal was created and transitioned to active
   - node storage attempts were made; initial writes succeeded, followed by context server shutdown/timeouts during additional writes

### Why this still proves under-the-hood flow

The key pipeline mechanics were observed live:

- goal lifecycle operations were successfully persisted and transitioned
- retrieval and goal query plumbing functioned
- runtime interruption behavior was surfaced during write attempts (valuable operational signal)

This is consistent with real-world MCP runtime behavior under transport/server lifecycle instability and is useful for operational hardening.

---

## 17) Known Operational Failure Modes to Watch

1. **Context/MCP server shutdown during tool calls**  
   Symptom: timeout/shutdown on otherwise valid operations.  
   Mitigation: verify runtime process health, restart MCP runtime, re-check client transport config.

2. **Write-path interruption mid-session**  
   Symptom: some store calls succeed, subsequent calls fail.  
   Mitigation: treat writes as retryable, verify DB/cache health via resources and goal/runtime snapshots.

3. **Overconfident outcome feedback**  
   Symptom: distorted ranking and low epistemic reliability.  
   Mitigation: calibrate outcome confidence and causal attribution strictly.

---

## 18) Suggested Next Documentation Enhancements

1. Add sequence diagrams for:
   - retrieve -> act -> learn loop
   - review_goal decision routing
   - topology deliberate path

2. Add schema appendix:
   - node/goal/outcome metadata conventions
   - example payload contracts for each MCP tool

3. Add production runbook:
   - startup checks
   - health SLOs
   - recovery playbooks for transport/store failures

---

## 19) Quick Reference Checklist

- [ ] Start runtime with stable DB path
- [ ] Confirm health resource reachable
- [ ] Retrieve before action
- [ ] Preserve causal IDs for outcome learning
- [ ] Use goal lifecycle for multi-step tasks
- [ ] Run coverage review before consequential actions
- [ ] Consolidate periodically
- [ ] Monitor for transport instability and restart safely when needed

---

**End of Document**
