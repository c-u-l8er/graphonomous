# Skill 07 — Consolidation

> **Tool:** `run_consolidation`
> **Purpose:** Trigger and inspect memory maintenance cycles — decay, prune,
> merge, strengthen, and promote knowledge nodes. Inspired by the brain's
> sleep-cycle consolidation.
> **Depends on:** [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) (you need stored nodes for
> consolidation to act on), [02_LEARNING_LOOP.md](02_LEARNING_LOOP.md) (outcome feedback adjusts
> confidence, which consolidation then acts upon)

---

## Why This Matters

A knowledge graph that only grows eventually becomes noisy, bloated, and slow.
Without maintenance:

- **Low-confidence noise** accumulates — half-remembered facts, stale claims,
  speculative guesses that were never verified
- **Near-duplicates** pile up — the same fact stored slightly differently 5 times
- **Stale knowledge** lingers — something true last month may not be true today
- **Co-retrieved knowledge** doesn't strengthen — nodes that always appear
  together never form stronger associations

Consolidation is the antidote. It runs a multi-stage pipeline during idle
periods (or on demand) that **decays**, **prunes**, **merges**, **strengthens**,
and **promotes** knowledge — keeping the graph lean, accurate, and well-organized.

Think of it like the brain's sleep cycles: you learn during the day (store nodes,
learn from outcomes), and the brain consolidates overnight (prune weak memories,
strengthen important ones, merge related memories into abstractions).

---

## How Consolidation Works

### The 7-Stage Pipeline

When a consolidation cycle runs, Graphonomous executes these stages in order:

```
Stage 1: decay_confidence
  └─ Apply time-based decay to all node confidence scores.
     Nodes that haven't been accessed or reinforced lose confidence.

Stage 2: prune_weak_nodes
  └─ Remove nodes whose confidence has dropped below the prune threshold.
     These are the graph's "forgotten" memories — too weak to keep.

Stage 3: prune_weak_edges
  └─ Remove edges whose weight has decayed below the edge threshold.
     Weak relationships are cleaned up.

Stage 4: strengthen_coactivated
  └─ Boost edges between nodes that are frequently co-retrieved.
     "Neurons that fire together wire together."

Stage 5: merge_similar_nodes
  └─ Merge nodes with embedding similarity > merge threshold (default ~0.95).
     Near-duplicates become single authoritative nodes.

Stage 6: promote_timescale
  └─ Move reinforced fast-memory nodes to slower timescales.
     Knowledge that keeps getting accessed is promoted to long-term memory.

Stage 7: generate_abstractions
  └─ Create semantic nodes from clusters of episodic memories.
     Patterns across specific events become generalized knowledge.
```

### Timescale Promotion

Nodes live on one of four timescales, each with a different TTL without
reinforcement:

| Timescale | TTL (No Reinforcement) | Description |
|-----------|----------------------|-------------|
| **fast** | ~1 hour | Current conversation context. Ephemeral. |
| **medium** | ~7 days | Session patterns. Promoted from fast when reinforced. |
| **slow** | ~90 days | Stable knowledge. Promoted from medium after repeated access. |
| **glacial** | Never expires | Core domain knowledge. Rarely changes. |

Consolidation promotes nodes up the timescale ladder when their `access_count`
exceeds a threshold relative to their age. Nodes are demoted or pruned when
their confidence decays below the prune threshold.

### Idle Detection

By default, the Consolidator GenServer checks every 5 minutes whether the
system has been idle for at least 30 seconds. If idle, it runs a full
consolidation cycle automatically. You never *need* to trigger consolidation
manually — it happens on its own.

But you *can* trigger it explicitly, and sometimes you *should*.

---

## Tool Reference: `run_consolidation`

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `action` | no | string | `"run_and_status"` | What to do: `"run"`, `"status"`, or `"run_and_status"` |
| `wait_ms` | no | number | 0 | Delay in milliseconds before reading status (0–30000). Gives consolidation time to complete before you read the results. |

### Actions

| Action | What It Does |
|--------|-------------|
| `run` | Trigger a consolidation cycle. Returns confirmation that it was triggered. Consolidation runs asynchronously. |
| `status` | Return current consolidator runtime info and graph health. Does not trigger consolidation. |
| `run_and_status` | Trigger a cycle, optionally wait, then return runtime info and health. **This is the default and most useful action.** |

