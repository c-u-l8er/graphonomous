---
name: deliberate
description: Use when retrieve returns routing "deliberate", when κ > 0 is detected, before high-stakes decisions with cyclic knowledge, or when the user asks to "deliberate", "reason through cycles", "analyze topology", "think through this carefully". For detecting contradictions use `belief`; this skill reasons through cyclic structures once detected. Routes through the `route` machine.
argument-hint: <question or decision to deliberate on>
---

# Topology and Deliberation

Detect and reason through circular dependencies (cycles) in knowledge.

## Key Concepts

**kappa** is the cycle-complexity invariant — it measures how entangled the knowledge is:
- **kappa = 0** — acyclic DAG, no cycles. Safe for fast retrieval.
- **kappa = 1** — simple cycle (A->B->C->A). Deliberation may help for high-stakes decisions.
- **kappa = 2+** — nested/overlapping cycles. Deliberation strongly recommended.

**SCCs (Strongly Connected Components)** are maximal cyclic clusters — groups of nodes where every node can reach every other node through directed edges.

**Fault-line edges** are the weakest links in a cycle — the assumptions most likely to be wrong. Examining these first is the fastest path to resolving contradictions.

## Arguments

Question to deliberate: $ARGUMENTS

## Analyze Topology

Read-only diagnostic — understand the structure:

```
route(action: "topology", query: "<topic>")
```

**Parameters:**
- `node_ids` (optional) — explicit array of node IDs to analyze
- `query` (optional) — retrieve nodes by query, then analyze
- Neither — analyzes full graph

If both `node_ids` and `query` are provided, `node_ids` takes precedence.

**Response fields:**
- `routing` — `"fast"` or `"deliberate"`
- `max_kappa` — highest kappa value found
- `sccs` — array of strongly connected components, each with its own `routing` and `kappa`
- `fault_line_edges` — weakest edges in cycles (examine these first)
- `deliberation_budget` — `max_iterations` and `focus_edges` to guide deliberation effort
- `recommendation` — human-readable guidance
- `selection` — how nodes were resolved (explicit/query/full_graph)
- `approximate` — whether analysis used approximation for large graphs

## Deliberate Through Cycles

Reason through cyclic knowledge and optionally persist conclusions:

```
route(action: "deliberate",
  query: "Should we use approach A or B given the conflicting evidence?",
  node_ids: ["<node1>", "<node2>"],
  write_back: true
)
```

**Response fields:**
- `conclusions` — array of resolved conclusions, each with `source_scc_id`, `source_kappa`, `fault_lines_examined`
- `deliberation.converged` — whether deliberation reached stable conclusions
- `deliberation.iterations_used` — how many reasoning passes were needed
- `deliberation.topology_change` — `kappa_before`, `kappa_after`, `new_nodes_created`

### When to use `write_back`

- `write_back: true` — crystallizes conclusions as new nodes. Use when you've reached a resolution you want to persist (reduces kappa for future retrievals).
- `write_back: false` — reasoning only, no graph changes. Use for exploration or when you're not confident in the conclusion yet.

## Full Workflow

1. **Detect** — `retrieve(action: "context", ...)` returns `topology.routing: "deliberate"`
2. **Diagnose** — `route(action: "topology", query: "...")` for detailed cycle info and fault-lines
3. **Examine fault-lines** — inspect the weakest edges identified in step 2
4. **Deliberate** — `route(action: "deliberate", query: "...", write_back: true)` to reason through and resolve
5. **Verify** — re-run `route(action: "topology", ...)` to confirm kappa decreased after resolution

## When NOT to deliberate

- When `routing: "fast"` — normal retrieval is sufficient
- For low-stakes decisions — deliberation has a cost
- When there are no cycles (kappa = 0) — nothing to deliberate about
- Over-deliberation is an anti-pattern — only deliberate when routing recommends it or you suspect contradictions
