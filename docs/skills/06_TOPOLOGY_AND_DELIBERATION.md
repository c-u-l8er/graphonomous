# Skill 06 — Topology and Deliberation

> **Tools covered:** `topology_analyze`, `deliberate`
> **Depends on:** [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) (retrieval provides topology annotations),
> [03_GRAPH_INSPECTION.md](03_GRAPH_INSPECTION.md) (inspecting nodes/edges that form cycles)
> **Concept:** κ (kappa) — the cycle-complexity invariant that drives routing decisions.

---

## Why This Matters

Not all knowledge is a clean tree. Real-world knowledge contains **circular
dependencies** — A depends on B, B depends on C, C depends on A. In a knowledge
graph, these manifest as **strongly connected components (SCCs)**: clusters of
nodes where every node is reachable from every other node through directed edges.

Circular reasoning is dangerous for LLMs. If you naively retrieve from a cyclic
region, you can end up in an echo chamber where mutually reinforcing (but
possibly wrong) nodes all look confident because they point at each other.

Graphonomous detects these cycles automatically using **Tarjan's SCC algorithm**
and computes a **κ (kappa) invariant** for each cluster:

- **κ = 0** → Acyclic (a clean DAG). Safe for fast retrieval.
- **κ > 0** → Cyclic. The region needs **deliberation** — structured reasoning
  that examines fault lines and resolves contradictions before trusting the
  knowledge.

This routing decision happens **automatically** on every `retrieve_context` call
(check the `topology` field in the response). The `topology_analyze` and
`deliberate` tools let you explicitly trigger and control this process.

---

## Key Concepts

### Strongly Connected Components (SCCs)

An SCC is a maximal set of nodes where you can reach any node from any other
node by following directed edges. If nodes A → B → C → A form a cycle, they
are in the same SCC.

```
Simple DAG (κ = 0):        Cycle (κ > 0):

  A → B → C                 A → B
      ↓                     ↑   ↓
      D                     C ← D
```

### The κ (Kappa) Invariant

κ measures the **structural complexity** of circular reasoning in an SCC:

| κ Value | Meaning | Implication |
|---------|---------|-------------|
| 0 | No cycles (DAG node or trivial SCC) | Fast retrieval is safe |
| 1 | Simple cycle | Moderate deliberation needed |
| 2+ | Nested / interleaved cycles | Deep deliberation needed |

Higher κ means more entangled reasoning paths. The deliberation budget
(how much effort to spend resolving conflicts) scales with κ.

### Fault-Line Edges

Within an SCC, **fault-line edges** are the edges that, if removed, would
break the cycle. They represent the *weakest assumptions* or *most questionable
connections* in the circular reasoning chain. Deliberation focuses on these
edges — examining whether they truly hold or represent a flaw in the graph.

```
A ──supports──→ B
↑                ↓
│            (fault line)
│                ↓
C ←──causal───── D

The "D → A" edge might be the fault line: the least certain link.
Breaking it would make the rest a clean chain A → B → D → C.
```

### Routing Decision

After topology analysis, each knowledge region gets a routing decision:

| Routing | Trigger | What to Do |
|---------|---------|-----------|
| `"fast"` | All subgraphs are acyclic (κ = 0 everywhere) | Proceed normally with `retrieve_context` results |
| `"deliberate"` | At least one SCC has κ > 0 | Use the `deliberate` tool or manually examine fault lines |

### DAG Nodes

Nodes that are **not** part of any SCC appear in the `dag_nodes` list. These are
the straightforward, acyclic parts of the knowledge region. You can trust them
through normal retrieval without deliberation.

---

## Tool Reference: `topology_analyze`

### Purpose

Compute the topological structure (SCCs, κ values, routing decision, fault-line
edges) for a set of nodes. This is a **read-only diagnostic** — it tells you
about the structure of a knowledge region without modifying anything.

### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `node_ids` | no | array | Explicit list of node IDs to analyze. If omitted and `query` is also empty, analyzes the full graph. |
| `query` | no | string | Natural-language query. If provided, retrieves relevant nodes first, then analyzes their topology. |

**Resolution order:**
1. If `node_ids` is provided → analyze exactly those nodes
2. If `query` is provided → retrieve relevant nodes (up to 20), then analyze
3. If neither → analyze the entire graph

