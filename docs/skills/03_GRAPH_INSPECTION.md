# Skill 03 — Graph Inspection

> **Tool:** `query_graph`
> **Purpose:** Inspect the knowledge graph state — list nodes, fetch individual
> nodes, examine edges, and run similarity searches.
> **When to use:** Whenever you need to see what's in the graph, verify stored
> knowledge, trace relationships, or find related content by embedding similarity.

---

## Overview

`query_graph` is a multi-operation tool. You select the operation via the
`operation` parameter and supply additional params depending on which operation
you chose. Think of it as four read-only tools behind one name.

| Operation | What It Does | Required Params | Optional Params |
|-----------|-------------|-----------------|-----------------|
| `list_nodes` | List nodes with optional filters | — | `node_type`, `min_confidence`, `limit` |
| `get_node` | Fetch a single node by ID | `node_id` | — |
| `get_edges` | Get all edges for a node | `node_id` | — |
| `similarity_search` | Embedding-based semantic search | `query` | `limit` |

---

## Operation: `list_nodes`

### When to Use

- Exploring what knowledge exists in the graph
- Filtering by type to find all procedural or episodic nodes
- Auditing low-confidence nodes that may need reinforcement
- Getting a count of stored knowledge

### Parameters

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `operation` | string | — | `"list_nodes"` |
| `node_type` | string | all types | Filter: `"episodic"`, `"semantic"`, or `"procedural"` |
| `min_confidence` | number | 0.0 | Only return nodes with confidence ≥ this value |
| `limit` | number | all | Maximum number of nodes to return |

### Examples

**List all nodes:**
```
query_graph(
  operation: "list_nodes"
)
```

**List high-confidence semantic knowledge:**
```
query_graph(
  operation: "list_nodes",
  node_type: "semantic",
  min_confidence: 0.7,
  limit: 20
)
```

**Find procedural knowledge that may need reinforcement:**
```
query_graph(
  operation: "list_nodes",
  node_type: "procedural",
  min_confidence: 0.0,
  limit: 50
)
→ Then filter client-side for confidence < 0.4 to find weak procedures.
```

**List recent episodic memories:**
```
query_graph(
  operation: "list_nodes",
  node_type: "episodic",
  limit: 10
)
```

### Response Shape

```
{
  "operation": "list_nodes",
  "status": "ok",
  "result": {
    "count": 42,
    "nodes": [
      {
        "id": "nd_abc123",
        "content": "The auth module uses JWT tokens with 1h expiry",
        "node_type": "semantic",
        "confidence": 0.85,
        "source": "src/auth/jwt.ts",
        "metadata": { ... },
        "created_at": "2025-06-15T10:30:00Z",
        "updated_at": "2025-06-15T14:20:00Z",
        "access_count": 7
      },
      ...
    ]
  }
}
```

---

## Operation: `get_node`

### When to Use

- You have a node ID (from retrieval, outcome, or goal linkage) and need full details
- Verifying a node's current confidence before deciding to trust it
- Reading metadata or source attribution for a specific knowledge claim
- Following up on a node referenced in an edge or goal

### Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `operation` | string | yes | `"get_node"` |
| `node_id` | string | yes | The ID of the node to fetch |

### Example

```
query_graph(
  operation: "get_node",
  node_id: "nd_abc123"
)
```

### Response Shape

```
{
  "operation": "get_node",
  "status": "ok",
  "result": {
    "node": {
      "id": "nd_abc123",
      "content": "The auth module uses JWT tokens with 1h expiry",
      "node_type": "semantic",
      "confidence": 0.85,
      "source": "src/auth/jwt.ts",
      "metadata": {
        "verified_by": "code_review",
        "related_file": "src/auth/middleware.ts"
      },
      "created_at": "2025-06-15T10:30:00Z",
      "updated_at": "2025-06-15T14:20:00Z",
      "access_count": 7,
      "timescale": "slow"
    }
  }
}
```

### Error Case

If the node ID does not exist, you'll get:

```
{
  "operation": "get_node",
  "status": "error",
  "error": "not found"
}
```

---

## Operation: `get_edges`

### When to Use

