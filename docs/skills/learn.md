---
name: learn
description: Use after completing a consequential action informed by retrieved knowledge. Reports outcomes to update confidence in the knowledge graph. Use when the user says "report outcome", "learn from this", "update confidence", or after any action that used retrieved context.
argument-hint: <action-description> <success|failure|partial_success|timeout>
---

# Learning Loop

Close the feedback loop so the graph learns what works and what doesn't.

## Arguments

Action and status: $ARGUMENTS

## Report an Outcome

```
learn(
  action: "from_outcome",
  action_id: "descriptive-slug-of-what-you-did",
  status: "success",
  confidence: 0.8,
  causal_node_ids: ["<id1>", "<id2>"]
)
```

**Required fields:**
- `action_id` — descriptive slug of the action taken
- `status` — one of: `success`, `partial_success`, `failure`, `timeout`
- `confidence` — 0.0–1.0, reliability of this feedback signal (NOT the original decision quality)
- `causal_node_ids` — from `causal_context` saved during retrieval

**Optional fields:**
- `evidence` — structured evidence object (test results, metrics, user feedback)
- `retrieval_trace_id` — audit trail linking back to the retrieval call
- `decision_trace_id` — for multi-agent setups tracking decision provenance
- `action_linkage` — metadata about what action was taken
- `grounding` — outcome provenance (where the feedback signal came from)

**Status meanings and confidence effects:**
- `success` → boosts confidence of causal nodes
- `failure` → reduces confidence of causal nodes (the knowledge was wrong/misleading)
- `partial_success` → small boost
- `timeout` → minimal change — **NOT the same as failure!** Use when outcome is unknown.

### Response structure

The response contains per-node confidence updates:
```json
{
  "processed": 3,
  "skipped": 0,
  "updates": [
    {"node_id": "abc", "old_confidence": 0.7, "new_confidence": 0.78},
    {"node_id": "def", "old_confidence": 0.6, "new_confidence": 0.67}
  ]
}
```

`processed` = causal nodes examined; `skipped` = nodes not found. Confidence adjustments are bounded — outcome confidence scales the delta (high-confidence feedback produces larger changes).

## Full provenance example

```
learn(
  action: "from_outcome",
  action_id: "fix-auth-middleware",
  status: "success",
  confidence: 0.9,
  causal_node_ids: ["node-abc", "node-def"],
  evidence: {"test_passed": true, "error_resolved": true, "regression_check": "clean"},
  retrieval_trace_id: "ret-12345",
  grounding: "test suite output confirmed fix"
)
```

## Pattern

1. `retrieve(action: "context", query: "...")` → save `causal_context`
2. Act on retrieved knowledge
3. `learn(action: "from_outcome", ...)` with real causal IDs and honest status

## Learn from Feedback

Process explicit feedback on a specific node:

```
learn(action: "from_feedback", node_id: "<id>", feedback_type: "positive")
learn(action: "from_feedback", node_id: "<id>", feedback_type: "negative")
learn(action: "from_feedback", node_id: "<id>", feedback_type: "correction", correction: "The correct fact is...")
```

- `positive` → routes through `learn_from_outcome` with status `success`
- `negative` → routes through `learn_from_outcome` with status `failure`
- `correction` → directly updates the node content

## Detect Novelty

Check if a query represents knowledge not yet in the graph:

```
learn(action: "detect_novelty", query: "some new concept", threshold: 0.35)
```

Returns `is_novel` (bool), `novelty_score` (0.0–1.0), and `nearest_nodes` with similarity scores. Higher novelty = less existing coverage.

## Learn from Interaction

Full learning pipeline for a user-model exchange:

```
learn(
  action: "from_interaction",
  user_message: "How does the auth middleware work?",
  model_response: "The auth middleware validates JWT tokens and...",
  novelty_threshold: 0.35
)
```

Pipeline: novelty check → store episodic node → extract semantic claims from response → create `derived_from` edges → link to nearest existing nodes.

## Anti-patterns to avoid
- Fire and forget — never reporting outcomes after using retrieved knowledge
- Using `failure` when you mean `timeout` — timeout means unknown, not wrong
- Fabricating causal node IDs — only use IDs from actual `causal_context`
- Setting confidence to 1.0 on every outcome — calibrate by signal reliability
- Discarding `causal_context` between retrieval and outcome — hold it in working memory