### Examples

**Analyze a specific knowledge region:**
```json
{
  "node_ids": ["nd_abc123", "nd_def456", "nd_ghi789", "nd_jkl012"]
}
```

**Analyze a topic area:**
```json
{
  "query": "authentication and authorization flow"
}
```

**Full graph analysis:**
```json
{}
```

### Response Shape

```json
{
  "status": "ok",
  "routing": "deliberate",
  "max_kappa": 2,
  "scc_count": 1,
  "sccs": [
    {
      "id": "scc_0",
      "nodes": ["nd_abc123", "nd_def456", "nd_ghi789"],
      "kappa": 2,
      "approximate": false,
      "fault_line_edges": [
        { "source": "nd_ghi789", "target": "nd_abc123" }
      ],
      "routing": "deliberate",
      "deliberation_budget": {
        "max_iterations": 3,
        "focus_edges": 1
      }
    }
  ],
  "dag_nodes": ["nd_jkl012"],
  "recommendation": "This knowledge region contains 1 strongly connected component(s) with max κ=2. Route to deliberation. Deliberate on fault lines: nd_ghi789→nd_abc123.",
  "node_count": 4,
  "selection": "explicit_node_ids"
}
```

**Key fields:**

| Field | Description |
|-------|-------------|
| `routing` | Top-level routing decision: `"fast"` or `"deliberate"` |
| `max_kappa` | Highest κ value across all SCCs |
| `scc_count` | Number of SCCs found |
| `sccs[]` | Array of SCC detail objects |
| `sccs[].nodes` | Node IDs in this SCC |
| `sccs[].kappa` | κ value for this SCC |
| `sccs[].fault_line_edges` | Edges to examine during deliberation |
| `sccs[].deliberation_budget` | Recommended effort for deliberating this SCC |
| `dag_nodes` | Node IDs not in any SCC (safe for fast retrieval) |
| `recommendation` | Human-readable routing recommendation |
| `selection` | How nodes were resolved: `"explicit_node_ids"`, `"query_retrieval_subgraph"`, or `"full_graph"` |

---

## Tool Reference: `deliberate`

### Purpose

Run **κ-driven deliberation** over a knowledge region. This tool orchestrates
the full pipeline:

1. **Resolve scope** — from explicit node IDs or query-based retrieval
2. **Analyze topology** — compute SCCs, κ, and fault-line edges
3. **Deliberate** — reason through cyclic regions, examine fault lines
4. **Optionally crystallize** — write conclusions back to the graph as new semantic nodes

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `query` | ✅ | string | — | The question or decision to deliberate over |
| `node_ids` | no | array | — | Optional: constrain deliberation to these specific nodes |
| `write_back` | no | boolean | `false` | If `true`, crystallized conclusions are stored as new semantic nodes in the graph |

### Examples

**Deliberate on a topic with auto-scope:**
```json
{
  "query": "Is caching at the API gateway redundant given the per-service Redis layer?"
}
```

**Deliberate on specific conflicting nodes:**
```json
{
  "query": "Which claim about token expiry is correct — 1 hour or 2 hours?",
  "node_ids": ["nd_claim_1h", "nd_claim_2h", "nd_code_evidence", "nd_doc_evidence"]
}
```

**Deliberate and persist conclusions:**
```json
{
  "query": "What is the correct deployment order for the microservices given their circular health-check dependencies?",
  "write_back": true
}
```

### Response Shape

```json
{
  "status": "ok",
  "query": "Which claim about token expiry is correct?",
  "deliberation": {
    "converged": true,
    "iterations_used": 2,
    "conclusions": [
      {
        "content": "Token expiry is set to 1 hour based on code evidence in src/auth/config.ts line 42. The 2-hour claim in the architecture doc appears to be outdated (last updated 2024-03).",
        "confidence": 0.82,
        "source_scc_id": "scc_0",
        "source_kappa": 1,
        "fault_lines_examined": [
          { "source": "nd_doc_evidence", "target": "nd_claim_2h" }
        ]
      }
    ],
    "topology_change": {
      "kappa_before": 1,
      "kappa_after": 0,
      "new_nodes_created": 1,
      "note": "Crystallized conclusion broke the cycle by establishing a definitive claim."
    }
  },
  "topology": {
    "routing": "deliberate",
    "max_kappa": 1,
    "scc_count": 1,
    "sccs": [ ... ],
    "dag_nodes": [ ... ]
  },
  "selection": {
    "mode": "explicit_node_ids",
    "node_count": 4,
    "write_back": true
  }
}
```

