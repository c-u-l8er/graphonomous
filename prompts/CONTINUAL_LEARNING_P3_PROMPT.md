# Graphonomous v0.3 — P3 Implementation Prompt (Week 6+)

## Prerequisites

P0, P1, and P2 must be complete. Verify:
- [ ] `mix benchmark.capability_spec` — 80/80 pass
- [ ] LongMemEval SHR > 90.4%
- [ ] kappa > 0 on > 15% of benchmark queries
- [ ] All tests pass, goal progress at 0.85

## Session Goal

Implement P3 capabilities: **causal edge metadata prep** and **GraphMemBench Phase 3** (full 200-scenario suite with competitor adapter stubs). Also: finalize the goal, update the spec, update portfolio-review.html with new benchmark numbers.

## Active Goal

Retrieve and complete: `goal_ae39998e19f363c1519679b15d24744d`

---

## Capability 11: Causal Edge Metadata Prep (1 day)

### What it does
Extends `:causal` edge metadata to support future CausalEngine (deferred until TickTickClock/WebHost ship). No behavioral changes — just ensuring the data substrate can store causal strength, confounders, and intervention history.

### No schema migration needed
Uses existing edge `metadata` JSON field:
```json
{
  "causal_strength": 0.75,
  "confounders": ["node_id_1", "node_id_2"],
  "intervention_history": [
    {"at": "2026-04-10T...", "action": "do(X=0.8)", "result": "Y increased"}
  ]
}
```

### File: `graphonomous/lib/graphonomous/learner.ex`
When `learn_from_outcome` updates a causal edge, also compute and store `causal_strength`:
```elixir
causal_strength = case outcome.status do
  :success -> min(1.0, old_strength + 0.1)
  :partial_success -> old_strength  # No change
  :failure -> max(0.0, old_strength - 0.15)
  :timeout -> max(0.0, old_strength - 0.05)
end
```

### Tests
- Successful outcome strengthens causal edge
- Failed outcome weakens causal edge
- causal_strength persists in edge metadata
- confounders field accepted and stored

---

## GraphMemBench Phase 3: Full Suite + Competitor Stubs (3 days)

### Add remaining 40 scenarios (Categories 11-15, 8 each)

**Category 11: Causal Metadata (8 scenarios)**
- causal_strength updates on outcome success
- causal_strength decreases on failure
- confounders stored in edge metadata
- Causal subgraph extraction (all causal edges from a node)
- Multiple causal parents with different strengths
- causal_strength survives consolidation
- Zero-strength causal edges flagged for review
- Causal edge creation during learn_from_outcome

**Category 12: End-to-End Workflows (8 scenarios)**
- Cold start: empty graph → ingest 50 nodes → retrieve → verify quality
- Knowledge evolution: 10 sessions with changing facts → verify revision chain
- Skill accumulation: store 5 procedures → retrieve by precondition → verify transfer
- Goal lifecycle: create → learn → act → complete with full epistemic coverage
- Contradiction resolution: 3-way conflict → consolidation → single winner
- Memory lifecycle: ingest → learn → forget → verify no data leak
- Attention-driven exploration: survey → identify gaps → learn → verify improvement
- Full v0.3 pipeline: all capabilities active, 100-node graph, measure latency

**Category 13: Regression Guards (8 scenarios)**
- Existing retrieval quality preserved (F1 >= 0.415 baseline)
- Existing consolidation throughput preserved (>= 27M nodes/sec)
- Existing topology accuracy preserved (100% SCC detection)
- Existing learning loop integrity (4/4 outcome tests)
- Existing goal lifecycle integrity (4/4 lifecycle tests)
- kappa=0 fast path latency not degraded by expanded topology window
- Embedding quality unaffected by new columns
- MCP tool response format backward-compatible

**Category 14: Competitor Adapter Stubs (8 scenarios)**
- Baseline adapter: full-context LLM (stuff everything in prompt)
- Mem0 adapter stub: simple vector search + LLM
- Zep adapter stub: temporal graph search
- Hindsight adapter stub: 4-way parallel retrieval + RRF
- Adapter interface contract validation (all adapters implement same interface)
- Cross-adapter result format compatibility
- Adapter latency measurement framework
- Adapter accuracy measurement framework

**Category 15: GraphMemBench Reporting (8 scenarios)**
- JSON output format validation
- Learning curve plotting data (accuracy at 5 checkpoints)
- Category-level accuracy breakdown
- Latency percentile reporting (p50, p95, p99)
- Comparison table generation (Graphonomous vs baselines)
- Confidence calibration measurement
- kappa distribution histogram data
- Deliberation accuracy measurement (kappa>0 answers vs kappa=0 fast path)

### Competitor adapter interface
```elixir
defmodule GraphMemBench.Adapter do
  @callback ingest(session :: map()) :: :ok | {:error, term()}
  @callback retrieve(query :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  @callback forget(node_id :: String.t()) :: :ok | {:error, term()}
  @callback stats() :: map()
end
```

Graphonomous adapter wraps MCP tools. Competitor adapters are stubs that define the interface but return `{:error, :not_implemented}` — actual integration comes when/if competitors provide APIs.

---

## Finalization Tasks (1 day)

### Update Graphonomous spec
**File: `graphonomous/docs/spec/README.md`**
Add section for v0.3 capabilities:
- Belief revision with provenance chains
- Conflict-aware consolidation (Stage 4.5)
- Two-phase retrieval (semantic + utility)
- Budget-aware forgetting with GDPR hard delete
- Scoped uncertainty propagation
- Procedural metadata + precondition matching
- Multi-agent schema prep
- GraphMemBench (120 scenarios, 15 categories)

### Update OS-E001
**File: `opensentience.org/docs/spec/OS-E001-EMPIRICAL-EVALUATION.md`**
Add v0.3 benchmark results:
- kappa activation rate (target: >15%)
- Two-phase retrieval SHR delta
- GraphMemBench pass rate
- Forgetting precision/recall
- New tool count (22 → 28 MCP tools)

### Update portfolio review
**File: `AmpersandBoxDesign/site/portfolio-review.html`**
- Update KPI card with new SHR
- Update benchmark scorecard
- Add v0.3 capability summary
- Update competitive comparison with new capabilities
- Note: kappa activation is now validated, not just theoretical

### Complete goal
```
manage_goal operation=set_progress goal_id=goal_ae39998e19f363c1519679b15d24744d progress=1.0
manage_goal operation=transition_goal goal_id=goal_ae39998e19f363c1519679b15d24744d status=completed
```

### Store outcome
```
learn_from_outcome action_id=v03_continual_learning status=success
  causal_node_ids=[all knowledge nodes linked to goal]
  evidence="GraphMemBench 120/120, kappa activation >15%, SHR improved"
```

---

## Verification Checklist

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` — ALL tests pass
- [ ] `mix benchmark.capability_spec` — 120/120 scenarios pass (Phase 1 + 2 + 3)
- [ ] `mix benchmark.longmemeval --split oracle --neural --limit 100` — SHR > 90.4%
- [ ] kappa > 0 on > 15% of benchmark queries
- [ ] Spec updated with v0.3 capabilities
- [ ] OS-E001 updated with new benchmark data
- [ ] Portfolio review updated with new numbers
- [ ] Goal completed with outcome learning
- [ ] Consolidation run to clean session knowledge
- [ ] Version bumped to v0.3.0 in mix.exs + npm/package.json
