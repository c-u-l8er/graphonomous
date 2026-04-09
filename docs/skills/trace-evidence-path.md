---
name: trace-evidence-path
description: Use when the user asks "why did you conclude X?", "trace the evidence", "show the reasoning chain", "how are these connected?", "find the path between nodes", "explain the provenance", or wants to understand evidence chains between two knowledge nodes. Weighted Dijkstra shortest-path tracing. Routes through the `retrieve` machine.
argument-hint: <from_node_id> <to_node_id> [k=3]
---

# Evidence Path Tracing

Find the lowest-cost evidence path between two knowledge nodes using weighted Dijkstra with optional K-shortest alternate paths via Yen's algorithm.

## Arguments

From/to node IDs and options: $ARGUMENTS

## When to Use

- **Explainability** — "Why did you conclude X from Y?" Trace the causal chain.
- **Provenance audit** — Verify that a conclusion has a legitimate evidence path.
- **Decision support** — Before high-stakes actions, show the reasoning chain.
- **Contradiction investigation** — When two nodes seem related but the connection is unclear.
- **After deliberation** — Verify that crystallized conclusions connect back to source evidence.

## Basic Usage

### Trace shortest evidence path
```
retrieve(action: "trace_evidence", source_id: "<source_node_id>", target_id: "<target_node_id>")
```

Returns the single lowest-cost path with per-edge cost breakdown.

### Find K alternate paths
```
retrieve(action: "trace_evidence", source_id: "<source_node_id>", target_id: "<target_node_id>", k: 3)
```

Returns up to K paths ranked by total cost, using Yen's algorithm. Useful for finding diverse reasoning chains.

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `source_id` | string | _(required)_ | Source node ID |
| `target_id` | string | _(required)_ | Target node ID |
| `k` | number | 1 | Number of alternate paths (max 10) |
| `half_life_hours` | number | 168.0 | Recency decay half-life (lower = prefer recent edges) |
| `bidirectional` | boolean | true | Search edges in both directions |
| `max_hops` | number | 10 | BFS expansion limit for subgraph construction |

## Cost Function

Each edge's cost is computed as:

```
cost = -log(confidence) + recency_decay(age_hours / half_life) + type_cost(edge_type)
```

**Type costs:**
| Edge Type | Cost | Rationale |
|-----------|------|-----------|
| `causal` | 0.0 | Direct causation is free — strongest evidence |
| `supports` | 0.1 | Supporting evidence is cheap |
| `related_to` | 0.5 | Association — weaker link |
| `contradicts` | 2.0 | Penalty for contradictory edges |
| other | 1.0 | Default penalty |

**Implications:**
- High-confidence causal edges are nearly free to traverse.
- Old edges are more expensive (recency decay).
- Contradictory paths are strongly penalized — if the shortest path traverses a `contradicts` edge, something may be wrong.

## Response Fields

```json
{
  "paths": [
    {
      "path": ["node_abc", "node_def", "node_ghi"],
      "total_cost": 0.423,
      "edges": [
        {"from": "node_abc", "to": "node_def", "cost": 0.105, "edge_type": "causal", "confidence": 0.9},
        {"from": "node_def", "to": "node_ghi", "cost": 0.318, "edge_type": "supports", "confidence": 0.7}
      ]
    }
  ],
  "subgraph_size": {"nodes": 15, "edges": 23}
}
```

## Full Workflow

1. **Identify endpoints** — use `retrieve(action: "context", ...)` or `consolidate(action: "query", ...)` to find the two nodes you want to connect.
2. **Trace path** — `retrieve(action: "trace_evidence", source_id: "<id_a>", target_id: "<id_b>", k: 3)`
3. **Interpret costs** — low total cost = strong evidence chain. Check for `contradicts` edges in any path.
4. **Report to user** — summarize the chain in natural language.
5. **Store episodic** — if the trace revealed something important, store it as an episodic node.

## Combining with Other Machines

| Scenario | Workflow |
|----------|----------|
| Verify deliberation output | `route(action: "deliberate")` -> `retrieve(action: "trace_evidence")` from source to conclusion |
| Audit before high-stakes action | `retrieve(action: "context")` -> identify causal chain -> `retrieve(action: "trace_evidence")` to verify |
| Investigate contradiction | `learn(action: "contradictions")` -> find conflicting nodes -> `retrieve(action: "trace_evidence")` between them |
| Topology + path | `route(action: "topology")` -> identify SCC members -> `retrieve(action: "trace_evidence")` within the cycle |
| Goal provenance | `route(action: "review_goal")` -> get linked nodes -> `retrieve(action: "trace_evidence")` from evidence to goal |

## Tuning Tips

- **Lower `half_life_hours`** (e.g., 24) to strongly prefer recent evidence chains.
- **Set `bidirectional: false`** to enforce strict causal direction.
- **Increase `k`** to find diverse paths — if path 1 goes through node X but path 2 doesn't, node X is not the only link.
- **Increase `max_hops`** for large graphs where the two nodes are far apart.
