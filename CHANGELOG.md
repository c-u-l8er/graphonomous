# Changelog

## [0.4.3] — 2026-04-21

### Added — OS-011 `&memory.episodic.store/replay`

- **`act(action: "store_trace")`** — persists a full OS-011 `InteractionTrace` (trace header + ordered edges) in episodic memory. Validates the payload against the canonical OS-011 §4 schema before writing.
- **`retrieve(action: "replay")`** — fetches a trace (by `trace_id` or by initial `state_hash` for procedural cluster lookup) and returns a replay manifest ready for a `&body.*` provider to execute. Destructive traces are flagged with `re_authorization_required: true` per OS-011 §4.4.
- **New types:** `Graphonomous.Types.InteractionTrace` and nested `Edge` — validating parsers for both JSON strings and decoded maps.
- **New tables:** `interaction_traces` + `trace_edges` (migration `2026_04_21_interaction_traces_os011`), indexed on `body_subtype`, `initial_state_hash`, `started_at`, and `trace_edges.state_before` for procedural clustering lookups.
- **19 new tests** covering schema validation, Store CRUD, machine routing, destructive-action flagging, and state-hash lookups. Total: **573 tests, 0 failures** (was 554).

### Impact

- Unblocks OS-011 conformance tests 7 (`trace_edge_complete`), 9–10 (replay state-divergence), and 11 (re-authorization) for downstream `&body.*` providers.
- Enables website/OS FSM emergence, skill crystallization (Graphonomous → FleetPrompt `SkillCandidate`), and cross-machine replay — the core of the dark-factory closed loop.
- Step 2 of the 7-step dark-factory loop (`Records InteractionTrace`) moves from ❌ to ✅ in `STACK_COMPLETION.md`.

## [0.3.3] — 2026-04-06

### Added

- **Embedder upgrade**: Switched from all-MiniLM-L6-v2 (384D) to nomic-embed-text-v2-moe (768D, 500M params) — improved semantic recall across all retrieval paths
- **MCP tool: `trace_evidence_path`** — weighted Dijkstra / Yen's K-shortest evidence paths with time-decay edge weighting and bidirectional search
- **Graph algorithms library** (6 algorithms, 72 new tests):
  - Dijkstra weighted shortest path (`Graphonomous.Graph.Algorithms.Dijkstra`)
  - DAG detection + topological sort (`Graphonomous.Graph.Algorithms.DAG`)
  - Bipartite matching: Hopcroft-Karp maximum + Hungarian optimal assignment (`Graphonomous.Graph.Algorithms.Matching`)
  - Louvain community detection with modularity scoring (`Graphonomous.Graph.Algorithms.Louvain`)
  - Incremental SCC maintenance (`Graphonomous.Graph.Algorithms.IncrementalSCC`)
  - Triangle counting with clustering coefficient (`Graphonomous.Graph.Algorithms.TriangleCounting`)
- **GraphMemBench v2**: κ-sensitive synthetic benchmark with 8 tiers (T1–T6 κ-topology, T7–T8 graph algorithms), difficulty knobs, and mixed-κ scenarios
- **LongMemEval full evaluation** (ICLR 2025, 500 questions, oracle split):
  - 92.6% QA proxy accuracy, 98.7% session hit rate, 1.4s mean latency
  - Topology ablation: ON = 92.6%/98.7% SHR vs OFF = 92.3%/97.9% SHR (+0.3pp QA, +0.8pp SHR)
  - Abstention accuracy: 96.7% (29/30 correct) via learned ANN-statistics threshold
- **LMStudio judge backend** for automated LongMemEval scoring
- **PPR experiment**: Personalized PageRank tested at w=0.18 and w=0.10; net negative on LongMemEval, flag-gated off (`enable_ppr`)
- **455 tests** (up from 309), 0 failures

### Changed

- MCP tool count: 28 → 29 (+ `trace_evidence_path`)
- Embedder dimensionality: 384D → 768D (retrieval, consolidation, and all similarity operations)
- Retriever: added `skip_topology` option for ablation testing; tuned SCC limit
- LongMemEval retrieval fixes: session-aggregate ranking boost, relative-date parser, preference query handling
- Graph algorithms attributed to v0.3.2 in README were actually shipped in v0.3.3

### Fixed

- Preference-type queries returning wrong sessions (query-type routing fix)
- Relative date references ("last Monday") not resolving correctly in temporal retrieval
- Session-aggregate ranking not boosting multi-turn conversation context

## [0.3.2] — 2026-04-03

### Added

