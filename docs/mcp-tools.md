# Graphonomous MCP Tools Reference

Graphonomous exposes its runtime capabilities over MCP as **tools** (action-oriented calls) and **resources** (read-only snapshots).

This page is a practical reference for using the current tool surface.

---

## Tool Categories

- **Knowledge graph write**: `store_node`, `store_edge`, `delete_node`, `manage_edge`
- **Knowledge graph read/query**: `retrieve_context`, `query_graph`, `topology_analyze`, `graph_traverse`, `graph_stats`
- **Specialized retrieval**: `retrieve_episodic`, `retrieve_procedural`, `coverage_query`
- **Learning loop**: `learn_from_outcome`, `learn_from_feedback`, `learn_detect_novelty`, `learn_from_interaction`, `deliberate`
- **Goal orchestration**: `manage_goal`, `review_goal`
- **Maintenance**: `run_consolidation`
- **Autonomy & prioritization**: `attention_survey`, `attention_run_cycle`

---

## 1) `store_node`

Store durable knowledge in the graph.

### Purpose
Create an atomic knowledge node with confidence and optional metadata.

### Required
- `content` (string)

### Optional
- `node_type` (`episodic | semantic | procedural | temporal | outcome | goal`)
- `confidence` (`0.0..1.0`)
- `source` (string)
- `metadata` (JSON object string)

### Example
```json
{
  "content": "Retriever combines similarity search with neighborhood expansion.",
  "node_type": "semantic",
  "confidence": 0.95,
  "source": "lib/graphonomous/retriever.ex"
}
```

---

## 2) `store_edge`

Create a directed relationship between two nodes.

### Required
- `source_id` (string)
- `target_id` (string)

### Optional
- `edge_type` (`causes | resolves | related_to | part_of | follows | contradicts | supersedes | depends_on | similar_to | supports | derived_from | temporal_before | temporal_after | co_occurs` — also accepts legacy: `causal`, `related`)
- `weight` (`0.0..1.0`, default 0.3)
- `metadata` (JSON object string)

### Example
```json
{
  "source_id": "node_a",
  "target_id": "node_b",
  "edge_type": "supports",
  "weight": 0.8
}
```

---

## 3) `retrieve_context`

Retrieve ranked context for a natural-language query.

### Purpose
Primary retrieval entrypoint. Returns:
- ranked `results`
- `causal_context` node IDs (for outcome feedback)
- topology annotations (`routing`, SCCs, κ metrics)

### Required
- `query` (string)

### Optional
- `limit`
- `expansion_hops`
- `neighbors_per_node`
- `min_score`
- `node_type`

### Example
```json
{
  "query": "goal coverage and topology routing behavior",
  "limit": 8,
  "expansion_hops": 1
}
```

---

## 4) `learn_from_outcome`

Close the feedback loop after an action.

### Purpose
Persist outcome evidence and update confidence on causal nodes.

### Required
- `action_id`
- `status` (`success | partial_success | failure | timeout`)
- `confidence` (`0.0..1.0`)
- `causal_node_ids` (JSON array string)

### Optional
- `action_linkage`
- `decision_trace_id`
- `retrieval_trace_id`
- `evidence`
- `grounding`

### Example
```json
{
  "action_id": "fix-retrieval-timeout-2026-03-28",
  "status": "success",
  "confidence": 0.85,
  "causal_node_ids": "[\"node_1\",\"node_2\"]",
  "evidence": "{\"tests\":\"pass\",\"user_confirmed\":true}"
}
```

---

## 5) `query_graph`

Inspect graph state with operation-based modes.

### Operations
- `list_nodes`
- `get_node`
- `get_edges`
- `similarity_search`

### Common fields
- `operation` (required)
- `node_id` (for `get_node` / `get_edges`)
- `query` (for `similarity_search`)
- `limit`
- `node_type`
- `min_confidence`

### Example
```json
{
  "operation": "similarity_search",
  "query": "consolidator decay behavior",
  "limit": 5
}
```

---

## 6) `manage_goal`

GoalGraph CRUD + lifecycle orchestration tool.

### Supported operations
- `create_goal`
- `get_goal`
- `list_goals`
- `update_goal`
- `delete_goal`
- `transition_goal`
- `set_progress`
- `link_nodes`
- `unlink_nodes`
- `review_goal`

### Typical payload fields
- `goal_id`
- `payload` (JSON object string)
- `status`
- `progress`
- `node_ids` (JSON array string)
- `metadata`
- `signal`
- `opts`

### Example (`create_goal`)
```json
{
  "operation": "create_goal",
  "payload": "{\"title\":\"Document MCP surface\",\"priority\":\"high\"}"
}
```

---

## 7) `review_goal`

Coverage-driven decision gate for goals.

### Purpose
Evaluate if knowledge is sufficient to:
- `act`
- `learn`
- `escalate`

### Required
- `goal_id`
- `signal` (JSON object)

### Optional
- `options` (scoring config)
- `apply_decision` (bool-like)
- `transition_metadata` (JSON object)

### Decision policy (when applied)
- `act` -> `active`
- `learn` -> `proposed`
- `escalate` -> `blocked`

---

## 8) `run_consolidation`

Trigger or inspect consolidation cycles.

### Actions
- `run`
- `status`
- `run_and_status` (default)

### Optional
- `wait_ms` (`0..30000`)

### Example
```json
{
  "action": "run_and_status",
  "wait_ms": 2000
}
```

---

## 9) `topology_analyze`

Analyze graph topology for SCC/κ complexity.

