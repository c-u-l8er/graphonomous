# Skill 01 — Retrieve and Remember

> The foundational read/write loop: `retrieve_context`, `store_node`, `store_edge`

---

## Why This Matters

Graphonomous is your **persistent memory**. Without it, every conversation starts
from zero. The retrieve-and-remember loop is the single most important pattern:

1. **Before you answer** → retrieve what you already know
2. **After you learn something** → store it so future sessions benefit

If you do nothing else with Graphonomous, do this.

---

## retrieve_context — Search Memory Before Acting

### When to Call It

- **Start of every conversation** about a topic you may have seen before
- **Before answering a factual question** that might be in memory
- **Before making a decision** that prior outcomes could inform
- **When the user references prior work** ("remember when we…", "last time…")

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `query` | ✅ | string | — | Natural-language search query |
| `limit` | | number | 10 | Max results to return |
| `expansion_hops` | | number | 1 | How many edge-hops to expand from seed results |
| `neighbors_per_node` | | number | 5 | Max neighbors expanded per seed node |
| `min_score` | | number | — | Minimum relevance score threshold (0.0–1.0) |
| `node_type` | | string | — | Filter: `episodic`, `semantic`, `procedural`, `temporal`, `outcome`, or `goal` |

### Example Calls

**Basic retrieval — broad topic search:**
```json
{
  "query": "authentication architecture and JWT token handling"
}
```

**Narrow retrieval — only procedural knowledge, high quality:**
```json
{
  "query": "how to deploy the API to production",
  "node_type": "procedural",
  "min_score": 0.4,
  "limit": 5
}
```

**Deep retrieval — follow more graph connections:**
```json
{
  "query": "database migration system and schema versioning",
  "expansion_hops": 2,
  "neighbors_per_node": 8,
  "limit": 15
}
```

### Understanding the Response

The response includes several important fields:

```json
{
  "status": "ok",
  "query": "authentication architecture",
  "count": 3,
  "causal_context": ["node-abc-123", "node-def-456", "node-ghi-789"],
  "stats": { "returned": 3 },
  "topology": {
    "routing": "fast",
    "max_kappa": 0,
    "scc_count": 0,
    "sccs": [],
    "dag_nodes": []
  },
  "results": [
    {
      "node_id": "node-abc-123",
      "content": "The auth module uses RS256 JWT tokens with 15-minute expiry",
      "node_type": "semantic",
      "confidence": 0.85,
      "similarity": 0.82,
      "score": 0.78,
      "source": "src/auth/jwt.ts",
      "hops": 0,
      "via": null
    }
  ]
}
```

**Key fields to use:**

| Field | What It Means | What to Do With It |
|-------|--------------|-------------------|
| `causal_context` | Node IDs that informed this retrieval | **Save these.** Pass them to `learn_from_outcome` later as `causal_node_ids`. |
| `results[].confidence` | How trusted this knowledge is | Weight high-confidence results more in your reasoning. |
| `results[].similarity` | How semantically close to your query | High similarity = direct match. Low similarity = tangential neighbor. |
| `results[].hops` | 0 = direct match, 1+ = graph neighbor | Hop-0 results are most relevant. Hop-1+ provide context. |
| `topology.routing` | `"fast"` or `"deliberate"` | If `"deliberate"`, the knowledge region has circular dependencies (κ > 0). Consider using the `deliberate` tool. |

### Provenance-Aware Retrieval

Retrieval automatically handles **fact versioning and provenance**:

- **Superseded nodes** (nodes with a `superseded_by` edge) receive a 0.3x score penalty,
  pushing outdated information lower in results
- **Knowledge-update queries** ("what is my current X?", "how many do I have?") automatically
  widen the BM25 candidate pool by 2.5x to find entity-attribute matches across sessions
- **Preference queries** ("recommend me X", "suggest Y") also get wider candidate pools
  and profile-node boosting
- **Fact-prefix BM25 variants** are generated at query time to bridge vocabulary gaps
  between questions and stored facts (e.g., "How many bikes?" generates
  `"possession: bike bikes own"` matching ingested `bm25_facts`)

When storing knowledge that **updates or corrects** earlier information, create a
`superseded_by` edge from the old node to the new one. The retriever will then
automatically deprioritize the outdated version:

