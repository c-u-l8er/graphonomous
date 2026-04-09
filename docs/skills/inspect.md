---
name: inspect
description: Use when the user asks to "show the graph", "list nodes", "what's stored", "check for duplicates", "trace edges", "get node", "browse memory", or wants to query specific nodes/edges in the knowledge graph. Read-only graph inspection. For aggregate health diagnostics, use `graph-health` instead. Routes through `consolidate` and `act` machines.
argument-hint: [list|get|edges|search|stats|traverse] [query or node_id]
---

# Graph Inspection

Read-only inspection of the knowledge graph — no side effects.

## Arguments

Operation and target: $ARGUMENTS

## Operations

### List nodes
```
consolidate(action: "query", operation: "list_nodes", node_type: "semantic", min_confidence: 0.5, limit: 20)
```
Browse what's stored. Filter by `node_type` (semantic, procedural, episodic, temporal, outcome, goal), `min_confidence`, `max_confidence`, `limit`.

### Get a specific node
```
consolidate(action: "query", operation: "get_node", node_id: "<id>")
```
Returns: `content`, `confidence`, `source`, `metadata`, `node_type`, `timescale` (fast/medium/slow/glacial), `access_count`, `created_at`, `updated_at`.

### Trace edges from a node
```
consolidate(action: "query", operation: "get_edges", node_id: "<id>")
```
Returns both outgoing and incoming edges with types and weights. Useful for tracing causal chains, finding contradictions, and understanding provenance.

### Similarity search
```
consolidate(action: "query", operation: "similarity_search", query: "<text>", limit: 5)
```
Embedding-based search. Returns nodes with similarity scores.

**Operation aliases:** `"get"`, `"edges"`, `"list"` also work as shorthand.

### Graph traverse (BFS walk)
```
consolidate(action: "traverse", start_node_id: "<id>", max_depth: 3, relationship_types: "causal,supports")
```
BFS walk from a starting node. Returns visited nodes, edges, depth map, and traversal metadata. Optionally filter by relationship types (comma-separated).

### Graph stats (aggregate health)
```
consolidate(action: "stats")
```
Returns node/edge counts, type distributions, confidence statistics (mean/min/max/std_dev), and orphan count (nodes with no edges). No parameters required.

### Manage edges
```
act(action: "manage_edge", operation: "list_all")
act(action: "manage_edge", operation: "list_for_node", node_id: "<id>")
act(action: "manage_edge", operation: "update", edge_id: "<id>", weight: 0.9, co_activation_count: 5)
act(action: "manage_edge", operation: "delete", edge_id: "<id>")
```
Full edge lifecycle management: list, update weight/co_activation_count/decay_rate, or delete.

### Delete a node
```
act(action: "delete_node", node_id: "<id>")
```
Remove a node and its connected edges from the graph.

## Resources (Read-Only Snapshots)

| URI | What It Returns |
|-----|----------------|
| `graphonomous://runtime/health` | Runtime health, service status, lightweight counts |
| `graphonomous://goals/snapshot` | Goal totals, status breakdown, serialized goals |
| `graphonomous://graph/node/{id}` | Individual node details + connected edges |
| `graphonomous://graph/recent` | Recently added/accessed nodes, sorted by recency |
| `graphonomous://consolidation/log` | Consolidator state + orchestrator plasticity metrics |

## `retrieve(action: "context")` vs `consolidate(action: "query", operation: "similarity_search")`

| | `retrieve(action: "context")` | `consolidate(action: "query", operation: "similarity_search")` |
|---|---|---|
| **Neighborhood expansion** | Yes (hops) | No |
| **Topology annotations** | Yes (routing, kappa) | No |
| **Causal context** | Yes (for outcome learning) | No |
| **Side effects** | Updates access counts | None |
| **Use when** | Acting on results (need causal tracking) | Checking duplicates, auditing, browsing |

**Rule:** Use `retrieve(action: "context")` when you plan to act on results. Use `consolidate(action: "query")` for read-only inspection.

## Common Patterns

### Duplicate prevention (check before storing)
```
consolidate(action: "query", operation: "similarity_search", query: "the fact I want to store", limit: 3)
```
- similarity > 0.90 — **duplicate** — update the existing node instead
- similarity 0.70-0.90 — **related** — store new node + add `related` edge
- similarity < 0.70 — **novel** — safe to store as new node

### Audit weak knowledge
```
consolidate(action: "query", operation: "list_nodes", min_confidence: 0.0, max_confidence: 0.3)
```
Find speculative or likely-wrong nodes needing reinforcement or pruning.

### Trace decision chains
```
consolidate(action: "query", operation: "get_node", node_id: "<id>")
consolidate(action: "query", operation: "get_edges", node_id: "<id>")
```
Follow `causal` and `supports` edges to reconstruct reasoning. Check for `contradicts` edges that indicate unresolved conflicts.

## Anti-patterns to avoid

- Using `retrieve(action: "context")` for browsing — it has side effects (updates access counts)
- Forgetting to check for duplicates before storing new nodes
- Running traversals with very high max_depth on large graphs — start with 2-3
