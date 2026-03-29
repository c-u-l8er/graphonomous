# κ × [&] Product Crosswalk
## Quick Reference for Spec Alignment

> Use this document to compare against each product's existing spec and identify where κ integration points land.

---

## Graphonomous (graphonomous.com)

**What it does now:** Continual learning knowledge graph. Episodic, semantic, procedural, temporal edges. MCP server. SQLite + sqlite-vec backend. Learn/consolidate/prune at inference time.

**What κ adds:**

| Existing Concept | κ Integration Point | Change Required |
|---|---|---|
| `recall/2` — retrieves context | Returns `{context, topology}` — topology includes SCC map + κ values | Add SCC computation to query path |
| Consolidation (sleep cycle metaphor) | κ-aware consolidation: SCC regions consolidate differently than DAG regions — cyclic clusters need multi-pass consolidation | Modify consolidation logic to respect SCC boundaries |
| Edge types (episodic, semantic, etc.) | No change to edge types — κ operates on the directed graph regardless of edge semantics | None |
| Pruning (weak connections decay) | κ-informed pruning: never prune an edge that would reduce a critical SCC to κ = 0 unless the whole cluster is decaying | Add κ check before pruning edges in SCC regions |
| MCP tool: `retrieve_context` | Augmented with `topology` field in response — returns SCC decomposition + κ annotations alongside context. Standalone `analyze_topology` tool for explicit topology queries. | Augment existing tool response + register new tool |

**New capability to register:**
```json
"&topology.analyze": { "provider": "graphonomous" }
```

**Elixir implementation note:** Tarjan's SCC is well-suited to Elixir — the recursive DFS maps cleanly to recursive function calls. The κ bipartition enumeration for small SCCs (<20 nodes) is CPU-bound but fast. For larger SCCs, approximate via `:digraph` module's built-in connected component functions + Stoer-Wagner min-cut.

---

## Deliberatic (deliberatic.com)

**What it does now:** Structured argumentation protocol. Dung's framework extended to weighted bipolar. Two-phase adaptive consensus (Raft fast-path, PBFT conflict-path). Merkle-chained evidence. Constitutional governance.

**What κ adds:**

| Existing Concept | κ Integration Point | Change Required |
|---|---|---|
| Trigger condition (when to deliberate) | κ > 0 in query subgraph = automatic trigger | Add κ-based invocation path |
| Argumentation depth (number of rounds) | Set by κ value: `max_rounds = κ + 1` | Accept κ parameter on deliberation endpoint |
| Propositions (what agents argue about) | Seeded from fault-line edges (minimum-cut edges of the SCC) — these are the critical bidirectional dependencies | Accept fault_lines parameter, generate initial propositions from them |
| Agent count | Scale with κ: `agents = min(κ, 3)` | Accept agent count as parameter or derive from κ |
| Confidence threshold | Higher for complex topology: `threshold = 0.7 + 0.05 * κ` | Accept threshold parameter |
| Evidence chains (Merkle-chained) | No change — evidence chains work the same regardless of trigger source | None |
| Constitutional governance | No change — governance constraints apply universally | None |

**New MCP tool:**
```json
{
  "name": "deliberate_on_scc",
  "inputSchema": {
    "scc_nodes": "array", "scc_edges": "array",
    "kappa": "integer", "fault_lines": "array",
    "governance": "object"
  }
}
```

**Key insight:** Deliberatic doesn't need to know about graph theory. It receives a set of propositions (derived from fault lines), a budget (derived from κ), and it argues. The graph intelligence lives in Graphonomous; the argumentation intelligence lives in Deliberatic. κ is the handshake between them.

---

## BendScript (bendscript.com)

**What it does now:** Interactive knowledge graph builder. Canvas-based. Nodes, edges, Stargates (sub-graph portals), fork/merge. Right-click context menus. Edge inspector with relationship types (context, causal, temporal, associative). Node inspector with markdown content. HUD showing node/edge/depth/zoom counts.

**What κ adds:**

| Existing Concept | κ Integration Point | Change Required |
|---|---|---|
| Canvas rendering (nodes + edges) | SCC clusters get visual grouping (colored halos, pulse animation proportional to κ) | Add SCC detection to render loop, draw cluster backgrounds |
| DAG edges (most current graphs) | Rendered with directional particle flow (animated dots moving src→dst) | Already directional; add particle animation for emphasis |
| SCC edges | Rendered with bidirectional particle flow (particles moving both ways) | New render style for edges within SCCs |
| HUD (nodes / edges / depth / zoom) | Add: κ readout (max κ across SCCs), SCC count, routing mode indicator | Extend HUD component |
| Right-click context menu (fork/merge/pin/stargate/delete) | Add: "Bend" (suggest edge to create feedback loop) and "Unbend" (suggest edge to remove to break loop) | New context menu items with topology preview |
| Edge creation ("Connect to…" context menu) | Topology preview per candidate: "→ NodeX (κ: 0→1 — creates feedback loop)" | Add `previewEdgeImpact` computation when submenu opens |
| Stargates (sub-graph portals) | Auto-suggest Stargates at SCC boundaries: "This cluster is a deliberation zone — create a Stargate?" | Add SCC-boundary detection to Stargate suggestion logic |
| Edge inspector (kind, label, strength) | Add κ impact indicator: "This edge is a fault line (part of the minimum cut)" | Annotate edges with their role in κ structure |
| Node inspector (text, type, pinned) | Add SCC membership indicator: "This node is in SCC-0 (κ=N)" | Annotate nodes with SCC membership |