### Purpose
Compute:
- SCCs
- κ values
- routing recommendation (`fast` or `deliberate`)
- fault-line edges

### Inputs
- `node_ids` (optional explicit set), or
- `query` (optional topic-driven selection)

---

## 10) `deliberate`

Run κ-driven deliberation over cyclic regions.

### Required
- `query`

### Optional
- `node_ids`
- `write_back` (persist crystallized conclusions)

### Use when
- topology routing indicates `deliberate`
- contradictions or cyclic dependencies need structured resolution

---

## 11) `attention_survey`

Read current attention priority map.

### Optional
- `include_idle` (bool)

### Returns
Priority-ranked attention items with dispatch modes such as:
- `act`
- `learn`
- `escalate`
- `idle`

---

## 12) `attention_run_cycle`

Execute one survey + triage + dispatch cycle.

### Optional
- `autonomy_override` (`observe | advise | act`)

### Use cases
- periodic autonomous prioritization
- bounded background orchestration
- generating action recommendations

---

## 13) `graph_traverse`

BFS walk from a starting node with depth and relationship filters.

### Required
- `start_node_id` (string)

### Optional
- `max_depth` (integer, default 3)
- `relationship_types` (comma-separated string, e.g. `"causal,supports"`)
- `include_content` (bool, default true)

### Returns
Subgraph with visited nodes, edges, depth map, and traversal metadata.

---

## 14) `graph_stats`

Aggregate graph statistics and health indicators.

### No required inputs

### Returns
- `node_count`, `edge_count`
- `type_distribution` (node types)
- `edge_type_distribution`
- Confidence statistics (mean, min, max, std_dev)
- `orphan_count` (nodes with no edges)

---

## 15) `coverage_query`

Standalone epistemic coverage assessment without goal binding.

### Required
- `query` (string)

### Optional
- `limit` (integer)
- `expansion_hops` (integer)
- `min_confidence` (float)

### Returns
Coverage score, decision (`act`/`learn`/`escalate`), relevant nodes, and confidence stats.

---

## 16) `retrieve_episodic`

Retrieve episodic (event/observation) nodes filtered by time range.

### Optional
- `since` (ISO 8601 datetime)
- `until` (ISO 8601 datetime)
- `limit` (integer, default 20)

### Returns
Episodic nodes sorted by recency.

---

## 17) `retrieve_procedural`

Semantic search scoped to procedural (how-to) nodes.

### Required
- `query` (string)

### Optional
- `limit` (integer, default 10)
- `min_confidence` (float)

### Returns
Procedural nodes with extracted steps from content.

---

## 18) `learn_from_feedback`

Process explicit feedback (positive/negative/correction) on a node.

### Required
- `node_id` (string)
- `feedback_type` (`positive` | `negative` | `correction`)

### Optional
- `correction` (string — required when `feedback_type` is `correction`)
- `source` (string)

### Behavior
- `positive` → `learn_from_outcome` with status `success`
- `negative` → `learn_from_outcome` with status `failure`
- `correction` → directly updates node content via `update_node`

---

## 19) `learn_detect_novelty`

Check whether a query represents novel knowledge not yet in the graph.

### Required
- `query` (string)

### Optional
- `threshold` (float, default 0.35)

### Returns
- `is_novel` (bool)
- `novelty_score` (float, 0.0–1.0)
- `nearest_nodes` with similarity scores

---

## 20) `learn_from_interaction`

Full learning pipeline for a user-model interaction.

### Required
- `user_message` (string)
- `model_response` (string)

### Optional
- `context` (JSON string)
- `novelty_threshold` (float, default 0.35)

### Pipeline
1. Novelty check on user message
2. Store episodic node for the interaction
3. Extract semantic claims from response sentences
4. Create `derived_from` edges to episodic node
5. Link to nearest existing nodes

---

## 21) `delete_node`

Remove a knowledge node and its connected edges.

### Required
- `node_id` (string)

### Example
```json
{
  "node_id": "nd_abc123"
}
```

---

## 22) `manage_edge`

Edge lifecycle management: list, update, and delete edges.

### Supported operations
- `list_all` — list all edges in the graph
- `list_for_node` — list edges connected to a specific node
- `update` — modify edge weight, co_activation_count, or decay_rate
- `delete` — remove an edge by ID

### Fields
- `operation` (required)
- `edge_id` (for update/delete)
- `node_id` (for list_for_node)
- `weight`, `co_activation_count`, `decay_rate` (for update)

### Example (`update`)
```json
{
  "operation": "update",
  "edge_id": "ed_xyz789",
  "weight": 0.9,
  "co_activation_count": 5
}
```

---

## Resources (Read-Only)

### `graphonomous://runtime/health`
Returns runtime health plus lightweight counts.

### `graphonomous://goals/snapshot`
Returns goal totals, status breakdown, and serialized goals.

### `graphonomous://graph/node/{id}`
Individual node details by ID, including content, confidence, metadata, and connected edges. URI template — replace `{id}` with the node ID.

### `graphonomous://graph/recent`
Recently added or accessed knowledge nodes (default limit 20), sorted by recency.

### `graphonomous://consolidation/log`
Consolidation state (cycle count, last run, config) and orchestrator plasticity metrics (learning rate, churn, counters).

---

## Recommended Call Pattern

For non-trivial tasks:

1. `retrieve_context`
2. reason/act
3. `store_node` / `store_edge` (if new durable knowledge emerged)
4. `learn_from_outcome`
5. `manage_goal` updates (if goal-driven work)
6. `run_consolidation` periodically

This preserves retrieval quality, learning integrity, and long-term graph hygiene.