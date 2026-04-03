# Graphonomous v0.3 Continual Learning Implementation Prompt

## Session Goal

Implement P0 continual learning capabilities for Graphonomous: **kappa activation**, **belief revision substrate**, and **conflict-aware consolidation**. These three capabilities together solve the kappa=0 problem — the single biggest gap between Graphonomous's competitive thesis and its measured behavior.

## Context

- **Active Graphonomous goal:** `goal_ae39998e19f363c1519679b15d24744d` — "Graphonomous v0.3 Continual Learning Capabilities"
- **Plan file:** `/home/travis/.claude/plans/smooth-tumbling-sunbeam.md`
- **Current state:** v0.2.0, 240 tests passing, 22 MCP tools, kappa=0 across all 150 benchmark questions

## The kappa=0 Root Cause

The Retriever's `analyze_topology/1` only builds adjacency from edges between the ~20 retrieved nodes. EdgeExtractor creates unidirectional edges via regex (A imports B -> edge A->B). Cycles require bidirectional edges, which almost never form because:

1. Regex extraction misses conceptual back-references
2. No mechanism creates `:contradicts`/`:supersedes` edges automatically
3. Topology window is too narrow (only retrieved nodes, not their neighbors)

## What to Build (P0, ~10 days)

### 1. Kappa Activation (3 days)

**File: `graphonomous/lib/graphonomous/edge_extractor.ex`**
- Add `extract_semantic_backrefs/1` — after forward edge creation, compute cosine similarity between target and source embeddings. If > 0.75, create reverse `:supports` edge.
- This requires access to embeddings during extraction (currently regex-only).

**File: `graphonomous/lib/graphonomous/retriever.ex`**
- Modify `analyze_topology/1` to expand the topology window: include 1-hop neighbors of retrieved nodes, not just the retrieved nodes themselves.
- Current code calls `Store.list_edges_between(node_ids)` where `node_ids` is ~20 retrieved results. Change to:
  1. Get edges for each retrieved node (`Store.list_edges_for_node/1`)
  2. Collect all neighbor IDs
  3. Build adjacency over `retrieved_ids ++ neighbor_ids`
  4. Run Tarjan SCC + kappa on the expanded set

### 2. Belief Revision Substrate (4 days)

**Schema migration (new file in `graphonomous/lib/graphonomous/store.ex` or migration system):**
```sql
ALTER TABLE nodes ADD COLUMN revision_id TEXT;
ALTER TABLE nodes ADD COLUMN superseded_by TEXT;

CREATE TABLE IF NOT EXISTS revisions (
  id TEXT PRIMARY KEY,
  operation TEXT NOT NULL,  -- 'expansion' | 'revision' | 'contraction'
  trigger_node_id TEXT NOT NULL,
  affected_node_ids TEXT NOT NULL DEFAULT '[]',
  rationale TEXT,
  agent_id TEXT,
  created_at TEXT NOT NULL
);
```

**New file: `graphonomous/lib/graphonomous/belief_revision.ex`**
```elixir
defmodule Graphonomous.BeliefRevision do
  @moduledoc """
  AGM-rational belief revision operations with provenance tracking.
  Provides storage/provenance substrate — reasoning about which belief wins
  is delegated to external systems (Deliberatic, BendScript) via pluggable hooks.
  """

  # Core operations
  def expand(content, opts \\ [])        # Add belief, check contradictions first
  def revise(node_id, new_content, opts) # Supersede old belief, propagate confidence
  def contract(node_id, opts)            # Remove belief, retract dependents

  # Detection
  def detect_contradictions(node_id_or_content) # Find contradicting nodes
  def propagate_retraction(node_id, opts)       # Walk derived_from/supports, reduce confidence

  # Hooks
  def register_resolution_hook(module)   # External resolver (Deliberatic, BendScript)
  def resolve_contradiction(node_a, node_b) # Call registered hook or use default heuristic
end
```

**New MCP tools (register in `graphonomous/lib/graphonomous/mcp/server.ex`):**
- `belief_revise` — `{node_id, new_content, rationale, operation: "expand"|"revise"|"contract"}`
- `belief_contradictions` — `{node_id}` or `{content}` — returns contradicting nodes with similarity scores

**New edge type:** Add `:superseded_by` to valid edge types in `Graph` module.

