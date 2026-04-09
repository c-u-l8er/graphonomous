---
name: consolidate
description: Use at end of productive sessions, after heavy storage bursts, periodically during long iterations, or when the user says "consolidate", "maintain graph", "merge nodes", "clean up memory". Merges similar nodes and strengthens edges — not for deleting specific nodes (use `forgetting`) or diagnostics (use `graph-health`).
---

# Consolidation

Trigger graph maintenance — decay weak knowledge, prune, merge duplicates, strengthen relationships.

## Trigger Consolidation

```
consolidate(action: "run", wait_ms: 2000)
```

The `consolidate` machine supports these actions:
- `run` — trigger consolidation (optionally wait with `wait_ms`)
- `stats` — aggregate graph health without triggering
- `query` — operation-based graph inspection
- `traverse` — BFS walk with depth/relationship filters

**`wait_ms`:** 0–30000 (max 30 seconds). How long to wait for completion before returning status.

## The 7-Stage Pipeline

1. **Decay confidence** — time-based confidence reduction. Nodes not accessed or reinforced gradually lose confidence.
2. **Prune weak nodes** — remove nodes below the confidence threshold. Eliminates knowledge that has decayed past usefulness.
3. **Prune weak edges** — remove edges below the weight threshold. Cleans up tenuous connections.
4. **Strengthen co-activated** — boost edges between nodes frequently retrieved together ("neurons that fire together wire together").
5. **Merge similar nodes** — combine near-duplicate nodes (similarity > 0.95 default). Consolidates redundant knowledge.
6. **Promote timescale** — move valuable, frequently-accessed nodes to slower decay tiers (fast → medium → slow → glacial).
7. **Generate abstractions** — create semantic summary nodes from clusters of episodic observations.

## Timescale System

Nodes live on one of 4 decay tiers:

| Tier | TTL | Decay Rate | Purpose |
|------|-----|------------|---------|
| **fast** | Hours | High | Working memory, session-local observations |
| **medium** | Days | Moderate | Recently reinforced knowledge |
| **slow** | Weeks | Low | Well-established, frequently-used facts |
| **glacial** | Months+ | Minimal | Core architectural knowledge, proven procedures |

Consolidation promotes nodes up tiers based on access frequency and confidence. Decay happens within each tier at its own rate.

## When to Consolidate

- End of every productive session
- Every 4–5 heavy storage/learning iterations
- After outcome learning bursts
- Before critical retrievals (ensures clean, high-quality graph)

Consolidation also runs automatically during idle — manual triggers supplement this.

## Consolidation Log Resource

Read the current consolidation state and orchestrator metrics without triggering a cycle:

```
Resource URI: graphonomous://consolidation/log
```

Returns consolidator state (cycle count, last run, config) and orchestrator plasticity metrics (current learning rate, churn estimate, counters). Useful for monitoring without side effects.

## Health Indicators

| Metric | Healthy Range | Problem If |
|--------|--------------|------------|
| Node count | Growing steadily | Stagnant or shrinking rapidly |
| Pruned count | > 0 occasionally | Always 0 (no decay) or very high (over-aggressive) |
| Merged count | Occasional | Never (duplicates accumulating) |
| Edge/node ratio | 0.5–3.0 | < 0.5 (isolated nodes) or > 3.0 (edge spaghetti) |
| Cycle count | Increasing | N/A (just informational) |

## Consolidation and Goals

Consolidation can prune nodes that are linked to goals, which affects coverage scores. After heavy consolidation, consider re-reviewing active goals with `review_goal` to ensure coverage hasn't dropped below thresholds.

## Anti-patterns to avoid
- Consolidation neglect — never running consolidation, letting the graph accumulate noise
- Running consolidation too frequently during active work (once per session boundary is usually enough)