- Tracing relationships from a node (what does it connect to?)
- Understanding the causal chain behind a decision or outcome
- Finding contradictions or supporting evidence for a claim
- Mapping the local neighborhood of a concept before deliberation

### Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `operation` | string | yes | `"get_edges"` |
| `node_id` | string | yes | The node whose edges you want to inspect |

### Example

```
query_graph(
  operation: "get_edges",
  node_id: "nd_abc123"
)
```

### Response Shape

```
{
  "operation": "get_edges",
  "status": "ok",
  "result": {
    "count": 3,
    "edges": [
      {
        "id": "ed_xyz789",
        "source_id": "nd_abc123",
        "target_id": "nd_def456",
        "edge_type": "supports",
        "weight": 0.8,
        "metadata": {},
        "created_at": "2025-06-15T11:00:00Z"
      },
      {
        "id": "ed_xyz790",
        "source_id": "nd_abc123",
        "target_id": "nd_ghi012",
        "edge_type": "causal",
        "weight": 0.6,
        "metadata": {}
      },
      {
        "id": "ed_xyz791",
        "source_id": "nd_jkl345",
        "target_id": "nd_abc123",
        "edge_type": "contradicts",
        "weight": 0.4,
        "metadata": { "note": "Doc says 2h, code says 1h" }
      }
    ]
  }
}
```

Note: This returns **both** outgoing edges (where `source_id` matches) **and**
incoming edges (where `target_id` matches). Always check the direction.

---

## Operation: `similarity_search`

### When to Use

- Finding nodes whose content is semantically similar to a query
- Lower-level alternative to `retrieve_context` (no neighborhood expansion, no topology)
- Checking for near-duplicates before storing a new node
- Exploring what the graph "knows" about a vague topic

### Parameters

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `operation` | string | yes | — | `"similarity_search"` |
| `query` | string | yes | — | Natural-language query for embedding comparison |
| `limit` | number | no | 10 | Maximum results to return |

### Example

**Basic search:**
```
query_graph(
  operation: "similarity_search",
  query: "authentication and session management",
  limit: 5
)
```

**Duplicate detection before storing:**
```
query_graph(
  operation: "similarity_search",
  query: "The auth module uses JWT tokens with 1 hour expiry",
  limit: 3
)
→ If a match comes back with similarity > 0.90, the knowledge is likely
  already stored. Consider updating the existing node instead.
```

### Response Shape

```
{
  "operation": "similarity_search",
  "status": "ok",
  "result": {
    "count": 5,
    "matches": [
      {
        "node_id": "nd_abc123",
        "content": "The auth module uses JWT tokens with 1h expiry",
        "node_type": "semantic",
        "confidence": 0.85,
        "similarity": 0.93,
        "score": 0.79
      },
      {
        "node_id": "nd_mno678",
        "content": "Session cookies are set httpOnly with secure flag",
        "node_type": "semantic",
        "confidence": 0.7,
        "similarity": 0.61,
        "score": 0.43
      },
      ...
    ]
  }
}
```

The `score` field combines similarity and confidence to rank results.

---

## `query_graph` vs `retrieve_context` — When to Use Which

| Scenario | Use | Why |
|----------|-----|-----|
| Need context to answer a user's question | `retrieve_context` | Includes neighborhood expansion, topology, causal_context for outcome tracking |
| Checking if a fact already exists | `query_graph` (similarity_search) | Lightweight, no side effects, just similarity |
| Inspecting a specific node by ID | `query_graph` (get_node) | Direct lookup, no search needed |
| Tracing edges from a known node | `query_graph` (get_edges) | Edge-specific operation |
| Auditing graph contents by type | `query_graph` (list_nodes) | Filter/list operation |
| Building context for `learn_from_outcome` | `retrieve_context` | Gives you `causal_context` node IDs directly |
| Pre-deliberation topology check | `topology_analyze` | Dedicated topology tool |

**General rule:** Use `retrieve_context` when you need knowledge to *act on*.
Use `query_graph` when you need to *inspect* the graph itself.

---

## Common Patterns

### Pattern 1 — Verify Before Trusting

When retrieved context includes a critical claim, verify it:

