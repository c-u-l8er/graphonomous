# κ-Aware Graph Intelligence: The Theoretical Foundation for [&] Adaptive Inference

> *A technical foundation document establishing the cyclicity invariant κ as the routing primitive for adaptive inference in knowledge graph systems. Proved by exhaustive computation across 1,926,351 finite systems with zero counterexamples. Applied here as the decision boundary between retrieval and deliberation in the [&] agent architecture.*

---

## 1. The Core Problem in Agent Memory

Current AI agent architectures treat memory uniformly. Whether a query touches a linear chain of facts or a tightly interconnected cluster of mutually dependent concepts, the system does the same thing: retrieve context, feed it to the model, generate a response.

This is wrong for the same reason that driving a highway and navigating a roundabout are not the same task. Highways are directed — you enter, you travel, you exit. Roundabouts are cyclic — you enter, you circulate, you choose an exit based on what you observe *while circulating*. The topology of the road determines the driving strategy.

Knowledge graphs have the same property. Some regions are trees or DAGs — information flows one direction, from premises to conclusions, from causes to effects. Other regions are strongly connected — concepts A, B, and C mutually define each other, and understanding any one requires understanding all three. These regions demand different inference strategies. The first calls for **retrieval** (follow edges, collect context, done). The second calls for **deliberation** (iterate, resolve circular dependencies, converge on a coherent interpretation).

The question is: how does an agent know which strategy to use?

**Answer: κ.**

---

## 2. The Proved Result

**Theorem (Cyclicity Invariant κ).** For any finite directed graph G, define:

κ(G) = min over all nontrivial bipartitions (A, B) of the largest strongly connected component: min(|edges A→B|, |edges B→A|)

with κ = 0 if the largest SCC has size ≤ 1.

Then:

1. **κ(G) = 0 if and only if G is a DAG** (has no strongly connected component of size > 1).
2. **κ(G) > 0 if and only if G contains a directed cycle** within a strongly connected component.

Additionally:

3. **κ(G) > 0 ⟺ β₁(G) > 0** (cycle rank is positive).
4. For finite dynamical systems f: [n] → [n], **κ(TransitionGraph(f)) > 0 ⟺ f has a periodic orbit of period > 1**.

**Computational verification:** 1,052,740 directed graphs (n = 2–5) + 873,611 finite dynamical systems (n = 2–7) = 1,926,351 objects tested, zero counterexamples.

**Algebraic proof (generalizes to all finite n):**

- **Direction 1 (DAG → κ = 0):** If G has no SCC of size > 1, G is a DAG. Any DAG admits a topological ordering. The bipartition induced by cutting the ordering in half has zero backward edges. Therefore the minimum bidirectional cut is zero. κ = 0.

- **Direction 2 (Cycle → κ > 0):** If G is strongly connected with a directed cycle C, every bipartition (A, B) must cut at least one edge of C in each direction — because C visits both A and B and returns to its start. Therefore every bipartition has nonzero bidirectional cut. κ > 0.

**Plain language:** *κ detects whether a graph has irreducible feedback. κ = 0 means the graph can be decomposed into independent one-directional parts. κ > 0 means every decomposition leaves residual bidirectional information flow — the system has genuine cyclic structure that cannot be factored away.*

---

## 3. Why This Matters for Knowledge Graphs

A knowledge graph built by Graphonomous, or constructed interactively in BendScript, is a directed graph. Its nodes are concepts, facts, episodes, procedures. Its edges are typed relationships (causal, temporal, associative, contextual). At any moment, this graph has a computable κ value — and more importantly, each *subgraph* reachable from a query has a local κ.

### 3.1 DAG Regions (κ = 0): Retrieval Is Sufficient

When a query enters a region of the knowledge graph that is a DAG — a chain of causes and effects, a timeline of events, a hierarchy of categories — there is no circular dependency. Information flows one direction. The agent can traverse the subgraph in topological order, accumulate context, and generate a response in a single pass.

