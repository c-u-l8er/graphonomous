# Graphonomous MCP Tools Reference

Graphonomous exposes its runtime capabilities over MCP as **5 loop-phase machines** (v0.4 default) and **5 read-only resources**. Each machine accepts an `action` parameter that dispatches to the underlying operation.

All 29 legacy v1 tools remain available for backward compatibility — machines delegate to them internally.

---

## Machine Architecture

```
retrieve → route → act → learn → consolidate
"What do I know?" → "What should I do?" → "Do it" → "Did it work?" → "Clean up"
```

---

## 1) `retrieve` Machine — "What do I know?"

### `action: "context"` — κ-aware ranked retrieval

Primary retrieval entrypoint. Returns ranked results, `causal_context` node IDs (for outcome feedback), and topology annotations (`routing`, SCCs, κ metrics).

**Required:** `query` (string)

**Optional:** `limit`, `expansion_hops`, `neighbors_per_node`, `min_score`, `node_type`

```json
{
  "action": "context",
  "query": "goal coverage and topology routing behavior",
  "limit": 8,
  "expansion_hops": 1
}
```

### `action: "episodic"` — time-range filtered retrieval

**Optional:** `since` (ISO 8601), `until` (ISO 8601), `limit` (default 20)

### `action: "procedural"` — semantic search for how-to nodes

**Required:** `query` (string)

**Optional:** `limit` (default 10)

### `action: "coverage"` — standalone epistemic assessment

No goal binding required. Returns coverage score, decision (act/learn/escalate), relevant nodes.

**Required:** `query` (string)

**Optional:** `limit`, `expansion_hops`

### `action: "trace_evidence"` — weighted Dijkstra evidence paths

Find the lowest-cost evidence path between two nodes. Optionally returns K alternate paths via Yen's algorithm.

Cost function: `cost(edge) = -log(confidence) + recency_decay(age_hours / half_life) + type_cost(edge_type)`

Type costs: `causal` = 0.0, `supports` = 0.1, `related_to` = 0.5, `contradicts` = 2.0, other = 1.0.

**Required:** `source_id`, `target_id`

**Optional:** `k` (default 1, max 10), `half_life_hours` (default 168.0), `bidirectional` (default true), `max_hops` (default 10)

### `action: "frontier"` — Wilson score uncertainty analysis

Identify highest-uncertainty nodes where evidence would most reduce uncertainty.

**Optional:** `min_gap` (default 0.3), `limit` (default 10)

---

## 2) `route` Machine — "What should I do?"

### `action: "topology"` — SCC/κ analysis

Compute SCCs, κ values, routing recommendation (`fast` or `deliberate`), and fault-line edges.

**Optional:** `node_ids` (explicit set) or `query` (topic-driven selection). If both provided, `node_ids` takes precedence.

### `action: "deliberate"` — κ-driven cyclic reasoning

Reason through cyclic knowledge regions and optionally persist conclusions.

**Required:** `query`

**Optional:** `node_ids`, `write_back` (bool — persist crystallized conclusions)

### `action: "attention_survey"` — read-only priority map

**Optional:** `include_idle` (bool)

Returns priority-ranked attention items with dispatch modes: `act`, `learn`, `escalate`, `idle`.

### `action: "attention_cycle"` — survey + triage + dispatch

**Optional:** `autonomy_override` (`observe` | `advise` | `act`)

### `action: "review_goal"` — coverage-driven decision gate

Evaluate if knowledge is sufficient to act, learn, or escalate.

**Required:** `goal_id`, `signal` (JSON object)

**Optional:** `options` (scoring config), `apply_decision` (bool), `transition_metadata` (JSON object)

Decision policy (when applied): `act` → active, `learn` → proposed, `escalate` → blocked.

---

## 3) `act` Machine — "Do it"

### `action: "store_node"` — store durable knowledge

**Required:** `content` (string)

**Optional:** `node_type` (`semantic` | `procedural` | `episodic` | `temporal` | `outcome` | `goal`), `confidence` (0.0–1.0), `source`, `metadata` (JSON), `agent_id`

```json
{
  "action": "store_node",
  "content": "Retriever combines similarity search with neighborhood expansion.",
  "node_type": "semantic",
  "confidence": 0.95,
  "source": "lib/graphonomous/retriever.ex"
}
```

### `action: "store_edge"` — create a directed relationship

**Required:** `source_id`, `target_id`

**Optional:** `edge_type` (`causal` | `causes` | `resolves` | `related` | `related_to` | `part_of` | `follows` | `contradicts` | `supersedes` | `depends_on` | `similar_to` | `supports` | `derived_from` | `temporal_before` | `temporal_after` | `co_occurs`), `weight` (0.0–1.0, default 0.3), `metadata` (JSON)

### `action: "delete_node"` — remove a node and its edges

**Required:** `node_id`

### `action: "manage_edge"` — edge lifecycle management

**Required:** `operation` (`list_all` | `list_for_node` | `update` | `delete`)

**Varies by operation:** `edge_id`, `node_id`, `weight`, `co_activation_count`, `decay_rate`

### `action: "manage_goal"` — goal CRUD and lifecycle

**Required:** `operation` (`create_goal` | `get_goal` | `list_goals` | `update_goal` | `delete_goal` | `transition_goal` | `set_progress` | `link_nodes` | `unlink_nodes`)

