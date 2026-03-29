# κ Integration Spec: Product-Level Specification
## Version 0.2.0 — Normalized

> How the cyclicity invariant κ is computed, surfaced, and used across Graphonomous, BendScript, Deliberatic, TickTickClock, and the [&] Protocol.
>
> **v0.2.0 changes (from Codex review):**
> - Normalized all field names to a single canonical schema (§2.4)
> - Resolved tool naming: `analyze_topology` is the standalone tool; `retrieve_context` gains a `topology` field — no `memory_recall_with_topology` tool
> - Fixed approximation representation: `kappa` is always an integer; large SCCs add `approximate: true` (no `exact` field)
> - Added instrumentation requirements (§7)
> - Clarified BendScript directed-edge policy (§4.3)

---

## 1. Overview

κ (kappa) is a graph-theoretic invariant that measures the minimum irreducible bidirectional information flow in a directed graph. It is the routing primitive that determines whether a query region of a knowledge graph requires single-pass retrieval (κ = 0) or iterative deliberation (κ > 0).

This spec defines:
- How κ is computed
- Where it is computed in the stack
- How it routes inference
- How it is surfaced to users
- How it integrates with each product

---

## 2. Computation

### 2.1 Algorithm

```
function compute_kappa(graph):
    # Pre-step: define node universe U from the analyzed subgraph/query result.
    # Ignore any edge where src ∉ U or dst ∉ U.
    # Exclude self-loops (u -> u) from adjacency for κ computation.
    # Step 1: Find all strongly connected components
    sccs = tarjan_scc(graph)                    # O(V + E)

    # Step 2: For each nontrivial SCC (size > 1)
    results = []
    for scc in sccs where |scc| > 1:
        # Step 3: Enumerate bipartitions, find minimum bidirectional cut
        k = infinity
        for (A, B) in nontrivial_bipartitions(scc):
            edges_a_to_b = count_edges(A, B, graph)
            edges_b_to_a = count_edges(B, A, graph)
            bidirectional_cut = min(edges_a_to_b, edges_b_to_a)
            k = min(k, bidirectional_cut)
            if k == 0: break  # early exit (can't go lower)

        # Step 4: Record SCC with its κ value and minimum-cut partition
        results.append({
            scc: scc,
            kappa: k,
            min_cut_partition: (A_min, B_min),
            min_cut_edges: edges_achieving_minimum
        })

    return results
```

### 2.2 Complexity

- **SCC decomposition:** O(V + E) via Tarjan's algorithm
- **κ computation per SCC:** O(2^|SCC| × |SCC|²) in the worst case (enumerating all bipartitions)
- **Practical constraint:** For SCCs up to ~20 nodes, bipartition enumeration is feasible in real time. For larger SCCs, use approximation:
  - Return SCC size as a proxy for κ, with `approximate: true` flag
  - κ field remains an integer (the estimate), never a symbol/atom/string
- **Node-universe rule (NORMATIVE):** Analyze only the node set supplied by retrieval/query scope (or explicit `node_ids` input). Do not pull in external nodes implicitly during κ analysis.
- **Self-loop rule (NORMATIVE):** Exclude self-loops (`source == target`) from κ adjacency and cut counts.

### 2.3 Incremental Updates

When an edge is added or removed from the knowledge graph:

1. **Edge addition:** Can only merge SCCs or enlarge existing ones. Re-run Tarjan on the affected component. If a new nontrivial SCC is formed, compute κ for it.
2. **Edge removal:** Can only split SCCs or shrink them. Re-run Tarjan on the affected component. Recompute κ for any remaining nontrivial SCCs.
3. **Optimization:** Maintain an SCC index alongside the knowledge graph. Incremental SCC algorithms (e.g., Bender, Fineman & Gilbert 2015) can update SCCs in O(V) amortized per edge change.

### 2.4 Canonical Schema (NORMATIVE — all implementations must match)

Every κ topology result — whether from Elixir, JavaScript, or MCP JSON — uses these exact field names:

```json
{
  "sccs": [
    {
      "id": "scc-0",
      "nodes": ["node-a", "node-b"],
      "kappa": 2,
      "approximate": false,
      "fault_line_edges": [
        {"source": "node-a", "target": "node-b"}
      ],
      "routing": "deliberate",
      "deliberation_budget": {
        "max_iterations": 3,
        "agent_count": 2,
        "timeout_multiplier": 2.0,
        "confidence_threshold": 0.80
      }
    }
  ],
  "dag_nodes": ["node-x", "node-y"],
  "routing": "deliberate",
  "max_kappa": 2,
  "scc_count": 1
}
```

**Field name rules (resolves all drift):**
- Top-level routing key: `routing` (not `overall_routing`)
- Edge endpoints: `source` / `target` (not `from`/`to`, not `a`/`b`)
- Fault lines: `fault_line_edges` (not `min_cut_edges`)
- κ type: always `integer` (never string, atom, or symbol)
- Approximation: `"approximate": true` boolean flag on the SCC object; `kappa` still holds the integer estimate
- Routing values: `"fast"` or `"deliberate"` (strings in JSON, atoms `:fast`/`:deliberate` in Elixir, strings in JS)

**Schema boundary rules (NORMATIVE):**
- **On MCP/JSON boundaries:** use canonical snake_case keys exactly as defined in §2.4 (`fault_line_edges`, `max_kappa`, `scc_count`, etc.).
- **Inside Elixir runtime:** atoms are allowed for routing values (`:fast`, `:deliberate`), but keys remain canonical and are serialized to JSON strings at the boundary.
- **Inside JavaScript UI code:** camelCase mirrors are allowed for local-only objects (`faultLineEdges`, `maxKappa`, `sccCount`) for ergonomics, but any network payload or persisted topology record must be converted back to canonical snake_case.

**Elixir atom mapping:**
```elixir
# Elixir uses atoms internally, converts to strings for MCP JSON
:fast       → "fast"
:deliberate → "deliberate"
```

**JavaScript mapping (local only):**
```javascript
// Local object ergonomics
{ faultLineEdges, maxKappa, sccCount, routing }

// MCP / wire payloads must remain canonical snake_case
{ fault_line_edges, max_kappa, scc_count, routing }
```

---

## 3. Routing Logic

### 3.1 The κ Router

The κ router sits between memory retrieval and reasoning. It inspects the topological structure of the retrieved subgraph and makes a routing decision.

```
function kappa_route(retrieved_subgraph):
    scc_analysis = compute_kappa(retrieved_subgraph)

    dag_context = nodes NOT in any nontrivial SCC
    scc_contexts = scc_analysis  # list of {scc, kappa, fault_line_edges, ...}

    # DAG regions: single-pass retrieval
    retrieval_context = topological_sort_and_collect(dag_context)

    # SCC regions: flag for deliberation
    deliberation_tasks = []
    for scc_info in scc_contexts:
        deliberation_tasks.append({
            nodes: scc_info.scc,
            kappa: scc_info.kappa,
            fault_lines: scc_info.fault_line_edges,
            budget: deliberation_budget(scc_info.kappa)
        })

    return {
        retrieval_context: retrieval_context,
        deliberation_tasks: deliberation_tasks,
        routing: "fast" if len(deliberation_tasks) == 0 else "deliberate"
    }
```

### 3.2 Deliberation Budget Function

The deliberation budget maps κ to concrete inference parameters. This is an engineering heuristic (not proved — to be tuned empirically). Caps on `max_iterations` and `confidence_threshold` are required to prevent runaway values when `approximate: true` SCCs use size-based κ estimates:

```
function deliberation_budget(kappa):
    return {
        max_iterations: min(kappa + 1, 4),
        agent_count: min(kappa, 3),
        timeout_multiplier: min(1.0 + 0.5*kappa, 3.5),
        confidence_threshold: min(0.7 + 0.05*kappa, 0.95)
    }
```

### 3.3 The Fast Path vs. Deliberation Path

