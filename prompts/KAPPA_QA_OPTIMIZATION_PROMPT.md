# κ-Topology QA & SHR Optimization — Session Prompt

## Mission

Push Graphonomous LongMemEval from **73% QA / 90.4% SHR → 95%+ QA / 97%+ SHR** by leveraging the κ-invariant topology that no other memory system has, and fixing structural retrieval gaps.

## Current Baseline (as of 2026-04-02)

| Metric | Value | Gap to Target |
|--------|-------|---------------|
| Session Hit Rate (SHR) | 90.4% | +6.6pp to 97% |
| QA Proxy Score | 73.04% | +22pp to 95% |
| Multi-session SHR | **85.0%** | worst category |
| Multi-session recall | **60.5%** | only finding 60% of needed sessions |
| Temporal SHR | 95.0% | strong |
| Temporal QA proxy | 74.2% | gap despite good SHR |
| Abstention accuracy | **0.0%** | broken threshold |
| Retrieval: similarity_limit | 10 | too few for multi-session |
| Retrieval: final_limit | 20 | |
| Retrieval: expansion_hops | 1 | can't reach cross-session nodes |
| Retrieval: hop_decay | 0.85 (flat) | not topology-aware |
| Deliberation | single-pass decompose-focus-reconcile | no iterative retrieval |
| Temporal indexing | none | biggest gap vs Chronos |
| Session edges at ingestion | **none** | turns stored as isolated nodes |
| Cross-session entity edges | **none** | BFS can't bridge sessions |

## Competitive Landscape

| System | Score | Key Technique |
|--------|-------|---------------|
| Supermemory ASMR | ~99% | 8 parallel LLM agents, majority vote (very expensive) |
| Chronos | 95.6% | Event tuples + temporal index + iterative tool-calling |
| Mastra OM | 94.87% | Observer/Reflector compression, no retrieval needed |
| **Graphonomous** | **73% QA / 90.4% SHR** | Graph expansion + κ routing + deliberation |
| Emergence AI | 86% | Well-tuned RAG only |
| Hindsight (Vectorize) | 91.4% SHR | Current SHR SOTA for vector-based |

---

## Part A: SHR Optimization Goals (tag: `shr-optimization`)

The SHR gap is primarily driven by **multi-session questions (85% SHR, 60.5% session recall)**. Root cause: turns are ingested as isolated nodes with no intra-session or cross-session edges, so BFS expansion can't bridge sessions.

### SHR Phase 1 — Structural Fixes (Implement First)

#### S1. Session-Aware Edge Linking at Ingestion (CRITICAL, +3-5pp SHR)
**Goal ID:** `goal_d98cc02a3043693529a881b5d754dd0d`
**File:** `lib/mix/tasks/benchmark/longmemeval.ex` → `ingest_session/2`

Currently `ingest_session/2` stores each turn as an isolated node. Fix:
```elixir
defp ingest_session(session_id, turns) when is_list(turns) do
  node_ids =
    turns
    |> Enum.with_index()
    |> Enum.map(fn {turn, turn_idx} ->
      # ... existing store_node code ...
      # Return the node_id
      node_id
    end)

  # Add sequential edges between consecutive turns
  node_ids
  |> Enum.chunk_every(2, 1, :discard)
  |> Enum.each(fn [prev, curr] ->
    Graphonomous.store_edge(%{
      source_id: prev,
      target_id: curr,
      edge_type: :sequence,
      weight: 0.9,
      metadata: %{"session_id" => session_id}
    })
  end)
end
```

This alone should improve multi-session SHR because BFS expansion from one turn now reaches all turns in the same session.

#### S2. Cross-Session Entity Edges (HIGH, +3-4pp SHR)
**Goal ID:** `goal_676413bfeb49f07f502e5756e2c522ea`
**File:** `lib/mix/tasks/benchmark/longmemeval.ex` (new post-ingestion phase)

After all sessions are ingested, run a second pass:
- Extract named entities (people, places, preferences) from each turn node
- For turns in different sessions mentioning the same entity, create `:related` edges
- Weight by entity specificity (proper nouns > common nouns)
- This creates the cross-session graph bridges that BFS needs

Implementation approach:
- Simple: keyword/regex entity extraction (fast, no LLM)
- Better: use existing `learn_from_interaction` which already does edge extraction
- Add as "Phase 1.5" in the benchmark task between ingestion and evaluation

#### S3. Session-Level Summary Nodes (HIGH, +3-5pp SHR)
**Goal ID:** `goal_43634453e8fa66e51bda30b5365ed73c`
**File:** `lib/mix/tasks/benchmark/longmemeval.ex`