```json
{
  "source_id": "old-fact-node-id",
  "target_id": "new-fact-node-id",
  "edge_type": "superseded_by",
  "weight": 0.9,
  "metadata": "{\"source\": \"fact_versioning\"}"
}
```

### Tips for Good Queries

**Do:** Write natural-language questions or topic descriptions.
```
"How does the WebSocket reconnection logic handle token refresh?"
"Error handling patterns in the payment processing pipeline"
"What did we learn about the Redis caching layer last session?"
```

**Don't:** Use single keywords or overly broad terms.
```
"auth"          ← too vague, low signal
"everything"    ← meaningless
"code"          ← not useful
```

---

## store_node — Write Knowledge to Memory

### When to Call It

- You learned a **new fact** from reading code, docs, or user input
- You discovered a **procedure or workflow** worth remembering
- You want to **record what happened** in this session (episodic)
- The user **told you something important** they'll want recalled later
- You **resolved an ambiguity** and want to preserve the resolution

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `content` | ✅ | string | — | The knowledge to store (natural language) |
| `node_type` | | string | `"semantic"` | `episodic`, `semantic`, `procedural`, `temporal`, `outcome`, or `goal` |
| `confidence` | | number | 0.5 | How sure you are (0.0–1.0) |
| `source` | | string | — | Where this knowledge came from |
| `metadata` | | string (JSON) | `{}` | Extra structured data as a JSON object string |

### Choosing the Right Node Type

**Semantic** — facts, definitions, architecture, relationships:
```json
{
  "content": "The Graphonomous.Store module uses raw SQL via exqlite with parameterized prepared statements. It manages SQLite tables: nodes, edges, outcomes, goals, and schema_migrations. ETS hot cache is rebuilt from SQLite on startup.",
  "node_type": "semantic",
  "confidence": 0.95,
  "source": "graphonomous/lib/graphonomous/store.ex"
}
```

**Procedural** — how-to knowledge, workflows, recipes:
```json
{
  "content": "To run Graphonomous tests: cd graphonomous && mix deps.get && mix compile --warnings-as-errors && mix test. Expects 31 tests, 0 failures. Use MIX_ENV=test prefix for isolated test runs.",
  "node_type": "procedural",
  "confidence": 0.9,
  "source": "graphonomous/CLAUDE.md"
}
```

**Episodic** — events, observations, interaction records:
```json
{
  "content": "2025-02-20: User asked about deploying Graphonomous to a Raspberry Pi. Discussed --embedder-backend fallback for constrained devices. User confirmed they have a Pi 4 with 4GB RAM.",
  "node_type": "episodic",
  "confidence": 0.85,
  "source": "conversation",
  "metadata": "{\"topic\": \"edge-deployment\", \"user_device\": \"raspberry-pi-4-4gb\"}"
}
```

### Writing Good Content

**Be atomic.** One fact per node. Don't combine unrelated knowledge:

✅ Good — atomic and verifiable:
```
"The Consolidator GenServer runs on a configurable interval (default 5 minutes) and checks for 30 seconds of inactivity before triggering consolidation."
```

❌ Bad — too many unrelated facts crammed together:
```
"The system has a consolidator that runs periodically, also there's an embedder that uses MiniLM, and the store uses SQLite, and goals can be created."
```

**Include evidence.** Reference where you found it:

✅ Good:
```json
{
  "content": "Graphonomous.MCP.Server registers 12 tool components and 2 resource components (HealthSnapshot, GoalsSnapshot) via Anubis.Server.",
  "source": "graphonomous/lib/graphonomous/mcp/server.ex",
  "confidence": 0.95
}
```

❌ Bad — no source, vague confidence:
```json
{
  "content": "The server has some tools registered.",
  "confidence": 0.5
}
```

### Temporal Validity Metadata

When storing facts that may change over time, include temporal metadata:

```json
{
  "content": "User prefers Italian food for dinner.",
  "node_type": "episodic",
  "confidence": 0.85,
  "source": "conversation",
  "metadata": "{\"document_date\": \"2023-04-01\", \"role\": \"user\", \"valid_until\": null}"
}
```

Key temporal metadata fields:
- `document_date` — when this fact was stated
- `event_date` — when the described event occurred (may differ from document_date)
- `valid_until` — set when this fact is superseded by a newer version (null = still current)
- `superseded` — boolean flag set to `true` when a newer version exists

### Setting Confidence Correctly