```
             ┌─────────────────┐
             │  Query arrives   │
             └────────┬────────┘
                      │
                      ▼
             ┌─────────────────┐
             │  &memory.recall  │   Graphonomous retrieves relevant subgraph
             └────────┬────────┘
                      │
                      ▼
             ┌─────────────────┐
             │  κ Router        │   Compute SCCs, κ values
             └────────┬────────┘
                      │
              ┌───────┴────────┐
              │                │
         κ = 0 (all DAG)    κ > 0 (has SCCs)
              │                │
              ▼                ▼
       ┌──────────┐    ┌──────────────┐
       │ Fast Path │    │  Deliberation │
       │ single    │    │  &reason via  │
       │ pass      │    │  Deliberatic  │
       │ retrieval │    │  κ-informed   │
       └─────┬────┘    │  budget       │
             │         └──────┬───────┘
             │                │
             └───────┬────────┘
                     │
                     ▼
             ┌──────────────┐
             │  &memory.learn │   Results feed back into graph
             └──────────────┘
```

---

## 4. Product Integration

### 4.1 Graphonomous

**Where κ lives:** Computed at query time on the retrieved subgraph. Cached per SCC in the knowledge graph index; invalidated on edge changes.

**What changes:**
- `Retriever.retrieve/2` now returns a `topology` key alongside existing `results`, `causal_context`, `stats`
- New module `Graphonomous.Topology` computes and returns the full SCC analysis for a given subgraph
- New function `Store.list_edges_between/1` fetches edges within a node set

**MCP tool: `analyze_topology` (NEW standalone tool):**
```json
{
  "name": "analyze_topology",
  "description": "Compute topological structure (SCCs, κ values, routing decision) for a set of nodes in the knowledge graph.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "node_ids": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Node IDs to analyze. If omitted, analyzes the full graph."
      },
      "query": {
        "type": "string",
        "description": "Optional query text. If provided, retrieves relevant nodes first, then analyzes their topology."
      }
    }
  }
}
```

**MCP tool: `retrieve_context` (EXISTING — augmented with topology):**

The existing `retrieve_context` tool gains a `topology` field in its response. No new tool name — same endpoint, richer response:

```json
{
  "status": "ok",
  "query": "company strategy",
  "count": 7,
  "results": ["...existing results..."],
  "causal_context": ["...existing..."],
  "stats": {"...existing..."},
  "topology": {
    "sccs": [
      {
        "id": "scc-0",
        "nodes": ["market-share", "revenue", "r-and-d", "product-quality", "customer-retention"],
        "kappa": 1,
        "approximate": false,
        "fault_line_edges": [
          {"source": "product-quality", "target": "market-share"}
        ],
        "routing": "deliberate",
        "deliberation_budget": {
          "max_iterations": 2,
          "agent_count": 1,
          "timeout_multiplier": 1.5,
          "confidence_threshold": 0.75
        }
      }
    ],
    "dag_nodes": ["founding-date", "ceo-name", "headquarters"],
    "routing": "deliberate",
    "max_kappa": 1,
    "scc_count": 1
  }
}
```

### 4.2 Deliberatic

**What changes:**
- Accepts `kappa` and `fault_line_edges` as input parameters on its deliberation endpoint.
- Uses `kappa` to set argumentation depth (number of rounds).
- Uses `fault_line_edges` (minimum-cut edges) to generate the initial propositions that agents must argue about — these are the critical bidirectional dependencies.

**MCP tool additions:**
```json
{
  "name": "deliberate_on_scc",
  "description": "Run structured argumentation on a strongly connected knowledge cluster. Uses κ to set deliberation budget and fault lines to seed propositions.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "scc_nodes": { "type": "array", "items": { "type": "string" } },
      "scc_edges": { "type": "array" },
      "kappa": { "type": "integer" },
      "fault_line_edges": { "type": "array" },
      "governance": { "type": "object" }
    }
  }
}
```

**Key insight:** Deliberatic doesn't need to know about graph theory. It receives a set of propositions (derived from fault lines), a budget (derived from κ), and it argues. The graph intelligence lives in Graphonomous; the argumentation intelligence lives in Deliberatic. κ is the handshake between them.

### 4.3 BendScript

**What changes:**

#### Directed-Edge Policy (NORMATIVE)

BendScript edges have a `kind` property. For κ computation, edge directionality is determined by kind:

