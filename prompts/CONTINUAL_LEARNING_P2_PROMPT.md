# Graphonomous v0.3 — P2 Implementation Prompt (Week 5+)

## Prerequisites

P0 and P1 must be complete before starting P2. Verify:
- [ ] `mix test` passes (all existing + P0 + P1 tests)
- [ ] `mix benchmark.capability_spec` — 40/40 pass
- [ ] LongMemEval SHR >= 90.4% with two-phase retrieval
- [ ] kappa > 0 activates on real queries
- [ ] Forgetting respects memory budget
- [ ] Goal progress at 0.5

## Session Goal

Implement P2 capabilities: **scoped uncertainty propagation**, **procedural metadata + enhanced retrieval**, and **multi-agent schema prep**. These are lower-priority capabilities that serve future portfolio products (AgenTroMatic, FleetPrompt, GeoFleetic) while improving current Graphonomous quality.

## Active Goal

Retrieve and update: `goal_ae39998e19f363c1519679b15d24744d`

---

## Capability 8: Scoped Uncertainty Propagation (3 days)

### What it does
Adds `evidence_count` to nodes. For nodes with outcome/feedback signals (evidence_count > 0), computes Wilson score confidence intervals instead of point estimates. Propagates uncertainty through edges: nodes derived from uncertain parents inherit wider intervals. New `epistemic_frontier` query returns nodes where investigation would most reduce uncertainty.

### Why scoped (not universal)
Most nodes come from file ingestion — they're either current or stale, not "uncertain." Interval confidence only makes sense for nodes that have been tested against reality via `learn_from_outcome` or `learn_from_feedback`. This avoids the complexity of interval math on 27K+ ingested file nodes.