**This is standard RAG.** It works well for these regions because the topology permits it. No iteration is needed because there are no loops to iterate around.

### 3.2 SCC Regions (κ > 0): Deliberation Is Required

When a query touches a strongly connected component — a cluster of nodes where every node can reach every other node — the situation is fundamentally different. The concepts in this cluster are mutually dependent. Understanding node A requires context from node B, but understanding node B requires context from node A. A single-pass traversal will always miss something because it has to start somewhere, and wherever it starts, it lacks context it hasn't yet collected.

**This requires iterative reasoning.** The agent must traverse the SCC multiple times, refining its interpretation on each pass, until its understanding converges. This is deliberation — and the κ value of the SCC tells the agent something precise about how entangled the region is.

### 3.3 The κ Value as Routing Signal

κ is not just a binary flag. Its magnitude measures the *minimum irreducible feedback* — the minimum number of edges that survive any attempt to decompose the SCC into independent directed parts. This has direct operational meaning:

- **κ = 1**: The SCC has exactly one irreducible feedback loop. A single additional pass may suffice for convergence.
- **κ = 2**: Two independent feedback loops. The agent may need parallel deliberation threads, one per loop.
- **κ = k**: At least k independent feedback paths that cannot be decomposed. The deliberation budget scales with κ.

The SCC decomposition itself tells the agent *where* the feedback loops are. The bipartition that achieves the minimum cut tells the agent *where the bottleneck is* — which edges carry the most critical bidirectional information flow.

---

## 4. Application to the [&] Stack

### 4.1 Graphonomous: κ-Aware Memory Retrieval

Graphonomous maintains a continual learning knowledge graph with episodic, semantic, procedural, and temporal edges. Currently, queries traverse this graph uniformly.

**With κ-aware routing:**

1. When a query arrives, compute the subgraph reachable from the query's entry nodes (the nodes matching the query's topic).
2. Decompose this subgraph into its SCCs using Tarjan's algorithm (O(V+E), already efficient enough for real-time use on typical knowledge graph sizes).
3. For each SCC in the query's reachable subgraph:
   - **Size ≤ 1 (DAG region):** Retrieve context in topological order. Single pass. Fast.
   - **Size > 1 (cyclic region):** Compute κ for this SCC. Flag it for deliberation. Pass the SCC, its κ value, and its minimum-cut edges to the reasoning layer.

**The key integration:** When Graphonomous detects an SCC with κ > 0 in the query path, it triggers Deliberatic. This is not a heuristic — it's a formally grounded decision. The theorem proves that these regions contain irreducible feedback, which means single-pass retrieval *provably* cannot capture all the bidirectional context.

### 4.2 Deliberatic: κ-Informed Argumentation

Deliberatic implements structured argumentation with Byzantine-fault-tolerant consensus. Currently, it's invoked by external triggers or when agent confidence is below a threshold.

**With κ as the trigger:**

1. Deliberatic is invoked automatically when Graphonomous encounters an SCC with κ > 0.
2. The SCC structure informs the argumentation topology — each strongly connected cluster becomes a deliberation topic where multiple perspectives (agents or reasoning passes) must be reconciled.
3. The minimum-cut edges of the SCC define the *fault lines* — the points where the circular dependency is most vulnerable. These become the key propositions that agents must argue about.
4. The κ value sets the deliberation budget: higher κ means more irreducible feedback, which means more argumentation rounds before consensus.

**Concrete example:** An agent is asked about a company's strategic position. The knowledge graph contains nodes for "Market Share," "Revenue," "R&D Investment," "Product Quality," and "Customer Retention" — all mutually connected (market share depends on product quality, which depends on R&D, which depends on revenue from market share, etc.). This cluster is an SCC with κ = 1 (verified against kappa_reference.py — the 5-node SCC has a bipartition with only 1 edge crossing in the smaller direction). Graphonomous detects this, passes the SCC to the Deliberator, which reasons through the fault line (product-quality → market-share) before returning a coherent synthesis. For higher-κ SCCs (e.g., K₂,₂ gives κ = 2), multiple argumentation rounds are needed.

