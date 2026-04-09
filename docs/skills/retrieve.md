---
name: retrieve
description: Use when the user asks to "recall", "search memory", "what do we know about", "retrieve context", "look up", or before any domain-specific action. The foundational read loop for Graphonomous knowledge. For storing new knowledge, use the `store` skill instead.
argument-hint: <query>
---

# Retrieve and Remember

Search the knowledge graph and store new knowledge.

## Arguments

Query to search for: $ARGUMENTS

## Retrieve Context

Search memory by natural language query using the `retrieve` machine:

```
retrieve(action: "context", query: "<query>", limit: 10, expansion_hops: 1)
```

**All parameters:**
- `action` (required) — "context" for κ-aware ranked retrieval
- `query` (required) — natural language search
- `limit` — max results (default 10)
- `expansion_hops` — 0 = fast/precise, 1 = contextual neighbors, 2 = deep discovery
- `neighbors_per_node` — how many neighbors per hop (default 4; use 8 for deep discovery)
- `node_type` — filter: "semantic", "procedural", "episodic", "temporal", "outcome", "goal"
- `min_score` — similarity threshold (0.0–1.0)

**Deep discovery example:**
```
retrieve(action: "context", query: "auth architecture", expansion_hops: 2, neighbors_per_node: 8)
```

### Response fields to use

Each result node includes:
- `similarity` — how closely the node matches your query (0.0–1.0)
- `hops` — 0 = direct match, 1+ = reached via expansion
- `via` — which edge/node path reached this result (for expansion hits)
- `causal_context` — **save this array** — you need it for `learn_from_outcome`

### Topology annotations

The response includes a `topology` object:
- `routing`: `"fast"` (no cycles, proceed normally) or `"deliberate"` (cycles found — use `/graphonomous:deliberate`)
- `max_kappa` — cycle complexity (0 = acyclic)
- `scc_count` — number of strongly connected components found

## Specialized Retrieval (other actions on the `retrieve` machine)

### Retrieve episodic nodes (events/observations)
```
retrieve(action: "episodic", since: "2026-03-01T00:00:00Z", until: "2026-03-29T23:59:59Z", limit: 20)
```
Time-range filtered retrieval of episodic nodes, sorted by recency. All parameters are optional.

### Retrieve procedural nodes (how-to knowledge)
```
retrieve(action: "procedural", query: "how to deploy the auth service", limit: 10)
```
Semantic search scoped to procedural nodes. Returns nodes with extracted steps from content.

## Store New Knowledge

After acting on retrieved context, store what you learned:

```
act(action: "store_node", content: "<one atomic fact>", node_type: "semantic", confidence: 0.7, source: "conversation")
```

**Node types:**
- `semantic` — facts, definitions, architecture ("what is?")
- `procedural` — workflows, how-to, recipes ("how to?")
- `episodic` — events, observations, outcomes ("what happened?")
- `temporal` — time-bound observations, monitoring events ("when did X happen?")
- `outcome` — measured results, benchmark scores ("what was the result?")
- `goal` — objectives, targets, intent ("what are we trying to achieve?")

**Confidence calibration:**
- 0.9–1.0: Directly observed in code/docs
- 0.7–0.89: Strong evidence, not directly verified
- 0.5–0.69: Single source, plausible
- 0.3–0.49: Indirect evidence, uncertain
- 0.0–0.29: Speculative

## Link Knowledge

Connect related nodes when it improves retrieval:

```
act(action: "store_edge", source_id: "<id>", target_id: "<id>", edge_type: "supports", weight: 0.8)
```

**Edge types:** `causal`, `causes`, `resolves`, `supports`, `contradicts`, `related`, `related_to`, `part_of`, `follows`, `supersedes`, `depends_on`, `similar_to`, `derived_from`, `temporal_before`, `temporal_after`, `co_occurs`

**Weight guidance:**
- 0.8–1.0: Strong, well-evidenced relationship
- 0.5–0.7: Moderate, reasonable inference
- 0.2–0.4: Weak, tentative connection

## Anti-patterns to avoid
- Skipping retrieval before acting (amnesia agent)
- Storing kitchen-sink nodes with multiple facts — one atomic fact per node
- Discarding `causal_context` from retrieval — hold it until outcome is resolved
- Setting all confidence to 0.9+ — calibrate honestly
- Storing duplicates — use `query_graph(operation: "similarity_search")` first; similarity > 0.90 = duplicate
