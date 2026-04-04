# Skill 12 — Forgetting

> **Tools:** `forget_node`, `forget_by_policy`, `gdpr_erase`
> **When:** Memory cleanup, budget management, privacy compliance, stale knowledge removal

---

## Why This Matters

A knowledge graph that never forgets becomes noisy. Old context drowns out
relevant knowledge, retrieval quality degrades, and storage grows unbounded.
Forgetting is not failure — it's hygiene.

Graphonomous provides three levels of forgetting, from gentle to permanent:

| Level | Tool | Reversible? | Use Case |
|-------|------|-------------|----------|
| **Soft** | `forget_node(mode: "soft")` | Yes | Hide from retrieval, keep structure |
| **Hard** | `forget_node(mode: "hard")` | No | Permanent delete, sever all edges |
| **Cascade** | `forget_node(mode: "cascade")` | No | Delete + orphaned dependents |
| **Policy** | `forget_by_policy` | Soft only | Auto-prune lowest-priority nodes |
| **GDPR** | `gdpr_erase` | No | Legal compliance with audit trail |

---

## Soft Forget — Hide but Keep

```
forget_node(node_id: "node_abc123", mode: "soft", reason: "outdated deploy docs")
```

**What happens:**
- Sets `forgotten_at` timestamp on the node
- Node excluded from all retrieval queries (`WHERE forgotten_at IS NULL`)
- Edges preserved — graph structure intact
- **Recoverable** — clear `forgotten_at` to restore

**Use when:**
- Knowledge is probably stale but you're not sure
- You want to test what retrieval looks like without this node
- Temporary suppression during an investigation

---

## Hard Forget — Permanent Delete

```
forget_node(node_id: "node_abc123", mode: "hard", reason: "confirmed incorrect")
```

**What happens:**
- Severs ALL edges (incoming and outgoing) using UtU-style constant-time unlink
- Deletes the node permanently
- Embedding data removed
- **No recovery possible**

**Use when:**
- Knowledge is confirmed wrong and has no historical value
- Node was created by mistake (test data, duplicate, malformed)

---

## Cascade Forget — Delete + Orphans

```
forget_node(node_id: "node_abc123", mode: "cascade", reason: "removing deprecated module knowledge")
```

**What happens:**
1. Hard-deletes the primary node (same as hard mode)
2. Finds dependent nodes that have **only this node as support** (no other incoming edges)
3. Hard-deletes each orphan
4. Returns count of cascaded deletions in reason field

**Use when:**
- Removing a cluster of related knowledge (e.g., all nodes about a deprecated feature)
- The primary node is the sole anchor for a subtree
- You've verified the dependents are genuinely orphaned

**Caution:** Cascade can delete more than expected if the dependency tree is deep.
Always check `graph_traverse` from the node first to understand the blast radius.

---

## Policy-Based Forgetting — Automatic Pruning

```
# Preview what would be forgotten (dry run)
forget_by_policy(policy: "hybrid", dry_run: true)

# Execute the pruning
forget_by_policy(policy: "hybrid", dry_run: false)
```

**The hybrid priority scoring formula:**

```
priority = confidence × recency × (1 + log(access_count + 1)) × (1 + connectivity)

recency   = max(exp(-hours_since_access / 360), 0.01)  # 30-day half-life
connectivity = min(edge_count / 10, 1.0)                # normalized
```

Nodes with **lowest priority** are soft-forgotten first, up to the budget
(default: keep max 10,000 nodes).

**Key behaviors:**
- Only **soft-forgets** (not hard delete) — reversible
- High-confidence, recently-accessed, well-connected nodes survive
- Low-confidence, stale, isolated nodes are pruned first
- `dry_run: true` returns candidates without acting — always preview first

**Use when:**
- Graph has grown past comfortable size
- Consolidation alone isn't pruning enough
- You want a principled, automatic cleanup pass
- End of a long project phase (archive old context)

---

## GDPR Erase — Legal Compliance

```
gdpr_erase(node_id: "node_abc123")
```

**What happens:**
1. Creates an **audit record** (node_id, node_type, timestamp, reason: "gdpr_erase")
2. Severs all edges
3. Permanently deletes the node
4. Logs warning: "GDPR erase: node {id} permanently deleted"
5. **No recovery possible** — complete removal

**Differences from hard forget:**
- Creates audit trail (hard forget does not)
- Designed for GDPR Article 17 "right to be forgotten" compliance
- Should be used when deletion is legally required, not just convenient

**Use when:**
- User requests deletion of their personal data
- Legal/compliance requirement to remove specific knowledge
- Audit trail of the deletion is required

---

## Forgetting vs. Consolidation vs. Belief Revision

These three mechanisms handle different kinds of "knowledge cleanup":

| Mechanism | What It Does | When to Use |
|-----------|-------------|-------------|
| **Consolidation** | Passive decay + prune + merge (7-stage pipeline) | Routine maintenance, runs automatically |
| **Belief revision** | Contract/revise with confidence propagation | Knowledge is *wrong* — update dependents |
| **Forgetting** | Active removal from retrieval or storage | Knowledge is *irrelevant* — remove entirely |

**Decision tree:**
1. Is the knowledge **wrong**? → Use `belief_revise` (contract or revise)
2. Is the knowledge **stale but might be relevant later**? → Use `forget_node(mode: "soft")`
3. Is the knowledge **definitely irrelevant**? → Use `forget_node(mode: "hard")`
4. Is it a **legal requirement** to delete? → Use `gdpr_erase`
5. Is the graph **too large overall**? → Use `forget_by_policy`
6. Do nothing — let `run_consolidation` handle natural decay

---

## The Forgetting Workflow

### Manual targeted cleanup:

```
1. Inspect    → graph_stats() to check graph size and distributions
2. Identify   → query_graph(operation: "list_nodes", ...) or retrieve with low min_score
3. Verify     → graph_traverse(start_node_id: "...", max_depth: 2) to check dependents
4. Forget     → forget_node(node_id: "...", mode: "soft/hard/cascade")
5. Confirm    → graph_stats() to verify counts changed
```

### Automated budget cleanup:

```
1. Preview    → forget_by_policy(dry_run: true) — review candidates
2. Assess     → Check if any candidates are still valuable
3. Execute    → forget_by_policy(dry_run: false)
4. Consolidate → run_consolidation() to clean up any edge debris
```

---

## Anti-Patterns

| Anti-Pattern | What Goes Wrong | Fix |
|---|---|---|
| **Hard-delete without checking dependents** | Orphans other nodes that relied on this one | Use `graph_traverse` first, or use cascade mode |
| **Policy-prune without dry run** | Accidentally forget valuable nodes | Always `dry_run: true` first |
| **GDPR erase for non-GDPR reasons** | Creates unnecessary audit overhead | Use hard forget for routine deletion |
| **Forgetting instead of revising** | Loses the correction opportunity — dependents aren't weakened | If knowledge is *wrong*, revise. If *irrelevant*, forget |
| **Never forgetting** | Graph bloats, retrieval quality degrades | Run `forget_by_policy` periodically or let consolidation prune |
| **Cascade without graph_traverse** | Deletes more nodes than expected | Always inspect the subtree before cascading |
