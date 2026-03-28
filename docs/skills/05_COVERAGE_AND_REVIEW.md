# Skill 05 — Coverage and Review

> **Tool:** `review_goal`
> **Purpose:** Epistemic self-modeling — assess whether the knowledge graph
> adequately covers a goal's domain before acting, and decide whether to
> **act**, **learn more**, or **escalate**.
> **Depends on:** [04_GOAL_MANAGEMENT.md](04_GOAL_MANAGEMENT.md) (goals must exist before reviewing them),
> [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) (retrieval results feed the coverage signal)

---

## Why This Matters

Node-level confidence tells you how much you trust a single fact. But before
taking a **consequential action** tied to a goal, you need a higher-level
question answered:

> "Does the graph know *enough* about this goal's domain for me to act
> confidently — or should I gather more information first?"

This is **epistemic coverage scoring**. It is the difference between an agent
that rushes into action on half-baked knowledge and one that pauses to
acknowledge its own ignorance.

The `review_goal` tool evaluates coverage for a specific goal and returns one of
three decisions:

| Decision | Meaning | Recommended Action |
|----------|---------|-------------------|
| **`act`** | The graph has sufficient coverage and confidence. Proceed. | Execute the goal's next action. |
| **`learn`** | Coverage gaps or low confidence detected. Gather more info. | Retrieve more context, read more files, ask the user. |
| **`escalate`** | The graph cannot adequately cover this goal area. Seek help. | Route to human review, multi-agent deliberation, or mark blocked. |

---

## The Coverage Review Flow

```
┌────────────────────────────────────────────────────────────┐
│  Goal exists (via manage_goal → create_goal)               │
└───────────┬────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────────┐
│  Gather a coverage signal:                                 │
│  - retrieve_context for the goal's domain                  │
│  - collect recent outcomes related to the goal             │
│  - note contradictions, gaps, unknowns                     │
└───────────┬────────────────────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────────────────────┐
│  Call review_goal(goal_id, signal)                         │
│  → Graphonomous evaluates:                                 │
│     - coverage_score (0.0–1.0)                             │
│     - uncertainty_score (0.0–1.0)                          │
│     - risk_score (0.0–1.0)                                 │
│     - decision_confidence (0.0–1.0)                        │
│  → Returns decision: act | learn | escalate                │
└───────────┬───────────────────┬──────────────┬─────────────┘
            │                   │              │
        decision:           decision:      decision:
          act               learn          escalate
            │                   │              │
            ▼                   ▼              ▼
     Execute the          Gather more     Mark goal
     goal's next          context, fill   blocked; route
     action.              knowledge       to human or
                          gaps, retry     multi-agent
                          review later.   deliberation.
```

---

## Tool Reference: `review_goal`

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `goal_id` | string | The ID of the goal to review (from `manage_goal` → `create_goal`) |
| `signal` | JSON object (or JSON string) | The coverage signal — what you've gathered so far for this goal's domain |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `options` | JSON object (or JSON string) | `{}` | Tuning knobs for the coverage evaluator |
| `apply_decision` | boolean | `true` | If true, automatically transitions the goal's status based on the decision |
| `transition_metadata` | JSON object (or JSON string) | `{}` | Extra metadata merged into the goal's transition record when `apply_decision` is enabled |

### Decision-to-Status Policy (when `apply_decision` is true)

| Decision | Goal Transitions To |
|----------|-------------------|
| `act` | `active` |
| `learn` | `proposed` |
| `escalate` | `blocked` |

If the goal is already in the target status, no transition occurs.

---

## The Coverage Signal

The `signal` parameter is a JSON object describing what you know (and don't
know) about the goal's domain. There is no rigid schema — you construct it
from your retrieval results and observations. However, the evaluator expects
and responds best to certain fields.

### Recommended Signal Fields