After ingesting all turns for a session, create one summary node:
```elixir
summary_content = turns
  |> Enum.map(fn t -> "[#{t["role"]}] #{String.slice(t["content"], 0, 200)}" end)
  |> Enum.join(" | ")

summary_id = Graphonomous.store_node(%{
  content: "Session summary: #{summary_content}",
  node_type: :semantic,
  confidence: 0.80,
  source: "longmemeval",
  metadata: %{"session_id" => session_id, "is_summary" => true, "turn_count" => length(turns)}
})

# Link summary to all turn nodes
Enum.each(turn_node_ids, fn nid ->
  Graphonomous.store_edge(%{source_id: summary_id, target_id: nid, edge_type: :contains, weight: 0.85})
end)
```

Creates LiCoMemory-style two-level hierarchy. Retrieval hits the summary, BFS expands to specific turns.

#### S4. Increase Retrieval Limits (HIGH, +2-3pp SHR)
**Goal ID:** `goal_30d212e4e8f40406bcf69499447cb8a9`
**File:** `lib/mix/tasks/benchmark/longmemeval.ex` → `evaluate_question/1`

Change retrieval call from:
```elixir
Graphonomous.retrieve_context(question_text, limit: 10, expansion_hops: 1, neighbors_per_node: 5)
```
To:
```elixir
Graphonomous.retrieve_context(question_text,
  similarity_limit: 20,
  final_limit: 40,
  expansion_hops: 1,
  neighbors_per_node: 5
)
```

For even better results, make limits adaptive:
```elixir
{sim_limit, final_limit} =
  if question_type in ["multi-session", "temporal-reasoning"],
    do: {25, 50},
    else: {10, 20}
```

### SHR Phase 2 — Retrieval Refinements

#### S5. Session Diversity Re-ranking (MEDIUM, +2-3pp SHR)
**Goal ID:** `goal_ea328d4b1ac438e428f8664ac7a9ded6`
**File:** `lib/graphonomous/retriever.ex`

Add session-aware diversity penalty alongside existing domain diversity:
```elixir
defp apply_session_diversity(entries) do
  session_counts = Enum.frequencies_by(entries, fn e ->
    get_in(e, [:metadata, "session_id"]) || "unknown"
  end)

  Enum.map(entries, fn entry ->
    sid = get_in(entry, [:metadata, "session_id"]) || "unknown"
    count = Map.get(session_counts, sid, 1)
    penalty = :math.pow(0.90, count - 1)
    %{entry | score: entry.score * penalty}
  end)
end
```

This spreads results across sessions, directly targeting the 60.5% multi-session recall.

#### S6. Multi-Hop Expansion for Multi-Session (MEDIUM, +2-3pp SHR)
**Goal ID:** `goal_a8dd4b2bcd66e6c583a18ba47564bb38`
**File:** `lib/graphonomous/retriever.ex`

After session-aware edges exist (S1, S2), increase expansion_hops to 2 for multi-session queries. One hop reaches same-session turns, two hops reaches cross-session entity bridges.

#### S7. Temporal Metadata Indexing (MEDIUM, +1-2pp SHR, +5-8pp temporal QA)
**Goal ID:** `goal_ef2897d27e15bd7a94ff2ec0983e8982`
**Files:** `lib/mix/tasks/benchmark/longmemeval.ex`, `lib/graphonomous/retriever.ex`

Store resolved timestamps in node metadata during ingestion. Add temporal range filtering to retrieval for temporal-reasoning questions.

#### S8. Abstention Calibration (MEDIUM, +2-3pp overall QA)
**Goal ID:** `goal_aac9a2f1d9b4e93f49c39a2ab88ac75c`
**File:** `lib/mix/tasks/benchmark/longmemeval.ex` → `evaluate_question/1`

Current abstention threshold (`avg_score < 0.15 or length(results) < 3`) gives 0% accuracy. Fix:
- Use confidence gap: `top_score - mean_score < 0.05` → likely no clear answer
- Use topology signal: no coherent SCC in results → likely abstention
- Raise score threshold to `avg_score < 0.25`
- All 6 abstention questions flipping = +3.6pp on overall QA proxy

---

## Part B: κ-Topology QA Optimization Goals (tag: `kappa-optimization`)

These goals specifically leverage the κ-invariant to improve answer quality on questions where retrieval already finds the right sessions.

### κ Phase 1 — High Impact, Implement First

#### K1. Iterative Retrieval in Deliberation (CRITICAL, +8-12pp QA)
**Goal ID:** `goal_ab2e008d496aa8ae6bef4d161e425c90`
**File:** `lib/graphonomous/deliberator.ex`

Current deliberation is single-pass: decompose → focus → reconcile. Change focus steps to issue **follow-up graph traversals** scoped to each SCC partition. The κ value already sets the iteration budget via `deliberation_budget/1`. Model after Chronos iterative tool-calling loops.

