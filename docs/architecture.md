# Graphonomous Architecture

Graphonomous is a continual-learning engine for AI agents, implemented in Elixir/OTP and exposed through an MCP server.  
Its design centers on a graph memory model, confidence-updating learning loops, and topology-aware reasoning.

---

## System Overview

At runtime, Graphonomous is composed of supervised services that each own a distinct responsibility:

- **Store**: durable persistence and hot cache
- **Embedder**: embedding generation backend
- **Graph**: node/edge CRUD and similarity orchestration
- **Retriever**: context retrieval + neighborhood expansion + topology annotation
- **Learner**: outcome ingestion and confidence updates
- **GoalGraph**: durable goal lifecycle management
- **Coverage**: epistemic scoring (`act` / `learn` / `escalate`)
- **Attention**: proactive goal prioritization loop
- **Consolidator**: periodic memory maintenance
- **MCP Server**: tool/resource interface for external agents

---

## Runtime Topology (Conceptual)

```text
Agent / Client (MCP)
        |
        v
+-------------------------+
| Graphonomous MCP Server |
+-------------------------+
   |      |         |
   |      |         +--> Goal / Coverage / Attention
   |      |
   |      +-------------> Retriever / Deliberator / Topology
   |
   +---------------------> Graph <-> Store <-> SQLite + ETS
                                \
                                 +-> Embedder

Learner <------------------ Outcomes (causal feedback)
Consolidator -----------> Decay / prune / maintain cycles
```

---

## Core Data Model

Graphonomous uses a directed knowledge graph with confidence-bearing nodes and weighted typed edges.

### Node Types

- **semantic**: facts, architecture truths, definitions
- **procedural**: workflows and operating instructions
- **episodic**: observed events and session outcomes
- **temporal**: time-indexed observations, monitoring events
- **outcome**: empirical results of actions (grounding)
- **goal**: durable intent, objectives, targets

### Edge Types

Relationship types include:

- `causes`, `resolves` — causal attribution
- `supports`, `contradicts` — evidential
- `related_to`, `similar_to` — topical affinity
- `part_of`, `follows`, `supersedes`, `depends_on` — structural
- `temporal_before`, `temporal_after`, `co_occurs` — temporal ordering
- `derived_from` — provenance
- Legacy aliases: `causal`, `related` (backward-compatible)

Each edge carries a weight (`0.0..1.0`, default 0.3), optional `co_activation_count`, and `decay_rate`.

---

## Persistence Layer

`Store` provides:

- **SQLite durability** for nodes, edges, outcomes, and goals
- **ETS hot cache** for low-latency reads
- schema bootstrap and migration application on startup
- cache warm-up from durable state after boot

Design intent: keep memory local-first and lightweight while still durable across restarts.

---

## Retrieval Pipeline

`Retriever` executes a multi-step pipeline:

1. Semantic similarity search (seed candidates)
2. Graph neighborhood expansion (bounded hops)
3. Confidence-aware ranking
4. Topology analysis over the retrieved subgraph
5. Return context with:
   - ranked results
   - causal context IDs
   - topology routing hint (`fast` or `deliberate`)

This provides both relevant memory and structural signal for downstream reasoning.

---

## Topology and Deliberation

Graphonomous computes SCC/topology properties and a κ-style complexity signal to identify cyclic reasoning regions.

- **`fast` routing**: low cycle complexity, proceed with normal retrieval flow
- **`deliberate` routing**: cyclic/entangled subgraph, invoke deeper structured deliberation

`Deliberator` can decompose cyclic regions, analyze fault-line edges, reconcile conclusions, and optionally write conclusions back into the graph.

---

## Learning Loop

`Learner` closes the causal feedback loop:

1. Persist action outcome
2. Update confidence on causal source nodes

Status signals include:

- `success`
- `partial_success`
- `failure`
- `timeout`

Confidence updates are blended with a learning-rate rule, so the graph continuously calibrates itself over real outcomes instead of static assumptions.

---

## Goal and Epistemic Control Plane

### GoalGraph

Durable multi-step intent with lifecycle states such as:

- `proposed`
- `active`
- `blocked`
- `completed`
- `abandoned`

Goals can link to supporting node IDs, track progress, and persist across sessions.

### Coverage

Before high-impact actions, Graphonomous can score epistemic readiness:

- `coverage_score`
- `uncertainty_score`
- `risk_score`

Decision output:

- **act**
- **learn**
- **escalate**

### Attention

Attention continuously ranks work across goals using urgency, coverage gaps, and topology signals; it supports `observe`, `advise`, and `act` autonomy levels.

---

## Consolidation

`Consolidator` runs periodic maintenance to protect graph quality over time:

1. Confidence decay
2. Prune weak nodes
3. Prune weak edges
4. Strengthen co-activated edges
5. Merge similar nodes
6. Promote timescale (fast → medium → slow → glacial)
7. Generate abstractions from episodic clusters

This prevents unbounded memory drift and keeps retrieval quality stable.

---

## MCP Surface

Graphonomous is MCP-first, exposing tools/resources for:

- storing memory
- querying/retrieving context
- reporting outcomes
- managing goals
- reviewing coverage
- running consolidation
- analyzing topology and running deliberation
- surveying/running attention cycles

This makes Graphonomous interoperable with MCP-capable assistants, editors, and agent runtimes.

---

## Architectural Properties

- **Modular**: clear boundaries between storage, retrieval, learning, and orchestration
- **Causal**: outcome feedback updates the exact nodes used for decisions
- **Topology-aware**: can detect when simple retrieval is insufficient
- **Durable**: goals and memory survive process and session boundaries
- **Operationally practical**: local DB + supervised services + MCP transport

---

## Practical Mental Model

You can think of Graphonomous as:

1. a **memory graph** (`Store` + `Graph`),
2. a **reasoning front-end** (`Retriever` + `Topology` + `Deliberator`),
3. a **learning backend** (`Learner` + `Consolidator`),
4. and a **control plane** (`GoalGraph` + `Coverage` + `Attention`),
5. all exposed through an **MCP API**.

That composition is what enables continual learning without retraining base model weights.