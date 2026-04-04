# Skill 02 — The Learning Loop

> **Tools covered:** `learn_from_outcome`
> **Depends on:** [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) (you must store nodes and retrieve context before you can close the loop)

---

## Why This Matters

Retrieval and storage alone give you a *static* knowledge graph — a notebook.
The learning loop turns it into a **self-correcting** knowledge graph. When you
report outcomes ("that worked" / "that failed"), Graphonomous adjusts confidence
on the nodes that drove the decision. Over time, good knowledge rises and bad
knowledge sinks.

Without the learning loop, the graph has no way to distinguish a brilliant
insight from a plausible-sounding hallucination. **Every consequential action
should close the loop.**

---

## The Closed-Loop Pattern

```
    ┌──────────────────────────────────────────────┐
    │                                              │
    ▼                                              │
 retrieve_context ──► reason ──► act ──► observe ──┘
    │                                    outcome
    │                                      │
    │              learn_from_outcome ◄─────┘
    │                     │
    │            confidence deltas applied
    │            to causal_node_ids
    ▼
 next retrieval now reflects
 updated confidence scores
```

The key insight: **`causal_node_ids`** are the node IDs returned by
`retrieve_context` in the `causal_context` array. These are the nodes that
*caused* you to make the decision. When the outcome is known, you feed them
back so Graphonomous can adjust their confidence.

---

## Tool Reference: `learn_from_outcome`

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `action_id` | string | A unique identifier for the action you took. Use a descriptive slug. |
| `status` | string | One of: `success`, `partial_success`, `failure`, `timeout` |
| `confidence` | number | 0.0–1.0. How confident you are in this outcome signal (not the action — the *signal quality*). |
| `causal_node_ids` | string (JSON array) | The node IDs that informed this action. Typically from `retrieve_context`'s `causal_context`. |

### Optional Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `evidence` | string (JSON object) | Structured evidence supporting the outcome. Include measurable signals. |
| `retrieval_trace_id` | string | Links back to the retrieval that produced the causal nodes. Useful for provenance auditing. |
| `decision_trace_id` | string | Links to the planner/executor decision context. Useful in multi-agent setups. |
| `action_linkage` | string (JSON object) | Metadata about what action was taken and why. |
| `grounding` | string (JSON object) | Provenance info: where the outcome observation came from. |

### Response Shape

```
{
  "action_id": "fix-auth-middleware",
  "status": "success",
  "retrieval_trace_id": null,
  "decision_trace_id": null,
  "processed": 3,       // how many causal nodes were examined
  "updated": 3,         // how many had their confidence adjusted
  "skipped": 0,         // how many were skipped (e.g., not found)
  "updates": [          // per-node deltas
    {"node_id": "abc123", "old_confidence": 0.6, "new_confidence": 0.72},
    {"node_id": "def456", "old_confidence": 0.5, "new_confidence": 0.62},
    {"node_id": "ghi789", "old_confidence": 0.7, "new_confidence": 0.81}
  ]
}
```

---

## How Confidence Updates Work

Graphonomous applies bounded adjustments scaled by:

1. **Outcome status:**
   - `success` → increase confidence on causal nodes
   - `failure` → decrease confidence on causal nodes
   - `partial_success` → proportional (smaller) increase
   - `timeout` → typically minimal or no adjustment

2. **Outcome confidence:** Your `confidence` parameter scales the delta.
   A `confidence: 0.9` success produces a larger boost than `confidence: 0.3`.

3. **Bounding:** Confidence is always clamped to `[0.0, 1.0]`. Nodes don't
   overshoot or undershoot.

The system also creates an internal `:outcome` node linked to the causal parents,
building a durable record of *what happened and why*.

---

## Status Values — Choose Correctly

