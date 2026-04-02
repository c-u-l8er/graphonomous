# Runtime Walkthrough

This page walks through the Graphonomous runtime from process startup to closed-loop learning, goal review, and maintenance.

If you want a practical mental model, think in this sequence:

1. **Boot services**
2. **Retrieve context**
3. **Act**
4. **Store durable knowledge**
5. **Learn from outcomes**
6. **Review goal coverage**
7. **Run consolidation**

---

## 1) Boot and Supervision

Graphonomous runs as an OTP application with supervised runtime components:

- Store
- Embedder
- Graph
- Retriever
- Learner
- GoalGraph
- Attention
- Consolidator
- MCP registry/server plumbing

### What happens at startup

- Store opens the SQLite database.
- Schema/migrations are applied.
- ETS hot cache is rebuilt from durable state.
- Core services come online and MCP tools/resources are exposed.

### Why this matters

You get:

- fast reads (ETS)
- durable writes (SQLite)
- process-level fault isolation (OTP supervision)

---

## 2) MCP Session Entry

Most integrations begin through MCP over stdio.

Typical first checks:

- Runtime health snapshot
- Goal snapshot
- Lightweight context retrieval for the current task

This gives the agent session orientation before making changes.

---

## 3) Retrieval Path (Context Before Action)

Graphonomous retrieval is not only semantic similarity. It combines:

1. embedding similarity search
2. graph-neighbor expansion
3. confidence-aware ranking
4. topology analysis (SCC/κ routing metadata)

### Retrieval output you should pay attention to

- `results`: ranked candidate context nodes
- `causal_context`: node IDs used later for outcome learning
- `topology.routing`: `fast` or `deliberate`
- `topology.max_kappa`: cycle complexity signal

### Routing behavior

- **fast**: proceed with normal reasoning
- **deliberate**: use deeper deliberation for cyclic/conflicting regions

---

## 4) Acting and Writing Memory

After retrieval, the agent reasons and executes work. New durable knowledge should be stored in atomic form.

### Node types

- `semantic`: facts/architecture
- `procedural`: how-to/workflows
- `episodic`: observed events or session outcomes
- `temporal`: time-indexed observations, monitoring events
- `outcome`: empirical results of actions (grounding)
- `goal`: durable intent, objectives, targets

### Good storage discipline

- one claim/procedure/event per node
- realistic confidence values
- source attribution when possible
- edges only when relationship quality justifies it

---

## 5) Closed-Loop Learning (Outcome Feedback)

After a meaningful action, Graphonomous can update confidence on the causal nodes that informed that action.

### Learning inputs

- `action_id`
- `status` (`success`, `partial_success`, `failure`, `timeout`)
- outcome `confidence`
- `causal_node_ids` (from retrieval causal context)
- optional evidence/trace metadata

### Confidence update model

Learner applies a bounded, learning-rate blend from prior confidence and status-scaled signal, so graph trust adapts over time.

### Practical effect

- useful nodes get reinforced
- weak/wrong assumptions are down-weighted
- retrieval quality improves across sessions

---

## 6) GoalGraph and Coverage Gate

For multi-step work, goals provide durable intent and lifecycle management.

### Goal lifecycle examples

- `proposed` -> `active` -> `completed`
- `active` -> `blocked` (if escalation needed)
- optional pause/abandon transitions as policy requires

### Coverage review

Coverage computes:

- `coverage_score`
- `uncertainty_score`
- `risk_score`
- decision: `act` | `learn` | `escalate`

This lets the runtime gate actions based on epistemic readiness, not just availability of any context.

---

## 7) Attention Loop (Prioritization Across Goals)

When many goals are in flight, attention can survey and rank what needs focus.

Autonomy modes:

- `observe` (read-only prioritization)
- `advise` (recommend actions)
- `act` (dispatch bounded actions)

Attention combines urgency, coverage state, and topology complexity to prioritize execution.

---

## 8) Consolidation Cycle (Memory Maintenance)

Consolidation keeps memory quality healthy over time.

The 7-stage pipeline includes:

1. Confidence decay
2. Prune weak nodes
3. Prune weak edges
4. Strengthen co-activated edges
5. Merge similar nodes
6. Promote timescale (fast → medium → slow → glacial)
7. Generate abstractions from episodic clusters

Operationally, run consolidation:

- at session boundaries
- after heavy write bursts
- periodically during long autonomous loops

---

## 9) End-to-End Example Walkthrough

A complete interaction often looks like this:

1. Agent retrieves context for user task.
2. Runtime returns ranked results + causal context + topology signal.
3. Agent performs work and returns output.
4. Agent stores key new semantic/procedural/episodic nodes.
5. Agent reports outcome against causal nodes.
6. Goal progress is updated.
7. Coverage is reviewed before next consequential step.
8. Consolidation runs to maintain graph quality.

---

## 10) Operational Checklist

Before ending a productive session:

- [ ] Store key durable knowledge
- [ ] Report outcomes for consequential actions
- [ ] Update linked goals/progress/status
- [ ] Trigger or verify consolidation
- [ ] Confirm runtime remains healthy

---

## 11) Common Failure Patterns to Avoid

- skipping retrieval on non-trivial tasks
- losing causal context before outcome reporting
- inflating confidence without evidence
- storing kitchen-sink nodes
- fabricating coverage or outcome signals
- ignoring repeated `learn`/`escalate` routing

---

## 12) Suggested Next Reads

- `quickstart`
- `architecture`
- `mcp-tools`
- `operations`
- `skills/SKILLS`

If you are integrating an autonomous agent, treat this walkthrough as the runtime backbone and the skills docs as strict operating policy.