```
1. retrieve_context(query: "database connection pool size")
   → Returns node nd_pool with content "Pool size is 10" at confidence 0.5

2. query_graph(operation: "get_edges", node_id: "nd_pool")
   → Check: are there supporting edges? Contradicting edges?

3. query_graph(operation: "get_node", node_id: "nd_pool")
   → Check: what's the source? When was it last updated?

4. Decision: confidence 0.5 with no supporting edges and stale timestamp
   → Don't fully trust this claim. Verify from source before acting.
```

### Pattern 2 — Audit Knowledge Gaps

```
1. query_graph(operation: "list_nodes", node_type: "semantic", min_confidence: 0.0, limit: 100)
   → Get all semantic nodes

2. Filter for confidence < 0.4
   → These are your weakest knowledge claims

3. For each weak node:
   query_graph(operation: "get_edges", node_id: "<weak_node_id>")
   → If no supporting edges exist, this is a gap to investigate

4. Store findings and create a goal to address the gaps
```

### Pattern 3 — Trace a Decision Chain

After an outcome, trace what knowledge led to the decision:

```
1. Start with causal_node_ids from the learn_from_outcome call

2. For each causal node:
   query_graph(operation: "get_node", node_id: "<id>")
   → Read what the node claims

3. For each causal node:
   query_graph(operation: "get_edges", node_id: "<id>")
   → See what supports or contradicts it

4. Build a narrative: "The decision was based on nodes A, B, C.
   A is well-supported (3 supporting edges, confidence 0.9).
   B has a contradiction (edge from D with type 'contradicts').
   C is isolated (no edges, confidence 0.5)."
```

### Pattern 4 — Duplicate Prevention

Before storing a new node, check for near-duplicates:

```
1. query_graph(
     operation: "similarity_search",
     query: "<content you want to store>",
     limit: 3
   )

2. If top match has similarity > 0.90:
   → The knowledge likely already exists
   → Consider updating the existing node's confidence instead
   → Or store an edge linking your new observation to the existing node

3. If top match has similarity 0.70-0.90:
   → Related but distinct knowledge exists
   → Store the new node AND create a "related" or "supports" edge

4. If no matches or similarity < 0.70:
   → This is novel knowledge — store it freely
```

---

## Operation Aliases

The `query_graph` tool accepts some shorthand aliases for convenience:

| You Can Say | It Resolves To |
|-------------|---------------|
| `"get"` | `get_node` |
| `"edges"` | `get_edges` |
| `"retrieve_context"` | `similarity_search` |

Any unrecognized operation string defaults to `list_nodes`.

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `"node_id is required for get_node"` | Called `get_node` without `node_id` | Provide the `node_id` parameter |
| `"node_id is required for get_edges"` | Called `get_edges` without `node_id` | Provide the `node_id` parameter |
| `"query is required for similarity_search"` | Called `similarity_search` without `query` | Provide a non-empty `query` string |
| `"not found"` | The node ID doesn't exist in the graph | Verify the ID; it may have been pruned by consolidation |
| Empty results | No matching nodes in the graph | The graph may be empty or the query too specific — broaden your search |

---

## Tips

1. **Start broad, narrow down.** Use `list_nodes` with a generous limit first,
   then `get_node` and `get_edges` for specific items of interest.

2. **Always check edge direction.** `get_edges` returns both inbound and
   outbound edges. A `supports` edge *from* node A *to* node B means A is the
   evidence and B is the claim — not the other way around.

3. **Use `min_confidence` thoughtfully.** Setting it too high (>0.8) may hide
   useful but unverified knowledge. Setting it to 0.0 shows everything including
   near-worthless nodes. Start at 0.3–0.5 for most inspection tasks.

4. **Similarity ≠ score.** In `similarity_search`, `similarity` is pure
   embedding cosine distance. `score` factors in confidence. A highly similar
   but low-confidence node will have a lower `score` than a moderately similar
   but high-confidence node.

5. **Watch for pruned nodes.** If you stored a node ID earlier in the session
   but `get_node` returns "not found", consolidation may have pruned it due to
   low confidence or merged it with a similar node. This is expected behavior.