| Status | When to Use | Confidence Effect |
|--------|-------------|-------------------|
| `success` | The action achieved its intended result fully | ↑ Boost causal nodes |
| `partial_success` | The action partly worked, or worked with caveats | ↑ Small boost |
| `failure` | The action did not achieve its goal, or produced a wrong/harmful result | ↓ Decrease causal nodes |
| `timeout` | The action did not complete in time; outcome is unknown | → Minimal/no change |

**Important:** `timeout` is not failure. It means you don't have a signal. Don't
use `failure` when you simply ran out of time — that would unfairly penalize the
causal knowledge.

---

## Practical Examples

### Example 1: Code Fix Succeeded

You retrieved context about an auth bug, suggested a fix, and the user confirmed it worked.

```
retrieve_context(query: "authentication middleware error handling")
→ causal_context: ["node-a1b2", "node-c3d4", "node-e5f6"]

// ... you suggest a fix, user confirms it works ...

learn_from_outcome(
  action_id: "fix-auth-error-handling-2025-06",
  status: "success",
  confidence: 0.85,
  causal_node_ids: '["node-a1b2", "node-c3d4", "node-e5f6"]',
  evidence: '{"fix_type": "null_check_added", "file": "src/middleware/auth.ts", "user_confirmed": true}'
)
```

### Example 2: Recommendation Failed

You retrieved context about deployment, recommended a strategy, but it caused issues.

```
retrieve_context(query: "deployment strategy for microservices")
→ causal_context: ["node-x1y2", "node-z3w4"]

// ... your recommendation caused downtime ...

learn_from_outcome(
  action_id: "deploy-strategy-rec-2025-06",
  status: "failure",
  confidence: 0.7,
  causal_node_ids: '["node-x1y2", "node-z3w4"]',
  evidence: '{"issue": "rolling update caused 5min downtime", "root_cause": "health check misconfigured"}'
)
```

The nodes that said "rolling updates work fine" now have reduced confidence.
Next time you retrieve context about deployment, alternative strategies will rank higher.

### Example 3: Partial Success with Exploration

You explored a directory structure and found some of what you expected but not all.

```
retrieve_context(query: "project directory structure and module layout")
→ causal_context: ["node-struct1", "node-struct2"]

// ... you explored and found 8 of 12 expected modules ...

learn_from_outcome(
  action_id: "explore-module-layout-iter3",
  status: "partial_success",
  confidence: 0.6,
  causal_node_ids: '["node-struct1", "node-struct2"]',
  evidence: '{"expected_modules": 12, "found_modules": 8, "missing": ["federation", "admin_ui", "telemetry", "rest_api"]}'
)
```

### Example 4: Timeout During Build

You tried to verify a build command but it timed out.

```
learn_from_outcome(
  action_id: "verify-build-cmd-elixir",
  status: "timeout",
  confidence: 0.3,
  causal_node_ids: '["node-build1"]',
  evidence: '{"command": "mix compile", "timeout_ms": 30000, "reason": "large dependency tree"}'
)
```

Low confidence on the signal means almost no adjustment. The "how to build" node
retains its current confidence — we didn't learn it was *wrong*, just that we
couldn't verify it this time.

### Example 5: With Full Provenance (Multi-Agent)

When operating in a multi-agent pipeline, include trace IDs and linkage metadata.

```
learn_from_outcome(
  action_id: "agent-planner-step-7",
  status: "success",
  confidence: 0.9,
  causal_node_ids: '["node-p1", "node-p2", "node-p3"]',
  retrieval_trace_id: "ret-trace-20250615-001",
  decision_trace_id: "dec-trace-planner-step-7",
  action_linkage: '{"agent": "planner-v2", "step": 7, "plan_id": "plan-abc"}',
  grounding: '{"observed_by": "executor-agent", "observation_method": "test_suite", "test_count": 42, "pass_count": 42}',
  evidence: '{"all_tests_passing": true, "coverage_delta": "+3.2%"}'
)
```

---

## The Retrieve → Act → Learn Pipeline (Step by Step)

