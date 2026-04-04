# Skill 11 — Belief Revision

> **Tools:** `belief_revise`, `belief_contradictions`
> **When:** Knowledge changes, contradictions detected, facts become outdated, corrections needed

---

## Why This Matters

Knowledge graphs accumulate beliefs over time. Some become wrong — code changes,
docs get updated, assumptions prove false. Without structured revision, stale
beliefs poison retrieval and corrupt downstream reasoning.

Graphonomous implements **AGM-style belief revision** (expand, revise, contract)
with automatic contradiction detection and confidence propagation. This means the
graph can *change its mind correctly* — updating not just the revised node but
all nodes that depended on it.

---

## The Three Operations

### Expand — Add a New Belief

Use when you learn something new. Graphonomous checks for contradictions automatically.

```
belief_revise(
  operation: "expand",
  content: "The API rate limit is 1000 req/min per tenant",
  confidence: 0.8,
  rationale: "Confirmed in infrastructure docs"
)
```

**What happens internally:**
1. Stores a new semantic node (default confidence 0.6 if unspecified)
2. Runs contradiction detection against existing knowledge
3. If contradictions found: creates bidirectional `:contradicts` edges (forming κ=1 SCCs)
4. Returns the new node_id + any contradictions found

**Response includes:**
```json
{
  "status": "ok",
  "node_id": "node_abc123",
  "contradictions": [
    {"node_id": "node_old456", "similarity": 0.87, "content_preview": "API rate limit is 500 req/min..."}
  ]
}
```

**When contradictions are returned**, you should decide:
- **Revise** the old node if the new information supersedes it
- **Deliberate** if both might be partially correct (different contexts)
- **Leave both** if the contradiction is productive (different perspectives)

### Revise — Replace a Belief

Use when you know the old belief is wrong and have better information.

```
belief_revise(
  operation: "revise",
  node_id: "node_old456",
  content: "The API rate limit is 1000 req/min per tenant (upgraded Q2 2026)",
  rationale: "Old limit was 500, confirmed upgrade in changelog"
)
```

**What happens internally:**
1. Creates a **new node** with slightly higher confidence (old + 0.1, capped at 0.9)
2. Marks old node as **superseded**: confidence reduced to 30% of original, `superseded_by` set
3. Creates a `:superseded_by` edge from old → new (weight 0.9)
4. **Propagates confidence reduction** through dependent nodes (`:derived_from`, `:supports`, `:causal` edges) with 0.6× decay factor
5. Records the revision with all affected node IDs

**This is the key differentiator:** Revision doesn't just update one node — it
cascades confidence decay through the dependency graph. If Node A supported
Node B which supported Node C, revising A automatically weakens B and C.

### Contract — Withdraw a Belief

Use when a belief is wrong but you don't have a replacement.

```
belief_revise(
  operation: "contract",
  node_id: "node_old456",
  rationale: "Rate limit docs were for a different service entirely"
)
```

**What happens internally:**
1. Reduces target node's confidence to 0.05 (near-zero, "withdrawn")
2. Propagates 0.6× confidence decay through dependent edges (same as revise)
3. Node is *not deleted* — structure preserved for provenance
4. Records the contraction with affected node list

**Use contract instead of forget when:**
- You want to preserve the revision history
- Other nodes reference this one and you want them weakened, not orphaned
- The information might become relevant again in a different context

---

## Detecting Contradictions

Check for contradictions proactively — don't wait for expand to find them.

```
belief_contradictions(content: "The deploy pipeline uses GitHub Actions")
```

Or check a specific node:

```
belief_contradictions(node_id: "node_abc123")
```

**Detection uses:**
- Semantic similarity ≥ 0.75 threshold
- Negation markers: "not", "incorrect", "wrong", "replaced", "deprecated", "outdated", "instead", "actually", "contrary"
- Confidence divergence (one high, one low on similar content)

**Returns up to 5 contradictions**, sorted by information value.

---

## The Belief Revision Workflow

The complete pattern for handling knowledge changes:

```
1. Detect    → belief_contradictions(content: "<new information>")
2. Assess    → Are contradictions real? Check context, recency, source quality
3. Decide    → Revise old? Contract old? Expand alongside? Deliberate?
4. Act       → belief_revise(operation: "revise/contract/expand", ...)
5. Verify    → topology_analyze() to check if new SCCs formed
6. Deliberate → If κ > 0 on affected region, deliberate to resolve
7. Learn     → learn_from_outcome on the revision action
```

### Example: Correcting a Stale Fact

```
# 1. You discover the deploy target changed
belief_contradictions(content: "Production deploys to us-east-1")
# → Returns: node_xyz claims "Production deploys to eu-west-1"

# 2. You verified us-east-1 in the Terraform config
belief_revise(
  operation: "revise",
  node_id: "node_xyz",
  content: "Production deploys to us-east-1 (migrated 2026-03)",
  rationale: "Verified in terraform/prod/main.tf, migration completed March 2026"
)
# → Old node superseded, dependents weakened

# 3. Check topology for cycles
topology_analyze(node_ids: ["node_xyz", "<new_node_id>"])
# → routing: "fast" (no cycles, clean revision)

# 4. Report outcome
learn_from_outcome(
  action_id: "belief_revision_deploy_target",
  status: "success",
  causal_node_ids: ["<new_node_id>"],
  confidence: 0.9
)
```

---

## Integration with Other Tools

### Belief Revision + Deliberation
When `belief_revise(operation: "expand")` returns contradictions, those create
`:contradicts` edges forming κ=1 SCCs. If the retrieval routing becomes
`"deliberate"`, use:

```
deliberate(query: "resolve contradiction about <topic>", write_back: true)
```

Deliberation may crystallize a resolution that supersedes both contradicting nodes.

### Belief Revision + Consolidation
The consolidation pipeline's Stage 4.5 (conflict-aware resolution) handles
contradictions that belief revision created but didn't resolve. Consolidation
uses recency, confidence, and evidence-count heuristics to auto-resolve
low-stakes conflicts. High-stakes conflicts are left for deliberation.

### Belief Revision + Coverage Review
After revising beliefs in a goal's knowledge area, re-run coverage review:

```
review_goal(goal_id: "...", signal: "<updated signal>")
```

Revised/contracted nodes may have shifted the coverage score, potentially
moving the decision from `act` to `learn` (if key supporting knowledge was weakened).

---

## Confidence Propagation Rules

When a node is revised or contracted, confidence decay propagates through:

| Edge Type | Propagation | Decay Factor |
|-----------|-------------|--------------|
| `:derived_from` | Yes | 0.6× |
| `:supports` | Yes | 0.6× |
| `:causal` / `:causes` | Yes | 0.6× |
| `:related` | No | — |
| `:contradicts` | No | — |
| `:superseded_by` | No (direction is old→new) | — |

Propagation stops when the confidence change is < 0.01 (negligible).

---

## Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|---|---|---|
| **Revise without checking** | Revising a node that isn't actually wrong | Always run `belief_contradictions` first |
| **Expand when you should revise** | Creates contradictions instead of resolving them | If old belief is wrong, revise it — don't just add the correction alongside |
| **Contract everything** | Over-aggressive retraction weakens the whole graph | Contract only when genuinely wrong with no replacement |
| **Ignore propagation** | Revising a foundational node without checking what depended on it | Review affected_node_ids in the response; re-assess weakened dependents |
| **Skip outcome learning** | Belief revision actions are never reported for confidence feedback | Always `learn_from_outcome` after revision |
