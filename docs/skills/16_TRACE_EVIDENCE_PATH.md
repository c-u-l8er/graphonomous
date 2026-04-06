# 16. Trace Evidence Path

Find provenance chains between knowledge nodes using weighted Dijkstra shortest-path traversal.

## When to Use

- When asked "why did you conclude X?" — trace the evidence chain
- To audit decision provenance between two knowledge nodes
- To investigate contradictions by finding paths through `contradicts` edges
- To verify deliberation conclusions by checking the reasoning chain
- When exploring how distant concepts are connected in the knowledge graph

## Algorithm

Weighted Dijkstra shortest-path with pluggable cost function:

```
cost(edge) = -log(confidence) + recency_decay(age, half_life) + type_cost(edge_type)
```

### Edge Type Costs

| Edge Type | Cost | Rationale |
|-----------|------|-----------|
| `causal` | 0.0 | Direct causation — strongest evidence |
| `supports` | 0.1 | Strong supporting evidence |
| `related_to` | 0.5 | Moderate relevance |
| `contradicts` | 2.0 | High cost — paths through contradictions are expensive |
| Other | 1.0 | Default |

Lower total cost = more confident, recent, direct evidence chain.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `from` | (required) | Source node ID |
| `to` | (required) | Target node ID |
| `k` | 1 | Number of alternate paths (Yen's K-shortest, max 10) |
| `half_life_hours` | 168 | Recency decay half-life |
| `bidirectional` | true | Search both directions |
| `max_hops` | 10 | Maximum path length |

## Response Format

Returns an array of paths, each containing:
- Node sequence (ordered list of node IDs)
- Total path cost
- Per-edge details (source, target, type, weight, cost contribution)

## Combining with Other Skills

- **`/graphonomous:deliberate`** → trace evidence path to verify deliberation conclusions
- **`/graphonomous:retrieve`** → retrieve context, then trace paths between retrieved nodes
- **`/graphonomous:belief`** → after belief revision, trace the evidence that triggered the change
- **`/graphonomous:review`** → trace coverage evidence to justify act/learn/escalate decisions

## Example

```
trace_evidence_path(
  from: "node_abc123",
  to: "node_def456",
  k: 3,
  half_life_hours: 72
)
```

Returns up to 3 shortest evidence paths between the two nodes, preferring recent, high-confidence, causal connections.
