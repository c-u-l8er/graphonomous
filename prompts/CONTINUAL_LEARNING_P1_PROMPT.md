# Graphonomous v0.3 — P1 Implementation Prompt (Week 3-4)

## Prerequisites

P0 must be complete before starting P1. Verify:
- [ ] `mix test` passes (240+ existing + new P0 tests)
- [ ] kappa > 0 appears on at least some retrieval queries
- [ ] `BeliefRevision` module exists with `expand/revise/contract/detect_contradictions`
- [ ] Consolidator Stage 4.5 (conflict resolution) is operational
- [ ] `:superseded_by` edge type works

## Session Goal

Implement P1 capabilities: **two-phase retrieval** (Q-value utility scoring), **simplified forgetting** (budget-aware hybrid pruning + GDPR hard delete), **GraphMemBench Phase 1** (40 scenarios), and **LongMemEval re-benchmark**.

## Active Goal

Retrieve and update: `goal_ae39998e19f363c1519679b15d24744d`

---

## Capability 4: Two-Phase Retrieval (2 days)

### What it does
Adds a second ranking phase to retrieval: after semantic similarity scoring, re-rank by Q-value (outcome utility). Nodes that have historically contributed to successful outcomes rank higher; nodes that led to failures rank lower.

### Research basis
MemRL (arxiv 2601.03192) demonstrates semantic + utility outperforms semantic-only. We use Bayesian updates instead of RL training — simpler, interpretable, already in the codebase.

### Schema migration
```sql
ALTER TABLE nodes ADD COLUMN q_value REAL DEFAULT 0.5;
ALTER TABLE nodes ADD COLUMN q_update_count INTEGER DEFAULT 0;
```

### File: `graphonomous/lib/graphonomous/retriever.ex`
After existing ranking pipeline, add Phase 2:

```elixir
defp utility_rerank(ranked, opts) do
  alpha = Keyword.get(opts, :utility_weight, 0.3)

  ranked
  |> Enum.map(fn entry ->
    q = Store.get_q_value(entry.node_id) || 0.5
    blended = (1.0 - alpha) * entry.score + alpha * q
    %{entry | score: blended, metadata: Map.put(entry.metadata || %{}, :utility, q)}
  end)
  |> Enum.sort_by(& &1.score, :desc)
end
```

Call `utility_rerank/2` after the existing scoring in the retrieval pipeline. Skip when `q_update_count == 0` for all candidates (no outcome data yet — avoids changing behavior until outcomes exist).

### File: `graphonomous/lib/graphonomous/learner.ex`
In `update_node_from_outcome/3`, after updating confidence, also update Q-value:

```elixir
q_learning_rate = 0.3  # Faster than confidence learning rate (0.2)
reward = case status do
  :success -> 1.0
  :partial_success -> 0.65
  :failure -> 0.0
  :timeout -> 0.25
end

new_q = old_q + q_learning_rate * (reward - old_q)
Store.update_q_value(node_id, new_q, q_update_count + 1)
```

### File: `graphonomous/lib/graphonomous/consolidator.ex`
In Stage 1 (decay), decay Q-values at HALF the confidence decay rate:
```elixir
q_decay = node.decay_rate * 0.5
new_q = node.q_value * (1.0 - q_decay)
```

### Tests
- Store 10 nodes. Mark 3 as causal in successful outcome, 2 in failed outcome. Verify re-ranking promotes successful nodes.
- Verify Q-values don't affect ranking when no outcomes exist (q_update_count == 0).
- Verify Q-value decay is slower than confidence decay.

---

## Capability 5: Simplified Forgetting (3 days)

### What it does
Two forgetting policies (not six):
1. **Budget-aware hybrid pruning** — combines LRU + priority-decay. Triggers when node count exceeds `max_nodes`. Scores each node: `priority = confidence * recency_factor * (1 + log(access_count + 1))`. Lowest-priority nodes forgotten first.
2. **Governance-gated hard delete** — UtU-style constant-time cascade deletion. Severs all edges, deletes node. Audit-logged. For GDPR compliance.

### Research basis
- FiFA (arxiv 2512.12856): hybrid policy achieves 0.911 composite score. LRU + priority-decay are the two most effective components.
- UtU (arxiv 2402.10695): constant-time graph unlearning via edge unlinking, 97.3% privacy protection.

