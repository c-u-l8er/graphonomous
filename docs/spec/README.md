# Graphonomous — Continual Learning Engine
## Technical Specification v0.4

**Date:** April 9, 2026
**Status:** Release Candidate  
**Author:** [&] Ampersand Box Design  
**License:** MIT (open core)

---

## 1. Overview

Graphonomous is a **continual learning engine** that makes small language models (1B–8B parameters) smarter over time in their deployment context. It does this by maintaining a self-evolving knowledge graph alongside the model — learning, consolidating, and pruning at inference time — without retraining model weights, requiring cloud connectivity, or suffering catastrophic forgetting.

### 1.1 The Problem

Current LLM deployments are **frozen at training time**. The industry's answer — scaling context windows to millions of tokens — is buying around the problem with compute. An 8B model on a $500 edge device should be able to learn from its specific environment. Graphonomous makes that possible.

### 1.2 Design Principles

1. **Learn without retraining** — The base model is immutable. All learning happens in the graph.
2. **Edge-native** — Designed for constrained devices from day one. SQLite, not Postgres, is the default.
3. **Graph over vectors** — Structured relationships beat flat similarity search.
4. **Multi-timescale memory** — Fast (seconds), medium (hours), slow (days), glacial (months).
5. **Consolidation cycles** — Idle-time memory consolidation inspired by the brain's sleep cycles.
6. **MCP-first API** — Every capability is exposed as an MCP tool. No REST API needed unless you want one.
7. **Source-aware ingestion modes** — Support both full baseline traversal (`scan`) and continuous filesystem-aware traversal (`watch`) so knowledge stays synchronized with changing local directories.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       GRAPHONOMOUS                            │
│                  Continual Learning Engine                     │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│   MCP Server (Hermes)           Phoenix LiveView (optional)    │
│   ├── tools/graph_*             └── Admin dashboard            │
│   ├── tools/memory_*                                           │
│   ├── tools/learn_*                                            │
│   ├── resources://graph/*                                      │
│   └── resources://stats/*                                      │
│                                                                │
├──────────────────────────────────────────────────────────────┤
│                                                                │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐    │
│   │  Retriever    │  │  Learner     │  │  Consolidator    │    │
│   │              │  │              │  │                  │    │
│   │  Graph-aware  │  │  Gradient-   │  │  Sleep-cycle     │    │
│   │  context      │  │  free CL     │  │  consolidation   │    │
│   │  injection    │  │  from        │  │  during idle     │    │
│   │              │  │  inference   │  │  periods         │    │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────────┘    │
│          │                 │                  │                │
│   ┌──────▼─────────────────▼──────────────────▼───────────┐    │
│   │                   Knowledge Graph                      │    │
│   │                                                        │    │
│   │  Nodes: episodic | semantic | procedural | temporal    │    │
│   │  Edges: typed, weighted, decaying                      │    │
│   │  Indexes: embedding (HNSW), temporal, type             │    │
│   └────────────────────────┬───────────────────────────────┘    │
│                            │                                   │
├────────────────────────────┼───────────────────────────────────┤
│   Storage Layer            │                                   │
│   ├── SQLite + sqlite-vec  │  (edge default)                   │
│   ├── PostgreSQL + pgvector│  (server mode)                    │
│   └── ETS/DETS             │  (hot cache)                      │
└────────────────────────────┘───────────────────────────────────┘
```

### 2.1 Component Summary

| Component | Responsibility | OTP Pattern |
|-----------|---------------|-------------|
| `Graphonomous.Graph` | Knowledge graph CRUD, queries, traversals | GenServer + ETS cache |
| `Graphonomous.Learner` | Detect novelty, create/update nodes from inference | GenServer |
| `Graphonomous.Consolidator` | Idle-time memory consolidation, pruning, merging | GenServer + `:timer` |
| `Graphonomous.Retriever` | Graph-aware context retrieval for LLM injection | Stateless module |
| `Graphonomous.FilesystemTraversal` | Directory ingestion via one-shot `scan` and continuous `watch`; emits traversal events as graph knowledge | Module + polling watcher process |
| `Graphonomous.CLI` | STDIO MCP entrypoint plus operational subcommands (`scan`, `watch`) | Escript entrypoint |
| `Graphonomous.MCP.Server` | MCP tool/resource exposure via Hermes | Hermes.Server |
| `Graphonomous.Federation` | Cross-instance graph sync (future) | GenServer |

---

## 3. Technology Stack

### 3.1 Core

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| **Language** | Elixir 1.17+ / OTP 27 | Fault-tolerant, concurrent, distributed-native. Consolidation as supervised GenServers. Federation as distributed Erlang (post-MVP). |
| **MCP Server** | `hermes_mcp` (v0.8+) | Most mature Elixir MCP SDK. Unified client+server. Phoenix integration. Streamable HTTP transport. JSON-RPC 2.0 compliant. |
| **Graph Storage (edge)** | SQLite via `exqlite` + `sqlite-vec` | Zero-config, single-file, embeddable. `sqlite-vec` adds HNSW vector indexing for embedding similarity. Perfect for edge. |
| **Graph Storage (server)** | PostgreSQL 16+ via `ecto` + `pgvector` | When running as a service. Full ACID, concurrent access, `pgvector` for embeddings. |
| **Embeddings** | `bumblebee` + ONNX / external API | Local embedding via Bumblebee (Nx-backed ONNX models like `all-MiniLM-L6-v2`). Fallback to API (OpenAI, Voyage, etc). |
| **Hot Cache** | ETS | In-memory cache for frequently accessed graph regions. Configurable TTL. |
| **Admin UI** | Phoenix LiveView (optional) | Real-time graph visualization, stats, consolidation controls. Only for server mode. |
| **Telemetry** | `:telemetry` + `telemetry_metrics` | Observable by default. All graph operations emit telemetry events. |

### 3.2 Why Not PostgreSQL by Default?

PostgreSQL is excellent, but Graphonomous targets edge devices where:
- Installing and running Postgres adds operational complexity
- A Raspberry Pi or mini PC may have 4-8GB RAM
- SQLite with sqlite-vec provides vector search without a separate process
- Single-file database = trivially portable, backupable, syncable

PostgreSQL becomes the backend when running Graphonomous as a hosted service (via webhost.systems) or in team/enterprise mode.

### 3.3 Why MCP-First (Not REST)?

The November 2025 MCP spec added OAuth 2.1, async tasks, structured outputs, and elicitation — making it a full workflow-capable protocol. MCP is now the standard way AI systems talk to tools.

By exposing Graphonomous as an MCP server:
- **Any MCP client** (Claude, ChatGPT, Cursor, VS Code, custom agents) can use it directly
- **No custom SDK** needed — the MCP protocol IS the API
- **Tool discovery** is built in — clients auto-discover available operations
- **Composable** — other MCP servers can chain with Graphonomous
- **OpenSentience integration** is trivial — OS agents just connect to the MCP server

A REST/GraphQL API can be added later as a thin wrapper if needed, but MCP is the primary interface.

---

## 4. Knowledge Graph Schema

### 4.1 Nodes

```elixir
defmodule Graphonomous.Schema.Node do
  @type memory_type :: :episodic | :semantic | :procedural | :temporal | :outcome | :goal
  @type timescale :: :fast | :medium | :slow | :glacial

  @type t :: %__MODULE__{
    id: binary(),                    # UUIDv7 (time-ordered)
    type: memory_type(),
    content: String.t(),             # The knowledge content
    embedding: [float()],            # Vector embedding (384-dim default)
    metadata: map(),                 # Arbitrary structured metadata

    # Grounding / attribution
    # For :outcome nodes, causal_parent_ids links back to the belief/procedure nodes
    # that informed the action. For other node types, it is typically empty.
    causal_parent_ids: [binary()],   # Node IDs this node is causally attributed to
    
    # Learning signals
    confidence: float(),             # 0.0–1.0, how certain we are
    access_count: non_neg_integer(), # How often retrieved
    access_recency: DateTime.t(),    # Last access time
    creation_source: atom(),         # :inference | :consolidation | :federation | :manual
    timescale: timescale(),          # Which memory tier
    
    # Lifecycle
    decay_rate: float(),             # How fast confidence decays without access
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
end
```

**Memory Types:**

| Type | What It Stores | Example | Decay Rate |
|------|---------------|---------|------------|
| `:episodic` | Specific events, interactions | "User asked about valve pressure after E-47 error on Jan 15" | High (fades unless reinforced) |
| `:semantic` | Facts, concepts, relationships | "Error E-47 indicates hydraulic pressure loss" | Low (stable knowledge) |
| `:procedural` | How-to knowledge, procedures | "To reset valve: 1) close intake 2) flush line 3) recalibrate" | Very low (skills persist) |
| `:temporal` | Time-indexed patterns | "E-47 errors spike on Mondays after weekend shutdown" | Medium (patterns update) |
| `:outcome` | Empirical results of actions (grounding) | "Reset procedure succeeded; pressure stable after 10m" | Low–Medium (environment can drift) |
| `:goal` | Durable intent over long horizons (GoalGraph) | "Deploy customer support agent for ACME Corp" | Very low (should persist until resolved) |

**Notes on `:outcome` and `:goal`:**
- `:outcome` nodes **close the loop**: action → observed result → update causal confidence on the nodes that drove the decision (`causal_parent_ids`).
- `:goal` nodes live in a **GoalGraph subgraph**. They typically store `status`, `horizon`, `completion_criteria`, and `decomposition` in `metadata`.

### 4.2 Edges

```elixir
defmodule Graphonomous.Schema.Edge do
  @type relationship ::
    :causal | :causes | :resolves | :related | :related_to | :part_of | :follows |
    :contradicts | :supersedes | :superseded_by | :depends_on | :similar_to |
    :supports | :derived_from | :temporal_before | :temporal_after | :co_occurs

  @type t :: %__MODULE__{
    id: binary(),
    source_id: binary(),
    target_id: binary(),
    relationship: relationship(),
    
    # Learning signals
    strength: float(),               # 0.0–1.0, how strong the connection
    co_activation_count: non_neg_integer(), # Times both nodes retrieved together
    
    # Lifecycle
    decay_rate: float(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
end
```

### 4.3 SQLite Schema (Edge Mode)

```sql
-- Nodes
CREATE TABLE nodes (
  id TEXT PRIMARY KEY,              -- UUIDv7
  type TEXT NOT NULL CHECK(type IN ('episodic','semantic','procedural','temporal','outcome','goal')),
  content TEXT NOT NULL,
  metadata TEXT DEFAULT '{}',        -- JSON (stores type-specific fields, see README)
  causal_parent_ids TEXT DEFAULT '[]', -- JSON array of node IDs (grounding attribution)
  confidence REAL DEFAULT 0.5,
  access_count INTEGER DEFAULT 0,
  access_recency TEXT,               -- ISO8601
  creation_source TEXT DEFAULT 'inference',
  timescale TEXT DEFAULT 'medium',
  decay_rate REAL DEFAULT 0.01,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Embeddings via sqlite-vec (HNSW index)
CREATE VIRTUAL TABLE node_embeddings USING vec0(
  id TEXT PRIMARY KEY,
  embedding FLOAT[384]              -- all-MiniLM-L6-v2 dimensionality
);

-- Edges
CREATE TABLE edges (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  target_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  relationship TEXT NOT NULL,
  strength REAL DEFAULT 0.3,
  co_activation_count INTEGER DEFAULT 0,
  decay_rate REAL DEFAULT 0.005,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(source_id, target_id, relationship)
);

-- Indexes
CREATE INDEX idx_nodes_type ON nodes(type);
CREATE INDEX idx_nodes_timescale ON nodes(timescale);
CREATE INDEX idx_nodes_confidence ON nodes(confidence);
CREATE INDEX idx_edges_source ON edges(source_id);
CREATE INDEX idx_edges_target ON edges(target_id);
CREATE INDEX idx_edges_relationship ON edges(relationship);
```

---

## 5. MCP Server Design

Graphonomous exposes itself as a single MCP server via Anubis. All operations — querying the graph, learning new knowledge, triggering consolidation, retrieving context — are MCP tools and resources.

### 5.1 Dual-Surface Architecture (v1 → v2)

Graphonomous provides two MCP server surfaces:

| Surface | Module | Version | Tools | Purpose |
|---------|--------|---------|-------|---------|
| **v1** (legacy) | `Graphonomous.MCP.Server` | 0.2.0 | 29 individual tools | Backward compatibility |
| **v2** (machines) | `Graphonomous.MCP.Machines.Server` | 0.4.0 | 5 loop-phase machines | Production default |

**Why machines?** Research shows tool selection accuracy degrades past ~30 tools. When Graphonomous (29 tools) runs alongside PRISM (47 tools) in the same session, the client sees 76 tools. At that scale, Opus-class models achieve only ~49% correct tool selection, and schema overhead burns 40–80K context tokens before conversation starts.

The machine architecture groups tools by **which phase of the closed memory loop** the agent is in when it calls them — not by what they touch (graph write, graph read, etc.).

```
retrieve → route → act → learn → consolidate
"What do   "What     "Do    "Did it   "Clean
 I know?"  should     it"    work?"    up"
            I do?"
```

**Impact:** 29 tools → 5 tools. ~85% reduction in schema tokens. Selection accuracy from ~49% to ~95%.

### 5.2 Machine Architecture (v2 — Production Default)

```elixir
defmodule Graphonomous.MCP.Machines.Server do
  use Anubis.Server,
    name: "graphonomous",
    version: "0.4.0",
    capabilities: [:tools, :resources]

  component(Graphonomous.MCP.Machines.Retrieve)
  component(Graphonomous.MCP.Machines.Route)
  component(Graphonomous.MCP.Machines.Act)
  component(Graphonomous.MCP.Machines.Learn)
  component(Graphonomous.MCP.Machines.Consolidate)

  # 5 resources (shared with v1)
end
```

Each machine module accepts an `action` parameter that dispatches to the existing v1 tool implementations internally. The v1 modules are preserved as the implementation layer — machines delegate to them.

#### `retrieve` — "What do I know?"

The agent calls this when it needs context before reasoning or acting.

| Action | Replaces | Description |
|--------|----------|-------------|
| `context` | `retrieve_context` | κ-aware ranked retrieval with topology annotations |
| `episodic` | `retrieve_episodic` | Time-range filtered episodic nodes |
| `procedural` | `retrieve_procedural` | Semantic search scoped to procedural nodes |
| `coverage` | `coverage_query` | Standalone epistemic coverage (act/learn/escalate) |
| `trace_evidence` | `trace_evidence_path` | Weighted Dijkstra evidence path between nodes |
| `frontier` | `epistemic_frontier` | Wilson interval uncertainty analysis |

#### `route` — "What should I do?"

The agent calls this to decide whether to act, learn, deliberate, or escalate.

| Action | Replaces | Description |
|--------|----------|-------------|
| `topology` | `topology_analyze` | SCC/κ analysis with routing recommendation |
| `deliberate` | `deliberate` | κ-driven deliberation over cyclic regions |
| `attention_survey` | `attention_survey` | Priority survey across active goals |
| `attention_cycle` | `attention_run_cycle` | Full triage → dispatch attention cycle |
| `review_goal` | `review_goal` | Coverage-driven act/learn/escalate gate |

#### `act` — "Do it"

The agent calls this to mutate the knowledge graph.

| Action | Replaces | Description |
|--------|----------|-------------|
| `store_node` | `store_node` | Store a knowledge node |
| `store_edge` | `store_edge` | Store a relationship edge |
| `delete_node` | `delete_node` | Remove a node |
| `manage_edge` | `manage_edge` | CRUD on edges |
| `manage_goal` | `manage_goal` | Goal CRUD + lifecycle transitions |
| `belief_revise` | `belief_revise` | Expand/contract/replace beliefs |
| `forget_node` | `forget_node` | Soft-hide from retrieval |
| `forget_policy` | `forget_by_policy` | Budget-aware priority pruning |
| `gdpr_erase` | `gdpr_erase` | Hard delete with audit trail |

#### `learn` — "Did it work?"

The agent calls this after acting, to close the feedback loop.

| Action | Replaces | Description |
|--------|----------|-------------|
| `from_outcome` | `learn_from_outcome` | Causal confidence updates from action results |
| `from_feedback` | `learn_from_feedback` | Positive/negative/correction feedback |
| `detect_novelty` | `learn_detect_novelty` | Similarity-based novelty scoring |
| `from_interaction` | `learn_from_interaction` | Full pipeline: novelty → store → extract → link |
| `contradictions` | `belief_contradictions` | Detect belief conflicts in the graph |

#### `consolidate` — "Clean up"

The agent calls this to maintain graph quality, typically at session boundaries.

| Action | Replaces | Description |
|--------|----------|-------------|
| `run` | `run_consolidation` | Trigger a consolidation cycle |
| `stats` | `graph_stats` | Aggregate counts, distributions, confidence |
| `query` | `query_graph` | Operation-based graph inspection |
| `traverse` | `graph_traverse` | BFS walk with depth/relationship filters |

### 5.3 v1 Tools (Legacy — 29 Individual Tools)

The v1 surface remains available for backward compatibility. Each tool is also callable via the v2 machine + action pattern above.

| Category | Tools |
|----------|-------|
| Graph Write | `store_node`, `store_edge`, `delete_node`, `manage_edge` |
| Graph Read | `retrieve_context`, `query_graph`, `topology_analyze`, `graph_traverse`, `graph_stats` |
| Specialized Retrieval | `retrieve_episodic`, `retrieve_procedural`, `coverage_query` |
| Graph Algorithms | `trace_evidence_path`, `epistemic_frontier` |
| Continual Learning | `learn_from_outcome`, `learn_from_feedback`, `learn_detect_novelty`, `learn_from_interaction` |
| Belief Management | `belief_revise`, `belief_contradictions` |
| Goal Orchestration | `manage_goal`, `review_goal` |
| Deliberation | `deliberate` |
| Attention | `attention_survey`, `attention_run_cycle` |
| Forgetting | `forget_node`, `forget_by_policy`, `gdpr_erase` |
| Maintenance | `run_consolidation` |

### 5.4 MCP Resources

| URI | Description |
|-----|------------|
| `graphonomous://runtime/health` | Runtime health, service status, lightweight counts |
| `graphonomous://goals/snapshot` | Goal totals, status breakdown, serialized goals |
| `graphonomous://graph/node/{id}` | Individual node details + connected edges (URI template) |
| `graphonomous://graph/recent` | Recently added/accessed nodes, sorted by recency |
| `graphonomous://consolidation/log` | Consolidator state + orchestrator plasticity metrics |

### 5.5 Dual-Loop Interlocking with PRISM

When PRISM (OS-009) benchmarks Graphonomous, both closed loops interlock:

```
PRISM compose ──→ PRISM interact ──→ PRISM observe ──→ PRISM reflect ──→ PRISM diagnose
                       │
                       ▼
              ┌─── Graphonomous ───┐
              │  retrieve → route  │
              │  → act → learn     │
              │  → consolidate     │
              └────────────────────┘
```

PRISM's `interact` phase drives the system-under-test through its own closed loop. PRISM's `observe` phase judges how well that inner loop performed. PRISM's `reflect` phase evolves scenarios based on where the inner loop failed.

**Combined tool count:** 5 (Graphonomous) + 6 (PRISM) = 11 tools in a shared session, down from 76.

See `AmpersandBoxDesign/prompts/DUAL_LOOP_MACHINES.md` for the full architecture design.

### 5.6 Migration Strategy

1. **Phase 1 (current):** Both v1 and v2 servers available. v2 is the default.
2. **Phase 2:** Skill prompts updated to reference machine verbs. PRISM benchmarks compare v1 vs v2 tool selection accuracy.
3. **Phase 3:** Deprecate v1 tool names. Adapter layer translates legacy calls.
4. **Phase 4:** Remove v1 server modules.

### 5.7 Example: Claude Desktop Integration

```json
{
  "mcpServers": {
    "graphonomous": {
      "command": "graphonomous",
      "args": ["--db", "~/.graphonomous/knowledge.db"],
      "env": {
        "GRAPHONOMOUS_EMBEDDING_MODEL": "all-MiniLM-L6-v2"
      }
    }
  }
}
```

With the v2 machine surface, Claude (or any MCP client) uses the closed memory loop:
1. **retrieve** (action: `context`) — gather relevant domain knowledge
2. **route** (action: `topology`) — check for cycles, decide depth
3. **act** (action: `store_node`) — mutate the graph
4. **learn** (action: `from_outcome`) — close the causal feedback loop
5. **consolidate** (action: `run`) — maintain graph quality

---

## 6. Continual Learning Pipeline

### 6.1 Learning Flow

```
User Query
    │
    ▼
┌─────────────────┐
│ Novelty Detector │──── Is this new? ────► Novel: create new nodes
│                 │                        Known: reinforce existing
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Graph Retriever  │──── Retrieve relevant subgraph
│                 │      Inject as context into LLM prompt
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ LLM Inference    │──── Model generates response
│ (external)      │      (Graphonomous does NOT run the LLM)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Learner          │──── Extract entities, relationships, patterns
│                 │      Create/update nodes and edges
│                 │      Update access counts, recency
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Orchestrator     │──── Should we learn this?
│                 │      Stability vs plasticity check
│                 │      Assign timescale
└─────────────────┘
```

#### 6.1.1 Outcome Grounding (Closed-Loop Learning)

Language-only learning produces *unverified* knowledge. Autonomy requires that the graph learn from **outcomes**: did a chosen procedure/policy actually work in this environment?

Graphonomous supports a closed loop by ingesting outcomes as first-class nodes and using causal attribution to update confidence on the nodes that drove the action.

**Core mechanism:**
- The runtime (typically OpenSentience) executes an action.
- The runtime reports an outcome via `learn_from_outcome`.
- Graphonomous creates an `:outcome` node and updates causal parents.

**Outcome ingestion contract (tool-level):**
- `learn_from_outcome` accepts `causal_node_ids` — the node IDs that were retrieved and used as context before the action.
- Graphonomous persists an `:outcome` node whose `causal_parent_ids` are set to those `causal_node_ids`.
- Graphonomous adjusts `confidence` on the causal parents:
  - success ⇒ increase (bounded)
  - failure ⇒ decrease (bounded)
  - partial_success ⇒ proportional adjustment
  - timeout ⇒ typically small/no adjustment (caller may re-run)
- Adjustments are scaled by:
  - `confidence` of the outcome evidence (not the LLM’s rhetoric)
  - `evidence_type` (e.g. `"performance"` vs `"external"`)
  - optional decay/recency (environment drift)

**Why this matters:** the graph becomes a record of *causal hypotheses* (“these nodes justified that action”) and *empirical results* (“it worked/failed”), not just a store of text.

#### 6.1.2 GoalGraph Persistence (Durable Intent)

Autonomous behavior requires goals that persist across:
- restarts,
- interruptions,
- context switches,
- multi-step plans.

Graphonomous models durable intent as `:goal` nodes (a GoalGraph subgraph). Goals are linked to the procedural/semantic knowledge that supports them, and goal state transitions are driven by outcomes.

**Goal node convention (stored primarily in `metadata`):**
- `status`: `active | completed | failed | suspended`
- `horizon`: `short | medium | long`
- `completion_criteria`: structured criteria (e.g. `{type: "outcome_threshold", target: 0.85}`)
- `decomposition`: list of subgoal IDs
- `parent_goal_id`: optional parent

**GoalGraph tools:**
- `goal_create` creates a durable intent anchor
- `goal_decompose` attaches subgoals
- `goal_retrieve_active` supports restart/resumption
- `goal_update_status` records state transitions (optionally with evidence)

**Outcome-to-goal linkage:**
- If an outcome includes `goal_id`, Graphonomous can:
  - attach `:outcome` → `:goal` edges (e.g. `:part_of` or `:related_to`)
  - update goal status when criteria are satisfied or retry budgets are exhausted (policy is implementation-defined; the tool surface supports it)

#### 6.1.3 Epistemic Coverage Scoring (Act vs Learn vs Escalate)

Node-level confidence is not enough for autonomy; agents need task-level awareness of whether the graph is *adequate* for the job.

Graphonomous provides `coverage_query(task_description)` to return:
- `relevant_nodes`: the likely supporting knowledge
- `coverage_score`: 0.0–1.0 (how much of the task’s domain appears covered)
- `confidence_mean`: mean confidence over relevant nodes
- `knowledge_gaps`: missing or low-confidence topics
- `recommendation`: `"act" | "learn_first" | "escalate"`

**Intended runtime behavior:**
- Before taking high-stakes or irreversible actions:
  1. call `coverage_query`
  2. if `"act"` → proceed
  3. if `"learn_first"` → gather more info / retrieve more context / request clarifications
  4. if `"escalate"` → route to Deliberatic (multi-agent deliberation) or human review

Graphonomous returns an assessment; the caller enforces policy (Delegatic) and chooses the control flow.

### 6.2 Consolidation Cycles

Consolidation runs during idle periods (configurable). Inspired by the brain's sleep-stage memory consolidation.

```elixir
defmodule Graphonomous.Consolidator do
  use GenServer

  @default_interval :timer.minutes(5)  # Check every 5 minutes
  @idle_threshold :timer.seconds(30)   # 30s of no activity = idle

  # Consolidation strategies (run in order)
  defp consolidation_pipeline do
    [
      &decay_confidence/1,      # Apply time-based decay to all nodes
      &prune_weak_nodes/1,      # Remove nodes below confidence threshold
      &prune_weak_edges/1,      # Remove edges below strength threshold
      &strengthen_coactivated/1, # Boost edges between frequently co-retrieved nodes
      &merge_similar_nodes/1,   # Merge nodes with >0.95 embedding similarity
      &promote_timescale/1,     # Move reinforced fast-memory to slow-memory
      &generate_abstractions/1  # Create semantic nodes from episodic clusters
    ]
  end
end
```

### 6.3 Multi-Timescale Memory

| Timescale | TTL Without Reinforcement | Update Frequency | Consolidation Behavior |
|-----------|--------------------------|------------------|----------------------|
| **Fast** | 1 hour | Every interaction | Current conversation context. Ephemeral. |
| **Medium** | 7 days | Hourly | Session patterns. Promoted from fast if reinforced. |
| **Slow** | 90 days | Daily | Stable knowledge. Promoted from medium after repeated access. |
| **Glacial** | Never expires | Weekly | Core domain knowledge. Rarely changes. |

Nodes are promoted up timescales when their `access_count` exceeds a threshold relative to their age. Nodes are demoted (or pruned) when their confidence decays below a threshold.

---

## 7. Project Structure

```
graphonomous/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── graphonomous/
│   │   ├── application.ex          # OTP application + supervision tree
│   │   ├── cli.ex                  # CLI entrypoint (MCP server, scan, watch)
│   │   ├── graph.ex                # Knowledge graph GenServer
│   │   ├── filesystem_traversal.ex # Directory scan/watch traversal + ingestion
│   │   ├── graph/
│   │   │   ├── node.ex             # Node schema + operations
│   │   │   ├── edge.ex             # Edge schema + operations
│   │   │   └── query.ex            # Graph query engine
│   │   ├── storage/
│   │   │   ├── behaviour.ex        # Storage behaviour (adapter pattern)
│   │   │   ├── sqlite.ex           # SQLite + sqlite-vec adapter
│   │   │   ├── postgres.ex         # PostgreSQL + pgvector adapter
│   │   │   └── ets_cache.ex        # ETS hot cache layer
│   │   ├── learner.ex              # Continual learning engine
│   │   ├── learner/
│   │   │   ├── novelty_detector.ex # Out-of-distribution detection
│   │   │   ├── entity_extractor.ex # Extract entities from text
│   │   │   └── pattern_detector.ex # Detect recurring patterns
│   │   ├── consolidator.ex         # Sleep-cycle consolidation
│   │   ├── consolidator/
│   │   │   ├── pruner.ex           # Weak node/edge removal
│   │   │   ├── merger.ex           # Similar node merging
│   │   │   ├── promoter.ex         # Timescale promotion
│   │   │   └── abstractor.ex       # Generate abstractions
│   │   ├── retriever.ex            # Graph-aware context retrieval
│   │   ├── orchestrator.ex         # Stability-plasticity balance
│   │   ├── embedder.ex             # Embedding generation (Bumblebee/API)
│   │   ├── mcp/
│   │   │   ├── server.ex           # Hermes MCP server definition
│   │   │   ├── tools/
│   │   │   │   ├── graph_tools.ex  # graph_* tools
│   │   │   │   ├── learn_tools.ex  # learn_* tools
│   │   │   │   ├── retrieve_tools.ex # retrieve_* tools
│   │   │   │   └── consolidate_tools.ex
│   │   │   └── resources/
│   │   │       ├── graph_resources.ex
│   │   │       └── stats_resources.ex
│   │   └── federation/             # Future: cross-instance sync
│   │       ├── sync.ex
│   │       └── protocol.ex
│   └── graphonomous_web/           # Optional Phoenix app
│       ├── router.ex
│       ├── live/
│       │   ├── dashboard_live.ex   # Graph visualization
│       │   └── console_live.ex     # Interactive query console
│       └── components/
├── priv/
│   ├── migrations/                 # Ecto migrations (Postgres mode)
│   └── sqlite/
│       └── schema.sql              # SQLite schema
├── test/
└── rel/                            # Release configuration
    └── env.sh.eex
```

---

## 8. Supervision Tree

```elixir
defmodule Graphonomous.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Storage layer (starts first)
      {Graphonomous.Storage, storage_config()},
      
      # ETS hot cache
      Graphonomous.Storage.ETSCache,
      
      # Embedding model (Bumblebee or API client)
      {Graphonomous.Embedder, embedder_config()},
      
      # Core graph GenServer
      Graphonomous.Graph,
      
      # Continual learning components
      Graphonomous.Orchestrator,
      Graphonomous.Learner,
      {Graphonomous.Consolidator, consolidator_config()},
      
      # MCP Server (primary API)
      {Graphonomous.MCP.Server, mcp_config()},
      
      # Optional: Phoenix endpoint (admin UI)
      maybe_start_web()
    ] |> List.flatten() |> Enum.reject(&is_nil/1)

    opts = [strategy: :rest_for_one, name: Graphonomous.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Supervision strategy: `:rest_for_one`** — If storage crashes, everything downstream restarts. If the learner crashes, the consolidator restarts too (it depends on learned state). The MCP server is independent.

---

## 9. Configuration

```elixir
# config/runtime.exs
config :graphonomous,
  # Storage backend
  storage: System.get_env("GRAPHONOMOUS_STORAGE", "sqlite"),  # "sqlite" | "postgres"
  
  # SQLite path (edge mode)
  sqlite_path: System.get_env("GRAPHONOMOUS_DB", "~/.graphonomous/knowledge.db"),
  
  # PostgreSQL (server mode)
  postgres_url: System.get_env("DATABASE_URL"),
  
  # Embedding model
  embedding_model: System.get_env("GRAPHONOMOUS_EMBEDDING_MODEL", "all-MiniLM-L6-v2"),
  embedding_provider: System.get_env("GRAPHONOMOUS_EMBEDDING_PROVIDER", "local"), # "local" | "openai" | "voyage"
  embedding_dimensions: 384,
  
  # Consolidation
  consolidation_interval: :timer.minutes(5),
  idle_threshold: :timer.seconds(30),
  min_confidence_threshold: 0.05,
  min_edge_strength_threshold: 0.02,
  merge_similarity_threshold: 0.95,
  
  # Memory limits (edge-aware)
  max_nodes: 50_000,        # Soft limit, triggers aggressive pruning
  max_fast_memory_nodes: 500,
  ets_cache_ttl: :timer.minutes(10),

  # Filesystem traversal (scan/watch)
  filesystem_traversal_enabled: true,
  filesystem_default_recursive: true,
  filesystem_default_include_hidden: false,
  filesystem_default_follow_symlinks: false,
  filesystem_respect_gitignore: true,
  filesystem_watch_poll_interval_ms: 1_000,
  filesystem_watch_ingest_on_start: false,
  filesystem_max_file_size_bytes: 1_000_000,
  filesystem_max_read_bytes: 16_384,
  
  # MCP transport
  mcp_transport: :stdio,     # :stdio | :streamable_http
  mcp_port: 4100,            # Only for streamable_http
  
  # Web UI
  enable_web: false,
  web_port: 4200
```

---

## 10. [&] Portfolio Integration

### 10.1 OpenSentience

Graphonomous runs as an MCP server that OpenSentience agents connect to. Each agent can have its own graph instance or share one.

```
~/.opensentience/
├── sockets/
│   └── graphonomous.sock       # Unix socket (local mode)
├── graphonomous/
│   ├── knowledge.db            # Default graph database
│   └── embeddings/             # Cached embedding model
```

OpenSentience agent manifest:
```json
{
  "name": "my-agent",
  "mcp_servers": [
    {
      "name": "graphonomous",
      "transport": "stdio",
      "command": "graphonomous",
      "args": ["--db", "~/.opensentience/graphonomous/knowledge.db"]
    }
  ],
  "bootstrap_commands": [
    {
      "command": "graphonomous",
      "args": ["scan", "/workspace/project", "--extensions", ".md,.ex,.exs,.txt"]
    },
    {
      "command": "graphonomous",
      "args": ["watch", "/workspace/project", "--poll-interval-ms", "1500", "--ingest-on-start"]
    }
  ]
}
```

### 10.2 FleetPrompt

CL strategies are packaged as FleetPrompt skills:

- `graphonomous/factory-floor-learner` — Optimized for industrial IoT
- `graphonomous/personal-assistant` — Privacy-first personal memory
- `graphonomous/codebase-learner` — Learns from code review interactions
- `graphonomous/customer-support` — Domain-specific support knowledge

Each skill configures consolidation strategies, memory type weights, and pruning thresholds.

### 10.3 Delegatic

Multi-agent CL coordination. When multiple Graphonomous instances run across a Delegatic company:
- Shared semantic knowledge (federated)
- Private episodic memory (per-agent)
- Consolidated procedural knowledge (merged across agents)

### 10.4 webhost.systems

Managed Graphonomous instances:
- PostgreSQL-backed (not SQLite)
- Managed consolidation scheduling
- Monitoring dashboard
- API key auth for remote MCP access
- Usage-based billing per node/query

---

## 10.5 PULSE Loop Manifest

Graphonomous is a **PULSE-conforming loop** under OS-010. Its temporal topology is declared in [`/PULSE/manifests/graphonomous.continual_learning.json`](../../../PULSE/manifests/graphonomous.continual_learning.json) against schema `pulse-loop-manifest.v0.1.json`.

**Loop ID:** `graphonomous.continual_learning`
**Loop name:** Graphonomous Continual Learning Loop
**Version:** 0.4.0
**Owner:** graphonomous
**Workspace scope:** required

**Phases (5 canonical kinds — one per Graphonomous machine):**

| Phase ID | Kind | MCP Machine | Outputs |
|---|---|---|---|
| `retrieve_ctx` | `retrieve` | `retrieve` | κ-aware context subgraph + topology signal |
| `route_topo` | `route` | `route` | Routing decision (`fast` or `deliberate`); inner deliberation loop fires when `kappa > 0` |
| `act_store` | `act` | `act` | Mutation (store_node, store_edge, manage_goal, …) |
| `learn_outcome` | `learn` | `learn` | Updated confidence + causal binding (`feedback_immutability`) |
| `consolidate_idle` | `consolidate` | `consolidate` | Merged/strengthened/pruned graph regions (idle-time) |

**Closure:** `consolidate_idle → retrieve_ctx` via `substrate:memory`, guarantee `eventual`.

**Cadence:**
- Primary: `event` (any tool invocation)
- Fallback: `idle` (consolidation)

**Nesting:**
- Parent loop: `prism.benchmark` (when registered as PRISM-evaluable system)
- Inner loop: `graphonomous.deliberate` triggered by `kappa > 0`, wait `until_done`

**Substrates:**
- `memory`: `graphonomous://workspace/{ws_id}` (self)
- `policy`: `delegatic://workspace/{ws_id}`
- `audit`: `delegatic://workspace/{ws_id}/audit`
- `auth`: `open_sentience://workspace/{ws_id}`
- `transport`: `mcp` (Hermes/Anubis)
- `time`: `ticktickclock://workspace/{ws_id}` (optional)

**Invariants enabled:** `phase_atomicity`, `feedback_immutability`, `append_only_audit`, `kappa_routing`, `outcome_grounding`, `trace_id_propagation` (`quorum_before_commit` is delegated to inner deliberation loop).

**Cross-loop connections:**
- `outcome_to_prism` — emits `OutcomeSignal` from `learn_outcome` to `prism.benchmark.observe` via CloudEvents v1, `at_least_once` delivery
- Optional `consolidation_to_prism` — emits `ConsolidationEvent` from `consolidate_idle` to PRISM diagnostics

**Conformance:** validated against the 12-test PULSE conformance suite. Reference manifest is the canonical example for the PULSE specification.

**Why this matters:** because Graphonomous declares its loop in PULSE, any PRISM-conforming benchmark can drive it without bespoke integration; any other [&] loop can subscribe to `OutcomeSignal` / `ConsolidationEvent` without coupling to Graphonomous internals.

---

## 11. Dependencies (mix.exs)

```elixir
defp deps do
  [
    # MCP Server
    {:hermes_mcp, "~> 0.8"},
    
    # Storage
    {:exqlite, "~> 0.23"},         # SQLite driver
    {:ecto_sql, "~> 3.12"},        # Ecto (for Postgres mode)
    {:postgrex, "~> 0.19"},        # Postgres driver
    
    # Embeddings
    {:bumblebee, "~> 0.6"},        # ML models in Elixir
    {:nx, "~> 0.9"},               # Numerical computing
    {:exla, "~> 0.9"},             # XLA backend for Nx
    
    # Utilities
    {:jason, "~> 1.4"},
    {:uuid, "~> 1.1"},            # UUIDv7 generation
    {:telemetry, "~> 1.3"},
    {:telemetry_metrics, "~> 1.0"},
    
    # Optional: Web UI
    {:phoenix, "~> 1.7", optional: true},
    {:phoenix_live_view, "~> 1.0", optional: true},
    
    # Dev/Test
    {:ex_doc, "~> 0.34", only: :dev},
    {:credo, "~> 1.7", only: [:dev, :test]},
    {:dialyxir, "~> 1.4", only: [:dev, :test]}
  ]
end
```

---

## 12. Implementation Roadmap

### Phase 0: Foundation (Weeks 1–4)

- [ ] Project scaffold (mix new, supervision tree, config)
- [ ] SQLite storage adapter with schema
- [ ] Node/Edge CRUD operations
- [ ] Basic embedding via Bumblebee (all-MiniLM-L6-v2)
- [ ] Vector similarity search via sqlite-vec
- [ ] Basic `retrieve_context` — semantic search + inject into prompt
- [ ] **Proof:** 8B model + Graphonomous > 8B model alone on domain QA

### Phase 1: Core CL Engine (Weeks 5–10)

- [ ] Learner: entity extraction from interactions
- [ ] Learner: novelty detection (embedding distance threshold)
- [ ] Learner: automatic edge creation (co-occurrence, temporal sequence)
- [ ] Consolidator: decay, prune, strengthen pipeline
- [ ] Consolidator: idle-time scheduling
- [ ] Multi-timescale memory (fast/medium/slow/glacial)
- [ ] Orchestrator: stability-plasticity monitoring

### Phase 2: MCP Server (Weeks 11–14)

- [ ] Hermes MCP server with all tools defined in §5.2
- [ ] MCP resources defined in §5.3
- [ ] STDIO transport (for Claude Desktop, Cursor, etc.)
- [ ] Streamable HTTP transport (for remote access)
- [ ] Integration test: Claude Desktop → Graphonomous MCP → domain QA

### Phase 3: Polish + Postgres (Weeks 15–18)

- [ ] PostgreSQL + pgvector storage adapter
- [ ] ETS hot cache layer
- [ ] Phoenix LiveView admin dashboard
- [ ] Telemetry dashboards (Grafana-compatible)
- [ ] Release packaging (mix release, Docker)

### Phase 4: Federation (Weeks 19–24)

- [ ] Graph delta sync protocol
- [ ] Privacy-preserving federation (share semantic, not episodic)
- [ ] Conflict resolution for contradictory knowledge
- [ ] OpenSentience plugin packaging

---

## 13. Open Questions

1. **Embedding model size vs quality:** `all-MiniLM-L6-v2` (384-dim, 80MB) vs `bge-small-en-v1.5` (384-dim, 130MB) vs larger models. Need to benchmark on edge devices.

2. **Entity extraction without LLM:** For the Learner to extract entities from interactions, do we use a small local NER model, regex patterns, or call the same LLM being augmented? Calling the LLM creates a circular dependency concern.

3. **Federation protocol:** Use CRDTs for conflict-free merge? Or operational transforms? CRDTs are simpler but may not handle semantic contradictions.

4. **Licensing model:** MIT core + proprietary extensions (federation, managed hosting)? Or AGPL to prevent cloud providers from offering it without contributing?

5. **sqlite-vec maturity:** sqlite-vec is relatively new. Need to evaluate HNSW index performance at 50K+ vectors on constrained hardware.

---

## 14. Success Criteria

### MVP (Phase 2 complete)

- An 8B model (Llama 3.1 8B) connected to Graphonomous via MCP answers domain-specific questions **measurably better** after 1 week of use than at deployment
- No catastrophic forgetting — old knowledge retrieval doesn't degrade
- Runs on a device with ≤16GB RAM and no GPU
- Total startup time < 3 seconds
- Consolidation cycle completes in < 500ms for 10K nodes

### Product-Market Fit (Phase 3)

- 100+ GitHub stars within 3 months of open source release
- 10+ community-contributed FleetPrompt CL skills
- 3+ production deployments (industrial IoT, personal AI, enterprise)
- Featured in at least 1 edge AI conference/publication

---

## 15. v0.3 Capabilities (Continual Learning)

v0.3 delivers ten continual learning capabilities across four priority tiers, validated by GraphMemBench (120 scenarios, 15 categories).

### 15.1 P0 — Foundation (Week 1-2)

1. **Kappa activation** — Semantic back-references and expanded topology window enable κ>0 detection on >15% of benchmark queries.
2. **Belief revision substrate** — Revision records, `:superseded_by` edges, confidence propagation, and pluggable hooks for AGM-style expand/revise/contract.
3. **Conflict-aware consolidation (Stage 4.5)** — Pluggable conflict resolution with recency, confidence, and evidence-count strategies.

### 15.2 P1 — Core CL (Week 3-4)

4. **Two-phase retrieval** — Q-value utility scoring on nodes, utility reranking in Retriever, Q-value updates via `learn_from_outcome`, and decay in Consolidator Stage 1.
5. **Budget-aware forgetting** — Hybrid pruning (LRU + priority-decay) with GDPR hard delete (UtU-style). Three new MCP tools: `forget_node`, `forget_by_policy`, `gdpr_erase`.
6. **GraphMemBench Phase 1** — 40 scenarios across 5 categories validating P0+P1 capabilities.

### 15.3 P2 — Advanced (Week 5)

7. **Scoped uncertainty propagation** — Wilson score intervals on evidence-bearing nodes, new `Uncertainty` module with interval/propagate/frontier/entropy/information_gain functions, `epistemic_frontier` MCP tool.
8. **Procedural metadata** — Structured skill metadata (preconditions/postconditions/parameters/domain) with precondition matching boost in `retrieve_procedural` and composition detection in Consolidator Stage 7.
9. **Multi-agent schema prep** — `agent_id` column on nodes and edges (default: `"default"`), filter support. No behavioral changes.
10. **GraphMemBench Phase 2** — 40 more scenarios (80 total) across categories 6-10.

### 15.4 P3 — Causal + Benchmarking (Week 6+)

11. **Causal edge metadata prep** — `causal_strength`, `confounders`, and `intervention_history` in edge metadata. Updated on outcome feedback via status-dependent strength adjustments.
12. **GraphMemBench Phase 3** — Full 120-scenario suite with categories 11-15: Causal Metadata, End-to-End Workflows, Regression Guards, Competitor Adapter Stubs, Reporting.
13. **Competitor adapter interface** — `GraphMemBench.Adapter` behaviour with `ingest/1`, `retrieve/2`, `forget/1`, `stats/0`. Graphonomous adapter wraps MCP tools; Baseline/Mem0/Zep/Hindsight adapters are stubs.

### 15.5 Benchmark Summary

| Metric | v0.2 | v0.3 | v0.4 |
|--------|------|------|------|
| MCP tools (v1 individual) | 22 | 29 | 29 |
| MCP machines (v2 loop-phase) | — | — | 5 |
| Unit tests | ~240 | ~305 |
| GraphMemBench scenarios | — | 120 (15 categories) |
| LongMemEval SHR | — | >90.4% |
| κ activation rate | — | >15% of benchmark queries |
| Forgetting (GDPR hard delete) | — | Yes |
| Competitor adapters | — | 5 (1 live + 4 stubs) |

---

*[&] Ampersand Box Design — Building the infrastructure of tomorrow.*
