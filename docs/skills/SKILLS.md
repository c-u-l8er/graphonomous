# Graphonomous MCP — Agent Skills

> **Purpose:** Teach any LLM connected to Graphonomous how to use its MCP tools
> correctly, idiomatically, and in the right sequence. Drop these files into your
> MCP client's context (or reference them in system prompts) so the model knows
> *when*, *why*, and *how* to call each tool.

---

## Quick Orientation

Graphonomous is a **continual learning engine** exposed entirely as MCP tools.
It maintains a **self-evolving knowledge graph** of episodic, semantic, and
procedural nodes connected by typed, weighted edges. Your job as an LLM agent
is to **read from and write to this graph** as you work, creating a durable
memory that improves over time.

### The Core Loop

Every interaction should follow this rhythm:

```
1. RETRIEVE  → retrieve_context (before answering / acting)
2. REASON    → use retrieved knowledge + conversation to think
3. ACT       → answer the user or perform the task
4. STORE     → store_node / store_edge (new knowledge learned)
5. LEARN     → learn_from_outcome (did it work? update confidence)
6. MAINTAIN  → run_consolidation (periodically, during idle)
```

---

## Skill Files

| File | What It Teaches |
|------|----------------|
| [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) | The foundational read/write loop — `retrieve_context`, `store_node`, `store_edge` |
| [02_LEARNING_LOOP.md](02_LEARNING_LOOP.md) | Closed-loop learning — `learn_from_outcome` and confidence updates |
| [03_GRAPH_INSPECTION.md](03_GRAPH_INSPECTION.md) | Inspecting graph state — `query_graph` operations |
| [04_GOAL_MANAGEMENT.md](04_GOAL_MANAGEMENT.md) | Durable intent — `manage_goal` CRUD and lifecycle |
| [05_COVERAGE_AND_REVIEW.md](05_COVERAGE_AND_REVIEW.md) | Epistemic self-modeling — `review_goal` and act/learn/escalate decisions |
| [06_TOPOLOGY_AND_DELIBERATION.md](06_TOPOLOGY_AND_DELIBERATION.md) | κ-aware routing — `topology_analyze` and `deliberate` |
| [07_CONSOLIDATION.md](07_CONSOLIDATION.md) | Memory maintenance — `run_consolidation` and decay/prune/merge |
| [08_ATTENTION.md](08_ATTENTION.md) | Autonomous focus — `attention_survey` and `attention_run_cycle` |
| [09_WORKFLOWS.md](09_WORKFLOWS.md) | End-to-end recipes for common tasks |
| [10_ANTI_PATTERNS.md](10_ANTI_PATTERNS.md) | What NOT to do — common mistakes and how to avoid them |
| [11_BELIEF_REVISION.md](11_BELIEF_REVISION.md) | AGM-style belief management — `belief_revise`, `belief_contradictions`, self-correcting knowledge |
| [12_FORGETTING.md](12_FORGETTING.md) | Memory lifecycle — `forget_node`, `forget_by_policy`, `gdpr_erase`, active memory management |
| [13_EPISTEMIC_FRONTIER.md](13_EPISTEMIC_FRONTIER.md) | Uncertainty-driven exploration — `epistemic_frontier`, Wilson intervals, information gain |
| [14_SYNC.md](14_SYNC.md) | Filesystem sync — batch-ingest changed files, extract edges, optional consolidation |
| [15_WATCH.md](15_WATCH.md) | Filesystem watch — continuous polling-based monitoring with live sync to graph |
| [16_TRACE_EVIDENCE_PATH.md](16_TRACE_EVIDENCE_PATH.md) | Evidence provenance — `trace_evidence_path`, weighted Dijkstra, Yen's K-shortest paths |

---

## Tool Inventory