### Schema migration
```sql
ALTER TABLE nodes ADD COLUMN forgotten_at TEXT;

CREATE TABLE IF NOT EXISTS forgetting_config (
  id TEXT PRIMARY KEY DEFAULT 'default',
  policy TEXT NOT NULL DEFAULT 'hybrid',
  max_nodes INTEGER DEFAULT 10000,
  max_age_hours INTEGER DEFAULT 720,
  updated_at TEXT NOT NULL
);
```

### New file: `graphonomous/lib/graphonomous/forgetter.ex`
```elixir
defmodule Graphonomous.Forgetter do
  @moduledoc """
  Policy-driven intentional forgetting with governance integration.
  Two policies: hybrid pruning (LRU + priority-decay) and GDPR hard delete.
  """

  @type forget_mode :: :soft | :hard | :cascade

  def forget(node_id, mode \\ :soft, opts \\ [])
  # :soft — set forgotten_at timestamp, exclude from retrieval, keep structure
  # :hard — delete node + all edges (UtU constant-time unlink)
  # :cascade — hard delete + propagate to nodes whose ONLY support is this node

  def forget_by_policy(policy \\ :hybrid, opts \\ [])
  # :hybrid — score all nodes by priority, forget lowest until under max_nodes
  # Returns {forgotten_count, surviving_count}

  def gdpr_erase(node_id)
  # Hard delete with audit record. No recovery. Requires OS-006 act-level autonomy.

  def candidates(policy \\ :hybrid, opts \\ [])
  # Dry run: return nodes that WOULD be forgotten, sorted by priority ascending

  def priority_score(node) do
    recency = recency_factor(node.access_recency)  # 1.0 for recent, decays to 0.0
    confidence = node.confidence
    access = 1.0 + :math.log(node.access_count + 1)
    connectivity = edge_count(node.id) / max_edge_count()  # 0.0 to 1.0

    confidence * recency * access * (1.0 + connectivity)
  end
end
```

### New MCP tools (3)
- `forget_node` — `{node_id, mode: "soft"|"hard"|"cascade", reason: string}`
- `forget_by_policy` — `{policy: "hybrid", dry_run: boolean, max_nodes: integer}`
- `gdpr_erase` — `{node_id}` — hard delete with audit trail

### File: `graphonomous/lib/graphonomous/consolidator.ex`
Replace Stage 2 (prune weak nodes) with:
```elixir
defp stage_prune_nodes(state) do
  config = Forgetter.get_config()
  node_count = Store.count_nodes()

  if node_count > config.max_nodes do
    {:ok, result} = Forgetter.forget_by_policy(:hybrid, max_nodes: config.max_nodes)
    emit_telemetry(:pruned_nodes, %{count: result.forgotten_count, policy: :hybrid})
  else
    # Fall back to existing confidence threshold pruning
    existing_prune_logic(state)
  end
end
```

### File: `graphonomous/lib/graphonomous/retriever.ex`
Filter out soft-forgotten nodes in retrieval:
```elixir
# In the retrieval query, add: WHERE forgotten_at IS NULL
```

### File: `graphonomous/lib/graphonomous/attention.ex`
Add memory pressure detection to survey:
```elixir
defp check_memory_pressure() do
  config = Forgetter.get_config()
  count = Store.count_nodes()
  if count > config.max_nodes * 0.9 do
    %{type: :memory_pressure, severity: :warning, node_count: count, max: config.max_nodes}
  end
end
```

### Tests
- Fill graph with 500 nodes of varying confidence/recency/access. Run hybrid forgetting with max_nodes=200. Verify high-priority nodes survive.
- Test GDPR erase removes node + all edges completely.
- Test soft forget excludes from retrieval but preserves structure.
- Test cascade forget propagates to orphaned dependents.
- Test retrieval filters out forgotten nodes.

---

## Capability 6: GraphMemBench Phase 1 (3 days)

### What it does
40 test scenarios across 5 categories (8 each) validating P0+P1 capabilities:

**Category 1: Kappa Activation (8 scenarios)**
- Store nodes with mutual references → verify kappa >= 1
- Store contradicting facts → verify `:contradicts` edges form SCC
- Retrieve with expanded topology window → verify neighbor inclusion
- Verify semantic back-references create reverse edges
- Test kappa computation on 2-node, 3-node, and N-node SCCs
- Test that kappa=0 fast path still works for acyclic subgraphs
- Test deliberation triggers when kappa > 0
- End-to-end: ingest file pair with mutual imports → retrieve → verify kappa > 0

**Category 2: Belief Revision (8 scenarios)**
- Expand: store new belief, no contradiction → clean expansion
- Revise: store contradicting belief → verify supersedes edge + confidence propagation
- Contract: remove belief → verify dependent confidence reduction
- Detect contradictions via semantic similarity
- Detect contradictions via explicit `:contradicts` edges
- Revision record created with correct fields
- Pluggable hook receives contradiction notification
- Chain revision: A superseded by B superseded by C → verify provenance chain

**Category 3: Conflict-Aware Consolidation (8 scenarios)**
- High-similarity, divergent-confidence pair tagged during retrieval
- Conflict resolved by temporal heuristic (newer wins)
- Conflict resolved by evidence heuristic (more outcomes wins)
- Unresolved conflict creates `:contradicts` edges
- Unresolved conflict escalates to attention
- Stage 4.5 runs between strengthen and merge
- Conflict resolution doesn't interfere with Stage 5 merge (0.95 threshold)
- Multiple conflicts in one consolidation cycle

**Category 4: Two-Phase Retrieval (8 scenarios)**
- Q-value updates from successful outcome increase ranking
- Q-value updates from failed outcome decrease ranking
- No Q-value effect when q_update_count == 0 for all candidates
- Blended scoring with alpha=0.3
- Q-value decay is half confidence decay rate
- High-confidence but low-utility node ranks below high-utility node
- Retrieve same query before and after outcome learning → verify rank change
- nDCG improvement after 5 outcome cycles

**Category 5: Intentional Forgetting (8 scenarios)**
- Soft forget excludes from retrieval
- Hard forget removes node + edges
- Cascade forget propagates to orphaned dependents
- GDPR erase leaves no trace
- Budget-aware hybrid pruning respects max_nodes
- Priority scoring favors high-confidence, recent, connected nodes
- Forgotten nodes don't appear in topology analysis
- Memory pressure triggers forgetting in attention survey

### Implementation
New file: `graphonomous/lib/mix/tasks/benchmark/capability_spec.ex`

Follow the pattern in `lib/mix/tasks/benchmark/longmemeval.ex`. Each category is a module with `run/1` that returns `{passed, failed, skipped}`. Results written to `benchmark_results/capability_spec.json`.

Run: `mix benchmark.capability_spec`

### Capability 7: LongMemEval Re-benchmark (1 day)

After two-phase retrieval is implemented:
```bash
source .envrc && mix benchmark.longmemeval --split oracle --neural --limit 100
```

Compare SHR against baseline 90.4%. The Q-value utility scoring should improve retrieval quality on "knowledge updates" questions (where outdated knowledge has low Q-values from failed outcomes).

---

## Files to Read Before Coding

1. `graphonomous/lib/graphonomous/retriever.ex` — current scoring pipeline (add Phase 2)
2. `graphonomous/lib/graphonomous/learner.ex` — `update_node_from_outcome` (add Q-value update)
3. `graphonomous/lib/graphonomous/consolidator.ex` — Stage 2 prune logic (replace with Forgetter)
4. `graphonomous/lib/graphonomous/store.ex` — SQL queries, migration system
5. `graphonomous/lib/graphonomous/attention.ex` — survey pipeline (add memory pressure)
6. `graphonomous/lib/mix/tasks/benchmark/longmemeval.ex` — benchmark pattern to follow
7. `graphonomous/lib/graphonomous/mcp/server.ex` — MCP tool registration

## Verification Checklist

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` — all existing + P0 + P1 tests pass
- [ ] `mix benchmark.capability_spec` — 40/40 scenarios pass
- [ ] `mix benchmark.longmemeval --split oracle --neural --limit 100` — SHR >= 90.4%
- [ ] Q-value field populated after outcome learning
- [ ] Forgetting respects budget (node count <= max_nodes after policy run)
- [ ] GDPR erase leaves no trace (node, edges, embeddings all removed)
- [ ] Update goal progress to 0.5
