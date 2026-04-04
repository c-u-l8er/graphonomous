# Skill 10 — Anti-Patterns

> What NOT to do when using Graphonomous MCP tools — and how to fix it.
>
> Every anti-pattern here comes from real failure modes: wasted tool calls,
> corrupted confidence landscapes, broken learning loops, noisy graphs, and
> agents that forget everything between sessions.

---

## Overview

This file catalogs the most damaging mistakes an LLM agent can make when
using Graphonomous. Each anti-pattern is structured as:

1. **The mistake** — what it looks like
2. **Why it's harmful** — the concrete damage it causes
3. **The fix** — what to do instead
4. **Example** — before/after showing the correction

Use this as a pre-flight checklist or periodic self-audit.

---

## Table of Anti-Patterns

| # | Name | Severity | Tools Affected |
|---|------|----------|----------------|
| 1 | [Amnesia Agent](#1--amnesia-agent) | 🔴 Critical | `retrieve_context` |
| 2 | [Fire and Forget](#2--fire-and-forget) | 🔴 Critical | `learn_from_outcome` |
| 3 | [Confidence Inflation](#3--confidence-inflation) | 🔴 Critical | `store_node`, `learn_from_outcome` |
| 4 | [Kitchen Sink Nodes](#4--kitchen-sink-nodes) | 🟠 High | `store_node` |
| 5 | [Phantom Causality](#5--phantom-causality) | 🟠 High | `learn_from_outcome` |
| 6 | [Edge Spaghetti](#6--edge-spaghetti) | 🟠 High | `store_edge` |
| 7 | [Orphan Goals](#7--orphan-goals) | 🟠 High | `manage_goal` |
| 8 | [Review Theater](#8--review-theater) | 🟠 High | `review_goal` |
| 9 | [Timeout Punishment](#9--timeout-punishment) | 🟡 Medium | `learn_from_outcome` |
| 10 | [Consolidation Neglect](#10--consolidation-neglect) | 🟡 Medium | `run_consolidation` |
| 11 | [Source Amnesia](#11--source-amnesia) | 🟡 Medium | `store_node` |
| 12 | [Goal Monolith](#12--goal-monolith) | 🟡 Medium | `manage_goal` |
| 13 | [Topology Blindness](#13--topology-blindness) | 🟡 Medium | `retrieve_context`, `topology_analyze`, `deliberate` |
| 14 | [Duplicate Flooding](#14--duplicate-flooding) | 🟡 Medium | `store_node` |
| 15 | [Status Shortcut](#15--status-shortcut) | 🟢 Low | `manage_goal` |
| 16 | [Metadata Void](#16--metadata-void) | 🟢 Low | `manage_goal`, `store_node` |
| 17 | [Over-Deliberation](#17--over-deliberation) | 🟢 Low | `deliberate`, `topology_analyze` |
| 18 | [Signal Fabrication](#18--signal-fabrication) | 🔴 Critical | `review_goal` |
| 19 | [Causal Context Discard](#19--causal-context-discard) | 🔴 Critical | `retrieve_context`, `learn_from_outcome` |
| 20 | [Progress Fantasy](#20--progress-fantasy) | 🟠 High | `manage_goal` |
| 21 | [Revise Without Checking](#21--revise-without-checking) | 🟠 High | `belief_revise` |
| 22 | [Expand When You Should Revise](#22--expand-when-you-should-revise) | 🟡 Medium | `belief_revise` |
| 23 | [Hard Delete Without Traversal](#23--hard-delete-without-traversal) | 🟠 High | `forget_node` |
| 24 | [Ignoring the Frontier](#24--ignoring-the-frontier) | 🟡 Medium | `epistemic_frontier` |
| 25 | [Forgetting Instead of Revising](#25--forgetting-instead-of-revising) | 🟡 Medium | `forget_node`, `belief_revise` |

---

## 🔴 Critical Anti-Patterns

These actively damage the knowledge graph or defeat core learning mechanisms.

---

### 1 — Amnesia Agent

**The mistake:** Never calling `retrieve_context` before answering questions or
taking actions. The agent treats every conversation as a blank slate.

**Why it's harmful:**
- Prior knowledge is ignored — the graph has no reason to exist
- The same questions get re-explored from scratch every session
- No causal context is captured, so the learning loop (Skill 02) cannot function
- The user gets inconsistent answers because prior corrections are never recalled

**The fix:** Call `retrieve_context` at the start of every conversation about a
topic that may have been discussed before, and before every consequential action.

**Before (bad):**
```
User: "How do I deploy the API?"
Agent: <answers from training data alone, ignoring 15 stored procedural nodes>
```

**After (good):**
```
User: "How do I deploy the API?"
Agent: retrieve_context(query: "API deployment procedure and steps")
       → Gets 4 procedural nodes with high confidence
       → Answers using stored knowledge, supplementing with training data
       → Saves causal_context for later outcome feedback
```

**Checklist:**
- [ ] Every session starts with at least one `retrieve_context` call
- [ ] Every factual question triggers a retrieval before answering
- [ ] Every multi-step action is preceded by context retrieval

---

### 2 — Fire and Forget

**The mistake:** Taking actions informed by graph knowledge but never calling
`learn_from_outcome` to report what happened.

**Why it's harmful:**
- The graph cannot distinguish good knowledge from bad knowledge
- Wrong information stays at the same confidence forever
- Correct information never gets reinforced
- The graph degrades into a static notebook instead of a learning system
- Over time, consolidation may prune good-but-unreinforced nodes

**The fix:** After every consequential action informed by retrieval, report the
outcome. Save the `causal_context` array from `retrieve_context` and pass it as
`causal_node_ids` when the outcome is known.

**Before (bad):**
```
retrieve_context(query: "fix database timeout")
→ causal_context: ["nd_a", "nd_b"]
// Agent suggests a fix. User says it worked.
// Agent moves on. causal_context is lost. No learning.
```

**After (good):**
```
retrieve_context(query: "fix database timeout")
→ causal_context: ["nd_a", "nd_b"]  // SAVE THIS

// Agent suggests a fix. User confirms it worked.

learn_from_outcome(
  action_id: "fix-db-timeout-pool-resize",
  status: "success",
  confidence: 0.85,
  causal_node_ids: '["nd_a", "nd_b"]',
  evidence: '{"fix": "increased pool from 5 to 20", "user_confirmed": true}'
)
// nd_a and nd_b get confidence boost. Graph learns.
```

---

### 3 — Confidence Inflation

**The mistake:** Setting confidence to 0.9–1.0 on everything, or always using
1.0 as the outcome confidence in `learn_from_outcome`.

**Why it's harmful:**
- All nodes look equally trustworthy — confidence becomes meaningless
- The retrieval ranker cannot distinguish verified facts from guesses
- Learning deltas are maximized, which overcorrects on noisy signals
- A single false positive at confidence 1.0 inflates bad knowledge aggressively
- Consolidation can't identify weak nodes for pruning

**The fix:** Calibrate confidence honestly based on evidence quality.

| Evidence Type | Appropriate Confidence |
|--------------|----------------------|
| Copied directly from source code | 0.90–0.95 |
| Read in official documentation | 0.80–0.90 |
| Inferred from multiple consistent signals | 0.65–0.80 |
| Told by user, plausible but unverified | 0.50–0.65 |
| Inferred from a single indirect source | 0.30–0.50 |
| Speculation or guess | 0.10–0.30 |

For outcome signals:

| Signal Quality | Appropriate `confidence` on Outcome |
|---------------|-------------------------------------|
| Test passed, user explicitly confirmed | 0.85–0.95 |
| Seems to have worked, no complaints | 0.60–0.75 |
| Indirect indicator of success | 0.40–0.60 |
| Guessing at the outcome | 0.10–0.30 |

**Before (bad):**
```
store_node(
  content: "I think the cache TTL is probably 5 minutes",
  confidence: 0.95  // ← speculation labeled as near-certain
)
```

**After (good):**
```
store_node(
  content: "Cache TTL appears to be 5 minutes based on a comment in config.ts line 42; not confirmed by runtime observation",
  confidence: 0.45,  // ← honest assessment of indirect evidence
  source: "src/config.ts#L42"
)
```

---

### 5 — Phantom Causality

**The mistake:** Calling `learn_from_outcome` with `causal_node_ids` that were
not actually used to inform the action — fabricating a causal link.

**Why it's harmful:**
- Nodes get credited (boosted) or blamed (penalized) for outcomes they did not influence
- The confidence landscape becomes random noise instead of a signal
- Trust attribution is corrupted — future retrievals rank on false merit
- Compounds over time: a node falsely credited with a success attracts more
  retrievals, generating more phantom credits

**The fix:** Only pass node IDs that were returned in the `causal_context` of
the specific `retrieve_context` call that preceded the action. Do not manually
add node IDs you "think might be related."

**Before (bad):**
```
// Retrieval returned causal_context: ["nd_x"]
// Agent also knows about "nd_y" from a previous conversation
// Agent includes both in the outcome

learn_from_outcome(
  action_id: "fix-logging",
  status: "success",
  confidence: 0.8,
  causal_node_ids: '["nd_x", "nd_y"]'  // ← nd_y was not part of this retrieval
)
```

**After (good):**
```
// Retrieval returned causal_context: ["nd_x"]
// Only credit the nodes that actually informed this specific action

learn_from_outcome(
  action_id: "fix-logging",
  status: "success",
  confidence: 0.8,
  causal_node_ids: '["nd_x"]'  // ← only the actual causal nodes
)
```

---

### 18 — Signal Fabrication

**The mistake:** Building a `review_goal` coverage signal from made-up data
instead of actual retrieval results.

**Why it's harmful:**
- The coverage evaluator produces decisions based on false evidence
- `act` decisions may be issued when the graph has zero relevant knowledge
- `escalate` decisions may wrongly block well-supported goals
- The goal lifecycle becomes driven by fiction, not epistemic reality
- Undermines the entire act/learn/escalate decision framework

**The fix:** Always call `retrieve_context` for the goal's domain before
building the coverage signal. Use real retrieved nodes, real outcomes, and
honest gap assessments.

**Before (bad):**
```
review_goal(
  goal_id: "goal_deploy",
  signal: '{"retrieved_nodes": [], "contradictions": 0, "coverage_estimate": 0.8}'
  // ← Claims 80% coverage with ZERO retrieved nodes. Fabricated.
)
```

**After (good):**
```
// Step 1: Actually retrieve context
retrieve_context(query: "deployment procedure and infrastructure setup")
→ results: [node_a (0.7), node_b (0.5)]

// Step 2: Build signal from real data
review_goal(
  goal_id: "goal_deploy",
  signal: '{"retrieved_nodes": [{"node_id": "node_a", "confidence": 0.7}, {"node_id": "node_b", "confidence": 0.5}], "contradictions": 0, "knowledge_gaps": ["rollback procedure unknown", "staging environment config missing"]}'
)
```

---

### 19 — Causal Context Discard

**The mistake:** Calling `retrieve_context`, using the results, but throwing
away the `causal_context` array before it can be fed to `learn_from_outcome`.

**Why it's harmful:**
- Without `causal_node_ids`, `learn_from_outcome` has nothing to update
- The learning call is completely wasted — zero confidence deltas applied
- The entire retrieve → act → learn loop is broken at the critical junction
- Equivalent to observing an experiment but never recording which variables
  were manipulated

**The fix:** Treat `causal_context` as a first-class value. When you call
`retrieve_context`, immediately note the `causal_context` array and hold it
in working memory until the outcome is resolved.

**Pattern to follow every time:**

```
// Step 1: Retrieve and CAPTURE causal context
retrieve_context(query: "...")
→ causal_context: ["nd_1", "nd_2", "nd_3"]  // ← SAVE THIS

// Step 2: Act (using retrieved knowledge)
// ... take action ...

// Step 3: Close the loop with the SAVED causal context
learn_from_outcome(
  action_id: "...",
  status: "...",
  confidence: ...,
  causal_node_ids: '["nd_1", "nd_2", "nd_3"]'  // ← USE THE SAVED VALUE
)
```

If you find yourself needing to close the loop but have lost the causal context,
you can either:
1. Skip the `learn_from_outcome` call (honest — no data is better than fake data)
2. Store an episodic node recording the outcome instead:
   ```
   store_node(
     content: "User confirmed the auth fix worked, but causal context was not captured for this action.",
     node_type: "episodic",
     confidence: 0.7,
     source: "conversation"
   )
   ```

---

## 🟠 High-Severity Anti-Patterns

These degrade graph quality and reduce the effectiveness of learning.

---

### 4 — Kitchen Sink Nodes

**The mistake:** Cramming multiple unrelated facts into a single node.

**Why it's harmful:**
- Retrieval becomes imprecise — searching for Topic A also returns Topic B noise
- Confidence applies to the entire node, not individual claims. One wrong fact
  in a multi-fact node penalizes all the correct facts during learning.
- Edge creation is ambiguous — does an edge from this node refer to claim 1 or claim 4?
- Consolidation can't merge/prune individual claims within a bloated node
- Goal linkage attributes all claims to all goals, inflating coverage scores

**The fix:** Store one atomic, verifiable fact per node. If you have five facts,
create five nodes.

**Before (bad):**
```
store_node(
  content: "The system uses SQLite for storage, the embedder runs MiniLM, the consolidator checks every 5 minutes, and the MCP server uses stdio transport. Also EXLA is excluded because of NIF issues.",
  confidence: 0.8
)
```

**After (good):**
```
store_node(content: "Graphonomous uses SQLite via exqlite for persistent storage of nodes, edges, outcomes, and goals.", node_type: "semantic", confidence: 0.95, source: "graphonomous/CLAUDE.md")
store_node(content: "The Embedder uses sentence-transformers/all-MiniLM-L6-v2 for local embedding generation via Bumblebee.", node_type: "semantic", confidence: 0.9, source: "graphonomous/CLAUDE.md")
store_node(content: "The Consolidator GenServer checks for activity every 5 minutes (configurable) and triggers consolidation after 30 seconds of inactivity.", node_type: "semantic", confidence: 0.9, source: "graphonomous.com/project_spec/README.md")
store_node(content: "The MCP server communicates over stdio transport via a vendored anubis_mcp dependency.", node_type: "semantic", confidence: 0.95, source: "graphonomous/CLAUDE.md")
store_node(content: "EXLA is intentionally excluded from dependencies due to NIF/CUDA mismatch issues that block boot on some machines.", node_type: "semantic", confidence: 0.95, source: "graphonomous/CLAUDE.md")
```

Five nodes are better than one. Each can be independently retrieved, updated,
linked, and confidence-scored.

---

### 6 — Edge Spaghetti

**The mistake:** Creating edges between every pair of nodes that seem remotely
connected, resulting in a dense mesh of weak, uninformative relationships.

**Why it's harmful:**
- Neighborhood expansion during `retrieve_context` returns noise instead of signal
- Topology analysis becomes expensive and produces spurious SCCs
- Every node becomes reachable from every other node within 2 hops — the graph
  loses its discriminative structure
- Consolidation may strengthen co-retrieved edges, amplifying the noise
- κ values inflate as random edge clusters form accidental cycles

**The fix:** Only create edges when the relationship adds genuine retrieval
value. Ask: "Would finding Node B after retrieving Node A genuinely help an
agent answer a question?"

**Edge creation decision framework:**

| Question | If Yes | If No |
|----------|--------|-------|
| Does A directly cause or enable B? | `causal` edge | Skip |
| Does A provide evidence for B's claim? | `supports` edge | Skip |
| Does A contradict B? | `contradicts` edge | Skip |
| Was A extracted or summarized from B? | `derived_from` edge | Skip |
| Are A and B about the same specific subsystem AND frequently needed together? | `related` edge | Skip |
| Are A and B both vaguely about "code"? | **Skip** | **Skip** |

**Rule of thumb:** If you can't articulate *why* this edge helps future retrieval
in one sentence, don't create it.

---

### 7 — Orphan Goals

**The mistake:** Creating goals but never linking knowledge nodes to them, never
updating progress, and never reviewing coverage.

**Why it's harmful:**
- `review_goal` has no signal to evaluate — always returns `learn` or `escalate`
- Progress stays at 0.0 regardless of actual work done
- New sessions can't resume effectively — the goal exists but has no context
- The GoalGraph becomes a list of names, not a connected knowledge structure
- Attention system can't prioritize because goals have no supporting evidence

**The fix:** Every time you store a node while working on a goal, link it.
Every time you complete a sub-task, update progress. Every time you need to
decide what to do next, review coverage.

**Minimum goal hygiene per session:**
1. After `store_node` → `manage_goal(operation: "link_nodes", ...)`
2. After meaningful work → `manage_goal(operation: "set_progress", ...)`
3. Before major actions → `review_goal(goal_id: "...", signal: {...})`
4. At session end → `manage_goal(operation: "set_progress", ...)` with latest state

---

### 8 — Review Theater

**The mistake:** Calling `review_goal` but then ignoring the decision — always
proceeding to act regardless of whether the decision was `learn` or `escalate`.

**Why it's harmful:**
- The coverage review provides zero value if its output is ignored
- The agent acts on insufficient knowledge, producing poor outcomes
- Failed outcomes penalize causal nodes that might have been reinforced had the
  agent gathered more info first
- Escalation signals go unheeded, meaning the agent spins on problems it
  cannot solve alone

**The fix:** Respect the decision. Build it into your control flow.

**Decision policy:**

| Decision | Required Action |
|----------|----------------|
| `act` | Proceed with the goal's next action |
| `learn` | Retrieve more context, read more files, ask the user — then re-review |
| `escalate` | Mark goal blocked, switch to another goal, or ask the user for help |

If you consistently disagree with the decision, adjust the thresholds in
`options` rather than ignoring the output:

```
review_goal(
  goal_id: "...",
  signal: {...},
  options: '{"thresholds": {"act": 0.55, "escalate": 0.20}}'
)
```

---

### 20 — Progress Fantasy

**The mistake:** Setting goal progress based on optimism ("I think we're about
60% done") rather than linked evidence.

**Why it's harmful:**
- Progress claims become unreliable — 80% today might be 40% tomorrow
- Future sessions resume with false confidence in how much work remains
- Completion thresholds may be triggered prematurely (e.g., a Ralph Loop
  stop condition based on progress ≥ 0.85)
- The attention system may deprioritize nearly-complete goals that are actually
  barely started

**The fix:** Base progress on **countable evidence**. Calculate it from the ratio
of completed sub-objectives, number of linked nodes, or coverage scores.

**Progress calculation methods:**

| Method | Formula |
|--------|---------|
| Sub-goal completion | `completed_subgoals / total_subgoals` |
| Node coverage | `linked_nodes_with_confidence_over_0.7 / estimated_total_needed` |
| Coverage score | Use the `coverage_score` from `review_goal` directly |
| Checklist | `checked_items / total_items` defined in completion criteria |

**Before (bad):**
```
// "I explored a few files, feels like 60%"
manage_goal(operation: "set_progress", goal_id: "goal_x", progress: 0.6)
```

**After (good):**
```
// 4 of 7 modules mapped with linked nodes, mean confidence 0.78
// Progress = 4/7 ≈ 0.57
manage_goal(operation: "set_progress", goal_id: "goal_x", progress: 0.57)
```

---

## 🟡 Medium-Severity Anti-Patterns

These reduce effectiveness but don't actively corrupt the graph.

---

### 9 — Timeout Punishment

**The mistake:** Reporting `status: "failure"` when an action timed out or was
interrupted — when the actual outcome is unknown.

**Why it's harmful:**
- Causal nodes get penalized (confidence decreased) for a "failure" that didn't
  actually happen
- Good knowledge is erroneously suppressed in future retrievals
- The confidence landscape drifts toward distrust of nodes that may be perfectly
  accurate
- Compounds over time: falsely penalized nodes get pruned by consolidation

**The fix:** Use `timeout` when the outcome is genuinely unknown. Reserve
`failure` for when the action definitively produced a wrong or harmful result.

| Actual Situation | Correct Status |
|-----------------|----------------|
| Command timed out, no output | `timeout` |
| User left before confirming | `timeout` |
| External API didn't respond | `timeout` |
| Action produced an error | `failure` |
| Action ran but gave wrong result | `failure` |
| Action completed but user said it was wrong | `failure` |
| Action partly worked with caveats | `partial_success` |
| Action fully succeeded | `success` |

---

### 10 — Consolidation Neglect

**The mistake:** Never calling `run_consolidation`, letting the graph grow
unboundedly without decay, pruning, or merging.

**Why it's harmful:**
- Low-confidence nodes accumulate and dilute retrieval quality
- Near-duplicate nodes fragment knowledge instead of consolidating it
- Stale episodic nodes clutter the graph long past their usefulness
- The graph becomes slower as it grows without maintenance
- Co-retrieved nodes never get their edges strengthened

**The fix:** Trigger consolidation periodically. Good cadences:

| Session Type | When to Consolidate |
|-------------|-------------------|
| Long exploration session (many stores) | Every 15–20 minutes or every 4–5 iterations |
| End of any productive session | Before signing off |
| After a burst of `store_node` calls (10+) | Immediately after the burst |
| After resolving contradictions | After `deliberate` with `write_back: true` |

**Pattern:**
```
run_consolidation(action: "run_and_status", wait_ms: 2000)
```

The `wait_ms: 2000` gives consolidation time to run its pipeline before
returning status, so you can see what happened.

---

### 11 — Source Amnesia

**The mistake:** Storing nodes without setting the `source` field.

**Why it's harmful:**
- Future sessions can't trace knowledge back to its origin
- Claims cannot be verified or updated when source files change
- Contradictions are harder to resolve ("which one came from actual code?")
- Consolidation can't prioritize well-sourced nodes over unsourced ones
- The graph loses provenance — one of its key advantages over flat context

**The fix:** Always set `source`. Use file paths, URLs, "conversation", or
whatever describes where the knowledge came from.

| Knowledge Origin | Source Value Example |
|-----------------|-------------------|
| Read from a source file | `"graphonomous/lib/graphonomous/store.ex"` |
| Found in documentation | `"graphonomous/README.md"` |
| Told by user in conversation | `"conversation"` |
| Inferred from multiple sources | `"inferred from store.ex + CLAUDE.md"` |
| Output of a tool or command | `"mix test output"` |
| From a previous node (derived) | `"derived from nd_abc123"` |

---

### 12 — Goal Monolith

**The mistake:** Creating one enormous goal that covers everything, instead of
decomposing into focused sub-goals.

**Why it's harmful:**
- Progress is impossible to measure accurately on a vague giant goal
- Coverage review is meaningless — the domain is too broad for any signal
- No clear stopping point — the goal is never "done"
- Can't parallelize or prioritize different aspects
- Attention system can't differentiate urgency within the monolith

**The fix:** Decompose into 3–6 sub-goals with a parent. Each sub-goal should
be completable in 1–3 sessions with clear criteria.

**Before (bad):**
```
manage_goal(operation: "create_goal",
  payload: '{"title": "Understand the entire system and make it perfect"}'
)
```

**After (good):**
```
// Parent
manage_goal(operation: "create_goal",
  payload: '{"title": "Comprehensive system understanding", "priority": "high", "horizon": "medium"}'
)
→ goal_parent

// Focused sub-goals
manage_goal(operation: "create_goal",
  payload: '{"title": "Map OTP supervision tree and GenServer responsibilities", "parent_goal_id": "goal_parent", "horizon": "short"}'
)

manage_goal(operation: "create_goal",
  payload: '{"title": "Document build, test, and release workflows", "parent_goal_id": "goal_parent", "horizon": "short"}'
)

manage_goal(operation: "create_goal",
  payload: '{"title": "Identify external integration points and dependencies", "parent_goal_id": "goal_parent", "horizon": "short"}'
)
```

---

### 13 — Topology Blindness

**The mistake:** Ignoring the `topology` field in `retrieve_context` responses
and never calling `topology_analyze` or `deliberate`.

**Why it's harmful:**
- Cyclic knowledge regions go undetected and unresolved
- Self-reinforcing claims inflate each other's confidence without external
  grounding
- Contradictions embedded in cycles persist indefinitely
- High-stakes decisions may be made on circular reasoning
- The κ-aware routing capability — one of Graphonomous's differentiators —
  goes completely unused

**The fix:** Check `topology.routing` on every `retrieve_context` response.
When it says `"deliberate"`, take it seriously.

**Decision tree:**
```
retrieve_context response
  └─ topology.routing?
      ├─ "fast" → Proceed normally. Knowledge is acyclic.
      │
      └─ "deliberate" → max_kappa > 0, cycles exist
          ├─ Low stakes? → Note the cycle, proceed with awareness
          └─ High stakes? → Call deliberate(query: "...", node_ids: <scc_nodes>)
```

---

### 14 — Duplicate Flooding

**The mistake:** Storing the same knowledge repeatedly without checking whether
it already exists — flooding the graph with near-identical nodes.

**Why it's harmful:**
- Retrieval returns multiple copies of the same fact, wasting result slots
- Consolidation has to merge them (if similarity threshold is met), wasting cycles
- Until merged, duplicate nodes each get independent confidence, edges, and
  goal linkage — splitting what should be unified
- Edge relationships become ambiguous (which copy should the edge point to?)

**The fix:** Check for duplicates before storing. Use `query_graph` with
`similarity_search` on the content you're about to store.

**Pattern:**
```
// Before storing, check for near-duplicates
query_graph(
  operation: "similarity_search",
  query: "The auth module uses RS256 JWT tokens with 15-minute expiry",
  limit: 3
)

// If top match has similarity > 0.90 → it's already stored
//   → Consider updating the existing node's confidence instead
//   → Or create a "supports" edge from your observation to the existing node

// If top match has similarity 0.70–0.90 → related but distinct
//   → Store as a new node AND link to the existing one

// If no match or similarity < 0.70 → novel knowledge
//   → Store freely
```

This doesn't need to be done for every single node — but for significant
semantic facts that are likely to be re-encountered, the check is worthwhile.

---

## 🟢 Low-Severity Anti-Patterns

Suboptimal but not actively harmful.

---

### 15 — Status Shortcut

**The mistake:** Using `manage_goal(operation: "update_goal")` to change a
goal's status instead of `manage_goal(operation: "transition_goal")`.

**Why it's harmful:**
- `update_goal` does a raw field update — no transition metadata is recorded
- The goal loses its audit trail: why did this status change happen?
- Future sessions see a goal in "completed" state with no record of when, why,
  or what evidence justified the transition
- Policy hooks that depend on transition events may not fire

**The fix:** Always use `transition_goal` for status changes. Include metadata.

**Before (bad):**
```
manage_goal(operation: "update_goal", goal_id: "goal_x", payload: '{"status": "completed"}')
```

**After (good):**
```
manage_goal(
  operation: "transition_goal",
  goal_id: "goal_x",
  status: "completed",
  metadata: '{"reason": "All 7 modules mapped with mean confidence 0.82", "nodes_linked": 15, "session": "2025-06-15"}'
)
```

---

### 16 — Metadata Void

**The mistake:** Never using the `metadata` field on nodes, edges, or goals.

**Why it's harmful (mildly):**
- Loses structured data that could aid future retrieval and filtering
- Makes it harder to build rich coverage signals for `review_goal`
- Reduces the expressiveness of the graph — everything is just free text

**The fix:** Use `metadata` for structured data that enriches the node:

```
store_node(
  content: "The MCP server registers 12 tool components.",
  node_type: "semantic",
  confidence: 0.95,
  source: "graphonomous/lib/graphonomous/mcp/server.ex",
  metadata: '{"tool_count": 12, "resource_count": 2, "category": "mcp-architecture", "file_line": 15}'
)
```

You don't need metadata on every node, but for nodes that represent countable,
filterable, or categorizable knowledge, it adds value.

---

### 17 — Over-Deliberation

**The mistake:** Calling `deliberate` or `topology_analyze` on every single
retrieval, even when `routing` is `"fast"` and κ = 0.

**Why it's harmful:**
- Wasted tool calls and latency for regions with no cycles
- Deliberation on acyclic regions produces trivially simple "conclusions" that
  add no value
- Creates unnecessary semantic nodes if `write_back: true` is used needlessly

**The fix:** Trust the topology annotation on `retrieve_context`. Only call
`topology_analyze` or `deliberate` when:
- `routing` is `"deliberate"` (κ > 0)
- You explicitly suspect a contradiction between specific nodes
- You want a pre-flight structural check before a high-stakes decision

---

## Compound Anti-Pattern: The Forgetting Agent

The most damaging failure mode is the **combination** of anti-patterns 1 + 2 + 19:

1. **Amnesia** — never retrieve before acting
2. **Fire and forget** — never report outcomes
3. **Causal context discard** — even if retrieval happens, don't save the thread

Together, these three create an agent that:
- Has a knowledge graph but never reads from it
- Generates knowledge but never validates it
- Cannot learn from successes or failures
- Is indistinguishable from an agent without Graphonomous

**If you fix only three things, fix these three.** Everything else is
optimization atop a working retrieve → act → learn loop.

---

## Self-Audit Checklist

Run through this checklist periodically (every few sessions or iterations):

### Retrieval
- [ ] Am I calling `retrieve_context` before answering domain questions?
- [ ] Am I saving `causal_context` from retrieval results?
- [ ] Am I checking `topology.routing` for `"deliberate"` signals?

### Storage
- [ ] Are my nodes atomic (one fact per node)?
- [ ] Am I setting `source` on every node?
- [ ] Am I calibrating `confidence` honestly?
- [ ] Am I checking for duplicates before storing common facts?

### Learning
- [ ] Am I calling `learn_from_outcome` after consequential actions?
- [ ] Am I using the correct `status` (not conflating `timeout` with `failure`)?
- [ ] Am I passing only legitimate `causal_node_ids`?
- [ ] Am I setting outcome `confidence` based on signal quality?

### Goals
- [ ] Do my active goals have linked knowledge nodes?
- [ ] Is progress based on evidence, not optimism?
- [ ] Am I using `transition_goal` (not `update_goal`) for status changes?
- [ ] Am I decomposing large goals into focused sub-goals?

### Review
- [ ] Am I building coverage signals from real retrieval results?
- [ ] Am I respecting `learn` and `escalate` decisions?
- [ ] Am I re-reviewing after addressing knowledge gaps?

### Maintenance
- [ ] Am I triggering `run_consolidation` periodically?
- [ ] Am I creating edges only when they add retrieval value?

---

## Summary

| Priority | Fix This First |
|----------|---------------|
| 🔴 1 | Always `retrieve_context` before acting (Anti-pattern #1) |
| 🔴 2 | Always save `causal_context` for later learning (Anti-pattern #19) |
| 🔴 3 | Always `learn_from_outcome` after consequential actions (Anti-pattern #2) |
| 🔴 4 | Calibrate confidence honestly — never default to 0.9+ (Anti-pattern #3) |
| 🔴 5 | Build `review_goal` signals from real retrieval, not fabrication (Anti-pattern #18) |
| 🟠 6 | Store atomic nodes, not kitchen-sink nodes (Anti-pattern #4) |
| 🟠 7 | Link nodes to goals and update progress from evidence (Anti-patterns #7, #20) |
| 🟡 8 | Trigger consolidation periodically (Anti-pattern #10) |
| 🟡 9 | Always set `source` on stored nodes (Anti-pattern #11) |
| 🟡 10 | Watch for `routing: "deliberate"` in retrieval topology (Anti-pattern #13) |
| 🟠 11 | Check contradictions before revising beliefs (Anti-pattern #21) |
| 🟠 12 | Traverse before cascade-deleting (Anti-pattern #23) |

---

## v0.3 Anti-Patterns (Belief Revision, Forgetting, Epistemic Frontier)

---

### 21 — Revise Without Checking

**The mistake:** Calling `belief_revise(operation: "revise")` without first
checking if the old node is actually contradicted or wrong.

**Why it's harmful:**
- Supersedes correct knowledge with unverified replacement
- Propagates 0.6× confidence decay through dependents — weakening good nodes
- Creates `:superseded_by` edges that can't be undone
- Once propagated, the damage compounds through the dependency graph

**The fix:** Always run `belief_contradictions` first. Verify the old node
is genuinely wrong before revising.

```
# Check first
belief_contradictions(node_id: "node_old")
# Only revise if contradictions confirmed
belief_revise(operation: "revise", node_id: "node_old", content: "...", rationale: "...")
```

---

### 22 — Expand When You Should Revise

**The mistake:** Using `belief_revise(operation: "expand")` to add corrected
information alongside wrong information, instead of revising the wrong node.

**Why it's harmful:**
- Both the wrong and correct versions remain active in retrieval
- Creates `:contradicts` edges and κ=1 SCCs that need deliberation
- Future retrievals return conflicting information
- The graph accumulates contradictions instead of resolving them

**The fix:** If you know the old belief is wrong, use `revise` to replace it.
Only use `expand` when adding genuinely new knowledge.

| Situation | Correct Operation |
|---|---|
| Old fact is wrong, you have the correct version | `revise` |
| Old fact is wrong, you don't have a replacement | `contract` |
| New fact, no conflict with existing knowledge | `expand` |
| New fact, legitimately contradicts existing (both may be right) | `expand` (then deliberate) |

---

### 23 — Hard Delete Without Traversal

**The mistake:** Using `forget_node(mode: "hard")` or `forget_node(mode:
"cascade")` without first checking what depends on the node.

**Why it's harmful:**
- Hard delete severs all edges permanently — orphaning dependent nodes
- Cascade delete removes the node *plus* all orphaned dependents — potentially
  deleting far more than expected
- No recovery possible after hard/cascade delete
- Goal coverage may silently degrade if linked nodes are deleted

**The fix:** Always inspect the neighborhood before hard-deleting.

```
# Check what depends on this node
graph_traverse(start_node_id: "node_target", max_depth: 2)

# Only then decide on mode
forget_node(node_id: "node_target", mode: "hard")  # or cascade if orphans are OK
```

---

### 24 — Ignoring the Frontier

**The mistake:** Starting exploratory or learning work without checking
`epistemic_frontier` — investigating things you're already certain about while
genuinely uncertain knowledge goes unexamined.

**Why it's harmful:**
- Wastes investigation effort on already-established knowledge
- High-uncertainty nodes remain uncertain, degrading coverage scores
- Goals stay in `learn` state because their uncertain nodes never get evidence
- The graph's overall reliability plateaus

**The fix:** Check the frontier before exploratory work.

```
# Before investigating, see what's most uncertain
epistemic_frontier(min_gap: 0.3, limit: 5)

# Investigate top information-gain nodes first
# Report outcomes to shrink the frontier
learn_from_outcome(action_id: "...", causal_node_ids: [...], ...)
```

---

### 25 — Forgetting Instead of Revising

**The mistake:** Using `forget_node` to remove wrong knowledge instead of
`belief_revise` to correct it.

**Why it's harmful:**
- Forgetting doesn't propagate confidence decay to dependent nodes
- Dependent nodes retain their original confidence despite their foundation
  being removed — creating unsupported claims
- No revision record — the correction is invisible to future sessions
- Misses the opportunity to strengthen the graph with corrected knowledge

**The fix:** If knowledge is *wrong*, revise it. If knowledge is *irrelevant*,
forget it. The distinction matters.

| Knowledge is... | Action |
|---|---|
| **Wrong** (has a correct replacement) | `belief_revise(operation: "revise")` |
| **Wrong** (no replacement available) | `belief_revise(operation: "contract")` |
| **Irrelevant** (correct but not useful) | `forget_node(mode: "soft")` |
| **Dangerous** (must be deleted) | `forget_node(mode: "hard")` or `gdpr_erase` |