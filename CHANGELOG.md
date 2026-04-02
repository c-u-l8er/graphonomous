# Changelog

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