| Field | Type | Description |
|-------|------|-------------|
| `retrieved_nodes` | array of objects | Nodes retrieved for this goal's domain. Include `node_id`, `confidence`, `similarity`, `content` (or a subset). |
| `outcomes` | array of objects | Recent outcome records related to this goal. Include `action_id`, `status`, `confidence`. |
| `contradictions` | number | Count of known contradictions in the retrieved knowledge. |
| `knowledge_gaps` | array of strings | Topics or questions the graph cannot currently answer. |
| `supporting_evidence_count` | number | How many nodes directly support this goal's domain. |
| `coverage_estimate` | number (0.0–1.0) | Your own pre-estimate of coverage (the evaluator may adjust). |

### Minimal Signal (Quick Review)

When you just want a fast assessment and don't have detailed evidence:

```json
{
  "retrieved_nodes": [
    {"node_id": "nd_abc", "confidence": 0.8},
    {"node_id": "nd_def", "confidence": 0.6}
  ],
  "outcomes": [],
  "contradictions": 0
}
```

### Rich Signal (Thorough Review)

For high-stakes goals, build a more complete picture:

```json
{
  "retrieved_nodes": [
    {"node_id": "nd_abc", "confidence": 0.85, "similarity": 0.91, "content": "Auth uses RS256 JWT"},
    {"node_id": "nd_def", "confidence": 0.6, "similarity": 0.78, "content": "Token expiry is 1h"},
    {"node_id": "nd_ghi", "confidence": 0.4, "similarity": 0.65, "content": "Refresh tokens stored in Redis"}
  ],
  "outcomes": [
    {"action_id": "fix-auth-leak-v1", "status": "failure", "confidence": 0.9},
    {"action_id": "fix-auth-leak-v2", "status": "success", "confidence": 0.85}
  ],
  "contradictions": 1,
  "knowledge_gaps": [
    "Token revocation mechanism is unknown",
    "Unclear how refresh token rotation works"
  ],
  "supporting_evidence_count": 5,
  "coverage_estimate": 0.55
}
```

---

## Coverage Evaluation Options

The `options` parameter lets you tune the evaluation algorithm. All fields are
optional — sensible defaults are applied if omitted.

| Option | Type | Description |
|--------|------|-------------|
| `top_k` | number | How many of the top-ranked retrieved nodes to consider |
| `min_context_nodes` | number | Minimum number of context nodes required to consider coverage adequate |
| `freshness_half_life_hours` | number | Half-life for freshness decay — older nodes contribute less to coverage |
| `graph_support_target` | number | Target ratio of supporting edges to total nodes |
| `weights` | JSON object | Custom weights for scoring dimensions (e.g., `{"confidence": 0.4, "freshness": 0.3, "support": 0.3}`) |
| `thresholds` | JSON object | Custom decision thresholds (e.g., `{"act": 0.7, "escalate": 0.3}`) |

### Example with Custom Options

```json
{
  "options": {
    "top_k": 15,
    "min_context_nodes": 5,
    "freshness_half_life_hours": 48,
    "thresholds": {
      "act": 0.75,
      "escalate": 0.25
    }
  }
}
```

This tells the evaluator:
- Consider the top 15 retrieved nodes
- Require at least 5 relevant context nodes to consider acting
- Halve freshness contribution every 48 hours
- Raise the "act" threshold to 0.75 (more cautious than default)
- Lower the "escalate" threshold to 0.25 (escalate only when truly lost)

---

## Understanding the Response

### Response Shape

```json
{
  "status": "ok",
  "goal_id": "goal_abc123",
  "applied_review": true,
  "apply_decision": true,
  "decision": "learn",
  "decision_confidence": 0.62,
  "coverage_score": 0.45,
  "uncertainty_score": 0.55,
  "risk_score": 0.38,
  "rationale": [
    "Coverage score 0.45 below act threshold (0.60)",
    "2 knowledge gaps identified",
    "1 contradiction found in retrieved nodes",
    "Mean confidence of relevant nodes: 0.58"
  ],
  "transition": {
    "attempted": true,
    "applied": true,
    "from_status": "active",
    "to_status": "proposed"
  },
  "goal": { ... },
  "evaluation": { ... }
}
```

### Key Response Fields