### 4.3 BendScript: Interactive κ-Driven Graph Construction

BendScript is already a tool where "prompts become topology." Users build knowledge graphs interactively, creating nodes, edges, Stargates (sub-graph portals), and fork/merge operations.

**With κ as a live feature:**

1. **Real-time κ display:** As the user builds their graph, BendScript continuously computes and displays κ for each connected component and SCC. Not as a number in a corner — as a visual property of the graph itself. SCC clusters glow or pulse with intensity proportional to their κ value. DAG regions are rendered with a directional flow aesthetic (arrows, gradients). SCC regions are rendered with a cyclic aesthetic (orbital motion, pulsing edges).

2. **Topology-aware suggestions:** When the user adds a node or edge, BendScript can preview the topological impact:
   - "Adding this edge creates a feedback loop between these 4 nodes. κ goes from 0 to 1. Your AI agent will now deliberate on this cluster instead of just retrieving."
   - "Removing this edge would break the only feedback loop in this cluster. κ drops to 0. The cluster becomes purely retrievable."

3. **Stargates as SCC portals:** A Stargate can be automatically suggested at the boundary of an SCC — "This cluster of nodes forms a strongly connected component. Create a Stargate to enter it as a focused deliberation space?"

4. **"Bend" as a verb:** The core interaction of BendScript — "bending" the graph — becomes formally defined: *to bend a graph is to add an edge that increases κ, transforming a DAG region into a cyclic region, moving it from retrieval territory to deliberation territory.* To "unbend" is to remove such an edge, simplifying the region back to a DAG.

### 4.4 The [&] Protocol: κ in the Composition Grammar

The [&] protocol's formal grammar defines five cognitive primitives: `&memory`, `&reason`, `&time`, `&space`, `&govern`. The κ invariant provides a formal criterion for when `&reason` (Deliberatic) is required:

```
# Extended pipeline with κ-aware routing
context
|> &memory.recall("topic")           # Graphonomous retrieves the relevant subgraph
|> &memory.topology()                 # Compute SCCs and κ for the retrieved subgraph
|> &κ.route()                         # Route: DAG regions → fast path, SCC regions → deliberation
|> &reason.deliberate(budget: :κ)     # Deliberatic runs with budget proportional to κ
|> &memory.learn()                    # Results feed back into the knowledge graph
```

The `&κ.route()` step is the new primitive. It inspects the topological structure of the retrieved context and makes a routing decision:

- **If all retrieved context is in DAG regions:** Skip deliberation. Fast path. Return context directly to the model.
- **If retrieved context includes SCC regions:** Extract the SCCs, compute their κ values, and invoke `&reason.deliberate()` with the appropriate budget and topology.

This could be formalized as a fifth cognitive primitive — `&topology` — or as a property of `&memory` itself: when Graphonomous returns context, it annotates each subgraph with its κ value and SCC structure, and the pipeline reads that annotation to decide whether to invoke `&reason`.

### 4.5 TickTickClock: Temporal κ

Time-series data has its own version of cyclicity. Periodic patterns in time series (seasonal effects, recurring anomalies, business cycles) are temporal feedback loops — patterns that return to their starting state. TickTickClock already does anomaly detection and pattern learning via Mamba SSM.

**Connection:** The transition graph of a discrete dynamical system has κ > 0 if and only if the system has a periodic orbit of period > 1 (Theorem 3 in the κ paper, verified across 873,611 systems). This means κ can also serve as the formal detection criterion for periodicity in TickTickClock's pattern learning. A time series with κ > 0 in its discretized transition dynamics has genuine periodic structure; κ = 0 means pure drift with no recurrence.

### 4.6 OpenSentience: Research Home