Implementation:
- In `build_focused_prompt/5`, after building the initial prompt, add a `retrieve_for_partition/3` call that queries Graph for nodes within the partition's node set
- In the main `deliberate_scc/6` loop, after each intermediate conclusion, check if confidence < threshold and issue another scoped retrieval
- Use `fault_line_edges` to decide which partition side needs more evidence
- Wire through `Retriever.retrieve/2` with a `scope_to_node_ids` option

Test: Run `mix benchmark.longmemeval --split oracle` before and after. QA proxy score should increase.

#### K2. κ-Guided Adaptive Retrieval Depth (HIGH, +3-5pp QA)
**Goal ID:** `goal_eae521c4f46b1a8e172f1474667e99f1`
**File:** `lib/graphonomous/retriever.ex`

After initial seed retrieval and topology analysis, adjust expansion depth:
```elixir
effective_hops = case topology.max_kappa do
  0 -> opts[:expansion_hops] || @default_expansion_hops  # keep default (1)
  k when k >= 1 -> min(k + 1, 3)                         # 2-3 hops for cyclic regions
end
```

This requires restructuring `do_retrieve/3` to:
1. Run similarity search (seeds)
2. Do a preliminary 1-hop expansion
3. Run topology analysis on the expanded set
4. If κ > 0, do additional hops up to `effective_hops`

#### K3. Temporal Contradiction Detection via κ (HIGH, +5-8pp QA)
**Goal ID:** `goal_b3613e912f86927f10a0f2a7f2470d6f`
**Files:** `lib/graphonomous/retriever.ex`, `lib/graphonomous/deliberator.ex`, edge types

Knowledge updates create contradictions: old fact ↔ new fact. When both exist with `contradicts` edges, they form a 2-node SCC with κ=1. The deliberator should detect these "temporal contradiction SCCs" and resolve to the temporally newer node.

Implementation:
- In `Deliberator.deliberate_scc/6`, detect 2-node SCCs with κ=1 where edges are `:contradicts`
- For these, skip full decompose-focus-reconcile — just compare `inserted_at` timestamps
- Boost the newer node's confidence, decay the older one
- Return conclusion favoring the newer fact
- Add `:supersedes` edge type if not present

### κ Phase 2 — Medium Impact

#### K4. κ-Modulated Hop Decay (MEDIUM, +2-3pp QA)
**Goal ID:** `goal_d5f5b195ed91d6fcc459179c1dc0480f`
**File:** `lib/graphonomous/retriever.ex`

Replace flat `@default_hop_decay 0.85` with κ-aware decay during BFS expansion:
```elixir
defp effective_hop_decay(base_decay, local_kappa) do
  base_decay + min(local_kappa * 0.02, 0.10)
end
```
- DAG regions (κ=0): use base decay (0.85)
- Cyclic regions: gentler decay (up to 0.95) because cycles mean distant nodes may circle back

Requires passing topology info into the BFS expansion step, which currently doesn't have it. May need a two-pass approach: expand → analyze topology → re-score with κ-aware decay.

#### K5. Fault-Line-Aware Retrieval Boosting (MEDIUM, +2-4pp QA)
**Goal ID:** `goal_3ce56e41b144cba14d4971ed0c02fc56`
**File:** `lib/graphonomous/retriever.ex`

After topology analysis, boost scores of nodes adjacent to `fault_line_edges`:
```elixir
defp apply_fault_line_boost(entries, topology) do
  fault_nodes = topology.sccs
    |> Enum.flat_map(& &1.fault_line_edges)
    |> Enum.flat_map(fn %{source: s, target: t} -> [s, t] end)
    |> MapSet.new()

  Enum.map(entries, fn entry ->
    if MapSet.member?(fault_nodes, entry.node_id),
      do: %{entry | score: entry.score * 1.15},
      else: entry
  end)
end
```

#### K6. κ-Bucketed Answer Strategies (MEDIUM, +3-5pp QA)
**Goal ID:** `goal_1d658ad0a747cebb8f44a31d74f32fa8`
**File:** `lib/graphonomous/retriever.ex` (or new module)

Route the entire answer strategy by κ profile:
- κ=0 everywhere → fast path, direct answer from top results
- κ=1 (contradiction pattern) → resolve contradictions first, then answer
- κ≥2 → full multi-pass deliberation

This builds on goals K1 and K3. Implement after those are done.

### κ Phase 3 — Polish

#### K7. SCC Confidence Propagation (LOW, +1-2pp QA)
**Goal ID:** `goal_7464c6c4b2d84f46c2c80e3e8044927c`

Propagate confidence through SCC edges during retrieval. High-confidence nodes boost low-confidence neighbors. Scale boost by 1/κ.

#### K8. Query-Time Edge Impact (LOW, +1-2pp QA)
**Goal ID:** `goal_d4334f3f76ffa2c9fd07b98f2aa82632`

Use `Topology.preview_edge_impact/3` at query time to detect semantically related but unlinked result nodes. Synthesize bridge reasoning in deliberation.

