# Graphonomous MCP Tools Reference

Graphonomous exposes its runtime capabilities over MCP as **tools** (action-oriented calls) and **resources** (read-only snapshots).

This page is a practical reference for using the current tool surface.

---

## Tool Categories

- **Knowledge graph write**: `store_node`, `store_edge`
- **Knowledge graph read/query**: `retrieve_context`, `query_graph`, `topology_analyze`
- **Learning loop**: `learn_from_outcome`, `deliberate`
- **Goal orchestration**: `manage_goal`, `review_goal`
- **Maintenance**: `run_consolidation`
- **Autonomy & prioritization**: `attention_survey`, `attention_run_cycle`

---

## 1) `store_node`

Store durable knowledge in the graph.

### Purpose
Create an atomic knowledge node (semantic/procedural/episodic) with confidence and optional metadata.

### Required
- `content` (string)

### Optional
- `node_type` (`episodic | semantic | procedural`)
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
- `edge_type` (`causal | related | contradicts | supports | derived_from`)
- `weight` (`0.0..1.0`)
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

## Resources (Read-Only)

### `graphonomous://runtime/health`
Returns runtime health plus lightweight counts.

### `graphonomous://goals/snapshot`
Returns goal totals, status breakdown, and serialized goals.

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