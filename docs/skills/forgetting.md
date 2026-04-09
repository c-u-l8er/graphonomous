---
name: forgetting
description: Use when nodes need to be removed from the knowledge graph — soft-hide from retrieval, hard-delete, cascade-delete orphans, GDPR-erase with audit, or run budget-aware priority pruning. Use when the user says "forget this", "delete node", "remove node", "GDPR erase", "prune low-priority", "run forgetting policy", or "remove from memory". For graph-wide cleanup use `consolidate`; for aggregate diagnostics use `graph-health`. Routes through the `act` machine.
argument-hint: <soft|hard|cascade|gdpr|policy> [node_id]
---

# Intentional Forgetting — Structured Knowledge Removal

Four forgetting modes plus budget-aware policy pruning.

## Arguments

Mode and target: $ARGUMENTS

## Forgetting Modes

### Soft Forget — Hide from Retrieval

```
act(action: "forget_node", node_id: "<id>", mode: "soft", reason: "Outdated reference")
```

Node gets `forgotten_at` timestamp internally, excluded from retrieval, but structure/edges preserved. Reversible.

### Hard Forget — Delete Node + Edges

```
act(action: "forget_node", node_id: "<id>", mode: "hard")
```

UtU-style constant-time unlink: severs all edges, deletes node. Irreversible.

### Cascade Forget — Delete + Orphaned Dependents

```
act(action: "forget_node", node_id: "<id>", mode: "cascade", reason: "Removing stale test data")
```

Also deletes orphaned dependents — nodes whose ONLY incoming support was from the deleted node.

### GDPR Erase — Permanent Audit-Logged Deletion

```
act(action: "gdpr_erase", node_id: "<id>")
```

Permanently removes node, all edges, and embedding data. Audit-logged per GDPR Article 17. No recovery possible.

## Budget-Aware Policy Pruning

Preview what would be forgotten:

```
act(action: "forget_policy", dry_run: true, max_nodes: 500)
```

Execute the policy:

```
act(action: "forget_policy", max_nodes: 500)
```

Priority scoring: `confidence x recency x (1 + log(access_count + 1)) x (1 + connectivity)`. Lowest-priority nodes forgotten first via soft-forget.

## When to Use Which

| Scenario | Mode |
|----------|------|
| Outdated but might be useful later | `forget_node` mode: `soft` |
| Definitely wrong, no dependents | `forget_node` mode: `hard` |
| Wrong + has orphaned dependents | `forget_node` mode: `cascade` |
| Contains PII / user data | `gdpr_erase` |
| Graph getting too large | `forget_policy` |
| Want to weaken, not remove | Use `act(action: "belief_revise", operation: "contract")` instead |

## Anti-patterns to avoid

- Don't GDPR-erase non-PII nodes — use soft/hard instead
- Don't forget without checking dependents — use cascade if unsure
- Always dry_run policy before executing
- Don't forget nodes that are part of active goals — check goal linkage first