| Field | Type | What It Tells You |
|-------|------|-------------------|
| `decision` | string | The recommended action: `"act"`, `"learn"`, or `"escalate"` |
| `decision_confidence` | number (0.0–1.0) | How confident the evaluator is in this decision |
| `coverage_score` | number (0.0–1.0) | Overall coverage adequacy. Higher = more of the goal's domain is covered. |
| `uncertainty_score` | number (0.0–1.0) | Overall uncertainty. Higher = more unknowns or low-confidence nodes. |
| `risk_score` | number (0.0–1.0) | Risk of acting with current knowledge. Factors in contradictions, gaps, and low confidence. |
| `rationale` | array of strings | Human-readable reasons explaining the decision |
| `transition` | object | Whether a goal status transition was attempted and applied |

### Interpreting the Scores Together

| coverage_score | uncertainty_score | risk_score | Likely Decision |
|---------------|------------------|------------|-----------------|
| ≥ 0.7 | ≤ 0.3 | ≤ 0.3 | **act** — solid knowledge, go ahead |
| 0.4–0.7 | 0.3–0.6 | 0.3–0.5 | **learn** — partial coverage, gather more |
| ≤ 0.4 | ≥ 0.6 | ≥ 0.5 | **escalate** — too much unknown, get help |

These ranges are heuristic; the actual decision depends on the configured
thresholds and weights.

---

## The Transition Mechanism

When `apply_decision` is `true` (the default), `review_goal` automatically
transitions the goal's lifecycle status based on the decision:

```
decision: act       →  goal status becomes "active"
decision: learn     →  goal status becomes "proposed"
decision: escalate  →  goal status becomes "blocked"
```

The `transition` object in the response reports what happened:

```json
{
  "transition": {
    "attempted": true,
    "applied": true,
    "from_status": "active",
    "to_status": "proposed"
  }
}
```

### Transition Metadata

When a transition is applied, the system records provenance metadata including:

- `source`: `"mcp.review_goal"`
- `policy`: `"coverage_decision"`
- `decision`: the decision string
- `decision_confidence`, `coverage_score`, `uncertainty_score`, `risk_score`

You can add extra metadata via the `transition_metadata` parameter:

```json
{
  "transition_metadata": {
    "reviewer": "agent-planner-v2",
    "iteration": 5,
    "review_trigger": "scheduled"
  }
}
```

### Disabling Auto-Transition

If you want the coverage evaluation without changing goal status (for
informational purposes), set `apply_decision` to `false`:

```json
{
  "goal_id": "goal_abc",
  "signal": { "retrieved_nodes": [...] },
  "apply_decision": false
}
```

The response will still include `decision`, scores, and rationale, but
`transition.attempted` and `transition.applied` will both be `false`.

---

## Practical Examples

### Example 1: Pre-Action Gate (Standard Pattern)

You have a goal "Implement rate limiting for the API." Before writing code,
check coverage.

**Step 1 — Retrieve context for the goal's domain:**

```
retrieve_context(
  query: "rate limiting implementation patterns, API throttling, request quotas",
  limit: 10
)
→ results: [node_a (0.8), node_b (0.6), node_c (0.45)]
→ causal_context: ["node_a", "node_b", "node_c"]
```

**Step 2 — Build the signal from retrieval results:**

```json
{
  "retrieved_nodes": [
    {"node_id": "node_a", "confidence": 0.8, "similarity": 0.89},
    {"node_id": "node_b", "confidence": 0.6, "similarity": 0.76},
    {"node_id": "node_c", "confidence": 0.45, "similarity": 0.62}
  ],
  "outcomes": [],
  "contradictions": 0,
  "knowledge_gaps": ["Unknown: which rate limiting algorithm to use (token bucket vs sliding window)"]
}
```

**Step 3 — Review the goal:**

```
review_goal(
  goal_id: "goal_rate_limit",
  signal: <the JSON object above>
)
```

**Step 4 — Act on the decision:**

- If `"act"` → proceed to implement rate limiting
- If `"learn"` → research rate limiting algorithms, read existing code, store knowledge, then re-review
- If `"escalate"` → ask the user for architectural guidance on rate limiting strategy

### Example 2: Iterative Review Loop

After a `learn` decision, loop back with improved knowledge:

