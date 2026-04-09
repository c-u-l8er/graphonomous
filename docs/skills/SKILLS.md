# Graphonomous MCP — Agent Skills

> **Purpose:** Teach any LLM connected to Graphonomous how to use its MCP machines
> correctly, idiomatically, and in the right sequence. These reference docs mirror
> the skills in the [ampersand-plugins](https://github.com/c-u-l8er/ampersand-plugins)
> Claude Code plugin. For Claude Code users, install the plugin directly:
> `claude plugin add c-u-l8er/ampersand-plugins`

---

## Quick Orientation

Graphonomous is a **continual learning engine** exposed as 5 MCP machines.
It maintains a **self-evolving knowledge graph** of semantic, procedural, episodic,
temporal, outcome, and goal nodes connected by typed, weighted edges. Your job as
an LLM agent is to **read from and write to this graph** as you work, creating a
durable memory that improves over time.

### The Core Loop

Every interaction should follow this rhythm:

```
retrieve → route → act → learn → consolidate
"What do I know?" → "What should I do?" → "Do it" → "Did it work?" → "Clean up"
```

### Machine Architecture (v0.4)

Graphonomous v0.4 exposes **5 loop-phase machines** instead of 29 individual tools. Each machine accepts an `action` parameter:

| Machine | Phase | Actions |
|---------|-------|---------|
| `retrieve` | "What do I know?" | context, episodic, procedural, coverage, trace_evidence, frontier |
| `route` | "What should I do?" | topology, deliberate, attention_survey, attention_cycle, review_goal |
| `act` | "Do it" | store_node, store_edge, delete_node, manage_edge, manage_goal, belief_revise, forget_node, forget_policy, gdpr_erase |
| `learn` | "Did it work?" | from_outcome, from_feedback, detect_novelty, from_interaction, contradictions |
| `consolidate` | "Clean up" | run, stats, query, traverse |

---

## Skill Reference Files

| File | Skill | What It Teaches |
|------|-------|----------------|
| [bootstrap.md](bootstrap.md) | `/graphonomous:bootstrap` | Session initialization — retrieve context, check goals, survey attention |
| [retrieve.md](retrieve.md) | `/graphonomous:retrieve` | The foundational read loop — κ-aware ranked retrieval + store new knowledge |
| [store.md](store.md) | `/graphonomous:store` | Dedicated write path — atomic nodes, confidence calibration, edges |
| [learn.md](learn.md) | `/graphonomous:learn` | Closed-loop learning — outcome, feedback, novelty, contradictions |
| [deliberate.md](deliberate.md) | `/graphonomous:deliberate` | κ-aware topology analysis and cyclic reasoning |
| [consolidate.md](consolidate.md) | `/graphonomous:consolidate` | Memory maintenance — 7-stage pipeline, stats, query, traverse |
| [goals.md](goals.md) | `/graphonomous:goals` | Durable intent tracking — goal CRUD and lifecycle |
| [belief.md](belief.md) | `/graphonomous:belief` | AGM-style belief revision — expand, revise, contract |
| [forgetting.md](forgetting.md) | `/graphonomous:forgetting` | Structured removal — soft, hard, cascade, GDPR, policy pruning |
| [epistemic-frontier.md](epistemic-frontier.md) | `/graphonomous:epistemic-frontier` | Uncertainty-guided investigation — Wilson intervals, information gain |
| [trace-evidence-path.md](trace-evidence-path.md) | `/graphonomous:trace-evidence-path` | Evidence provenance — weighted Dijkstra, Yen's K-shortest paths |
| [attention.md](attention.md) | `/graphonomous:attention` | Autonomous focus — survey, triage, dispatch |
| [review.md](review.md) | `/graphonomous:review` | Coverage evaluation — act/learn/escalate routing |
| [inspect.md](inspect.md) | `/graphonomous:inspect` | Read-only graph inspection — list, get, edges, search, traverse |
| [graph-health.md](graph-health.md) | `/graphonomous:graph-health` | Combined diagnostics — weak nodes, orphans, staleness |
| [workflows.md](workflows.md) | `/graphonomous:workflows` | End-to-end recipes — cold start, debug, Ralph loop, handoff |
| [sync.md](sync.md) | `/graphonomous:sync` | Batch filesystem ingest to knowledge graph |
| [watch.md](watch.md) | `/graphonomous:watch` | Continuous filesystem monitoring with change detection |

---

## Resources (Read-Only Snapshots)

| URI | What It Returns |
|-----|----------------|
| `graphonomous://runtime/health` | Runtime health: node/edge counts, consolidator state, uptime |
| `graphonomous://goals/snapshot` | Current GoalGraph snapshot: all goals with status/progress |
| `graphonomous://graph/node/{id}` | Individual node details + connected edges |
| `graphonomous://graph/recent` | Recently added/accessed nodes, sorted by recency |
| `graphonomous://consolidation/log` | Consolidator state + orchestrator plasticity metrics |

---

## Node Types

| Type | Store When You Learn... | Examples |
|------|------------------------|---------|
| **semantic** | A fact, definition, or architectural truth | "Module X is responsible for Y", "The API uses JWT auth" |
| **procedural** | A procedure, workflow, or recipe | "To deploy: run X then Y then Z" |
| **episodic** | Something that happened — an event or observation | "Build failed due to missing dep" |
| **temporal** | A time-bound observation or monitoring event | "CPU spike at 14:30 during load test" |
| **outcome** | A measured result or benchmark score | "Latency dropped 40% after caching change" |
| **goal** | An objective, target, or intent | "Need to migrate auth to new compliance standard" |

**Rule of thumb:** "what is?" → semantic. "how to?" → procedural. "what happened?" → episodic.

---

## Edge Types

| Type | Meaning | Example |
|------|---------|---------|
| `causal` / `causes` | A causes or drives B | "Config change → behavior change" |
| `supports` | A provides evidence for B | "Test result → hypothesis" |
| `contradicts` | A conflicts with B | "Doc says X, but code does Y" |
| `related` / `related_to` | Thematically connected | "Auth module ↔ User module" |
| `derived_from` | Extracted or derived from | "Summary ← source document" |
| `supersedes` | Replaced by newer version | "Old preference → updated preference" |
| `resolves` | A resolves issue B | "Fix → bug report" |
| `part_of` | A is a component of B | "Function → module" |
| `follows` | A comes after B | "Step 2 → Step 1" |
| `depends_on` | A requires B | "Feature → dependency" |
| `similar_to` | A resembles B | "Pattern A ↔ Pattern B" |
| `temporal_before` / `temporal_after` | Temporal ordering | "Event 1 before Event 2" |
| `co_occurs` | A and B happen together | "Error X co-occurs with config Y" |

---

## Confidence Scores

| Range | Meaning | When to Use |
|-------|---------|-------------|
| **0.9–1.0** | Verified fact, directly observed | Copied from code/docs, confirmed by test |
| **0.7–0.89** | Strong evidence, not directly verified | Multiple consistent sources |
| **0.5–0.69** | Moderate, reasonable inference | Single source, plausible |
| **0.3–0.49** | Low confidence, uncertain | Indirect evidence, may be outdated |
| **0.0–0.29** | Speculative or likely wrong | Guess, contradicted by other evidence |

**Default is 0.5.** Always adjust based on evidence quality.

---

## Session Startup Checklist

1. **Retrieve prior context:**
   ```
   retrieve(action: "context", query: "summary of prior work on <topic>")
   ```

2. **Check active goals:**
   ```
   act(action: "manage_goal", operation: "list_goals", filters: {"status": "active"})
   ```

3. **Survey attention:**
   ```
   route(action: "attention_survey", include_idle: false)
   ```

4. **Proceed** with the user's request, using retrieved context.

---

## End-of-Session Checklist

1. **Store new knowledge:** `act(action: "store_node", ...)`
2. **Report outcomes:** `learn(action: "from_outcome", ...)`
3. **Update goal progress:** `act(action: "manage_goal", operation: "set_progress", ...)`
4. **Consolidate:** `consolidate(action: "run")`

---

## How to Use These Skill Files

**For Claude Code users:** Install the plugin — `claude plugin add c-u-l8er/ampersand-plugins` — and skills are available as `/graphonomous:<skill>` commands.

**For other agents/system prompts:** Include `SKILLS.md` first, then whichever skill files are relevant. Minimum viable context: this file alone.

**For agent bootstrapping:** Use [workflows.md](workflows.md) for end-to-end recipes.

**For repository wiring:** These skills are referenced by `AGENTS.md`, `CLAUDE.md`, and `README.md` in the graphonomous repo.