### Examples

**Trigger and check (most common):**

```json
{
  "action": "run_and_status",
  "wait_ms": 2000
}
```

This triggers consolidation, waits 2 seconds for it to complete (or make
progress), then returns the current status. For small-to-medium graphs, 2000ms
is usually enough. For large graphs, increase to 5000–10000ms.

**Just check status (no trigger):**

```json
{
  "action": "status"
}
```

Use this when you want to inspect the consolidator's state without triggering
a new cycle — for example, to check when the last cycle ran or whether one is
currently in progress.

**Fire-and-forget trigger:**

```json
{
  "action": "run",
  "wait_ms": 0
}
```

Trigger consolidation and return immediately. You don't need to see the results
right away — you'll benefit on the next retrieval.

**Trigger with generous wait:**

```json
{
  "action": "run_and_status",
  "wait_ms": 5000
}
```

For larger graphs or when you want to confirm consolidation completed before
continuing.

### Response Shape

**For `run` action:**

```json
{
  "status": "ok",
  "action": "run",
  "result": {
    "triggered": "true",
    "wait_ms": 0
  }
}
```

**For `status` action:**

```json
{
  "status": "ok",
  "action": "status",
  "result": {
    "consolidator": {
      "interval_ms": 300000,
      "decay_rate": 0.01,
      "prune_threshold": 0.1,
      "merge_similarity": 0.95,
      "last_run": "2025-06-15T14:30:00Z",
      "cycle_count": 42,
      "total_pruned": 18,
      "total_merged": 7,
      "total_promoted": 12
    },
    "health": {
      "node_count": 156,
      "edge_count": 89,
      "goal_count": 5,
      "outcome_count": 23,
      "uptime_ms": 3600000
    }
  }
}
```

**For `run_and_status` action:**

Same shape as `status`, but consolidation was triggered first and `wait_ms`
was respected before reading the values. The stats reflect post-consolidation
state (if consolidation completed within the wait window).

---

## When to Trigger Consolidation

### Trigger at the end of productive sessions

After a session where you created many nodes and ran several learning loops,
consolidation helps clean up and strengthen the new knowledge:

```json
{
  "action": "run_and_status",
  "wait_ms": 3000
}
```

This is the #1 use case. It's part of the recommended end-of-session checklist
(see [SKILLS.md](SKILLS.md)).

### Trigger periodically during long autonomous runs

In a Ralph Loop or similar iterative protocol, trigger consolidation every
4–5 iterations:

```
Iteration 1: explore → store → learn
Iteration 2: explore → store → learn
Iteration 3: explore → store → learn
Iteration 4: explore → store → learn
Iteration 5: CONSOLIDATE + explore → store → learn
...
```

This prevents the graph from accumulating noise during the run.

### Trigger before important retrievals

If you suspect the graph has stale or low-quality knowledge and you're about
to do a critical retrieval (e.g., for a high-stakes `review_goal`), consolidate
first so the retrieval draws from cleaned-up knowledge:

```
Step 1: run_consolidation(action: "run_and_status", wait_ms: 3000)
Step 2: retrieve_context(query: "critical topic")
Step 3: review_goal(...)
```

### Trigger after bulk ingestion

If you used the `scan` CLI command to ingest a directory or manually stored
many nodes in rapid succession, consolidation can merge near-duplicates and
establish the timescale baseline:

```json
{
  "action": "run_and_status",
  "wait_ms": 5000
}
```

### Check status for diagnostics

When debugging why retrieval seems off, or why confidence scores look strange,
check the consolidator status:

```json
{
  "action": "status"
}
```

Look at:
- `last_run` — when did consolidation last execute?
- `total_pruned` — are many nodes being pruned? Maybe the prune threshold is too aggressive.
- `total_merged` — are many nodes being merged? Maybe you're storing too many duplicates.
- `cycle_count` — how many cycles have run total?

---

## When NOT to Trigger Consolidation

### Don't trigger mid-thought

If you're in the middle of a multi-step reasoning process — retrieving context,
examining edges, building a signal for `review_goal` — don't consolidate.
Consolidation may prune or merge nodes you're currently referencing.

### Don't trigger with every single turn

Consolidation is a maintenance operation, not something to run after every
`store_node`. The automatic idle-time trigger handles routine maintenance.
Manual triggers should be deliberate: end of session, periodic during long
runs, or before critical operations.