**JavaScript implementation note:** Port `tarjan_scc` and `compute_kappa` to JS. Run in a web worker to avoid blocking the canvas render loop. For graphs under ~100 nodes (typical BendScript usage), the full computation takes <10ms and can run on every graph mutation. Cache SCC results and invalidate on edge add/remove.

**The "bend" verb, formalized:**
- **To bend** = add an edge that increases κ (transforms DAG → SCC, or increases SCC's κ)
- **To unbend** = remove an edge that decreases κ (simplifies SCC → DAG, or reduces κ)
- **Bending through graph space** = navigating the topology from κ=0 (pure retrieval) to κ>0 (deliberation)

---

## The [&] Protocol (protocol spec v0.1.0)

**What it defines now:** Five cognitive primitives (`&memory`, `&reason`, `&time`, `&space`, `&govern`). Composition operator `&`. Pipeline operator `|>`. Formal BNF grammar. JSON schema. Capability registry. Composition algebra. Governance constraints. Capability contracts.

**What κ adds:**

| Existing Concept | κ Integration Point | Change Required |
|---|---|---|
| Cognitive primitives (4) | Add `&topology` as a built-in operation (not a 5th primitive — it's a property of `&memory`) | Extend grammar with topology operations |
| Pipeline pattern | Insert `&topology.route()` between `&memory.recall()` and `&reason.deliberate()` | Document the κ-aware pipeline pattern |
| Capability contracts (§9) | `&topology.analyze` contract: must return SCC decomposition + κ values | Add contract definition |
| Governance constraints | κ can inform governance: "Never skip deliberation when κ > 2" or "Always deliberate on financial topics" | Add κ-based governance examples |
| Provider registry | `graphonomous` registers as `&topology.analyze` provider | Add to registry spec |
| Composition algebra (commutative, idempotent, etc.) | `&topology.route()` is a routing operator, not a capability — it doesn't compose with `&` but sits in the `\|>` pipeline | Document as pipeline-only operation |

**Extended pipeline pattern:**
```
context
|> &memory.recall("topic")
|> &topology.analyze()           # NEW: compute SCCs + κ
|> &topology.route()             # NEW: fast path vs deliberation
|> &reason.deliberate(budget: :κ)
|> &memory.learn()
```

**Grammar addition:**
```
TopologyOp := "&topology" "." ("analyze" | "route" | "kappa")
```

---

## TickTickClock (ticktickclock.com)

**What it does now:** Temporal intelligence. Anomaly detection, pattern prediction, time-series continual learning via Mamba SSM.

**What κ adds:**

| Existing Concept | κ Integration Point | Change Required |
|---|---|---|
| Pattern detection (Mamba SSM) | Complementary structural signal: discretize time series → build transition graph → compute κ → κ > 0 confirms periodic structure | Add discrete transition graph construction + κ computation as secondary signal |
| Anomaly detection | κ change over time = topological anomaly: if a previously periodic signal (κ > 0) becomes aperiodic (κ → 0), that's a structural regime change | Monitor κ of sliding-window transition graphs |
| Baseline drift | κ drift = the periodicity structure of the signal is changing | Track κ over time as a meta-feature |

**Priority:** Lower than Graphonomous/BendScript/Deliberatic. TickTickClock already has strong pattern detection. κ adds a complementary structural signal but isn't the primary mechanism.

---

## OpenSentience (opensentience.org)

**What it does now:** Open research initiative. Machine cognition foundations.

**What κ adds:**

| Content | What to Publish |
|---|---|
| The κ paper | Full theoretical background — traced monoidal categories, specialization theorems, Wilson loop correspondence. The intellectual depth piece. |
| The proof code | Runnable verification. 1,926,351 objects. Zero counterexamples. "Don't trust us — run it yourself." |
| Interactive demos | Live κ computation on user-constructed graphs. Drag nodes, add edges, watch κ change. |
| Scale Topology Axis essay | Broader context — connections to physics, cosmology, consciousness. The "why this matters beyond software" piece. |
| Applied κ paper | This document's parent — how κ became a routing primitive for agent inference. The "from theory to product" story. |

**Role:** Credibility and intellectual legitimacy. When someone asks "why does [&] route inference based on graph topology?", the answer is a proved theorem published on the research arm, not a marketing claim.

---

## Implementation Order

```
Phase 1 (foundation):
  ├── Port κ computation to Elixir          → Graphonomous
  ├── Port κ computation to JavaScript      → BendScript
  └── Integrate Tarjan SCC into graph index → Graphonomous

Phase 2 (routing):
  ├── retrieve_context + topology field     → Graphonomous MCP
  ├── κ router (fast vs deliberate)         → [&] pipeline
  ├── deliberate_on_scc endpoint            → Deliberatic MCP
  └── SCC visualization on canvas           → BendScript

Phase 3 (polish):
  ├── Topology preview on edge hover        → BendScript
  ├── Bend/Unbend context menu              → BendScript
  ├── HUD κ display + routing indicator     → BendScript
  ├── &topology in protocol grammar         → [&] spec
  └── Publish κ paper + demos               → OpenSentience

Phase 4 (validation):
  ├── A/B test: κ-routed vs uniform         → Graphonomous
  ├── Benchmark: topology computation cost  → Graphonomous
  └── User testing: does topology view help → BendScript
```

---

*Crosswalk version: 0.1.0. Use alongside: kappa_theory_applied.md (theory), kappa_integration_spec.md (product spec), kappa_reference.py (implementation). Align against: existing Graphonomous spec, Deliberatic spec, BendScript codebase, [&] Protocol v0.1.0, TickTickClock spec, OpenSentience content plan.*