**Key fields:**

| Field | Description |
|-------|-------------|
| `deliberation.converged` | Did the deliberation reach a stable conclusion? |
| `deliberation.iterations_used` | How many reasoning passes were needed |
| `deliberation.conclusions[]` | Array of crystallized conclusions |
| `deliberation.conclusions[].confidence` | How confident the conclusion is (0.0–1.0) |
| `deliberation.conclusions[].source_scc_id` | Which SCC this conclusion resolves |
| `deliberation.conclusions[].source_kappa` | The κ value of the source SCC |
| `deliberation.conclusions[].fault_lines_examined` | Which fault-line edges were examined |
| `deliberation.topology_change` | How deliberation changed the topology |
| `deliberation.topology_change.kappa_before` / `kappa_after` | κ before and after crystallization |
| `deliberation.topology_change.new_nodes_created` | Number of conclusion nodes written back |

---

## When to Use Each Tool

| Situation | Tool | Why |
|-----------|------|-----|
| `retrieve_context` returned `routing: "deliberate"` | `deliberate` | The retrieval already told you there are cycles — reason through them |
| You want to preview topology before acting | `topology_analyze` | Read-only diagnostic; see the structure without committing to deliberation |
| Two nodes explicitly contradict each other | `deliberate` | Pass both as `node_ids` and ask which is correct |
| You're storing many related nodes and want to check for cycles | `topology_analyze` | Post-ingestion health check |
| A goal review says "escalate" due to uncertain knowledge | `deliberate` | Resolve the uncertainty through structured reasoning |
| Pre-flight check before a high-stakes decision | `topology_analyze` then `deliberate` | First diagnose, then treat |
| Routine retrieval with `routing: "fast"` | Neither | No cycles detected — proceed normally |

---

## The Full Deliberation Workflow

### Step 1: Detect (Passive)

Every `retrieve_context` call includes topology annotations. Watch for them:

```json
// In retrieve_context response:
{
  "topology": {
    "routing": "deliberate",  // ← This is your signal
    "max_kappa": 1,
    "scc_count": 1,
    "sccs": [
      {
        "nodes": ["nd_a", "nd_b", "nd_c"],
        "kappa": 1,
        "fault_line_edges": [
          { "source": "nd_c", "target": "nd_a" }
        ]
      }
    ]
  }
}
```

### Step 2: Diagnose (Optional)

If you want more detail before committing to deliberation, run `topology_analyze`:

```json
{
  "node_ids": ["nd_a", "nd_b", "nd_c"]
}
```

This gives you the full SCC breakdown, fault lines, deliberation budget, and a
human-readable recommendation string.

### Step 3: Deliberate

Run focused deliberation on the cyclic region:

```json
{
  "query": "Which of these claims about the auth flow is correct given the circular evidence?",
  "node_ids": ["nd_a", "nd_b", "nd_c"]
}
```

### Step 4: Apply Conclusions

If `write_back: true`, conclusions are automatically stored as semantic nodes.

If `write_back: false` (the default), you receive conclusions in the response
and can decide how to use them:

- **Trust and proceed:** Use the conclusion in your response to the user.
- **Store manually:** If the conclusion is valuable, use `store_node` to persist it.
- **Report outcome:** After acting on the conclusion, use `learn_from_outcome`.
- **Mark contradiction:** Use `store_edge` with `edge_type: "contradicts"` to
  flag the losing claim for future consolidation.

### Step 5: Verify Resolution

After crystallizing a conclusion (via `write_back` or manual `store_node`),
run `topology_analyze` again on the same nodes to confirm the cycle was broken:

```json
{
  "node_ids": ["nd_a", "nd_b", "nd_c", "<new_conclusion_node_id>"]
}
```

