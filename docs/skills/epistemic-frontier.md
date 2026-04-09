---
name: epistemic-frontier
description: Use when you need to identify where uncertainty is highest in the knowledge graph, prioritize investigation, or quantify confidence bounds. Use when the user says "where is uncertainty highest?", "what should I investigate?", "show epistemic frontier", "Wilson intervals", "information gain", "what don't we know?", or "uncertainty analysis". Routes through the `retrieve` machine.
argument-hint: [min_gap] [limit]
---

# Epistemic Frontier — Uncertainty-Guided Investigation

Find nodes where investigation would most reduce graph uncertainty.

## Arguments

Optional parameters: $ARGUMENTS

## Query the Frontier

```
retrieve(action: "frontier", limit: 5, min_gap: 0.3)
```

Response:
```json
{
  "status": "ok",
  "count": 5,
  "frontier": [
    {
      "node_id": "node_abc123",
      "content": "BM25 hybrid retrieval improves SHR by 12pp...",
      "confidence": 0.625,
      "evidence_count": 1,
      "interval_lower": 0.0833,
      "interval_upper": 0.9683,
      "width": 0.885,
      "information_gain": 0.0828,
      "access_count": 0
    }
  ]
}
```

**Key fields:**
- `interval_lower` / `interval_upper` — Wilson score 95% confidence bounds
- `width` — interval width (upper - lower); wider = more uncertain
- `information_gain` — expected interval narrowing from one more evidence point
- `evidence_count` — number of outcome observations backing this node

Only nodes with `evidence_count > 0` appear on the frontier. Nodes without evidence are either current or stale, not "uncertain" in the statistical sense.

## The Investigation Loop

1. **Query frontier** — `retrieve(action: "frontier", limit: 5, min_gap: 0.3)`
2. **Pick highest info_gain node** — investigate it (run tests, check docs, verify claims)
3. **Report outcome** — `learn(action: "from_outcome", causal_node_ids: ["<frontier_node>"], status: "success", ...)`
4. **Re-query frontier** — the investigated node should have narrowed or dropped off
5. **Repeat** — each cycle reduces graph uncertainty where it matters most

## Wilson Score Intervals

The frontier uses Wilson score confidence intervals (z=1.96 for 95% confidence):

- **1 evidence point**: very wide intervals (~0.89 width) regardless of confidence
- **2 evidence points**: significantly narrower (~0.58 width)
- **5+ evidence points**: reasonably tight bounds
- **10+ evidence points**: converging on true confidence

This is why the frontier is powerful: it tells you exactly where one more data point would have the biggest impact.

## Integration with Other Machines

### Frontier + Learn
Every `learn(action: "from_outcome", ...)` call increments `evidence_count` and updates `confidence` on causal nodes. This naturally narrows their Wilson intervals and may drop them off the frontier.

### Frontier + Coverage Review
Use frontier data to inform coverage decisions:
```
route(action: "review_goal", goal_id: "...", signal: "frontier shows 3 high-uncertainty nodes in this area")
```
If key nodes are on the frontier, coverage review may route to `learn` instead of `act`.

### Frontier + Attention
The attention engine can incorporate frontier data when prioritizing goals — goals with high-uncertainty supporting knowledge may need investigation before execution.

## Anti-patterns to avoid

- Don't ignore high-information-gain nodes — they're where learning has most value
- Don't assume evidence_count=0 nodes are "fine" — they're just not measurable yet
- Don't set min_gap too low — very narrow intervals aren't worth investigating
- Always report outcomes after investigating frontier nodes — that's how the frontier shrinks