---

## Recommended Implementation Order

Do SHR structural fixes first (they unlock the κ optimizations), then κ QA work:

| Order | Goal | Tag | Expected Impact |
|-------|------|-----|-----------------|
| 1 | S1: Session-Aware Edge Linking | shr | +3-5pp SHR |
| 2 | S4: Increase Retrieval Limits | shr | +2-3pp SHR |
| 3 | S3: Session Summary Nodes | shr | +3-5pp SHR |
| 4 | S2: Cross-Session Entity Edges | shr | +3-4pp SHR |
| 5 | S5: Session Diversity Re-ranking | shr | +2-3pp SHR |
| 6 | S8: Abstention Calibration | shr | +2-3pp QA |
| 7 | K1: Iterative Retrieval in Deliberation | κ | +8-12pp QA |
| 8 | K2: κ-Adaptive Retrieval Depth | κ | +3-5pp QA |
| 9 | K3: Temporal Contradiction via κ | κ | +5-8pp QA |
| 10 | K4: κ-Modulated Hop Decay | κ | +2-3pp QA |
| 11 | K5: Fault-Line Boosting | κ | +2-4pp QA |
| 12 | S7: Temporal Metadata Indexing | shr | +5-8pp temporal QA |
| 13 | S6: Multi-Hop for Multi-Session | shr | +2-3pp SHR |
| 14 | K6: κ-Bucketed Answer Strategies | κ | +3-5pp QA |
| 15 | K7: SCC Confidence Propagation | κ | +1-2pp QA |
| 16 | K8: Query-Time Edge Impact | κ | +1-2pp QA |

**Benchmark after each change** to track incremental impact.

---

## Key Source Files

| File | Purpose |
|------|---------|
| `lib/graphonomous/retriever.ex` | Retrieval pipeline (similarity → BFS → rerank → topology → deliberate) |
| `lib/graphonomous/deliberator.ex` | κ-driven decompose-focus-reconcile |
| `lib/graphonomous/topology.ex` | Tarjan SCC, κ computation, fault lines, edge impact preview |
| `lib/graphonomous/graph.ex` | Node/edge CRUD, similarity search, BFS |
| `lib/graphonomous/store.ex` | SQLite persistence layer |
| `lib/graphonomous/types/edge.ex` | Edge type definitions (16 types) |
| `lib/mix/tasks/benchmark/longmemeval.ex` | LongMemEval benchmark task (ingestion + evaluation) |
| `lib/mix/tasks/benchmark/retrieval.ex` | Retrieval quality benchmark (graph vs flat) |
| `test/graphonomous/retriever_test.exs` | Retriever tests |
| `test/graphonomous/deliberator_test.exs` | Deliberator tests |
| `test/graphonomous/topology_test.exs` | Topology tests |

## Development Workflow

1. Read the spec: `docs/spec/README.md`
2. Read the current implementation of the target module
3. Write the change
4. Run `mix compile --warnings-as-errors && mix format --check-formatted`
5. Run `mix test` (full suite)
6. Run `mix benchmark.longmemeval --split oracle` to measure impact
7. Compare before/after SHR + QA proxy scores per category
8. Update the Graphonomous goal progress via `manage_goal` → `set_progress`
9. Update `opensentience.org/docs/spec/OS-E001-EMPIRICAL-EVALUATION.md` and `.html` with new numbers
10. Update `AmpersandBoxDesign/site/portfolio-review.html` competitive table

## Research References

- **Chronos** (95.6%): Event tuple decomposition, dual calendar index, iterative tool-calling. arxiv.org/abs/2603.16862
- **Mastra OM** (94.87%): Observer/Reflector agents, three-date temporal model. mastra.ai/research/observational-memory
- **Supermemory ASMR** (~99%): 8 parallel prompt variants, majority vote. blog.supermemory.ai
- **MAGMA**: Multi-graph (semantic/temporal/causal/entity), policy-guided traversal. arxiv.org/abs/2601.03236
- **LiCoMemory CogniGraph** (73.8%): Three-layer hierarchy, cross-layer hyperlinks. arxiv.org/abs/2511.01448
- **AssoMem**: Clue anchoring, MI-driven fusion. arxiv.org/abs/2510.10397
- **RECoT**: Decompose questions via triple extraction, hop-by-hop retrieval refinement

## Success Criteria

- SHR ≥ 97% on oracle split (100 questions)
- SHR ≥ 95% on full 500-question set
- Multi-session SHR ≥ 95% (up from 85%)
- Multi-session recall ≥ 85% (up from 60.5%)
- QA proxy score ≥ 90% on oracle split
- QA proxy score ≥ 85% on full 500-question set
- Abstention accuracy ≥ 80%
- All existing tests pass
- No regression in retrieval latency (< 5s per query at 27K nodes)