If `routing` is now `"fast"` and `max_kappa` is 0, the deliberation successfully
resolved the circular dependency.

---

## Practical Examples

### Example 1: Contradictory Documentation

You retrieve context and get two nodes that disagree:

- Node A (confidence 0.6): "The API rate limit is 100 req/s per user"
- Node B (confidence 0.7): "The API rate limit is 1000 req/min per user"

These are related by edges (both cite the same design doc) forming a micro-cycle.

**Run deliberation:**
```json
{
  "query": "What is the actual API rate limit — 100/s or 1000/min? These are equivalent if per-second is averaged, but which is the canonical value?",
  "node_ids": ["<node_a_id>", "<node_b_id>"],
  "write_back": true
}
```

**Expected conclusion:** The deliberator examines fault lines and may conclude
that 1000/min and 100/s are mathematically consistent (1000/60 ≈ 16.7/s is not
100/s actually), so these are genuinely contradictory. The conclusion resolves
which value is authoritative.

### Example 2: Circular Dependency in Architecture

Three modules appear to depend on each other circularly according to stored
knowledge:

- "Auth depends on UserService for user lookup"
- "UserService depends on Analytics for usage tracking"
- "Analytics depends on Auth for request validation"

**First, diagnose:**
```json
// topology_analyze
{
  "query": "module dependency cycle between auth, user service, and analytics"
}
```

If κ > 0 and you see the cycle confirmed:

**Then, deliberate:**
```json
{
  "query": "Is this circular dependency real or is one of these edges actually an indirect/optional dependency? Which edge is the weakest?",
  "write_back": true
}
```

The deliberator examines fault lines and may conclude that the Analytics → Auth
edge is actually through a shared middleware, not a direct hard dependency.

### Example 3: Self-Reinforcing Claims with No External Evidence

You notice three nodes all supporting each other at high confidence:

- Node X supports Node Y
- Node Y supports Node Z
- Node Z supports Node X
- None have external evidence (all sourced from "inference")

**This is exactly what κ-aware routing catches.** The cycle of mutual support
inflates confidence without grounding. Deliberation forces the question:
"Where is the external evidence?"

```json
{
  "query": "These three claims reinforce each other but have no external grounding. Examine the fault lines to determine if any claim has independent evidence.",
  "node_ids": ["<x_id>", "<y_id>", "<z_id>"]
}
```

### Example 4: Pre-Goal Topology Check

Before starting work on a goal, check whether the relevant knowledge has
structural issues:

```json
// topology_analyze
{
  "query": "knowledge related to deploying to Kubernetes with Helm charts"
}
```

- If `routing: "fast"` → proceed with the goal confidently
- If `routing: "deliberate"` → run `deliberate` first to resolve conflicts,
  then proceed with cleaner knowledge

---

## `write_back` — When to Use It

| Scenario | `write_back` | Why |
|----------|-------------|-----|
| Resolving a clear contradiction between two nodes | `true` | Crystallize the definitive answer |
| Exploratory deliberation ("what are the trade-offs?") | `false` | You want to see conclusions before committing |
| Pre-flight check before high-stakes action | `false` | Inspect conclusions, then decide manually |
| Automated pipeline / Ralph Loop iteration | `true` | Let the graph self-heal without manual intervention |
| User explicitly asked you to resolve a conflict | `true` | The user expects a durable resolution |

**When `write_back: true`:**
- New semantic nodes are created containing the conclusions
- The `topology_change.new_nodes_created` field tells you how many
- `kappa_after` should be less than `kappa_before` (ideally 0) — the cycle was broken

**When `write_back: false`:**
- Conclusions appear in the response but nothing is stored
- You can still manually `store_node` + `store_edge` based on the conclusions
- This gives you full control over what goes into the graph

---

## Integration with Retrieval (Topology Annotations)

You don't need to manually call `topology_analyze` before every action. The
`retrieve_context` tool **already includes topology annotations** on every response:

```json
{
  "topology": {
    "routing": "fast",     // or "deliberate"
    "max_kappa": 0,        // or > 0
    "scc_count": 0,
    "sccs": [],
    "dag_nodes": []
  }
}
```

**Routing decision tree for agents:**