**Varies by operation:** `goal_id`, `payload` (JSON), `status`, `progress`, `node_ids` (JSON array), `metadata`, `filters`

```json
{
  "action": "manage_goal",
  "operation": "create_goal",
  "payload": "{\"title\":\"Document MCP surface\",\"priority\":\"high\"}"
}
```

### `action: "belief_revise"` — AGM-style belief revision

**Required:** `operation` (`expand` | `revise` | `contract`)

**For expand:** `content`, `confidence`

**For revise:** `node_id`, `content`, `rationale`

**For contract:** `node_id`, `rationale`

### `action: "forget_node"` — intentional forgetting

**Required:** `node_id`, `mode` (`soft` | `hard` | `cascade`)

**Optional:** `reason`

### `action: "forget_policy"` — budget-aware priority pruning

**Optional:** `dry_run` (bool), `max_nodes`

### `action: "gdpr_erase"` — GDPR Article 17 permanent deletion

**Required:** `node_id`

---

## 4) `learn` Machine — "Did it work?"

### `action: "from_outcome"` — close the feedback loop

**Required:** `action_id`, `status` (`success` | `partial_success` | `failure` | `timeout`), `confidence` (0.0–1.0), `causal_node_ids` (JSON array)

**Optional:** `evidence`, `retrieval_trace_id`, `decision_trace_id`, `action_linkage`, `grounding`

```json
{
  "action": "from_outcome",
  "action_id": "fix-retrieval-timeout-2026-03-28",
  "status": "success",
  "confidence": 0.85,
  "causal_node_ids": "[\"node_1\",\"node_2\"]",
  "evidence": "{\"tests\":\"pass\",\"user_confirmed\":true}"
}
```

### `action: "from_feedback"` — explicit feedback on a node

**Required:** `node_id`, `feedback_type` (`positive` | `negative` | `correction`)

**Optional:** `correction` (required when feedback_type is `correction`), `reason`

### `action: "detect_novelty"` — check for novel knowledge

**Required:** `query`

**Optional:** `threshold` (default 0.35), `limit` (default 5)

### `action: "from_interaction"` — full learning pipeline

**Required:** `user_message`, `model_response`

**Optional:** `context` (JSON), `extract_claims` (bool, default true)

Pipeline: novelty check → store episodic → extract semantic claims → create `derived_from` edges → link to nearest existing nodes.

### `action: "contradictions"` — detect belief conflicts

**Required:** `node_id` or `content` (one required)

---

## 5) `consolidate` Machine — "Clean up"

### `action: "run"` — trigger consolidation

**Optional:** `wait_ms` (0–30000)

7-stage pipeline: decay confidence → prune weak nodes → prune weak edges → strengthen co-activated → merge similar → promote timescale → generate abstractions.

### `action: "stats"` — aggregate graph health

Returns node/edge counts, type distributions, confidence stats, orphan count. No parameters required.

### `action: "query"` — operation-based graph inspection

**Required:** `operation` (`list_nodes` | `get_node` | `get_edges` | `similarity_search`)

**Varies by operation:** `node_id`, `query`, `limit`, `node_type`, `min_confidence`, `max_confidence`

### `action: "traverse"` — BFS walk

**Required:** `start_node_id`

**Optional:** `max_depth` (default 2, max 5), `relationship_types` (comma-separated or JSON array), `limit` (default 50)

---

## Resources (Read-Only)

### `graphonomous://runtime/health`
Runtime health plus lightweight counts.

### `graphonomous://goals/snapshot`
Goal totals, status breakdown, and serialized goals.

### `graphonomous://graph/node/{id}`
Individual node details by ID, including content, confidence, metadata, and connected edges.

### `graphonomous://graph/recent`
Recently added or accessed knowledge nodes (default limit 20), sorted by recency.

### `graphonomous://consolidation/log`
Consolidation state (cycle count, last run, config) and orchestrator plasticity metrics (learning rate, churn, counters).

---

## Recommended Call Pattern

For non-trivial tasks, follow the 5-machine loop:

1. `retrieve(action: "context", query: "...")`
2. Check `topology.routing` — if `"deliberate"`, `route(action: "deliberate", ...)`
3. `act(action: "store_node", ...)` / `act(action: "store_edge", ...)`
4. `learn(action: "from_outcome", ...)`
5. `act(action: "manage_goal", ...)` updates if goal-driven
6. `consolidate(action: "run")` periodically

This preserves retrieval quality, learning integrity, and long-term graph hygiene.

---

## Legacy v1 Tool Names

For backward compatibility, the following individual tool names still work and delegate to the corresponding machine action internally:

`store_node`, `store_edge`, `delete_node`, `manage_edge`, `retrieve_context`, `query_graph`, `topology_analyze`, `graph_traverse`, `graph_stats`, `retrieve_episodic`, `retrieve_procedural`, `coverage_query`, `trace_evidence_path`, `epistemic_frontier`, `learn_from_outcome`, `learn_from_feedback`, `learn_detect_novelty`, `learn_from_interaction`, `belief_revise`, `belief_contradictions`, `deliberate`, `manage_goal`, `review_goal`, `attention_survey`, `attention_run_cycle`, `forget_node`, `forget_by_policy`, `gdpr_erase`, `run_consolidation`