### Write Tools
| Tool | Purpose | Key Params |
|------|---------|------------|
| `store_node` | Store a knowledge node | `content` (required), `node_type`, `confidence`, `source`, `metadata`, `agent_id` |
| `store_edge` | Create a directed edge between nodes | `source_id` + `target_id` (required), `edge_type`, `weight`, `metadata`, `agent_id` |
| `delete_node` | Remove a node and its edges from the graph | `node_id` (required) |
| `manage_edge` | List, update, or delete edges | `operation` (required), `edge_id`, `source_id`, `target_id`, `updates` |
| `learn_from_outcome` | Report action outcome and update causal node confidence | `action_id` + `status` + `confidence` + `causal_node_ids` (required), `evidence` |
| `learn_from_feedback` | Process positive/negative/correction feedback on a node | `node_id` + `feedback_type` (required), `correction` |
| `learn_detect_novelty` | Check if a query represents novel knowledge | `query` (required), `threshold` |
| `learn_from_interaction` | Full learning pipeline: novelty → episodic → semantic extraction → edges | `user_message` + `model_response` (required), `context` |
| `belief_revise` | AGM-style belief revision: expand, revise, or contract beliefs | `operation` (required), `content`, `node_id`, `rationale`, `confidence`, `agent_id` |
| `belief_contradictions` | Detect contradictions for a node or content string | `node_id` or `content` (one required) |
| `forget_node` | Forget a node: soft (hide), hard (delete), or cascade (delete + orphans) | `node_id` (required), `mode` (soft/hard/cascade), `reason` |
| `forget_by_policy` | Auto-prune lowest-priority nodes by hybrid LRU + priority-decay policy | `policy`, `dry_run`, `max_nodes` |
| `gdpr_erase` | Permanent GDPR Article 17 deletion with audit trail | `node_id` (required) |
| `manage_goal` | Goal CRUD and lifecycle operations | `operation` (required), varies by operation |
| `review_goal` | Epistemic coverage evaluation with decision policy | `goal_id` + `signal` (required) |
| `deliberate` | κ-driven deliberation over cyclic knowledge regions | `query` (required), `node_ids`, `write_back` |
| `run_consolidation` | Trigger memory maintenance cycle | `action`, `wait_ms` |
| `attention_run_cycle` | Execute one attention survey+triage+dispatch cycle | `autonomy_override` |

### Read Tools
| Tool | Purpose | Key Params |
|------|---------|------------|
| `retrieve_context` | Hybrid search (nomic 768d + BM25 + cross-encoder reranking) with topology | `query` (required), `limit`, `expansion_hops`, `min_score`, `node_type` |
| `query_graph` | Inspect graph state (list, get, edges, similarity) | `operation` (required), varies by operation |
| `topology_analyze` | Compute SCCs, κ values, routing decision | `node_ids`, `query` |
| `graph_traverse` | BFS walk from a starting node with depth/relationship filters | `start_node_id` (required), `max_depth`, `relationship_types` |
| `graph_stats` | Aggregate graph statistics (counts, distributions, orphans) | _(none required)_ |
| `retrieve_episodic` | Time-range filtered episodic node retrieval | `since`, `until`, `limit` |
| `retrieve_procedural` | Semantic search scoped to procedural nodes with precondition matching | `query` (required), `limit`, `min_confidence` |
| `coverage_query` | Standalone epistemic coverage assessment (act/learn/escalate) | `query` (required), `limit`, `expansion_hops` |
| `trace_evidence_path` | Weighted Dijkstra / Yen's K-shortest paths for evidence provenance tracing | `from` + `to` (required), `k`, `half_life_hours`, `bidirectional`, `max_hops` |
| `epistemic_frontier` | Identify highest-uncertainty nodes where evidence would most reduce uncertainty | `min_gap` (default 0.3), `limit` (default 10) |
| `attention_survey` | Read current attention priority map | `include_idle` |

### Resources (Read-Only)
| URI | What It Returns |
|-----|----------------|
| `graphonomous://runtime/health` | Runtime health: node/edge counts, consolidator state, uptime |
| `graphonomous://goals/snapshot` | Current GoalGraph snapshot: all goals with status/progress |
| `graphonomous://graph/node/{id}` | Individual node details + connected edges (URI template) |
| `graphonomous://graph/recent` | Recently added/accessed nodes, sorted by recency |
| `graphonomous://consolidation/log` | Consolidator state + orchestrator plasticity metrics |

---

## Node Types — Use Them Correctly