| Edge kind | Directionality for κ | Rationale |
|-----------|---------------------|-----------|
| `causal` | **Directed** (a → b) | Cause precedes effect |
| `temporal` | **Directed** (a → b) | Before precedes after |
| `context` | **Skip** (excluded from κ graph) | Symmetric, no feedback |
| `associative` | **Skip** (excluded from κ graph) | Symmetric, no feedback |
| `user` | **Skip** (excluded from κ graph) | Ambiguous directionality |

This is a **hard rule**, not a toggle. Only `causal` and `temporal` edges participate in SCC/κ computation. The filter constant:
```javascript
const DIRECTED_KINDS = ['causal', 'temporal'];
```

#### Visual Layer
- **SCC clusters rendered visually:** Nodes within a nontrivial SCC share a colored halo or background region. Color intensity scales with κ.
- **Minimum-cut edges highlighted:** Fault-line edges rendered in dashed style (`ctx.setLineDash([6, 4])`) with brighter color.
- **κ badge on SCC clusters:** Each SCC cluster shows its κ value as a small badge, e.g., "κ=2".

#### Interaction Layer
- **Topology preview via context menu:** When the user right-clicks a node and selects "Connect to…" (a new context menu item), BendScript shows candidate target nodes with topology impact annotations:
  - "→ NodeX: creates feedback loop (κ: 0→1)"
  - "→ NodeY: strengthens loop (κ: 1→2)"
  - "→ NodeZ: no topological change"
- **"Bend" action:** Right-click context menu on DAG nodes — automatically suggests the nearest edge that would create a feedback loop.
- **"Unbend" action:** Right-click context menu on SCC nodes — identifies the fault-line edge and offers to remove it.

**Note:** BendScript does NOT currently have drag-to-connect edge creation. The topology preview is accessed via the context menu "Connect to…" flow. Do not implement drag-to-connect in this phase.

#### HUD
- **Global κ display:** The existing HUD gains a κ readout showing the maximum κ across all SCCs in the graph, and a count of SCCs.
- **Routing indicator:** "mode: RETRIEVAL" (all κ = 0) or "mode: DELIBERATION" (any κ > 0).

### 4.4 The [&] Protocol

**Grammar extension:**

```
# Extended [&] capability grammar — topology-aware routing
TopologyOp      := "&topology" "." ("analyze" | "route" | "kappa")

# Updated pipeline pattern
InferencePipeline :=
    "&memory.recall" "(" QueryExpr ")"
    "|>" "&topology.analyze" "()"
    "|>" "&topology.route" "()"
    "|>" "&reason.deliberate" "(" "budget:" ":κ" ")"
    "|>" "&memory.learn" "()"
```

**Schema extension (ampersand.schema.json):**

```json
{
  "capabilities": {
    "&topology.analyze": {
      "provider": "graphonomous",
      "description": "Compute SCC decomposition and κ values for a subgraph",
      "config": {
        "max_scc_size_for_exact": 20,
        "approximation_strategy": "scc_size_proxy"
      }
    },
    "&topology.route": {
      "provider": "builtin",
      "description": "Route inference based on κ: DAG regions → fast path, SCC regions → deliberation",
      "config": {
        "deliberation_provider": "deliberatic",
        "fast_path_provider": "graphonomous"
      }
    }
  }
}
```

### 4.5 TickTickClock

**Connection:** For discrete time-series dynamics, the transition graph of the system has κ > 0 if and only if the system has a periodic orbit. TickTickClock can use this as a formal periodicity detector:

- Discretize time-series data into state transitions
- Build the transition graph
- Compute κ
- κ > 0 → periodic pattern detected, flag for temporal reasoning
- κ = 0 → pure drift, no recurrence

This is a secondary integration (TickTickClock already has Mamba SSM for pattern detection), but it provides a complementary structural signal.

### 4.6 OpenSentience

**Role:** Research home for the theoretical foundations. Hosts:
- The κ paper (theoretical background, proofs, categorical framework)
- The proof code (runnable verification)
- Interactive demos (live κ computation on user-constructed graphs)
- The original Scale Topology Axis essay (broader theoretical context connecting κ to physics, cosmology, and consciousness science)

---

## 5. Implementation Priority