```
Iteration 1:
  review_goal → decision: "learn"
  rationale: "Only 2 relevant nodes found, coverage_score: 0.35"

Action: Retrieve more context, read 3 source files, store 5 new nodes.

Iteration 2:
  review_goal → decision: "learn"
  rationale: "Coverage improved to 0.55 but 1 contradiction found"

Action: Investigate contradiction. Store resolution as a new node.
  Create "contradicts" edge to mark the outdated claim.

Iteration 3:
  review_goal → decision: "act"
  rationale: "Coverage 0.72, no contradictions, mean confidence 0.78"

Proceed with implementation.
```

### Example 3: Informational Review (No Auto-Transition)

Check coverage without modifying goal status — useful for status reporting:

```
review_goal(
  goal_id: "goal_migration",
  signal: {
    "retrieved_nodes": [...],
    "outcomes": [
      {"action_id": "trial-migration-v1", "status": "partial_success", "confidence": 0.7}
    ],
    "contradictions": 0,
    "knowledge_gaps": ["Unclear rollback procedure"]
  },
  apply_decision: false
)
```

Report the scores to the user without changing the goal's lifecycle state.

### Example 4: High-Stakes Goal with Strict Thresholds

For a security-sensitive goal, raise the bar for "act":

```
review_goal(
  goal_id: "goal_auth_overhaul",
  signal: { ... },
  options: {
    "min_context_nodes": 8,
    "thresholds": {
      "act": 0.85,
      "escalate": 0.35
    }
  }
)
```

This demands 85% coverage before allowing autonomous action and escalates
only below 35%.

### Example 5: Post-Outcome Review

After `learn_from_outcome` reports a failure, review the goal again to
reassess coverage:

```
learn_from_outcome(
  action_id: "deploy-config-change",
  status: "failure",
  confidence: 0.9,
  causal_node_ids: '["node_x", "node_y"]',
  evidence: '{"error": "config key not found in production env"}'
)

// The causal nodes now have lower confidence. Re-review the goal.

review_goal(
  goal_id: "goal_config_deploy",
  signal: {
    "retrieved_nodes": [
      {"node_id": "node_x", "confidence": 0.35},
      {"node_id": "node_y", "confidence": 0.45}
    ],
    "outcomes": [
      {"action_id": "deploy-config-change", "status": "failure", "confidence": 0.9}
    ],
    "contradictions": 0,
    "knowledge_gaps": ["Production environment variables not fully mapped"]
  }
)
→ decision: "learn" (confidence dropped after failure; need more info)
```

---

## Building the Coverage Signal — Best Practices

### Always Retrieve First

The signal is only as good as the data you put into it. Before calling
`review_goal`, always call `retrieve_context` for the goal's topic. Don't
guess at or fabricate the signal.

```
// Good: signal built from actual retrieval
retrieve_context(query: "goal topic")
→ use results to build signal

// Bad: signal made up from assumptions
review_goal(signal: {"retrieved_nodes": [], "coverage_estimate": 0.8})
→ claims 80% coverage with zero evidence
```

### Include All Relevant Outcomes

If you've previously called `learn_from_outcome` for actions related to this
goal, include those outcomes in the signal. Past successes and failures are
critical data for the evaluator.

### Count Contradictions Honestly

If `retrieve_context` returned nodes that conflict with each other, or if
you used `query_graph(operation: "get_edges")` and found `contradicts` edges,
report that count in the signal. Contradictions significantly affect the risk
score and can flip a decision from `act` to `learn`.

### Identify Knowledge Gaps Explicitly

If you noticed topics or questions the graph can't answer, list them in
`knowledge_gaps`. The evaluator uses gap count as a coverage signal. Being
explicit about what you *don't* know is more valuable than pretending you
know everything.

---

## Integration with Goal Lifecycle

Coverage review is the bridge between the GoalGraph and the learning loop.
Here's how it fits into the full cycle:

```
create_goal → proposed
      │
      ▼
review_goal → decision: learn
      │         (status stays proposed)
      ▼
  Gather knowledge (retrieve, store, explore)
      │
      ▼
review_goal → decision: act
      │         (status → active)
      ▼
  Execute goal actions
      │
      ▼
learn_from_outcome → confidence updates
      │
      ▼
review_goal → decision: act (continue) or learn (setback)
      │
      ▼
  ... iterate until complete ...
      │
      ▼
manage_goal(operation: "transition_goal", status: "completed")
```

### Typical Goal Progression with Reviews

| Phase | Coverage Score | Decision | Goal Status |
|-------|---------------|----------|-------------|
| Initial creation | — | — | `proposed` |
| First review (cold graph) | 0.2 | `learn` | `proposed` |
| After seeding knowledge | 0.5 | `learn` | `proposed` |
| After deeper research | 0.72 | `act` | `active` |
| Mid-execution, after a failure | 0.55 | `learn` | `proposed` |
| After fixing gaps | 0.78 | `act` | `active` |
| Goal completed successfully | — | — | `completed` (manual) |

---

## When to Call `review_goal`

### Call it:

- **Before starting high-stakes work** on a goal (pre-action gate)
- **After a learning phase** to check if you've gathered enough knowledge
- **After an outcome failure** to reassess whether you still have adequate coverage
- **Periodically during long-running goal execution** (e.g., every N iterations in a Ralph Loop)
- **When the user asks** "are we ready to proceed?" or "do we know enough?"

### Don't call it:

- For trivial, low-stakes goals (e.g., answering a quick factual question)
- When you don't have a stored goal to review (create one first via `manage_goal`)
- Every single turn — reserve it for decision points where coverage matters
- With an empty or fabricated signal (the review is only as good as the input)

---

## `review_goal` vs `coverage_query` (Spec Comparison)

The spec describes both a `coverage_query` tool (task-level, no goal binding)
and GoalGraph `review_goal` (goal-level, with persistence and lifecycle
transitions). In the current implementation, `review_goal` is the primary
interface and combines both capabilities:

- It evaluates coverage (the `coverage_query` concept)
- It persists the review on the goal record
- It optionally applies status transitions based on the decision policy

If you need lightweight, goal-free coverage checking, you can call
`review_goal` with `apply_decision: false` and use the scores informatively
without any lifecycle side effects.

---

## Common Mistakes

### ❌ Reviewing without retrieving first

```
// Building a signal from nothing
review_goal(
  goal_id: "goal_x",
  signal: {"retrieved_nodes": [], "contradictions": 0}
)
```

An empty signal almost always produces `learn` or `escalate`. This is
technically correct (you have no knowledge!) but wasted a call. Retrieve
context for the goal's domain first.

### ❌ Over-trusting `act` on a thin signal

If the signal only contains 1–2 nodes, coverage may score high simply because
those nodes happen to be confident. Use `min_context_nodes` in options to
enforce a minimum evidence threshold:

```json
{"options": {"min_context_nodes": 4}}
```

### ❌ Ignoring `learn` decisions repeatedly

If you keep getting `learn` and keep acting anyway, the coverage review
provides zero value. Respect the decision or raise the thresholds explicitly
if you disagree.

### ❌ Not including outcomes in the signal

If you've previously called `learn_from_outcome` with results relevant to
this goal, those outcomes are critical context. Omitting them means the
evaluator doesn't know about past successes or failures.

### ❌ Using `escalate` as permanent block

`escalate` means "I need help now." It's a temporary state. After the human
or external system provides guidance, store that knowledge, re-review, and
resume. Don't leave goals blocked indefinitely.

---

## Summary

| Principle | Practice |
|-----------|----------|
| Know before you act | Call `review_goal` before high-stakes goal actions |
| Build honest signals | Use real retrieval results, report real gaps and contradictions |
| Respect the decision | `act` = go, `learn` = gather more, `escalate` = ask for help |
| Review iteratively | After each learning phase, re-review to check improvement |
| Use auto-transition | Let `apply_decision: true` manage goal lifecycle automatically |
| Tune for risk tolerance | Adjust thresholds via `options` for security-critical vs exploratory goals |
| Close the full loop | Retrieve → Review → Act → Outcome → Review again |