```
retrieve_context(query: "...")
  │
  ├─ topology.routing == "fast"
  │   └─ Proceed normally. Use results as-is.
  │
  └─ topology.routing == "deliberate"
      │
      ├─ Low stakes (casual question, reversible action)
      │   └─ Mention the cycle to the user, proceed with caution
      │
      └─ High stakes (irreversible action, critical decision)
          └─ Call deliberate(query: "...", node_ids: <scc_nodes>)
              before acting on the knowledge
```

---

## Topology in the Attention System

The attention system (see [08_ATTENTION.md](08_ATTENTION.md)) also factors in
topology. When `attention_survey` returns items with `max_kappa > 0` and
`routing: "deliberate"`, it means the goal's supporting knowledge has structural
complexity that should be addressed before taking action.

---

## Common Mistakes

| Mistake | Why It's Bad | Fix |
|---------|-------------|-----|
| Ignoring `routing: "deliberate"` from retrieval | You may act on circular, self-reinforcing knowledge | At minimum, acknowledge the cycle; for high-stakes, deliberate first |
| Running `deliberate` on an empty graph | No nodes to analyze → trivially fast | Check `retrieve_context` or `list_nodes` first to ensure there's content |
| Always using `write_back: true` | Fills the graph with auto-generated conclusions that may be low quality | Use `false` first, inspect conclusions, then `true` when you trust the process |
| Running `topology_analyze` on the full graph frequently | Expensive on large graphs (all nodes + all edges between them) | Scope with `query` or `node_ids` when possible |
| Confusing κ with confidence | κ measures structural complexity, not trustworthiness | A node can have high confidence but be part of a high-κ cycle (circular support) |
| Not re-checking topology after crystallization | You don't know if the cycle was actually broken | Run `topology_analyze` again on the same nodes + conclusion node |
| Deliberating when `routing` is `"fast"` | Wasted computation — no cycles to resolve | Trust the topology annotation; deliberation is for cyclic regions |

---

## Understanding Deliberation Convergence

The `deliberation.converged` field tells you whether the deliberation reached
a stable conclusion:

| Value | Meaning | What to Do |
|-------|---------|-----------|
| `true` | Deliberation resolved the cycle(s) | Trust the conclusions (modulo confidence) |
| `false` | Deliberation did not converge within budget | The knowledge region is deeply entangled; consider escalating to the user, adding external evidence, or breaking the problem into smaller scoped deliberations |

`iterations_used` tells you how many passes were needed. Compare to the
deliberation budget from topology analysis to understand how hard the problem was.

---

## Quick Reference

```
topology_analyze(query: "...")
→ Read-only diagnostic. See SCCs, κ, fault lines, routing recommendation.

topology_analyze(node_ids: [...])
→ Same, but scoped to specific nodes.

deliberate(query: "...", node_ids: [...], write_back: false)
→ Reason through cycles, get conclusions, but don't store them.

deliberate(query: "...", write_back: true)
→ Auto-scope via retrieval, reason through cycles, store conclusions.
```

**Decision framework:**
- `retrieve_context` says `routing: "fast"` → proceed normally
- `retrieve_context` says `routing: "deliberate"` → run `topology_analyze` for detail, then `deliberate` to resolve
- κ = 0 → no cycles, fast path
- κ = 1 → simple cycle, straightforward deliberation
- κ ≥ 2 → complex entanglement, may need multiple deliberation passes or scope narrowing

---

## Summary

| Principle | Practice |
|-----------|----------|
| Not all knowledge is acyclic | Watch for `routing: "deliberate"` in retrieval responses |
| κ measures cycle complexity | Higher κ = more entangled reasoning = more deliberation effort |
| Fault lines are the weakest links | Deliberation focuses on these edges to break cycles |
| Diagnose before treating | Use `topology_analyze` to understand structure before `deliberate` |
| Crystallization closes cycles | `write_back: true` stores conclusions that break circular dependencies |
| Verify resolution | Re-run `topology_analyze` after deliberation to confirm κ dropped |
| Not every cycle needs deliberation | For low-stakes questions with `routing: "deliberate"`, acknowledging uncertainty may suffice |
| The graph self-heals over time | Deliberation + consolidation gradually eliminate circular reasoning artifacts |