Here is the full pattern you should follow for any consequential action:

### Step 1: Retrieve

```
retrieve_context(
  query: "<what you need to know to act>",
  limit: 10,
  expansion_hops: 1
)
```

**Save the `causal_context` array from the response.** You will need it in Step 3.

### Step 2: Act

Use the retrieved knowledge (plus conversation context) to take your action:
answer a question, write code, suggest a fix, explore a directory, etc.

Observe the outcome. Was it successful?

### Step 3: Learn

```
learn_from_outcome(
  action_id: "<descriptive-slug-for-this-action>",
  status: "<success|partial_success|failure|timeout>",
  confidence: <0.0-1.0>,
  causal_node_ids: '<the JSON array from causal_context>',
  evidence: '<JSON object with measurable outcome details>'
)
```

### Step 4: Optionally Store New Knowledge

If the action revealed new information, store it:

```
store_node(
  content: "Learned that X after attempting Y",
  node_type: "episodic",
  confidence: 0.8,
  source: "learn_from_outcome action_id=<slug>"
)
```

---

## Writing Good `action_id` Values

The `action_id` is your human-readable (and machine-traceable) label for what
happened. Make them descriptive and unique-ish:

| Good | Bad |
|------|-----|
| `fix-auth-null-check-2025-06` | `action1` |
| `explore-graphonomous-lib-dir` | `test` |
| `recommend-deploy-strategy-v2` | `a` |
| `iter5-map-supervision-tree` | `learn` |
| `verify-mix-compile-clean` | `123` |

Pattern: `<verb>-<target>-<qualifier>` or `<context>-<verb>-<target>`.

---

## Writing Good `evidence` Objects

Evidence should be **structured and measurable**. Include signals that would
let a future agent (or human) understand *why* the outcome was what it was.

### Good evidence:
```
{
  "file_modified": "lib/graphonomous/store.ex",
  "test_result": "31 tests, 0 failures",
  "compilation": "clean, 0 warnings",
  "user_confirmed": true
}
```

### Bad evidence:
```
{
  "note": "it worked"
}
```

### Evidence field suggestions by domain:

| Domain | Useful Fields |
|--------|--------------|
| Code changes | `file`, `function`, `line_range`, `test_result`, `compile_warnings` |
| Exploration | `path_explored`, `files_found`, `expected_count`, `actual_count` |
| Recommendations | `user_accepted`, `user_feedback`, `correction_needed` |
| Build/deploy | `command`, `exit_code`, `duration_ms`, `output_snippet` |
| Architecture | `modules_identified`, `interfaces_found`, `unknowns_remaining` |

---

## Confidence on the Outcome Signal

The `confidence` parameter on `learn_from_outcome` is about **how reliable the
outcome signal is**, not how confident you are in the original decision.

| Confidence | Signal Source |
|------------|--------------|
| **0.9–1.0** | Direct observation: test passed, build succeeded, user explicitly confirmed |
| **0.7–0.89** | Strong indirect signal: user didn't complain, metrics improved |
| **0.5–0.69** | Moderate signal: seems to have worked but not definitively confirmed |
| **0.3–0.49** | Weak signal: inferred outcome, no direct feedback |
| **0.0–0.29** | Very unreliable: guessing at the outcome |

**When in doubt, use 0.5–0.7.** Don't inflate signal confidence — it over-amplifies
learning deltas and can destabilize the graph.

---

## When to Close the Loop

### Always close the loop when:
- You suggested a code fix and know whether it worked
- You explored a file/directory and can assess completeness
- You answered a question and got user feedback
- You followed a procedural node and can verify the result
- A goal subaction produced a measurable outcome