- **MCP tool: `belief_revise`** — AGM-rational belief revision with three operations: expand (add + contradiction detection), revise (supersede with provenance tracking), contract (retract + propagate)
- **MCP tool: `belief_contradictions`** — detect contradicting nodes via embedding similarity (threshold 0.75) with content_preview and confidence
- **MCP tool: `forget_node`** — intentional forgetting in three modes: soft (hidden from retrieval, reversible), hard (UtU constant-time delete), cascade (hard + orphan propagation)
- **MCP tool: `forget_by_policy`** — budget-aware hybrid priority pruning; scores nodes by confidence × recency × access × connectivity; supports dry_run with candidate listing
- **MCP tool: `gdpr_erase`** — GDPR Article 17 compliant permanent deletion with audit record (node_type, reason, erased_at); no recovery
- **MCP tool: `epistemic_frontier`** — Wilson score confidence intervals at 95%; returns nodes sorted by information gain with interval_lower, interval_upper, width, evidence_count, access_count
- **Consolidation Stage 4.5**: contradiction detection during consolidation pipeline
- **Q-value tracking**: learn_from_outcome now updates q_values alongside confidence; retrieve_context uses q_values for outcome-weighted ranking
- **Multi-agent scoping**: agent_id metadata field for per-agent node attribution; shared graph with cross-agent discovery via graph expansion
- **Precondition matching**: typed-retrieval now boosts nodes matching query preconditions
- **17 interactive A/B demos** covering all 28 MCP tools (up from 11 demos)
- **309 tests** (up from 240), 120 GraphMemBench scenarios across 5 categories

### Changed

- MCP tool count: 22 → 28 (+ 5 resources unchanged)
- Consolidation pipeline: 7-stage → 8-stage (added contradiction detection)
- learn_from_outcome response now includes `new_q_value`, `old_q_value`, `q_update_count` in updates array
- Demo suite expanded: 6 new demos (belief-revision, intentional-forgetting, epistemic-frontier, causal-chains, qvalue-retrieval, multi-agent-memory), 2 existing demos updated

### Fixed

- store_node MCP timeout bug: GenServer.call defaulting to 5s while embedder takes up to 15s; added 30s timeout + exit catch in facade
- All demo payloads now match real MCP tool output structures (previously showed fabricated response fields)

## [0.2.0] — 2026-04-02

### Added

- **3 new node types**: `temporal` (time-indexed observations), `outcome` (empirical results), `goal` (durable intent)
- **11 new edge types**: `causes`, `resolves`, `related_to`, `part_of`, `follows`, `supersedes`, `depends_on`, `similar_to`, `temporal_before`, `temporal_after`, `co_occurs`
- **4 new node fields**: `causal_parent_ids`, `creation_source`, `timescale`, `decay_rate`
- **2 new edge fields**: `co_activation_count`, `decay_rate`
- **MCP tool: `delete_node`** — remove a node and its connected edges
- **MCP tool: `manage_edge`** — edge lifecycle management (list_all, list_for_node, update, delete)
- **Store APIs**: `list_all_edges/0`, `update_edge/2`, `delete_edge/1`
- **DDL migrations**: `2026_04_02_node_spec_fields`, `2026_04_02_edge_spec_fields` (ALTER TABLE for existing databases)
- **Consolidation stages 3-7**: prune_weak_edges, strengthen_coactivated, merge_similar_nodes, promote_timescale, generate_abstractions
- **Timescale system**: 4-tier decay (fast/medium/slow/glacial) with promotion based on access frequency
- **240 tests** (up from ~148), including direct MCP execute/2 tests for all 22 tools

### Changed

- Edge weight default: 0.5 → 0.3 (spec-aligned)
- Node `creation_source` defaults to `:inference` (was nil)
- Node `timescale` defaults to `:medium` (was nil)
- MCP tool count: 20 → 22 (+ 5 resources unchanged)
- Backward-compatible: legacy edge types (`causal`, `related`) still accepted

### Fixed

- `access_recency` field reference in `retrieve_episodic` and `recent_nodes` resource (was silently returning nil, now correctly uses `last_accessed_at`)
- `store_edge` MCP tool default weight hardcoded to 0.5 in 3 places (now 0.3)
- `Graph.normalize_edge_attrs` default weight was 0.5 (now 0.3)
- `Graphonomous.update_node/2` argument order bug — attrs were piped as first arg to `Graph.update_node/2` instead of node_id (caused `LearnFromFeedback` correction to crash)

## [0.1.12] — 2026-03-29

- Previous release (20 MCP tools, 3 node types, 5 edge types)