### Don't trigger with very long wait_ms just to block

The `wait_ms` parameter caps at 30000ms (30 seconds). Even this is quite long
for most graphs. If consolidation takes more than a few seconds, let it run
asynchronously and check status later:

```json
// Trigger now
{ "action": "run", "wait_ms": 0 }

// Check later
{ "action": "status" }
```

---

## Consolidation Configuration

Consolidation behavior is controlled by CLI flags or environment variables set
at server startup. You cannot change these dynamically through MCP — they're
set once when Graphonomous launches.

| Configuration | CLI Flag | Env Var | Default | Description |
|---------------|----------|---------|---------|-------------|
| Interval | `--consolidator-interval-ms` | `GRAPHONOMOUS_CONSOLIDATOR_INTERVAL_MS` | 300000 (5 min) | How often to check for idle and potentially consolidate |
| Decay rate | `--consolidator-decay-rate` | `GRAPHONOMOUS_CONSOLIDATOR_DECAY_RATE` | 0.01 | Per-cycle confidence decay (fraction subtracted) |
| Prune threshold | `--consolidator-prune-threshold` | `GRAPHONOMOUS_CONSOLIDATOR_PRUNE_THRESHOLD` | 0.1 | Confidence below this → node gets pruned |
| Merge similarity | `--consolidator-merge-similarity` | `GRAPHONOMOUS_CONSOLIDATOR_MERGE_SIMILARITY` | 0.95 | Embedding similarity above this → nodes get merged |
| Learning rate | `--learning-rate` | `GRAPHONOMOUS_LEARNING_RATE` | (varies) | Affects how much confidence changes per outcome |

### What the Knobs Do

**Decay rate** — Higher values mean faster forgetting. A rate of 0.01 means
each consolidation cycle subtracts 0.01 from every node's confidence (before
bounding). If a node at 0.5 confidence isn't accessed or reinforced through
10 cycles, it drops to 0.4. Eventually it hits the prune threshold and is
removed.

- Low decay (0.001–0.005): Graph remembers everything for a long time. Good for
  stable domains where knowledge changes slowly.
- High decay (0.02–0.05): Graph forgets aggressively. Good for rapidly changing
  environments where stale knowledge is dangerous.

**Prune threshold** — Nodes below this confidence are removed.

- Low threshold (0.05): Only truly dead knowledge is pruned.
- High threshold (0.2–0.3): More aggressive pruning. Graph stays tighter but
  may lose marginally useful knowledge.

**Merge similarity** — How similar two nodes must be to be merged.

- High threshold (0.95–0.99): Only near-exact duplicates merge. Conservative.
- Lower threshold (0.85–0.90): Paraphrases and close variants merge more
  aggressively. Risks losing nuance.

---

## Understanding Consolidation's Effect on Your Work

### Nodes May Disappear

If you stored a node a few sessions ago with confidence 0.3 and never retrieved
or reinforced it, consolidation may prune it. This is by design — the graph
forgets what doesn't prove useful.

If you try to `get_node` or reference a node ID and it returns "not found", it
may have been **pruned** (confidence decayed below threshold) or **merged** (combined
with a similar node). This is not a bug — it's the self-correcting memory system
doing its job.

### What to do if a needed node was pruned:

1. Re-store the knowledge with fresh confidence:
   ```json
   {
     "content": "The important fact that I still need",
     "confidence": 0.7,
     "source": "re-established from prior knowledge"
   }
   ```
2. Reinforce it by accessing it (retrieving it) and reporting successful outcomes.
3. Consider raising the initial confidence for critical knowledge so it resists decay.

### Edges May Disappear

Weak edges are pruned just like weak nodes. If a relationship was marginal
(weight 0.2) and hasn't been reinforced, consolidation may remove it.

### Nodes May Merge

Two nodes about the same topic with very high embedding similarity may be merged
into one. The surviving node typically retains the higher confidence and combines
metadata. The merged-away node's ID becomes invalid.

### Co-Retrieved Nodes Get Stronger

Nodes that are frequently retrieved together (co-activated) have their connecting
edges strengthened. Over time, this means that your most useful knowledge
clusters become tighter and easier to retrieve as a unit.

### Episodic → Semantic Promotion

