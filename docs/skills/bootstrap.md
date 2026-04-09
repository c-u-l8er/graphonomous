---
name: bootstrap
description: Use when starting a new session, switching topics, or when the user says "bootstrap", "start session", "initialize graphonomous", or "load memory". Activates the Graphonomous-first memory loop and orients on prior context.
---

# Graphonomous Bootstrap

Initialize the Graphonomous-first memory loop for this session.

## Steps

1. **Retrieve prior context** for the user's current topic:
   ```
   retrieve(action: "context", query: "summary of prior work on <topic>")
   ```

2. **Check active goals** to regain session continuity:
   ```
   act(action: "manage_goal", operation: "list_goals", filters: {"status": "active"})
   ```

3. **Survey attention** to see what needs focus:
   ```
   route(action: "attention_survey", include_idle: false)
   ```

4. **Adopt the policy**: "Graphonomous-first memory loop is active."

5. **Report** to the user: what prior context exists, which goals are active, and what the attention engine recommends focusing on.

## Core Loop (apply for remainder of session)

For every non-trivial task, run the closed memory loop:

1. **Retrieve** — `retrieve(action: "context", query: "...")` before reasoning/acting. Never skip for domain-specific work.
2. **Route** — check `topology.routing` in response. If `"deliberate"`, run `route(action: "deliberate", query: "...")`
3. **Act** — `act(action: "store_node", ...)` to mutate the graph
4. **Learn** — `learn(action: "from_outcome", ...)` when you have an outcome signal. Preserve `causal_context` between retrieval and outcome.
5. **Consolidate** — `consolidate(action: "run")` periodically and at session end

### Machine Architecture (v0.4)

Graphonomous v0.4 exposes **5 loop-phase machines** instead of 29 individual tools. Each machine accepts an `action` parameter:

| Machine | Phase | Actions |
|---------|-------|---------|
| `retrieve` | "What do I know?" | context, episodic, procedural, coverage, trace_evidence, frontier |
| `route` | "What should I do?" | topology, deliberate, attention_survey, attention_cycle, review_goal |
| `act` | "Do it" | store_node, store_edge, delete_node, manage_edge, manage_goal, belief_revise, forget_node, forget_policy, gdpr_erase |
| `learn` | "Did it work?" | from_outcome, from_feedback, detect_novelty, from_interaction, contradictions |
| `consolidate` | "Clean up" | run, stats, query, traverse |

## Node and Edge Discipline

- Prefer **small, atomic nodes** — one fact/procedure/event per node
- Choose node types correctly: `semantic` (facts), `procedural` (how-to), `episodic` (events), `temporal` (time-bound observations), `outcome` (measured results), `goal` (objectives/targets)
- Set confidence based on evidence quality, not optimism
- Include `source` whenever possible (file path, URL, "conversation")
- Create edges only when they improve retrieval: `causal`, `causes`, `resolves`, `supports`, `contradicts`, `related`, `related_to`, `part_of`, `follows`, `supersedes`, `depends_on`, `similar_to`, `derived_from`, `temporal_before`, `temporal_after`, `co_occurs`

## Hard Prohibitions

Do NOT:
- Skip retrieval habitually — prior context likely exists
- Skip outcome learning on consequential actions
- Inflate confidence indiscriminately (no blanket 0.9+)
- Store kitchen-sink nodes (multiple unrelated facts)
- Fabricate coverage signals or causal provenance
- Ignore repeated `learn`/`escalate` decisions from coverage review
- Create edge spaghetti (link everything to everything)
- Neglect consolidation indefinitely

## Available Resources (Read-Only Snapshots)

| URI | What It Returns |
|-----|----------------|
| `graphonomous://runtime/health` | Runtime health, service status, counts |
| `graphonomous://goals/snapshot` | Goal totals and status breakdown |
| `graphonomous://graph/node/{id}` | Individual node details + edges |
| `graphonomous://graph/recent` | Recently accessed nodes |
| `graphonomous://consolidation/log` | Consolidator + orchestrator metrics |

## Extended Actions (via machines)

Beyond the core loop, each machine exposes additional actions:
- **`retrieve(action: "episodic")`** — time-range filtered episodic nodes
- **`retrieve(action: "procedural")`** — semantic search for how-to knowledge
- **`retrieve(action: "coverage")`** — epistemic coverage check (no goal required)
- **`retrieve(action: "trace_evidence")`** — Dijkstra evidence paths between nodes
- **`retrieve(action: "frontier")`** — Wilson interval uncertainty analysis
- **`learn(action: "from_feedback")`** — process positive/negative/correction on a node
- **`learn(action: "detect_novelty")`** — check if a concept is novel to the graph
- **`learn(action: "from_interaction")`** — full learning pipeline for exchanges
- **`learn(action: "contradictions")`** — detect belief conflicts
- **`consolidate(action: "stats")`** — aggregate graph health
- **`consolidate(action: "traverse")`** — BFS walk with depth/relationship filters
- **`consolidate(action: "query")`** — operation-based graph inspection

## Session End Checklist

Before ending a productive session:
1. Store key new knowledge: `act(action: "store_node", ...)`
2. Report pending outcomes: `learn(action: "from_outcome", ...)`
3. Update goal progress: `act(action: "manage_goal", operation: "set_progress", ...)`
4. Trigger consolidation: `consolidate(action: "run")`