### Research basis
UQ position paper (arxiv 2505.22655) — point estimates conflate "I'm 70% sure" with "I have no idea." Wilson score intervals (used in Reddit's ranking algorithm) provide principled intervals from binary success/failure counts.

### Schema migration
```sql
ALTER TABLE nodes ADD COLUMN evidence_count INTEGER DEFAULT 0;
```

### New file: `graphonomous/lib/graphonomous/uncertainty.ex`
```elixir
defmodule Graphonomous.Uncertainty do
  @moduledoc """
  Uncertainty quantification for outcome-bearing nodes.
  Uses Wilson score intervals for confidence bounds.
  Only applies to nodes with evidence_count > 0.
  """

  @type interval :: {lower :: float(), upper :: float()}

  def interval(%{evidence_count: 0}), do: :no_evidence
  def interval(%{confidence: c, evidence_count: n}) do
    # Wilson score interval at 95% confidence (z = 1.96)
    z = 1.96
    phat = c
    denom = 1 + z * z / n
    center = (phat + z * z / (2 * n)) / denom
    spread = z * :math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n) / denom
    {max(0.0, center - spread), min(1.0, center + spread)}
  end

  def propagate(node_id)
  # Walk :derived_from and :supports edges outward.
  # For each child: if parent interval is wider than child's, widen child's.
  # Widening factor: child_width = max(child_width, parent_width * edge_weight)

  def frontier(opts \\ [])
  # Return nodes where: evidence_count > 0 AND interval width > min_gap
  # Sorted by information_gain (widest intervals with highest access_count first)
  # These are the nodes where one more outcome would most narrow uncertainty.

  def entropy(%{confidence: c, evidence_count: 0}), do: 1.0  # Maximum uncertainty
  def entropy(node) do
    {lo, hi} = interval(node)
    hi - lo  # Simple width as entropy proxy
  end

  def information_gain(node) do
    # Expected interval narrowing from one additional evidence point
    current = entropy(node)
    projected = interval(%{node | evidence_count: node.evidence_count + 1})
    case projected do
      :no_evidence -> 0.0
      {lo, hi} -> current - (hi - lo)
    end
  end
end
```

### New MCP tool
- `epistemic_frontier` — `{min_gap: float (default 0.3), limit: integer (default 10)}`
  Returns nodes with widest intervals, sorted by information gain.

### Integration points

**File: `graphonomous/lib/graphonomous/learner.ex`**
In `learn_from_outcome` and `learn_from_feedback`: increment `evidence_count` on causal nodes.

**File: `graphonomous/lib/graphonomous/coverage.ex`**
Replace `uncertainty_score` heuristic with `Uncertainty.entropy/1` averaged over retrieved nodes with evidence. For nodes without evidence, use the existing heuristic (they're file-ingested, not tested).

**File: `graphonomous/lib/graphonomous/attention.ex`**
Add frontier nodes to survey: high-information-gain nodes with wide intervals are candidates for "investigate further" attention items.

### Tests
- Node with confidence=0.7, evidence_count=1 → wide interval ~[0.35, 0.93]
- Same node after 10 successful outcomes → narrow interval ~[0.60, 0.80]
- Node with evidence_count=0 → returns `:no_evidence`
- Propagation: parent with wide interval → child inherits wider interval
- Frontier returns widest-interval nodes sorted by information gain
- Coverage uses entropy for evidence-bearing nodes, heuristic for others

---

## Capability 9: Procedural Metadata + Enhanced Retrieval (3 days)

### What it does
Adds structured metadata to procedural nodes (preconditions, postconditions, parameters, domain) without building a full skill composition engine. Enhances `retrieve_procedural` to match by preconditions AND semantic similarity. Makes procedures discoverable by what they need and what they produce.

### Why metadata-only (not full composition)
Agentelic and FleetPrompt (the primary consumers of skill composition) are spec-only. The main beneficiary today is Claude Code using Graphonomous MCP tools. Structured metadata + enhanced retrieval gives 80% of the value at 20% of the effort. Composition engine deferred until FleetPrompt ships.

### Research basis
Agent KB (TechRxiv 2025) shows 51-78% procedure reuse rates when procedures are well-indexed. Voyager's skill library pattern works because procedures are semantically searchable.

### Schema note
No migration needed — use existing `metadata` JSON field on nodes:
```json
{
  "skill": {
    "preconditions": ["has_git_repo", "has_test_suite"],
    "postconditions": ["tests_passing", "code_formatted"],
    "parameters": [{"name": "branch", "type": "string", "default": "main"}],
    "domain": "software_development",
    "success_rate": 0.85,
    "usage_count": 12
  }
}
```

### File: `graphonomous/lib/graphonomous/retriever.ex`
Enhance `retrieve_procedural` to support precondition matching:

```elixir
def retrieve_procedural(query, opts) do
  # Existing: semantic similarity search scoped to procedural nodes
  semantic_results = existing_procedural_retrieval(query, opts)

  # NEW: If opts[:preconditions] provided, boost nodes whose preconditions match
  case Keyword.get(opts, :preconditions) do
    nil -> semantic_results
    required_preconds ->
      semantic_results
      |> Enum.map(fn result ->
        node_preconds = get_in(result.metadata, ["skill", "preconditions"]) || []
        match_score = precondition_match_score(required_preconds, node_preconds)
        %{result | score: result.score * (1.0 + match_score)}
      end)
      |> Enum.sort_by(& &1.score, :desc)
  end
end

defp precondition_match_score(required, available) do
  return 0.0 if required == [] or available == []
  matched = Enum.count(required, &(&1 in available))
  matched / length(required)  # 0.0 to 1.0
end
```

### File: `graphonomous/lib/graphonomous/learner.ex`
When `learn_from_interaction` stores a procedural node, auto-extract skill metadata if the content contains structured indicators (e.g., "Prerequisites:", "Steps:", "Result:").

### File: `graphonomous/lib/graphonomous/consolidator.ex`
In Stage 7 (generate abstractions): when 3+ procedural nodes share similar postconditions (>60% overlap), note this in the generated abstraction's metadata as a composition candidate (but don't compose yet).

### Modify `retrieve_procedural` MCP tool
Add optional `preconditions` parameter:
```json
{
  "name": "retrieve_procedural",
  "parameters": {
    "query": "string",
    "preconditions": "JSON array of required precondition strings (optional)",
    "limit": "integer"
  }
}
```

### Tests
- Store procedural node with skill metadata → retrieve by precondition match
- Precondition boosting: node matching 3/3 preconditions ranks above node matching 1/3
- No preconditions provided → existing behavior unchanged
- Skill metadata survives consolidation
- Stage 7 identifies composition candidates but doesn't compose

---

## Capability 10: Multi-Agent Schema Prep (1 day)

### What it does
Adds `agent_id` to nodes and edges. This is schema-only — no behavioral changes. Prepares the data substrate for when AgenTroMatic, Delegatic, or FleetPrompt ship and need agent-scoped memory.

### Schema migration
```sql
ALTER TABLE nodes ADD COLUMN agent_id TEXT DEFAULT 'default';
ALTER TABLE edges ADD COLUMN agent_id TEXT DEFAULT 'default';
```

### File: `graphonomous/lib/graphonomous/types/node.ex`
Add `agent_id` to the Node struct with default `"default"`.

### File: `graphonomous/lib/graphonomous/types/edge.ex`
Add `agent_id` to the Edge struct with default `"default"`.

### File: `graphonomous/lib/graphonomous/store.ex`
- Include `agent_id` in INSERT statements
- Add `agent_id` to SELECT result mapping
- Add `list_nodes_by_agent(agent_id)` query (for future use)

### Tests
- Store node without agent_id → defaults to "default"
- Store node with agent_id → persists correctly
- Query by agent_id returns only that agent's nodes
- Existing behavior unchanged (all queries work with "default" agent_id)

---

## GraphMemBench Phase 2 (2 days)

Add 40 more scenarios (8 each) to `mix benchmark.capability_spec`:

**Category 6: Uncertainty Propagation (8 scenarios)**
- Wilson interval computation at various evidence counts
- Interval narrowing with more evidence
- Propagation through derived_from edges
- Frontier query returns widest intervals
- Information gain calculation
- Coverage integration uses entropy for evidence-bearing nodes
- No-evidence nodes excluded from interval computation
- Attention survey includes high-information-gain nodes

**Category 7: Procedural Retrieval (8 scenarios)**
- Precondition matching boosts relevant procedures
- Full precondition match scores higher than partial
- No preconditions → existing behavior
- Skill metadata persists through store/retrieve cycle
- Multiple procedures with overlapping postconditions
- Domain-scoped retrieval
- Procedure success_rate from outcome history
- Stage 7 composition candidate detection

**Category 8: Multi-Agent Prep (8 scenarios)**
- Node created with agent_id persists
- Edge created with agent_id persists
- Default agent_id is "default"
- Query by agent_id filters correctly
- Mixed agent_id nodes in same graph
- Graph stats include agent_id distribution
- Topology analysis works across agent boundaries
- Forgetting respects agent_id scope

**Category 9: Integration Scenarios (8 scenarios)**
- Full loop: store → contradict → revise → retrieve (kappa>0) → outcome → Q-value update → re-retrieve (improved ranking)
- Uncertainty + forgetting: forget low-confidence wide-interval nodes first
- Procedural + belief revision: procedure updated via revision, old version superseded
- Multi-turn conversation simulation (5 turns) with belief changes
- Memory pressure → forgetting → kappa recomputation (cycles may dissolve)
- Attention survey with goals + uncertainty + memory pressure + conflicts
- Consolidation full pipeline (all stages including 4.5) on 100-node graph
- End-to-end: 50-session simulation with evolving facts, measure learning curve

**Category 10: Stress (8 scenarios)**
- 1000-node forgetting under budget pressure
- 5000-edge topology analysis latency
- 100 concurrent conflict resolutions in one consolidation
- Q-value convergence after 50 outcome cycles
- Uncertainty propagation through 10-hop chain
- GraphMemBench full suite latency < 60 seconds
- Memory usage stays bounded during 500-node ingestion + forgetting cycle
- Consolidation throughput at 1000+ nodes

---

## Files to Read Before Coding

1. `graphonomous/lib/graphonomous/retriever.ex` — retrieval pipeline (add precondition matching)
2. `graphonomous/lib/graphonomous/learner.ex` — outcome learning (add evidence_count increment)
3. `graphonomous/lib/graphonomous/coverage.ex` — uncertainty scoring (replace with entropy)
4. `graphonomous/lib/graphonomous/attention.ex` — survey (add frontier nodes)
5. `graphonomous/lib/graphonomous/consolidator.ex` — Stage 7 (add composition detection)
6. `graphonomous/lib/graphonomous/store.ex` — SQL queries (add agent_id)
7. `graphonomous/lib/graphonomous/types/node.ex` — struct (add fields)
8. `graphonomous/lib/mix/tasks/benchmark/capability_spec.ex` — P1 benchmark (extend)

## Verification Checklist

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` — all existing + P0 + P1 + P2 tests pass
- [ ] `mix benchmark.capability_spec` — 80/80 scenarios pass (Phase 1 + Phase 2)
- [ ] Uncertainty intervals narrow with more evidence
- [ ] Procedural retrieval with preconditions returns better matches
- [ ] agent_id column populated correctly
- [ ] Update goal progress to 0.85
- [ ] Run consolidation to clean up session knowledge
