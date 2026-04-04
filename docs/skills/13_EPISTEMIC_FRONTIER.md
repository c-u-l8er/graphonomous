# Skill 13 — Epistemic Frontier

> **Tools:** `epistemic_frontier`
> **When:** Deciding what to investigate next, prioritizing learning, identifying knowledge gaps

---

## Why This Matters

Most memory systems can tell you what they know. Graphonomous can tell you
**what it doesn't know** — and more precisely, **where one more piece of
evidence would most reduce uncertainty**.

The epistemic frontier identifies nodes where confidence is uncertain *and*
where investigation would actually help. This transforms vague "we need to
learn more" into a ranked, actionable list of specific knowledge gaps.

---

## How It Works

```
epistemic_frontier(min_gap: 0.3, limit: 10)
```

**Returns:**
```json
{
  "status": "ok",
  "count": 5,
  "frontier": [
    {
      "node_id": "node_abc123",
      "content": "The caching layer handles invalidation via TTL...",
      "confidence": 0.65,
      "evidence_count": 3,
      "interval_lower": 0.42,
      "interval_upper": 0.83,
      "width": 0.41,
      "information_gain": 0.084,
      "access_count": 12
    }
  ]
}
```

### The Math (Wilson Score Intervals)

For each node with evidence, Graphonomous computes a **95% confidence interval**
using the Wilson score formula:

```
p̂ = confidence (clamped to [0, 1])
z = 1.96 (95% CI)
n = evidence_count

center = (p̂ + z²/2n) / (1 + z²/n)
spread = z × √[(p̂(1-p̂) + z²/4n) / n] / (1 + z²/n)

interval = [max(0, center - spread), min(1, center + spread)]
width = upper - lower
```

**Information gain** is the expected narrowing of the interval if one more
evidence point were added:

```
current_entropy = width at evidence_count
projected_entropy = width at (evidence_count + 1)
information_gain = max(0, current_entropy - projected_entropy)
```

Nodes are ranked by **information_gain descending** — the node where your next
observation would most reduce uncertainty comes first.

### What Gets Included

- Only nodes with `evidence_count > 0` (excludes file-ingested nodes that have
  no outcome feedback yet)
- Only nodes where `interval width ≥ min_gap` (filters out already-certain nodes)
- Sorted by information gain, not raw uncertainty

### What This Means Intuitively

| Frontier Signal | Interpretation |
|---|---|
| High info gain, moderate confidence | Most valuable to investigate — one more data point shifts the picture significantly |
| Wide interval, low evidence count | Early-stage knowledge — needs more observation before committing |
| Wide interval, high evidence count | Genuinely contested — evidence points both ways, might need deliberation |
| Narrow interval (below min_gap) | Excluded — already well-established, don't waste effort here |

---

## Using the Frontier

### Pattern 1: "What should I learn next?"

Before starting exploratory work, check what the graph is most uncertain about:

```
# 1. Get the frontier
epistemic_frontier(min_gap: 0.3, limit: 5)

# 2. Pick the highest-gain node
# 3. Investigate it (read code, run tests, check docs)
# 4. Store what you find
store_node(content: "...", confidence: 0.85, source: "verified in source")

# 5. Report outcome to update the original node's evidence
learn_from_outcome(
  action_id: "frontier_investigation_<topic>",
  status: "success",
  causal_node_ids: ["<frontier_node_id>"],
  confidence: 0.85
)
```

Each `learn_from_outcome` call increments `evidence_count`, which narrows the
Wilson interval and may remove the node from the frontier entirely.

### Pattern 2: Goal-Directed Frontier

Combine with coverage review to find knowledge gaps *for a specific goal*:

```
# 1. Review goal coverage
review_goal(goal_id: "...", signal: "...")
# → decision: "learn" (gaps exist)

# 2. Check what's uncertain
epistemic_frontier(min_gap: 0.2, limit: 10)

# 3. Cross-reference: which frontier nodes are linked to this goal?
# (Use graph_traverse or query_graph to check edges)

# 4. Investigate the most relevant frontier nodes
# 5. Re-review coverage after learning
review_goal(goal_id: "...", signal: "<updated signal>")
# → decision might now be "act"
```

### Pattern 3: Research Prioritization

When multiple goals need learning, use the frontier to decide which to
investigate first:

```
# 1. Survey attention for active goals
attention_survey(include_idle: false)

# 2. For each goal with dispatch_mode: "learn"
#    Check if its knowledge area has frontier nodes
epistemic_frontier(min_gap: 0.25, limit: 20)

# 3. Investigate frontier nodes that overlap with the highest-attention goals
# This maximizes information gain per unit of effort
```

### Pattern 4: Maintenance Monitoring

Periodically check the frontier to detect knowledge decay:

```
# If the frontier grows (more high-uncertainty nodes), the graph is becoming
# less reliable — perhaps due to knowledge aging or contradictory evidence
epistemic_frontier(min_gap: 0.2, limit: 20)

# Compare count to previous checks
# Growing frontier → trigger consolidation or investigation
# Shrinking frontier → graph is stabilizing
```

---

## Integration with Other Tools

### Frontier + Attention Engine

The attention engine already incorporates "knowledge gap" as a scoring
dimension. But `epistemic_frontier` provides *node-level* granularity:

- **Attention** tells you *which goal* needs learning
- **Frontier** tells you *which specific fact* is most uncertain
- Together: prioritize the most uncertain knowledge within the highest-priority goal

### Frontier + Belief Revision

Frontier nodes with wide intervals and high evidence counts may be contradicted:

```
# Node has wide interval despite many evidence points → likely contradictions
belief_contradictions(node_id: "<frontier_node_id>")
# If contradictions found → belief_revise to resolve
```

### Frontier + Deliberation

If frontier analysis reveals a cluster of uncertain nodes that form a cycle
(κ > 0), deliberation may resolve the uncertainty more efficiently than
investigating each node individually:

```
topology_analyze(node_ids: [<frontier_node_ids>])
# If κ > 0 → deliberate over the cluster
deliberate(query: "resolve uncertainty about <topic>", node_ids: [...])
```

---

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `min_gap` | 0.3 | Minimum interval width to include. Lower = more results (including less-uncertain nodes). Higher = only the most uncertain |
| `limit` | 10 | Maximum frontier nodes to return |

**Tuning guidance:**
- `min_gap: 0.2` — broad view, good for maintenance monitoring
- `min_gap: 0.3` — default, good for directed investigation
- `min_gap: 0.5` — only deeply uncertain nodes, good for triage
- `limit: 5` — focused investigation of top priorities
- `limit: 20` — survey mode, understanding the uncertainty landscape

---

## Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|---|---|---|
| **Ignoring the frontier** | Investigating things you're already certain about | Check frontier before starting exploratory work |
| **Investigating without reporting outcomes** | Frontier never shrinks because evidence_count doesn't increase | Always `learn_from_outcome` after investigating a frontier node |
| **min_gap too low** | Frontier includes near-certain nodes, wasting investigation effort | Start at 0.3, lower only if frontier is empty |
| **Frontier without goal context** | Investigating uncertain things that don't matter to current work | Cross-reference frontier with active goals and attention priorities |
| **Treating frontier as a to-do list** | Investigating every uncertain node sequentially | Use information gain ranking — the top node is worth more than the next 5 combined |