**Integration with Learner:** In `learn_from_interaction`, after `store_node`, call `detect_contradictions`. If found, create `:contradicts` edges (these form 2-node SCCs = kappa=1).

**Integration with Consolidator Stage 5:** Before merging (cosine > 0.95), check if pair has `:contradicts` edges. If so, route to `BeliefRevision.resolve_contradiction/2` instead of merging.

### 3. Conflict-Aware Consolidation (3 days)

**File: `graphonomous/lib/graphonomous/retriever.ex`**
- Add `detect_and_tag_conflicts/1` after ranking, before return
- Tag pairs where: semantic similarity > 0.8 AND confidence divergence > 0.3
- Store conflict tags in node metadata (or a lightweight ETS cache)

**File: `graphonomous/lib/graphonomous/consolidator.ex`**
- Add Stage 4.5 between "strengthen coactivated" and "merge similar"
- `stage_resolve_conflicts/0`:
  1. Find all conflict-tagged pairs
  2. For each pair, try resolution strategies in order:
     a. Temporal (newer supersedes older)
     b. Evidence (more outcome references wins)
     c. External hook (registered resolver)
     d. Escalate to attention (create attention item)
  3. Winning resolution: call `BeliefRevision.revise/3`
  4. Unresolved: create `:contradicts` edges (activates kappa)

**Key insight:** Unresolved conflicts get `:contradicts` edges = guaranteed kappa>=1. This is the PRIMARY kappa activation mechanism for organic (non-synthetic) knowledge.

## Files to Read Before Coding

Read these files FIRST to understand the current implementation:

1. `graphonomous/lib/graphonomous/retriever.ex` — retrieval pipeline, `analyze_topology/1`, scoring
2. `graphonomous/lib/graphonomous/consolidator.ex` — 7-stage pipeline, decay rates, prune logic
3. `graphonomous/lib/graphonomous/learner.ex` — `learn_from_interaction`, `learn_from_outcome`, confidence updates
4. `graphonomous/lib/graphonomous/edge_extractor.ex` — regex extraction, edge type assignment
5. `graphonomous/lib/graphonomous/topology.ex` — `tarjan_scc/1`, `compute_kappa/2`, `analyze/1`
6. `graphonomous/lib/graphonomous/store.ex` — SQLite schema, migrations, CRUD operations
7. `graphonomous/lib/graphonomous/graph.ex` — edge types, graph operations
8. `graphonomous/lib/graphonomous/mcp/server.ex` — MCP tool registration pattern
9. `graphonomous/lib/graphonomous/types/node.ex` — Node struct definition
10. `graphonomous/lib/graphonomous/types/edge.ex` — Edge struct definition

## Coding Conventions

- Use `mix format` style
- All new modules need `@moduledoc` and `@doc` on public functions
- Add to existing test files or create new ones in `test/graphonomous/`
- New MCP tools follow the pattern in existing tool modules under `lib/graphonomous/mcp/tools/`
- Schema changes go through the Store migration system
- Emit telemetry events for new operations (follow existing `[:graphonomous, :*, :*]` pattern)

## Verification Checklist

After implementing P0:

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` — all 240+ existing tests pass (regression)
- [ ] New tests for BeliefRevision module pass
- [ ] New tests for conflict-aware consolidation pass
- [ ] New tests for expanded topology window pass
- [ ] Run `mix benchmark.run` — verify kappa>0 appears in at least some queries
- [ ] Manual test: store two contradicting facts via MCP, verify `:contradicts` edges form, verify kappa=1 on retrieval involving both

## Research References (for context, not implementation)

- Kumiho (arxiv 2603.17244) — AGM maps to property graph operations (validates our approach)
- SleepGate (arxiv 2603.14517) — separate conflict detection from resolution (our Stage 4.5 design)
- MemRL (arxiv 2601.03192) — two-phase retrieval (P1, not this session)
- MAGMA (arxiv 2601.03236) — multi-view adjacency indexes (future optimization for kappa)
- UtU (arxiv 2402.10695) — constant-time graph unlearning (P1 forgetting, not this session)

## Success Criteria for This Session

1. **kappa > 0 activates** on at least one real retrieval query (not synthetic)
2. **Belief revision** creates revision records and supersedes edges
3. **Conflict detection** tags conflicts during retrieval
4. **Conflict resolution** runs during consolidation Stage 4.5
5. **All existing tests pass**
