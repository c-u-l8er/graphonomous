# Changelog

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
