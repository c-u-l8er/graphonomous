# Graphonomous FAQ

This page answers the most common questions about Graphonomous, its MCP interface, and operating model.

## What is Graphonomous?

Graphonomous is a continual-learning memory engine for AI agents. It stores knowledge as a graph, supports confidence-updating feedback loops, and exposes all capabilities through MCP tools/resources.

---

## Does Graphonomous retrain model weights?

No. Graphonomous does **not** retrain model weights.  
Learning happens in the memory graph by storing knowledge and updating confidence based on outcomes.

---

## What problem does it solve?

It gives agents durable, evolving memory and better decision quality over time by combining:

- semantic retrieval
- graph neighborhood expansion
- causal outcome feedback
- goal tracking
- topology-aware routing (`fast` vs `deliberate`)

---

## What are the core node types?

Use node types intentionally (6 types):

- `semantic` — facts, architecture, definitions
- `procedural` — workflows and how-to steps
- `episodic` — events and observations
- `temporal` — time-indexed observations, monitoring events
- `outcome` — empirical results of actions (grounding)
- `goal` — durable intent, objectives, targets

---

## What are the core edge types?

16 edge types (including 2 legacy aliases):

- `causes`, `resolves` — causal attribution
- `supports`, `contradicts` — evidential
- `related_to`, `similar_to` — topical affinity
- `part_of`, `follows`, `supersedes`, `depends_on` — structural
- `temporal_before`, `temporal_after`, `co_occurs` — temporal ordering
- `derived_from` — provenance
- Legacy aliases: `causal`, `related` (backward-compatible)

Default edge weight is 0.3. Edges should be added only when they improve retrieval quality or provenance clarity.

---

## How does retrieval work?

`retrieve_context` generally does:

1. similarity retrieval
2. graph expansion
3. ranking with confidence-aware scoring
4. topology analysis (SCC/κ-aware metadata)

Results include a `causal_context` array for later feedback via `learn_from_outcome`.

---

## What is `causal_context` and why does it matter?

`causal_context` is the list of node IDs that informed the current action.  
You should pass those IDs into `learn_from_outcome` so Graphonomous can update confidence on the actual causal nodes.

---

## What outcomes can I report?

`learn_from_outcome` supports:

- `success`
- `partial_success`
- `failure`
- `timeout`

Use `timeout` when an action did not complete in time (instead of incorrectly marking it as failure).

---

## How do goals work?

Graphonomous includes durable GoalGraph operations:

- create/list/get/update/delete goals
- transition status
- set progress
- link/unlink evidence nodes
- run epistemic review (`review_goal`)

Typical statuses include `proposed`, `active`, `blocked`, `completed`, and `abandoned`.

---

## What is coverage review?

`review_goal` evaluates whether current knowledge is sufficient to proceed.  
It returns decision-oriented signals such as:

- `act` (enough coverage)
- `learn` (need more context)
- `escalate` (insufficient/too risky)

---

## What does topology-aware routing mean?

Graphonomous analyzes retrieved subgraphs for cycles and complexity.  
If topology is simple, routing is `fast`. If cyclic complexity is higher, routing may indicate `deliberate`, signaling deeper reasoning is safer.

---

## What does consolidation do?

Consolidation is a 7-stage periodic memory maintenance pipeline:

1. Confidence decay
2. Prune weak nodes
3. Prune weak edges
4. Strengthen co-activated edges
5. Merge similar nodes
6. Promote timescale (fast → medium → slow → glacial)
7. Generate abstractions from episodic clusters

Use `run_consolidation` to trigger/inspect cycles manually when needed.

---

## Is Graphonomous usable from constrained machines?

Yes. It is designed for local operation with practical defaults and fallback modes.  
A common setup uses a local SQLite DB path and a lightweight embedder backend configuration for reliability.

---

## How do I run it quickly?

Typical options:

- run as MCP server over stdio
- run one-shot traversal/scan mode
- run watch mode for ongoing ingestion

See `quickstart` and `runtime` docs pages for exact commands and settings.

---

## How should agents use Graphonomous by default?

For non-trivial work, use this loop:

1. retrieve context
2. reason and act
3. store durable knowledge
4. report outcomes
5. maintain via consolidation

This is the recommended operating pattern for robust continual learning.

---

## Where can I find the full tool list and payload shapes?

See the MCP tools reference pages in this docs site, especially:

- retrieval and graph query
- node/edge storage
- outcome learning
- goal management and review
- topology analysis and deliberation
- attention and consolidation

---

## Is there a best-practice checklist?

Yes—short version:

- retrieve first for meaningful tasks
- store atomic nodes (avoid “kitchen-sink” nodes)
- keep confidence calibrated to evidence quality
- preserve causal IDs for feedback
- avoid fabricated provenance/signals
- review goals before consequential actions
- consolidate periodically

---

If you want a deeper operational playbook, start with the docs `quickstart`, then `architecture`, then the workflows and anti-patterns sections.