### Phase 1: Core (ship first)
- [ ] Port κ computation to Elixir (Graphonomous server-side)
- [ ] Port κ computation to JavaScript (BendScript client-side)
- [ ] Integrate Tarjan's SCC into Graphonomous's graph index
- [ ] Return topology annotations from `retrieve_context`
- [ ] Add SCC visualization to BendScript canvas

### Phase 2: Routing (ship second)
- [ ] Implement κ router in the [&] pipeline
- [ ] Connect κ router to Deliberatic trigger
- [ ] Add deliberation budget function
- [ ] Test on real knowledge graph queries: does κ-aware routing improve answer quality?

### Phase 3: Polish (ship third)
- [ ] BendScript topology preview via context menu
- [ ] Bend/Unbend context menu actions
- [ ] HUD κ display and routing indicator
- [ ] TickTickClock periodicity detection via κ
- [ ] OpenSentience publication of κ paper and demos

### Phase 4: Optimization
- [ ] Incremental SCC maintenance (avoid full recomputation on every edge change)
- [ ] Approximate κ for large SCCs (> 20 nodes)
- [ ] Benchmark: latency impact of topology computation on query path
- [ ] A/B test: κ-routed inference vs. uniform retrieval on quality metrics

---

## 6. Success Metrics

| Metric | Baseline (no κ) | Target (with κ) | How to Measure |
|---|---|---|---|
| Answer coherence on circular topics | Human eval ~60% | Human eval ~80% | Blind eval on queries touching SCCs |
| Unnecessary deliberation calls | N/A (no routing) | < 20% of queries | Track κ=0 queries that hit deliberation anyway |
| Deliberation convergence speed | Fixed rounds | κ+1 rounds avg | Measure rounds to convergence |
| User engagement in BendScript | Nodes/edges per session | +30% | Track topology actions (bend/unbend/stargate) |
| OpenSentience traffic | Baseline | Organic from dev community | Track referrals from product UIs |

---

## 7. Instrumentation Requirements (NEW in v0.2.0)

All κ computation must emit telemetry. This is required for Gate C (performance) and Gate D (product effect) validation.

### 7.1 Latency Counters (Elixir — `:telemetry`)

```elixir
# Emit on every topology computation
# REQUIRED UNIT: duration_ms (float milliseconds)
# If measured via :timer.tc/1, convert with: duration_ms = duration_us / 1000.0
:telemetry.execute(
  [:graphonomous, :topology, :analyze],
  %{duration_ms: elapsed_ms, node_count: n, edge_count: e},
  %{scc_count: scc_count, max_kappa: max_kappa, routing: routing}
)
```

Track:
- `topology.analyze.duration_ms` — p50, p95, p99 (canonical latency metric)
- `topology.analyze.node_count` — distribution of subgraph sizes
- `topology.analyze.edge_count` — distribution of subgraph densities
- `topology.analyze.scc_count` — how often SCCs are found
- `topology.analyze.routing.deliberate_ratio` — deliberate / total analyzes
- `topology.analyze.self_loop_filtered_count` — number of self-loops ignored during adjacency construction

### 7.2 Routing Decision Counters

```elixir
:telemetry.execute(
  [:graphonomous, :topology, :route],
  %{},
  %{decision: :fast | :deliberate, max_kappa: max_kappa, trigger: :retrieve_context | :analyze_topology}
)
```

Track:
- `topology.route.fast_count` — queries routed to fast path
- `topology.route.deliberate_count` — queries routed to deliberation
- `topology.route.deliberate_ratio` — deliberate / total (target: < 30% on typical workloads)

### 7.3 BendScript Performance (JavaScript — `performance.now()`)

```javascript
const t0 = performance.now();
const topo = analyzeTopology(plane);
const elapsed = performance.now() - t0;
console.debug(`[κ] topology: ${elapsed.toFixed(1)}ms, maxκ=${topo.maxKappa}, sccs=${topo.sccCount}`);
```

Target: < 50ms at 100 nodes.

---

*Spec version: 0.2.0. Status: Draft (normalized). Depends on: kappa_reference.py (computation), kappa_theory_applied.md (theoretical foundations). Products affected: Graphonomous, Deliberatic, BendScript, [&] Protocol, TickTickClock, OpenSentience.*