| Evidence Quality | Confidence | Example |
|-----------------|------------|---------|
| Directly copied from source code | 0.90–1.0 | You read the exact line in the file |
| Read in official docs/README | 0.85–0.95 | The README says "31 tests, 0 failures" |
| Inferred from multiple consistent sources | 0.7–0.85 | Three files reference the same pattern |
| Told by user, plausible but unverified | 0.5–0.7 | User says "we use Redis for caching" |
| Single indirect source, may be outdated | 0.3–0.5 | Old comment in code, might be stale |
| Speculation / best guess | 0.1–0.3 | "I think this module probably does X" |

### Using Metadata

The `metadata` field accepts a JSON object string. Use it for structured data
that enriches the node beyond free-text content:

```json
{
  "content": "The MCP server exposes store_node, store_edge, retrieve_context, learn_from_outcome, query_graph, manage_goal, review_goal, run_consolidation, topology_analyze, deliberate, attention_survey, and attention_run_cycle as tools.",
  "node_type": "semantic",
  "confidence": 0.95,
  "source": "graphonomous/lib/graphonomous/mcp/server.ex",
  "metadata": "{\"tool_count\": 12, \"resource_count\": 2, \"category\": \"mcp-architecture\"}"
}
```

### Response

```json
{
  "status": "stored",
  "node_id": "a1b2c3d4-...",
  "node_type": "semantic",
  "confidence": 0.95
}
```

**Save the `node_id`!** You'll need it to:
- Create edges with `store_edge`
- Link nodes to goals with `manage_goal` → `link_nodes`
- Report outcomes with `learn_from_outcome` → `causal_node_ids`
- Inspect later with `query_graph` → `get_node`

---

## store_edge — Connect Knowledge Together

### When to Call It

- Two nodes are **causally related** (A causes/enables B)
- One node **supports or contradicts** another
- A new node was **derived from** an existing one
- Two concepts are **thematically related** and should be co-retrieved

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `source_id` | ✅ | string | — | Source node ID (edge goes FROM this node) |
| `target_id` | ✅ | string | — | Target node ID (edge goes TO this node) |
| `edge_type` | | string | `"causal"` | `causes`, `resolves`, `related_to`, `part_of`, `follows`, `contradicts`, `supersedes`, `depends_on`, `similar_to`, `supports`, `derived_from`, `temporal_before`, `temporal_after`, `co_occurs` (also accepts legacy: `causal`, `related`) |
| `weight` | | number | 0.3 | Edge strength / importance (0.0–1.0) |
| `metadata` | | string (JSON) | `{}` | Extra structured data |

### Choosing the Right Edge Type

**causal** — A leads to, causes, or enables B:
```json
{
  "source_id": "config-change-node-id",
  "target_id": "behavior-change-node-id",
  "edge_type": "causal",
  "weight": 0.8
}
```

**supports** — A provides evidence for B:
```json
{
  "source_id": "test-result-node-id",
  "target_id": "hypothesis-node-id",
  "edge_type": "supports",
  "weight": 0.7
}
```

**contradicts** — A conflicts with or disproves B:
```json
{
  "source_id": "actual-code-behavior-node-id",
  "target_id": "outdated-doc-claim-node-id",
  "edge_type": "contradicts",
  "weight": 0.9
}
```

**related** — A and B cover related topics:
```json
{
  "source_id": "auth-module-node-id",
  "target_id": "user-module-node-id",
  "edge_type": "related",
  "weight": 0.6
}
```

**derived_from** — A was extracted, summarized, or generated from B:
```json
{
  "source_id": "summary-node-id",
  "target_id": "source-document-node-id",
  "edge_type": "derived_from",
  "weight": 0.8
}
```

### Edge Weight Guidelines

| Weight | Meaning | When to Use |
|--------|---------|-------------|
| 0.8–1.0 | Strong, critical relationship | Direct causal link, strong evidence |
| 0.5–0.7 | Moderate relationship | Related but not critical |
| 0.2–0.4 | Weak relationship | Tangential connection, tentative |

### When NOT to Create Edges

- Don't create edges between every pair of nodes — the graph becomes noise
- Don't create edges for trivial "both are in the same file" connections
- Don't duplicate edges — check with `query_graph(operation: "get_edges")` first
- Do create edges when the relationship adds retrieval value (co-retrieval during `retrieve_context` uses edge traversal)