### Skip the loop when:
- You're just answering a casual/trivial question (no consequential action)
- You have no outcome signal at all (don't guess — use `timeout` if you must)
- The action was purely informational with no success/failure semantics

### Use `timeout` when:
- The action didn't finish in time
- The user moved on before confirming
- External systems didn't respond

---

## Common Mistakes

### ❌ Forgetting to capture `causal_context`
If you don't save the `causal_context` from `retrieve_context`, you have no
node IDs to feed into `learn_from_outcome`. The whole loop breaks.

**Fix:** Always note the `causal_context` array when you retrieve.

### ❌ Using `failure` when you mean `timeout`
Failure means the knowledge was *wrong*. Timeout means you don't know.
Mislabeling timeout as failure unfairly punishes causal nodes.

### ❌ Using confidence 1.0 on every outcome
This maximizes learning deltas and can overcorrect. Be honest about signal quality.

### ❌ Passing an empty `causal_node_ids` array
If no causal nodes are provided, there's nothing to update. The learning call
is wasted. If you don't have causal node IDs, you probably shouldn't be calling
`learn_from_outcome` at all.

### ❌ Reporting outcomes for actions informed by conversation alone
If you didn't use `retrieve_context` before acting, you have no causal nodes
from the graph. In that case, store the outcome as an episodic node instead:

```
store_node(
  content: "Answered user question about X. User confirmed answer was correct.",
  node_type: "episodic",
  confidence: 0.8,
  source: "conversation"
)
```

---

## Integration with Goals

When an action is linked to a goal, the learning loop becomes even more powerful.
After calling `learn_from_outcome`, consider:

1. **Updating goal progress** via `manage_goal(operation: "set_progress", ...)`
2. **Reviewing coverage** via `review_goal` to decide next steps
3. **Linking the outcome** to the goal via `manage_goal(operation: "link_nodes", ...)`

See [04_GOAL_MANAGEMENT.md](04_GOAL_MANAGEMENT.md) and
[05_COVERAGE_AND_REVIEW.md](05_COVERAGE_AND_REVIEW.md) for details.

---

## Integration with Belief Revision

When `learn_from_outcome` reveals that causal knowledge was **wrong** (status:
`failure`), the learning loop reduces confidence on those nodes. But if the
knowledge is fundamentally incorrect — not just unreliable — consider going
further:

1. **Detect contradictions**: `belief_contradictions(node_id: "<failed_causal_node>")`
2. **Revise or contract**: `belief_revise(operation: "revise", node_id: "...", content: "<corrected knowledge>")`
3. **Propagate**: Revision automatically propagates confidence decay through dependent nodes

The learning loop adjusts *confidence*. Belief revision adjusts *content and structure*.
Use both when knowledge needs correction, not just re-weighting.

See [11_BELIEF_REVISION.md](11_BELIEF_REVISION.md) for the full belief revision workflow.

---

## Integration with Epistemic Frontier

Each `learn_from_outcome` call increments the `evidence_count` on causal nodes.
This feeds into the **epistemic frontier** — the set of nodes where additional
evidence would most reduce uncertainty (Wilson score intervals).

After a round of outcome reporting, check what's still uncertain:

```
epistemic_frontier(min_gap: 0.3, limit: 5)
```

The frontier shrinks as you close more learning loops. If a node keeps
appearing on the frontier despite multiple outcomes, it may be genuinely
contested — consider `belief_contradictions` or `deliberate`.

See [13_EPISTEMIC_FRONTIER.md](13_EPISTEMIC_FRONTIER.md) for details.

---

## Summary

| Principle | Practice |
|-----------|----------|
| Every consequential action deserves an outcome report | Call `learn_from_outcome` after acting on graph knowledge |
| Capture causal provenance | Save `causal_context` from `retrieve_context` |
| Be honest about signal quality | Set `confidence` based on observation directness |
| Use the right status | `success`/`failure`/`partial_success`/`timeout` — don't conflate them |
| Include structured evidence | Measurable, specific, machine-readable |
| Don't guess at outcomes | No signal → `timeout` or skip the loop entirely |
| Knowledge gets better over time | Each loop iteration sharpens the graph's confidence landscape |