| Type | Store When You Learn... | Examples |
|------|------------------------|---------|
| **semantic** | A fact, definition, relationship, or architectural truth | "Module X is responsible for Y", "The API uses JWT auth", "Config Z defaults to 500ms" |
| **procedural** | A procedure, workflow, how-to, or recipe | "To deploy: run X then Y then Z", "Debug by checking logs at /var/log/foo" |
| **episodic** | Something that happened — an event, observation, or interaction record | "User asked about auth on 2025-01-15", "Build failed due to missing dep", "Explored /src/api and found 12 endpoints" |

**Rule of thumb:** If it answers "what is?" → semantic. If it answers "how to?" → procedural. If it answers "what happened?" → episodic.

---

## Edge Types — When to Use Each

| Type | Meaning | Example |
|------|---------|---------|
| `causal` | A causes or drives B | "Config change → behavior change" |
| `supports` | A provides evidence for B | "Test result → hypothesis" |
| `contradicts` | A conflicts with B | "Doc says X, but code does Y" |
| `related` | A is thematically connected to B | "Auth module ↔ User module" |
| `derived_from` | A was derived or extracted from B | "Summary node ← source document node" |
| `superseded_by` | A was replaced by B (created by belief revision) | "Old fact → revised fact" |

---

## Confidence Scores — What They Mean

| Range | Meaning | When to Use |
|-------|---------|-------------|
| **0.9–1.0** | Verified fact, directly observed in source | Copied from code/docs, confirmed by test output |
| **0.7–0.89** | High confidence, strong evidence but not directly verified | Inferred from multiple consistent sources |
| **0.5–0.69** | Moderate confidence, reasonable inference | Single source, plausible but unverified |
| **0.3–0.49** | Low confidence, uncertain | Inferred from indirect evidence, may be outdated |
| **0.0–0.29** | Speculative or likely wrong | Guess, contradicted by other evidence |

**Default is 0.5.** Always adjust based on evidence quality.

---

## Session Startup Checklist

When you begin a new conversation with Graphonomous connected:

1. **Retrieve prior context** for the user's topic:
   ```
   retrieve_context(query: "summary of prior work on <topic>")
   ```

2. **Check active goals** if this is a project session:
   ```
   manage_goal(operation: "list_goals")
   ```

3. **Survey attention** to see what needs focus:
   ```
   attention_survey(include_idle: false)
   ```

4. **Proceed with the user's request**, using retrieved context to inform your response.

---

## End-of-Session Checklist

Before ending a productive session:

1. **Store any new knowledge** discovered during the conversation.
2. **Report outcomes** for actions taken via `learn_from_outcome`.
3. **Update goal progress** if goals were advanced.
4. **Trigger consolidation** if the session was long or produced many nodes:
   ```
   run_consolidation(action: "run_and_status", wait_ms: 2000)
   ```

---

## Repository Wiring References

These skills are wired into repository-level instructions and onboarding docs:

- `AGENTS.md` — repository-wide agent behavior policy (Graphonomous-first loop)
- `CLAUDE.md` — Claude-specific operating instructions and required skills loading
- `README.md` — always-on skills wiring section for runtime/prompt integration
- `docs/ZED.md` — chat startup wiring guidance for loading bootstrap + skills in Zed

If you are configuring an assistant/chat runtime, treat these files as the
operational entry points that enforce this skills pack every session.

## How to Use These Skills Files

**For system prompts:** Include `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` and
`SKILLS.md` first, then whichever numbered skill files are relevant to the task.

**For context injection:** Reference specific skill files when the user asks
about a capability (e.g., "see 04_GOAL_MANAGEMENT.md for goal operations").

**For agent bootstrapping:** Use `09_WORKFLOWS.md` to give the agent end-to-end
recipes it can follow autonomously.

**For repository-consistent behavior:** Keep this skills pack aligned with
`AGENTS.md`, `CLAUDE.md`, `README.md`, and `docs/ZED.md` whenever behavior
rules are changed.

**Minimum viable context:** If you can only include two files, include
`AGENT_BOOTSTRAP_PROMPT.md` and `SKILLS.md`.