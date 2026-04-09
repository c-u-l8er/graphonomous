---
name: store
description: Use when the user says "remember this", "save this", "store this fact", "add to memory", "note this down", "persist this knowledge", or wants to save a specific piece of knowledge without retrieval. Dedicated write path to the knowledge graph. Routes through `act` machine.
argument-hint: <knowledge to store> [--type semantic|procedural|episodic] [--confidence <0.0-1.0>]
---

# Store Knowledge

Save a specific piece of knowledge to the Graphonomous knowledge graph.

## Arguments

Knowledge to store and optional flags: $ARGUMENTS

## When to Use

- User explicitly asks to remember or save something
- A decision, finding, or fact should persist beyond this session
- After learning something that isn't tied to a specific retrieval (use `/graphonomous:learn` when it is)

## Quick Store

```
act(action: "store_node", content: "<one atomic fact>", node_type: "semantic", confidence: 0.7, source: "conversation")
```

## Step-by-Step

1. **Check for duplicates first** — always:
```
consolidate(action: "query", operation: "similarity_search", query: "<the fact>", limit: 3)
```
- similarity > 0.90 — **duplicate** — update existing node via `learn(action: "from_feedback", node_id: "<id>", feedback_type: "correction", correction: "<updated content>")`
- similarity 0.70–0.90 — **related** — store new node + add `related` edge
- similarity < 0.70 — **novel** — safe to store

2. **Store the node:**
```
act(action: "store_node",
  content: "<one atomic fact — keep it focused>",
  node_type: "semantic",
  confidence: 0.7,
  source: "conversation",
  metadata: {"topic": "<topic>", "session": "<context>"}
)
```

3. **Link to related nodes** (if similarity search found neighbors):
```
act(action: "store_edge", source_id: "<new_id>", target_id: "<related_id>", edge_type: "related_to", weight: 0.5)
```

## Node Types

| Type | Use When | Example |
|------|----------|---------|
| `semantic` | Facts, definitions, architecture | "WebHost.Systems uses Supabase Auth with JWT" |
| `procedural` | Workflows, how-to, recipes | "To deploy: run mix release, then docker build" |
| `episodic` | Events, observations, what happened | "Auth middleware was refactored on 2026-03-15" |
| `temporal` | Time-bound monitoring events | "CPU spike at 14:30 during load test" |
| `outcome` | Measured results, benchmarks | "Latency dropped 40% after caching change" |
| `goal` | Objectives, intent (prefer `/graphonomous:goals` for formal goals) | "Need to migrate auth to new compliance standard" |

## Confidence Calibration

- **0.9–1.0**: Directly observed in code/docs/tests
- **0.7–0.89**: Strong evidence, not directly verified
- **0.5–0.69**: Single source, plausible
- **0.3–0.49**: Indirect evidence, uncertain
- **0.0–0.29**: Speculative — flag as such

## Batch Store (multiple facts)

For storing several related facts at once:

1. Store each as a separate node (one atomic fact per node)
2. Create edges between them:
   - Same topic → `related_to` (weight 0.5)
   - Cause/effect → `causal` (weight 0.7)
   - One supports another → `supports` (weight 0.6)
   - One supersedes another → `supersedes` (weight 0.8)

## Anti-patterns to avoid

- Storing without duplicate checking — always search first
- Multi-fact nodes — split into atomic pieces and link with edges
- Setting confidence above 0.7 for conversational knowledge — reserve 0.8+ for verified facts
- Storing ephemeral session state — use tasks/plans for that, not the knowledge graph
- Skipping edges — isolated nodes are hard to retrieve later