Clusters of episodic memories about the same topic may trigger abstraction:
the consolidator generates a semantic node that captures the pattern across
individual events. For example:

- Episodic: "User asked about auth bug on June 15"
- Episodic: "User asked about auth Token on June 16"
- Episodic: "Auth review session on June 18"
- **Abstracted semantic**: "Auth is a recurring concern — likely needs comprehensive documentation or rework"

---

## Consolidation + the Learning Loop

Consolidation and the learning loop (`learn_from_outcome`) work together:

```
learn_from_outcome:
  success → boosts confidence on causal nodes
  failure → reduces confidence on causal nodes

consolidation:
  decay → gradually lowers confidence on all untouched nodes
  prune → removes nodes that decayed below threshold
  strengthen → boosts edges between co-retrieved nodes
  merge → combines near-duplicates

Net effect:
  - Knowledge that proves useful (positive outcomes + frequent access)
    RISES in confidence and gets promoted to slower timescales.
  - Knowledge that proves wrong (negative outcomes) or irrelevant
    (never accessed) SINKS and eventually gets pruned.
  - The graph naturally converges toward high-quality, useful knowledge.
```

This is the fundamental value proposition of Graphonomous: **the graph gets
better over time without retraining any model weights**.

---

## Consolidation + Active Forgetting

Consolidation handles **passive** memory management (decay, prune, merge).
For **active** memory management, use the forgetting tools:

| Need | Tool | How It Complements Consolidation |
|------|------|----------------------------------|
| Hide a node from retrieval (reversible) | `forget_node(mode: "soft")` | Faster than waiting for decay; node stays in graph |
| Delete a node permanently | `forget_node(mode: "hard")` | Immediate removal; consolidation would take many cycles |
| Delete a node + orphaned dependents | `forget_node(mode: "cascade")` | Cleans up subtrees; consolidation can't do targeted cascades |
| Auto-prune lowest-priority nodes | `forget_by_policy(policy: "hybrid")` | Budget-aware cleanup; consolidation has no budget concept |
| GDPR-compliant permanent deletion | `gdpr_erase` | Legal requirement; consolidation doesn't create audit trails |

**When to use which:**
- Let **consolidation** handle routine maintenance (run automatically or at session end)
- Use **forget_node** when you *know* specific nodes should go
- Use **forget_by_policy** when the graph is too large overall
- Use **gdpr_erase** only for legal compliance

See [12_FORGETTING.md](12_FORGETTING.md) for full details on active forgetting.

---

## Consolidation + Belief Revision

When `belief_revise(operation: "revise")` supersedes a node, the old node's
confidence drops to 30% of its original value. Consolidation may then prune
it in subsequent cycles if it stays below the prune threshold. This is the
intended lifecycle: revise → decay → prune.