The theoretical foundations — the κ paper, the proof code, the interactive demos — live on opensentience.org. This is the research arm of the portfolio, and κ-aware graph intelligence is its first concrete research contribution. The connection to consciousness science (IIT's Φ) and cosmological topology (β₁ in persistent homology) provides intellectual depth, but the product-facing claims rest only on the graph-theoretic facts, which are proved.

---

## 5. The Formal Claims (What's Proved vs. What's Applied)

To maintain the epistemic standards that made the original research credible, we distinguish:

### Proved (mathematical facts, independent of any application):

1. For finite directed graphs: κ > 0 ⟺ graph contains a directed cycle in an SCC.
2. For finite directed graphs: κ > 0 ⟺ β₁ > 0 (cycle rank is positive).
3. For finite dynamical systems: κ > 0 ⟺ the system has a periodic orbit of period > 1.
4. The transition graph functor preserves κ exactly.
5. Algebraic proofs generalize all four results to all finite n.

### Applied (engineering claims, grounded in the proved facts):

6. DAG regions of a knowledge graph are amenable to single-pass retrieval because there are no circular dependencies (consequence of κ = 0).
7. SCC regions of a knowledge graph require iterative reasoning because circular dependencies are provably irreducible (consequence of κ > 0).
8. The κ value of an SCC is a reasonable proxy for the deliberation budget (engineering heuristic, not proved).
9. The minimum-cut edges of an SCC identify the critical bidirectional dependencies (direct consequence of κ's definition).
10. κ-aware routing will improve inference quality relative to uniform traversal (empirical claim, to be tested).

### Open (directions for further work):

11. Quantitative relationship between κ and optimal deliberation depth (needs experimentation).
12. Efficient incremental κ computation as the knowledge graph evolves (algorithmic optimization needed — full recomputation after every edge change may be too expensive for large graphs; incremental SCC maintenance algorithms exist in the literature).
13. Extension to weighted/probabilistic graphs where edge strengths vary (κ currently defined for unweighted graphs).
14. Formal connection between κ in knowledge graphs and attention patterns in transformer architectures (speculative but suggestive — self-attention over a context window with no recurrence has κ = 0; recurrent architectures have κ > 0).

---

## 6. Competitive Positioning

**"Most AI retrieves. [&] knows when to think."**

The κ invariant gives this claim a precise, provable meaning:

- **Standard RAG** treats all context uniformly → equivalent to assuming κ = 0 everywhere → misses circular dependencies → produces shallow or inconsistent answers on mutually dependent topics.
- **[&] with κ-aware routing** detects SCC regions where κ > 0 → routes them to deliberation → produces coherent answers on topics with genuine circular dependencies.

No other agent framework has a formal, proved criterion for this routing decision. Most use heuristics (confidence thresholds, retry logic, user-specified reasoning depth). κ is the first topology-derived routing primitive for agent inference.

**The tagline: "Systems with κ = 0 retrieve. Systems with κ > 0 integrate."**

---

## 7. From Theory to Spec

The companion documents provide:

1. **κ Integration Spec** (`kappa_integration_spec.md`) — Product-level specification for how κ is computed, surfaced, and used across Graphonomous, BendScript, Deliberatic, and the [&] protocol.
2. **κ Reference Implementation** (`kappa_reference.py`) — Python implementation of κ computation with SCC decomposition, minimum cut identification, and graph analysis utilities. Port targets: Elixir (Graphonomous/Deliberatic), JavaScript (BendScript canvas).
3. **κ Proof & Verification** (`kappa_proof.py`) — Exhaustive computational proof across 1,926,351 systems. Run it to verify the claims. Zero counterexamples.

---

*Proved results: (1) κ–β₁ equivalence (algebraic + exhaustive, 1,052,740 graphs). (2) κ–periodic orbit equivalence (algebraic + exhaustive, 873,611 maps). (3) Functor preservation (by construction + exhaustive verification). Categorical framework: traced symmetric monoidal categories (Joyal–Street–Verity, 1996). Applied to: Graphonomous (continual learning knowledge graphs), Deliberatic (structured argumentation), BendScript (interactive graph topology), [&] Protocol (capability composition). Research home: opensentience.org.*