---

## The Full Read/Write Pattern in Practice

### Scenario: User asks "How does the consolidation system work?"

**Step 1 — Retrieve what you already know:**
```json
// retrieve_context
{
  "query": "consolidation system architecture and behavior",
  "limit": 8
}
```

Suppose you get 2 results at confidence 0.6. Useful but partial.

**Step 2 — Answer from retrieval + conversation context.**

You combine retrieved knowledge with what you know from training.

**Step 3 — Store the NEW knowledge you just synthesized:**

```json
// store_node (fact 1)
{
  "content": "Graphonomous.Consolidator runs a 7-stage pipeline during idle periods: decay_confidence → prune_weak_nodes → prune_weak_edges → strengthen_coactivated → merge_similar_nodes → promote_timescale → generate_abstractions. Idle is defined as 30 seconds of no activity.",
  "node_type": "semantic",
  "confidence": 0.9,
  "source": "graphonomous.com/project_spec/README.md"
}
```

```json
// store_node (fact 2)
{
  "content": "Consolidation supports four strategies: full (all stages), prune (remove low-confidence), merge (combine similar), strengthen (boost co-retrieved). Default interval is 5 minutes.",
  "node_type": "semantic",
  "confidence": 0.85,
  "source": "graphonomous.com/project_spec/README.md"
}
```

**Step 4 — Connect the new nodes to existing knowledge:**

```json
// store_edge (links new node to an existing architecture node)
{
  "source_id": "<new-consolidation-node-id>",
  "target_id": "<existing-architecture-overview-node-id>",
  "edge_type": "related",
  "weight": 0.7
}
```

**Step 5 — Save `causal_context` from retrieval for later learning.**

The `causal_context` array from step 1 (`["node-x", "node-y"]`) should be held
in working memory. If the user later confirms your answer was helpful or if you
verify the facts, feed that into `learn_from_outcome` (see Skill 02).

---

## Retrieval Expansion: How Hops Work

When `expansion_hops` > 0, Graphonomous doesn't just return the top similarity
matches — it **walks the graph outward** from each seed result:

```
expansion_hops: 0  →  Only direct similarity matches (fast, precise)
expansion_hops: 1  →  Direct matches + their immediate neighbors (default)
expansion_hops: 2  →  Direct matches + neighbors + neighbors-of-neighbors
```

Results from expansion have `hops: 1` or `hops: 2` and include a `via` field
showing which seed node they were reached through. This is how Graphonomous
surfaces **contextually related knowledge** that may not match the query text
directly but is graph-connected to things that do.

**When to increase hops:**
- Broad exploratory queries ("tell me everything about module X")
- When initial retrieval is sparse and you want more context

**When to keep hops low (0 or 1):**
- Precise factual lookups ("what port does service Y listen on?")
- When you want fast, focused results

---

## Topology Annotations on Retrieval

Every `retrieve_context` response includes a `topology` field:

```json
{
  "topology": {
    "routing": "fast",
    "max_kappa": 0,
    "scc_count": 0
  }
}
```

- **`routing: "fast"`** — The retrieved knowledge region is acyclic (a clean DAG). Proceed normally.
- **`routing: "deliberate"`** — The region contains circular dependencies (strongly connected components with κ > 0). The knowledge may be self-referential or contradictory. Consider using the `deliberate` tool to reason through it.
- **`max_kappa`** — The maximum cycle complexity. Higher κ = more entangled reasoning required.

You don't need to act on this in every interaction, but when `routing` is
`"deliberate"`, it's a signal that the knowledge has structural complexity worth
examining before drawing conclusions.

---

## Common Mistakes

| Mistake | Why It's Bad | Fix |
|---------|-------------|-----|
| Not retrieving before answering | You ignore knowledge from prior sessions | Always `retrieve_context` first |
| Storing huge multi-topic nodes | Hard to retrieve, hard to update confidence on individual facts | One atomic fact per node |
| Forgetting to set `source` | Future sessions can't trace where knowledge came from | Always include the file path or "conversation" |
| Using confidence 0.5 for everything | Defeats the purpose of confidence scoring | Calibrate based on evidence quality |
| Ignoring `causal_context` from retrieval | Can't close the learning loop later | Save it for `learn_from_outcome` |
| Creating edges between every node | Noise drowns out signal in graph traversal | Only edge when the relationship adds retrieval value |