If you want the old belief preserved for historical reference, raise its
confidence above the prune threshold (but below the new node's confidence)
after revision. Otherwise, let consolidation handle the cleanup.

---

## Consolidation + Goals

Consolidation affects goal-linked nodes. If a node linked to a goal gets
pruned, the goal's effective coverage shrinks. This means:

- After consolidation, a previously `act`-ready goal might need re-review.
- If key nodes were pruned, `review_goal` may downgrade the decision to `learn`.
- Consolidation effectively raises the bar for goal confidence — only
  well-supported, recently-accessed knowledge survives.

**Best practice:** After a consolidation cycle, re-review any active goals
that are near their `act` threshold:

```
Step 1: run_consolidation(action: "run_and_status", wait_ms: 3000)
Step 2: manage_goal(operation: "list_goals", payload: '{"status": "active"}')
Step 3: For each active goal:
          retrieve_context + build signal + review_goal
```

---

## Monitoring Graph Health

Use `run_consolidation(action: "status")` as a health check. Key indicators:

| Metric | Healthy | Concerning | Action |
|--------|---------|-----------|--------|
| `node_count` growing steadily | ✅ | Graph bloat (growing much faster than knowledge is being added) | Consolidate more frequently; check for duplicate storage patterns |
| `total_pruned` > 0 | ✅ | `total_pruned` = 0 after many cycles (nothing ever decays) | Check decay rate — may be too low |
| `total_pruned` >> nodes stored | ⚠️ | Pruning most of what you store | Either storing too many low-confidence nodes or decay/prune too aggressive |
| `total_merged` > 0 occasionally | ✅ | `total_merged` very high | Storing too many near-duplicates. Check for duplicates before `store_node` (see Skill 03, Pattern 4) |
| `cycle_count` increasing | ✅ | `cycle_count` = 0 or stale `last_run` | Consolidator may not be running. Check server logs. |
| `edge_count` / `node_count` ratio 0.5–3.0 | ✅ | Ratio > 5 (extremely dense graph) | Many redundant edges. Consolidation will help, but consider being more selective with `store_edge`. |
| `edge_count` / `node_count` ratio < 0.1 | ⚠️ | Graph is very sparse (isolated nodes) | Create more edges to improve retrieval neighborhood expansion. |

---

## Consolidation Resources (Read-Only)

In addition to the `run_consolidation` tool, you can read consolidated state
via MCP resources:

| Resource URI | What It Returns |
|-------------|----------------|
| `graphonomous://runtime/health` | Node/edge/goal/outcome counts, uptime, consolidator state |
| `graphonomous://goals/snapshot` | Full GoalGraph snapshot with status, progress, linked nodes |

These are **read-only** and don't trigger any consolidation. They're useful for
quick health checks without the overhead of a tool call.

---

## Practical Workflow: End-of-Session Maintenance

Here's the recommended end-of-session consolidation pattern:

```
Step 1: Review what you've done this session
  query_graph(operation: "list_nodes", node_type: "episodic", limit: 20)
  → See what episodic memories were created

Step 2: Ensure all outcomes are reported
  (any pending learn_from_outcome calls should be made first)

Step 3: Update goal progress
  manage_goal(operation: "set_progress", goal_id: "...", progress: 0.X)

Step 4: Trigger consolidation
  run_consolidation(action: "run_and_status", wait_ms: 3000)

Step 5: Report results
  Tell the user:
  - "Consolidation complete. Graph has X nodes, Y edges.
     Z nodes pruned, W merged since last cycle.
     Consolidator has run N total cycles."
```

---

## Common Mistakes

| Mistake | Why It's Bad | Fix |
|---------|-------------|-----|
| Never triggering consolidation manually | Relying entirely on idle-time auto-trigger, which may not fire in busy sessions | Trigger at end of session and periodically during long runs |
| Triggering every turn | Needless overhead; consolidation is a batch operation | Trigger at natural breakpoints: end of session, every ~5 iterations, before critical operations |
| Using `wait_ms: 30000` always | Blocks the conversation for 30 seconds unnecessarily | Start with 2000–3000ms; only increase for very large graphs |
| Ignoring the status response | Missing early signals of graph bloat or configuration issues | Read `node_count`, `total_pruned`, `total_merged` after consolidation |
| Storing critical knowledge at low confidence | Consolidation will decay and eventually prune it | Store critical facts at confidence 0.7+ and reinforce through access and positive outcomes |
| Not re-reviewing goals after consolidation | Goal coverage may have changed due to pruned/merged nodes | Re-review active goals after consolidation, especially near decision thresholds |
| Panicking when node IDs become invalid | Pruning and merging naturally invalidate old IDs | Expected behavior. Re-store if needed. Use `retrieve_context` (query-based) rather than hardcoding node IDs across sessions. |
| Setting prune threshold too high at startup | Aggressively prunes marginally useful knowledge | Use defaults (0.1) unless you have a specific reason to change |

---

## Summary

| Principle | Practice |
|-----------|----------|
| The graph must forget to stay useful | Consolidation prunes weak knowledge and strengthens strong knowledge |
| Consolidation is like sleep | It runs during idle periods automatically; manual triggers supplement this |
| Trigger at session boundaries | End-of-session consolidation is the most important manual trigger |
| Monitor health via status | Use `status` action to track graph size, prune/merge rates, cycle count |
| Successful knowledge survives | Nodes reinforced by positive outcomes and frequent access resist decay |
| Unused knowledge fades | Nodes that are never retrieved or reinforced eventually get pruned — this is correct |
| Near-duplicates merge automatically | The merge stage combines highly similar nodes, deduplicating the graph |
| Goals may need re-review after consolidation | Coverage can change when nodes are pruned or merged |
| Configuration is set at server startup | Decay rate, prune threshold, merge similarity, and interval are CLI/env configs |
| The graph gets better over time | This is the whole point — a self-healing, self-improving knowledge graph |