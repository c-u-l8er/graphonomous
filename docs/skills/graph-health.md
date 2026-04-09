---
name: graph-health
description: Use when the user asks "is the graph healthy?", "run diagnostics", "graph quality", "check graph health", "memory health", "audit the graph", "how big is the graph?", "any problems?", or wants a combined health report. Runs stats, identifies weak nodes, checks for orphans, and reports frontier uncertainty. Routes through `consolidate`, `retrieve`, and `act` machines.
argument-hint: [--full] [--fix]
---

# Graph Health Check

Combined diagnostic that assesses knowledge graph quality in one pass.

## Arguments

Optional flags: $ARGUMENTS

- No arguments: quick health summary (stats + top issues)
- `--full`: deep audit (stats + weak nodes + orphans + frontier + staleness)
- `--fix`: auto-fix found issues (prune orphans, decay stale nodes)

## Quick Health Check

### Step 1 — Graph stats
```
consolidate(action: "stats")
```
Returns: node count, edge count, type distributions, confidence stats (mean/min/max/std_dev), orphan count.

### Step 2 — Interpret and report

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Orphan ratio | < 10% | 10–30% | > 30% |
| Mean confidence | > 0.5 | 0.3–0.5 | < 0.3 |
| Edge/node ratio | > 1.5 | 0.5–1.5 | < 0.5 |
| Confidence std_dev | < 0.25 | 0.25–0.35 | > 0.35 |

Report a summary like:
> **Graph Health: Good** — 142 nodes, 238 edges (1.68 edge/node), mean confidence 0.64, 8 orphans (5.6%)

## Full Audit (--full)

### Step 3 — Find weak knowledge
```
consolidate(action: "query", operation: "list_nodes", min_confidence: 0.0, max_confidence: 0.3, limit: 20)
```
Nodes below 0.3 confidence are speculative — candidates for reinforcement or pruning.

### Step 4 — Epistemic frontier
```
retrieve(action: "frontier", limit: 10)
```
Identifies where uncertainty is highest — the most valuable areas to investigate next.

### Step 5 — Check for staleness
```
retrieve(action: "episodic", since: null, until: null, limit: 5)
```
If the most recent episodic node is old, the graph may be stale.

### Step 6 — Orphan details
If orphan count > 10%, list them:
```
consolidate(action: "query", operation: "list_nodes", limit: 50)
```
Cross-reference with edge data to identify which nodes lack connections.

## Auto-Fix (--fix)

When `--fix` is passed, take corrective action on found issues:

### Fix orphans — connect or prune
For each orphan node:
1. Search for related nodes: `consolidate(action: "query", operation: "similarity_search", query: "<orphan content>", limit: 3)`
2. If similarity > 0.5 with any node → create `related_to` edge
3. If no matches and confidence < 0.3 → prune: `act(action: "forget_node", node_id: "<id>", strategy: "soft")`

### Fix weak nodes — reinforce or decay
For nodes with confidence < 0.2:
1. Check if still relevant (search for supporting context)
2. If supporting evidence exists → `learn(action: "from_feedback", node_id: "<id>", feedback_type: "positive")`
3. If no support → `act(action: "forget_node", node_id: "<id>", strategy: "soft")`

### Fix staleness — flag for sync
If graph is stale (no episodic nodes in 7+ days), recommend running `/graphonomous:sync` to ingest recent filesystem changes.

## Health Report Format

```
## Graph Health Report

**Overall: [Good|Warning|Critical]**

| Metric          | Value | Status |
|-----------------|-------|--------|
| Nodes           | 142   | —      |
| Edges           | 238   | —      |
| Edge/Node Ratio | 1.68  | ✓      |
| Mean Confidence | 0.64  | ✓      |
| Orphans         | 8 (5.6%) | ✓   |
| Weakest Nodes   | 3 below 0.2 | ⚠  |

**Top Issues:**
1. 3 nodes below 0.2 confidence — candidates for reinforcement
2. Frontier suggests investigating: [topic areas]

**Recommendations:**
- Run `/graphonomous:sync` to update filesystem nodes
- Review weak nodes: [list IDs]
```

## Combining with Other Skills

| Situation | Follow-up |
|-----------|-----------|
| High orphan count | `/graphonomous:sync --full` to rebuild edges |
| Low mean confidence | `/graphonomous:consolidate` to merge and strengthen |
| Frontier gaps | `/graphonomous:retrieve <frontier topic>` to fill gaps |
| Stale graph | `/graphonomous:watch <dir>` for continuous sync |

## Anti-patterns to avoid

- Running health checks too frequently — once per session or after major changes is enough
- Auto-fixing without reporting what was changed — always show the user what --fix did
- Treating orphans as always bad — some nodes are intentionally standalone (e.g., one-off observations)
- Ignoring the frontier — it tells you where to invest learning effort next
