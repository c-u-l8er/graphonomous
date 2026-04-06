# Skill 09 — Workflows

> End-to-end recipes for common tasks. Each workflow shows the exact sequence of
> Graphonomous MCP tool calls for a real scenario, with decision points and
> branching logic.
>
> **Depends on:** All prior skills (01–08). Each workflow references the relevant
> skill file for deeper explanation of individual tools.

---

## Table of Contents

1. [Workflow A — Session Startup (Cold Start)](#workflow-a--session-startup-cold-start)
2. [Workflow B — Session Startup (Warm Resume)](#workflow-b--session-startup-warm-resume)
3. [Workflow C — Answer a Question from Memory](#workflow-c--answer-a-question-from-memory)
4. [Workflow D — Explore and Map a Codebase](#workflow-d--explore-and-map-a-codebase)
5. [Workflow E — Goal-Driven Iterative Work (Ralph Loop)](#workflow-e--goal-driven-iterative-work-ralph-loop)
6. [Workflow F — Debug a Problem with Persistent Memory](#workflow-f--debug-a-problem-with-persistent-memory)
7. [Workflow G — Resolve Contradictory Knowledge](#workflow-g--resolve-contradictory-knowledge)
8. [Workflow H — Knowledge Graph Maintenance](#workflow-h--knowledge-graph-maintenance)
9. [Workflow I — End-of-Session Cleanup](#workflow-i--end-of-session-cleanup)
10. [Workflow J — Teach Graphonomous About a New Domain](#workflow-j--teach-graphonomous-about-a-new-domain)
11. [Workflow K — Multi-Agent Handoff](#workflow-k--multi-agent-handoff)
12. [Workflow L — Trace Evidence for Decision Explainability](#workflow-l--trace-evidence-for-decision-explainability)
13. [Workflow Composition — Combining Recipes](#workflow-composition--combining-recipes)

---

## Workflow A — Session Startup (Cold Start)

**When:** First time connecting to a Graphonomous instance, or the graph is empty.

**Goal:** Establish a baseline of knowledge and orient the agent.

### Steps

```
Step 1 — Check graph health
─────────────────────────────
Tool: query_graph
  operation: "list_nodes"
  limit: 1

Purpose: Determine if the graph is empty or populated.

→ If count == 0: this is a cold start, proceed to Step 2.
→ If count > 0: switch to Workflow B (Warm Resume).
```

```
Step 2 — Store orientation node
───────────────────────────────
Tool: store_node
  content: "Session started. Graph is empty. Beginning knowledge seeding."
  node_type: "episodic"
  confidence: 1.0
  source: "session-init"
  metadata: '{"session_type": "cold_start"}'

→ Save the returned node_id (e.g., "nd_session_start").
```

```
Step 3 — Create a bootstrap goal
─────────────────────────────────
Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Bootstrap knowledge graph", "priority": "high", "horizon": "short", "description": "Seed the graph with foundational knowledge about the current project/domain."}'

→ Save the returned goal_id (e.g., "goal_bootstrap").
```

```
Step 4 — Activate the goal
──────────────────────────
Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_bootstrap>"
  status: "active"
  metadata: '{"reason": "Cold start — no prior knowledge exists"}'
```

```
Step 5 — Begin knowledge seeding
─────────────────────────────────
Now proceed to either:
  - Workflow D (Explore and Map a Codebase) if working on code
  - Workflow J (Teach About a New Domain) if the user is providing information
  - Whatever the user requests, but store knowledge as you go
```

---

## Workflow B — Session Startup (Warm Resume)

**When:** Connecting to a Graphonomous instance that already has knowledge from
prior sessions.

**Goal:** Regain context quickly and pick up where you left off.

### Steps

```
Step 1 — List active goals
──────────────────────────
Tool: manage_goal
  operation: "list_goals"
  payload: '{"status": "active"}'

→ Note all active goals, their IDs, titles, and progress values.
→ If no active goals, check for "proposed" goals:

Tool: manage_goal
  operation: "list_goals"
  payload: '{"status": "proposed"}'
```

```
Step 2 — Retrieve prior context for the user's topic
─────────────────────────────────────────────────────
Tool: retrieve_context
  query: "<user's opening message or topic>"
  limit: 10
  expansion_hops: 1

→ Read the results to understand what the graph already knows.
→ Save causal_context for potential later outcome reporting.
→ Note the topology.routing field.
```

```
Step 3 — Survey attention (optional but recommended)
────────────────────────────────────────────────────
Tool: attention_survey
  include_idle: false

→ See what the attention engine thinks needs focus.
→ High attention_score items may be more important than what the user asked about.
→ Mention to the user if there are high-priority pending items.
```

```
Step 4 — Orient and proceed
───────────────────────────
Combine:
  - Active goals (from Step 1)
  - Retrieved context (from Step 2)
  - Attention priorities (from Step 3)
  - User's current request

Present a brief orientation to the user:
  "I can see we have [N] active goals. [Goal X] is at [Y]% progress.
   I found [Z] relevant knowledge nodes about your topic.
   [Attention item if relevant]. How would you like to proceed?"

Then follow the user's direction, or resume the highest-priority goal.
```

---

## Workflow C — Answer a Question from Memory

**When:** The user asks a question that the graph may already have knowledge about.

**Goal:** Provide an accurate answer grounded in stored knowledge, then record
any new information discovered.

### Steps

```
Step 1 — Retrieve relevant context
───────────────────────────────────
Tool: retrieve_context
  query: "<user's question, rephrased for semantic search>"
  limit: 8
  expansion_hops: 1

→ Save causal_context: ["nd_a", "nd_b", "nd_c", ...]
→ Note topology.routing
→ Read results carefully — they ARE your memory of this topic
```

```
Step 2 — Check for deliberation need
─────────────────────────────────────
IF topology.routing == "deliberate":
  │
  ├─ Low stakes (casual question, not critical):
  │   → Mention uncertainty to user, answer with caveats
  │
  └─ High stakes (critical decision, architectural question):
      │
      Tool: deliberate
        query: "<user's question>"
        node_ids: <nodes from topology.sccs[].nodes>
        write_back: false
      │
      → Use deliberation conclusions to inform your answer
      → Consider write_back: true if conclusions are definitive

IF topology.routing == "fast":
  → Proceed normally with retrieved results
```

```
Step 3 — Answer the user
────────────────────────
Compose your answer using:
  - Retrieved knowledge (cite node content and confidence)
  - Deliberation conclusions (if applicable)
  - Your own training knowledge (clearly marked as non-graph-sourced)

Be transparent about confidence levels:
  - "Based on stored knowledge (confidence 0.85): ..."
  - "I'm less certain about this (confidence 0.4): ..."
  - "This isn't in the knowledge graph, but from my training: ..."
```

```
Step 4 — Store new knowledge (if the answer revealed something new)
───────────────────────────────────────────────────────────────────
IF you synthesized new knowledge (combined multiple nodes, drew a conclusion):

Tool: store_node
  content: "<the new insight, stated as an atomic fact>"
  node_type: "semantic"
  confidence: <based on evidence quality>
  source: "synthesis from retrieval"

Tool: store_edge
  source_id: "<new_node_id>"
  target_id: "<most relevant retrieved node_id>"
  edge_type: "derived_from"
  weight: 0.7
```

```
Step 5 — Close the learning loop (if user gives feedback)
─────────────────────────────────────────────────────────
IF user confirms the answer was correct:

Tool: learn_from_outcome
  action_id: "answer-<topic-slug>-<date>"
  status: "success"
  confidence: 0.8
  causal_node_ids: '<causal_context from Step 1>'
  evidence: '{"user_confirmed": true, "topic": "<topic>"}'

IF user says the answer was wrong:

Tool: learn_from_outcome
  action_id: "answer-<topic-slug>-<date>"
  status: "failure"
  confidence: 0.8
  causal_node_ids: '<causal_context from Step 1>'
  evidence: '{"user_rejected": true, "correction": "<what user said instead>"}'

Tool: store_node
  content: "<the correct information from the user>"
  node_type: "semantic"
  confidence: 0.85
  source: "user correction"
```

---

## Workflow D — Explore and Map a Codebase

**When:** The user wants you to understand and document a codebase, or you need
to build knowledge about a project.

**Goal:** Systematically explore directories and files, storing architectural
knowledge as atomic graph nodes with a goal tracking overall progress.

### Steps

```
Step 1 — Create an exploration goal with sub-goals
───────────────────────────────────────────────────
Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Codebase comprehension: <project name>", "priority": "high", "horizon": "medium"}'
→ goal_parent

Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Map directory structure and module layout", "parent_goal_id": "<goal_parent>", "horizon": "short"}'
→ goal_structure

Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Document build, test, and run workflows", "parent_goal_id": "<goal_parent>", "horizon": "short"}'
→ goal_workflows

Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Map module responsibilities and interfaces", "parent_goal_id": "<goal_parent>", "horizon": "short"}'
→ goal_modules

Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Identify dependencies and integration points", "parent_goal_id": "<goal_parent>", "horizon": "short"}'
→ goal_deps

Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Catalog risks, unknowns, and technical debt", "parent_goal_id": "<goal_parent>", "horizon": "short"}'
→ goal_risks

Activate the parent and first sub-goal:

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_parent>"
  status: "active"
  metadata: '{"reason": "Beginning codebase exploration"}'

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_structure>"
  status: "active"
  metadata: '{"reason": "Starting with structural mapping"}'
```

```
Step 2 — Explore top-level structure
─────────────────────────────────────
Read the project's root directory, README, and config files.

For each significant discovery, store a node:

Tool: store_node
  content: "Project root contains: <list of directories and their apparent purposes>"
  node_type: "semantic"
  confidence: 0.9
  source: "<path to directory listing>"
→ nd_structure_1

Tool: store_node
  content: "Build system uses <tool>. Entry point is <file>."
  node_type: "procedural"
  confidence: 0.9
  source: "<path to config file>"
→ nd_build_1

Link all discoveries to the current sub-goal:

Tool: manage_goal
  operation: "link_nodes"
  goal_id: "<goal_structure>"
  node_ids: '["nd_structure_1", "nd_build_1"]'
```

```
Step 3 — Dive into each major module
─────────────────────────────────────
For each major directory / module:

1. Read key files (entry points, exports, types)
2. Store one semantic node per module describing responsibility
3. Store edges connecting related modules:

Tool: store_edge
  source_id: "<module_a_node>"
  target_id: "<module_b_node>"
  edge_type: "related"
  weight: 0.6

4. If you find a "how to" (build, test, deploy):

Tool: store_node
  content: "To <action>: <steps>"
  node_type: "procedural"
  confidence: <based on evidence>
  source: "<file where you found it>"

5. Record what you did as episodic:

Tool: store_node
  content: "Explored <path>. Found <N> files covering <topics>."
  node_type: "episodic"
  confidence: 0.95
  source: "exploration"
```

```
Step 4 — Update progress after each module
──────────────────────────────────────────
Tool: manage_goal
  operation: "set_progress"
  goal_id: "<goal_structure>"
  progress: <estimated based on modules explored / total modules>

Tool: manage_goal
  operation: "set_progress"
  goal_id: "<goal_parent>"
  progress: <weighted average of sub-goal progress>
```

```
Step 5 — Close the learning loop per exploration batch
──────────────────────────────────────────────────────
Tool: retrieve_context
  query: "project structure and module layout for <project>"
  limit: 5
→ causal_context: [...]

Tool: learn_from_outcome
  action_id: "explore-<module-name>"
  status: "success"  (or "partial_success" if you couldn't read everything)
  confidence: 0.8
  causal_node_ids: '<causal_context>'
  evidence: '{"modules_explored": <N>, "files_read": <M>, "nodes_created": <K>}'
```

```
Step 6 — Review coverage before marking sub-goal complete
─────────────────────────────────────────────────────────
Tool: retrieve_context
  query: "complete structural map of <project>"
  limit: 15
→ results (use to build signal)

Tool: review_goal
  goal_id: "<goal_structure>"
  signal: '{"retrieved_nodes": [<from results>], "outcomes": [<recent>], "contradictions": 0, "knowledge_gaps": [<any gaps noticed>]}'

→ decision: "act" → mark sub-goal completed, move to next
→ decision: "learn" → explore more, fill gaps, re-review
→ decision: "escalate" → ask user about inaccessible areas
```

```
Step 7 — Complete sub-goal and advance
──────────────────────────────────────
Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_structure>"
  status: "completed"
  metadata: '{"nodes_linked": <N>, "modules_mapped": <M>, "avg_confidence": <X>}'

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_workflows>"
  status: "active"
  metadata: '{"reason": "Structure mapping complete, moving to workflow documentation"}'

Repeat Steps 2–7 for each sub-goal.
```

```
Step 8 — Final consolidation
────────────────────────────
When all sub-goals are complete:

Tool: run_consolidation
  action: "run_and_status"
  wait_ms: 3000

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_parent>"
  status: "completed"
  metadata: '{"total_nodes": <N>, "total_edges": <M>, "sub_goals_completed": 5}'
```

---

## Workflow E — Goal-Driven Iterative Work (Ralph Loop)

**When:** Performing autonomous iterative work toward a goal. Each iteration is
a bounded cycle of retrieve → act → learn → review.

**Goal:** Make measurable progress on a goal through disciplined iteration, with
self-correction via the learning loop and coverage review.

### Configuration

| Setting | Value |
|---------|-------|
| Max iterations | 8–12 |
| Actions per iteration | 1–3 |
| Retrieve limit | 8–12 |
| Consolidation cadence | Every 4–5 iterations |
| Blocked retry limit | 2 per gap |

### Steps (One Iteration)

```
Step 1 — Select objective
─────────────────────────
Tool: manage_goal
  operation: "list_goals"
  payload: '{"status": "active"}'

Choose the highest-priority active goal (or the one with the
highest attention score if using the attention system).

Define a single-iteration objective:
  "This iteration I will: <specific, bounded action>"
```

```
Step 2 — Retrieve context for the objective
───────────────────────────────────────────
Tool: retrieve_context
  query: "<objective description>"
  limit: 10
  expansion_hops: 1

→ Save causal_context
→ Check topology.routing
→ Note existing knowledge relevant to this objective
```

```
Step 3 — Take bounded action (1–3 actions)
──────────────────────────────────────────
Actions can be:
  - Read a file and extract knowledge
  - Write or modify code
  - Run a command and observe output
  - Ask the user a clarifying question
  - Analyze retrieved knowledge and draw conclusions

For each discovery or result:

Tool: store_node
  content: "<atomic fact or observation>"
  node_type: "<semantic|procedural|episodic>"
  confidence: <calibrated>
  source: "<where you found it>"
→ Save node_id

Tool: manage_goal
  operation: "link_nodes"
  goal_id: "<active_goal_id>"
  node_ids: '["<new_node_id>"]'
```

```
Step 4 — Close the learning loop
─────────────────────────────────
Tool: learn_from_outcome
  action_id: "iter<N>-<objective-slug>"
  status: "<success|partial_success|failure>"
  confidence: <signal quality>
  causal_node_ids: '<causal_context from Step 2>'
  evidence: '{"iteration": <N>, "objective": "<objective>", "result": "<what happened>"}'
```

```
Step 5 — Review coverage and decide next step
──────────────────────────────────────────────
Tool: retrieve_context
  query: "<goal title/description>"
  limit: 12
→ Build signal from results

Tool: review_goal
  goal_id: "<active_goal_id>"
  signal: '<signal object>'

Decision routing:

  "act" → Update progress, plan next iteration's objective
      Tool: manage_goal
        operation: "set_progress"
        goal_id: "<active_goal_id>"
        progress: <new_value>

  "learn" → Identify what's missing, orient next iteration to fill gaps
      → Next iteration objective = fill the specific gap identified in rationale

  "escalate" → Switch goals or ask user
      Tool: manage_goal
        operation: "transition_goal"
        goal_id: "<active_goal_id>"
        status: "blocked"
        metadata: '{"reason": "<from review rationale>", "blocked_at_iteration": <N>}'
      → Select next highest-priority goal and continue
```

```
Step 6 — Periodic consolidation (every 4–5 iterations)
──────────────────────────────────────────────────────
Tool: run_consolidation
  action: "run_and_status"
  wait_ms: 2000

→ Note any merge/prune signals in the status response
```

```
Step 7 — Check stop conditions
──────────────────────────────
STOP if:
  - Goal progress >= 0.85 and review_goal says "act"
  - Max iterations reached
  - Hard blocker with no viable alternative goal
  - All active goals completed

CONTINUE otherwise → return to Step 1 for next iteration
```

### Iteration Output Template

After each iteration, record a summary (mentally or as an episodic node):

```
Tool: store_node
  content: "Ralph Loop iteration <N>: Objective was '<X>'. Performed <actions>. Status: <success/partial/failure>. Goal progress: <old> → <new>. Decision: <act/learn/escalate>. Next: <plan>."
  node_type: "episodic"
  confidence: 0.95
  source: "ralph-loop-iter-<N>"
  metadata: '{"iteration": <N>, "goal_id": "<id>", "decision": "<act|learn|escalate>"}'
```

---

## Workflow F — Debug a Problem with Persistent Memory

**When:** The user reports a bug or problem, and you want to use graph memory to
track debugging attempts, hypotheses, and outcomes.

**Goal:** Systematic debugging with recorded hypotheses, tests, and results that
persist for future reference.

### Steps

```
Step 1 — Retrieve any prior knowledge about the problem area
─────────────────────────────────────────────────────────────
Tool: retrieve_context
  query: "<description of the bug / error message / affected area>"
  limit: 10
  expansion_hops: 1

→ Save causal_context
→ Check if similar bugs have been debugged before
→ Look for procedural nodes about debugging this area
```

```
Step 2 — Create a debugging goal
─────────────────────────────────
Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Debug: <brief bug description>", "priority": "high", "horizon": "short", "description": "<full error message and reproduction steps>"}'
→ goal_debug

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_debug>"
  status: "active"
  metadata: '{"trigger": "<error message or user report>"}'
```

```
Step 3 — Record the hypothesis
──────────────────────────────
Tool: store_node
  content: "Hypothesis: <what you think is causing the bug and why>"
  node_type: "semantic"
  confidence: 0.4  (hypotheses start at low confidence)
  source: "debugging-hypothesis"
  metadata: '{"bug_id": "<goal_debug>", "hypothesis_number": 1}'
→ nd_hypothesis_1

Tool: manage_goal
  operation: "link_nodes"
  goal_id: "<goal_debug>"
  node_ids: '["nd_hypothesis_1"]'
```

```
Step 4 — Test the hypothesis
────────────────────────────
Perform the diagnostic action (read code, run test, check logs, etc.)

Tool: store_node
  content: "<what you observed — the test result>"
  node_type: "episodic"
  confidence: 0.9
  source: "<file or command output>"
→ nd_test_result_1
```

```
Step 5 — Update hypothesis confidence based on evidence
───────────────────────────────────────────────────────
IF hypothesis confirmed:

  Tool: store_edge
    source_id: "nd_test_result_1"
    target_id: "nd_hypothesis_1"
    edge_type: "supports"
    weight: 0.8

  Tool: learn_from_outcome
    action_id: "debug-hypothesis-1-test"
    status: "success"
    confidence: 0.85
    causal_node_ids: '["nd_hypothesis_1"]'
    evidence: '{"test": "<what you did>", "result": "hypothesis confirmed"}'

IF hypothesis refuted:

  Tool: store_edge
    source_id: "nd_test_result_1"
    target_id: "nd_hypothesis_1"
    edge_type: "contradicts"
    weight: 0.8

  Tool: learn_from_outcome
    action_id: "debug-hypothesis-1-test"
    status: "failure"
    confidence: 0.85
    causal_node_ids: '["nd_hypothesis_1"]'
    evidence: '{"test": "<what you did>", "result": "hypothesis refuted", "alternative": "<new direction>"}'

  → Go back to Step 3 with a new hypothesis
```

```
Step 6 — Record the fix
────────────────────────
When the bug is fixed:

Tool: store_node
  content: "Root cause of <bug>: <explanation>. Fix: <what was changed and why>."
  node_type: "semantic"
  confidence: 0.9
  source: "<file changed>"
→ nd_root_cause

Tool: store_node
  content: "To debug <category of bug>: check <steps>. Common causes: <list>."
  node_type: "procedural"
  confidence: 0.85
  source: "debugging-experience"
→ nd_debug_procedure

Tool: store_edge
  source_id: "nd_root_cause"
  target_id: "nd_hypothesis_1"  (the winning hypothesis)
  edge_type: "supports"
  weight: 0.9

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_debug>"
  status: "completed"
  metadata: '{"root_cause": "<summary>", "fix": "<summary>", "hypotheses_tested": <N>}'
```

**Why this matters:** Next time a similar bug occurs, `retrieve_context` will
surface the root cause, the debugging procedure, and the fix — saving
significant time. The failed hypotheses (now low-confidence from outcome
feedback) help future debugging avoid dead ends.

---

## Workflow G — Resolve Contradictory Knowledge

**When:** You discover (via retrieval, edge inspection, or deliberation) that
the graph contains contradictory claims.

**Goal:** Investigate, resolve, and record the resolution durably.

### Steps

```
Step 1 — Identify the contradiction
────────────────────────────────────
You might discover this through:
  - retrieve_context returning conflicting nodes
  - query_graph(get_edges) showing a "contradicts" edge
  - topology_analyze showing κ > 0 with a cycle of mutual support
  - User pointing out inconsistency in your answers

Note the contradicting node IDs:
  - nd_claim_a: "<claim A>"
  - nd_claim_b: "<claim B (contradicts A)>"
```

```
Step 2 — Diagnose the topology
──────────────────────────────
Tool: topology_analyze
  node_ids: ["<nd_claim_a>", "<nd_claim_b>", <any related nodes>]

→ Check if this is part of a larger cycle (κ > 0)
→ Note fault-line edges
```

```
Step 3 — Investigate the sources
────────────────────────────────
Tool: query_graph
  operation: "get_node"
  node_id: "<nd_claim_a>"
→ Check source, confidence, created_at, access_count

Tool: query_graph
  operation: "get_node"
  node_id: "<nd_claim_b>"
→ Check source, confidence, created_at, access_count

Tool: query_graph
  operation: "get_edges"
  node_id: "<nd_claim_a>"
→ What supports or contradicts claim A?

Tool: query_graph
  operation: "get_edges"
  node_id: "<nd_claim_b>"
→ What supports or contradicts claim B?
```

```
Step 4 — Deliberate (if needed)
───────────────────────────────
IF the contradiction involves cycles or the answer isn't clear from sources:

Tool: deliberate
  query: "Which claim is correct: '<claim A>' or '<claim B>'? Evaluate based on source evidence, recency, and supporting edges."
  node_ids: ["<nd_claim_a>", "<nd_claim_b>", <supporting nodes>]
  write_back: false  (inspect first)

→ Read conclusions
→ If conclusions are sound, re-run with write_back: true
```

```
Step 5 — Record the resolution
───────────────────────────────
IF you can determine which claim is correct:

Tool: store_node
  content: "Resolution: <the correct claim> is authoritative. <the incorrect claim> was outdated/incorrect because <reason>."
  node_type: "semantic"
  confidence: 0.85
  source: "<how you verified>"
→ nd_resolution

Tool: store_edge
  source_id: "nd_resolution"
  target_id: "<correct_claim_node>"
  edge_type: "supports"
  weight: 0.9

Tool: store_edge
  source_id: "nd_resolution"
  target_id: "<incorrect_claim_node>"
  edge_type: "contradicts"
  weight: 0.9

IF you cannot resolve it:

Tool: store_node
  content: "Unresolved contradiction: <claim A> vs <claim B>. Needs verification from <specific source>."
  node_type: "episodic"
  confidence: 0.5
  source: "contradiction-investigation"
  metadata: '{"unresolved": true, "node_a": "<id>", "node_b": "<id>"}'
```

```
Step 6 — Let consolidation help
────────────────────────────────
If you stored a resolution with strong confidence and a "contradicts" edge to
the incorrect claim, consolidation will eventually:
  - Decay the incorrect claim's confidence
  - Potentially prune it below threshold
  - Strengthen the correct claim through co-activation with the resolution

Tool: run_consolidation
  action: "run"
  wait_ms: 1000
```

---

## Workflow H — Knowledge Graph Maintenance

**When:** Periodic housekeeping to keep the graph healthy. Run this during idle
times, after long sessions, or when the user explicitly asks.

**Goal:** Audit, clean, consolidate, and strengthen the knowledge graph.

### Steps

```
Step 1 — Get health overview
────────────────────────────
Tool: run_consolidation
  action: "status"

→ Check last consolidation time, node/edge counts, health metrics
```

```
Step 2 — Audit low-confidence nodes
────────────────────────────────────
Tool: query_graph
  operation: "list_nodes"
  min_confidence: 0.0
  limit: 50

→ Identify nodes with confidence < 0.3
→ For each, decide:
   - Should it be verified? (retrieve_context + check source)
   - Should it be pruned? (leave for consolidation)
   - Should it be reinforced? (store_edge with supporting evidence)
```

```
Step 3 — Check for orphan nodes
───────────────────────────────
For a sample of nodes (especially episodic ones):

Tool: query_graph
  operation: "get_edges"
  node_id: "<sample_node_id>"

→ If zero edges: this is an orphan
→ Consider linking it to related nodes or goals via store_edge
→ Orphans with low confidence are consolidation candidates
```

```
Step 4 — Run full topology analysis
────────────────────────────────────
Tool: topology_analyze
  (no params — full graph)

→ Check for unexpected cycles (high κ where there shouldn't be any)
→ If cycles found, run Workflow G to resolve contradictions
→ Compare scc_count to previous runs to track graph health trends
```

```
Step 5 — Trigger consolidation
──────────────────────────────
Tool: run_consolidation
  action: "run_and_status"
  wait_ms: 3000

→ Review the status response:
   - How many nodes were pruned?
   - How many were merged?
   - How many were strengthened?
   - Any timescale promotions?
```

```
Step 6 — Record the maintenance event
──────────────────────────────────────
Tool: store_node
  content: "Graph maintenance performed. Before: <node_count> nodes, <edge_count> edges. After consolidation: <stats>. Identified <N> low-confidence nodes, <M> orphans, <K> cycles."
  node_type: "episodic"
  confidence: 0.95
  source: "maintenance"
  metadata: '{"maintenance_type": "periodic", "pre_node_count": <N>, "post_node_count": <M>}'
```

---

## Workflow I — End-of-Session Cleanup

**When:** A productive session is ending. Run this to preserve state for next time.

**Goal:** Ensure all valuable knowledge is stored, outcomes reported, goals
updated, and the graph is in good shape for the next session.

### Steps

```
Step 1 — Store any unstored knowledge
──────────────────────────────────────
Review the conversation for facts, procedures, or events worth remembering.

For each:
Tool: store_node
  content: "<knowledge>"
  node_type: "<semantic|procedural|episodic>"
  confidence: <calibrated>
  source: "conversation"
```

```
Step 2 — Report any outstanding outcomes
────────────────────────────────────────
For any actions taken during the session where you have causal_context,
but haven't yet reported an outcome:

Tool: learn_from_outcome
  action_id: "<descriptive action slug>"
  status: "<outcome status>"
  confidence: <signal quality>
  causal_node_ids: '<causal_context>'
  evidence: '{"session_end": true, ...}'
```

```
Step 3 — Update goal progress
─────────────────────────────
Tool: manage_goal
  operation: "list_goals"
  payload: '{"status": "active"}'

For each active goal that was advanced this session:

Tool: manage_goal
  operation: "set_progress"
  goal_id: "<goal_id>"
  progress: <updated value>
```

```
Step 4 — Store session summary
──────────────────────────────
Tool: store_node
  content: "Session summary: <3-5 sentence recap of what was accomplished, key decisions made, and what remains to be done>"
  node_type: "episodic"
  confidence: 0.9
  source: "session-summary"
  metadata: '{"session_type": "productive", "goals_advanced": [<goal_ids>], "nodes_created": <N>}'
```

```
Step 5 — Trigger consolidation
──────────────────────────────
Tool: run_consolidation
  action: "run_and_status"
  wait_ms: 2000

→ Let the consolidator clean up before the graph goes idle
```

---

## Workflow J — Teach Graphonomous About a New Domain

**When:** The user wants to seed the graph with domain knowledge — documentation,
architecture decisions, team practices, etc.

**Goal:** Systematically ingest information into well-structured, atomic,
properly-typed graph nodes.

### Steps

```
Step 1 — Create a domain knowledge goal
────────────────────────────────────────
Tool: manage_goal
  operation: "create_goal"
  payload: '{"title": "Learn domain: <domain name>", "priority": "high", "horizon": "medium", "description": "<what the user wants you to learn>"}'
→ goal_domain

Tool: manage_goal
  operation: "transition_goal"
  goal_id: "<goal_domain>"
  status: "active"
```

```
Step 2 — Check for existing knowledge
──────────────────────────────────────
Tool: retrieve_context
  query: "<domain name> architecture and concepts"
  limit: 10

→ If results exist: summarize what's already known, ask
  user what's new or changed
→ If empty: proceed to seeding from scratch
```

```
Step 3 — Ingest user-provided information as atomic nodes
─────────────────────────────────────────────────────────
As the user provides information, decompose into atomic facts:

Rules:
  - ONE fact per node
  - Choose the right type (semantic for facts, procedural for how-to)
  - Set confidence based on source:
    - Official docs/user-confirmed → 0.85-0.95
    - User recollection ("I think...") → 0.5-0.7
    - Inferential → 0.3-0.5
  - Always set source to indicate origin
  - Always include relevant metadata

Example extraction from user input:
  User says: "Our API uses JWT with RS256, tokens expire in 1h, refresh via
  /auth/refresh endpoint, and we use Redis for session storage"

  This becomes 4 nodes:
  1. "The API uses RS256-signed JWT tokens for authentication"
     type: semantic, confidence: 0.85, source: "user-provided"
  2. "JWT tokens expire after 1 hour"
     type: semantic, confidence: 0.85, source: "user-provided"
  3. "To refresh an expired token, POST to /auth/refresh"
     type: procedural, confidence: 0.85, source: "user-provided"
  4. "Session state is stored in Redis"
     type: semantic, confidence: 0.85, source: "user-provided"
```

```
Step 4 — Create edges between related nodes
───────────────────────────────────────────
After storing a batch of nodes:

Tool: store_edge
  source_id: "<jwt_node>"
  target_id: "<expiry_node>"
  edge_type: "related"
  weight: 0.8

Tool: store_edge
  source_id: "<refresh_node>"
  target_id: "<jwt_node>"
  edge_type: "causal"
  weight: 0.7
  metadata: '{"reason": "Token refresh produces new JWT"}'

Tool: store_edge
  source_id: "<session_node>"
  target_id: "<jwt_node>"
  edge_type: "related"
  weight: 0.6
```

```
Step 5 — Link nodes to goal and update progress
────────────────────────────────────────────────
Tool: manage_goal
  operation: "link_nodes"
  goal_id: "<goal_domain>"
  node_ids: '["<jwt_node>", "<expiry_node>", "<refresh_node>", "<session_node>"]'

Tool: manage_goal
  operation: "set_progress"
  goal_id: "<goal_domain>"
  progress: <estimate based on how much of the domain has been covered>
```

```
Step 6 — Verify by retrieval
────────────────────────────
After seeding, verify the knowledge is retrievable:

Tool: retrieve_context
  query: "authentication and session management"
  limit: 8

→ Confirm the newly stored nodes appear in results
→ If they don't, check that content is descriptive enough for embedding match
→ Store any synthesis insights as additional nodes
```

```
Step 7 — Duplicate check
────────────────────────
Before storing new batches, check for near-duplicates:

Tool: query_graph
  operation: "similarity_search"
  query: "<content you're about to store>"
  limit: 3

→ If similarity > 0.90: likely duplicate, skip or update existing
→ If similarity 0.70-0.90: related but distinct, store + edge
→ If similarity < 0.70: novel, store freely
```

---

## Workflow K — Multi-Agent Handoff

**When:** One agent session is passing work to another (different model, different
context window, different role), and Graphonomous is the shared memory.

**Goal:** Ensure the receiving agent can resume work seamlessly using the graph
as the handoff medium.

### Steps (Sending Agent)

```
Step 1 — Store all remaining knowledge
───────────────────────────────────────
Follow Workflow I Steps 1–3 (end-of-session cleanup).
```

```
Step 2 — Report all outcomes
────────────────────────────
Ensure every action taken has a corresponding learn_from_outcome call.
Include trace IDs for provenance:

Tool: learn_from_outcome
  action_id: "<action>"
  status: "<status>"
  confidence: <confidence>
  causal_node_ids: '<ids>'
  decision_trace_id: "agent-alpha-session-42"
  action_linkage: '{"agent": "alpha", "session": 42, "handoff_to": "beta"}'
```

```
Step 3 — Store handoff briefing
───────────────────────────────
Tool: store_node
  content: "Agent handoff briefing: <what was accomplished, what remains, key open questions, recommended next actions, any caveats or risks>"
  node_type: "episodic"
  confidence: 0.9
  source: "agent-handoff"
  metadata: '{"from_agent": "alpha", "to_agent": "beta", "session": 42, "active_goals": ["<goal_ids>"]}'
→ nd_handoff

Link to all active goals:

Tool: manage_goal
  operation: "link_nodes"
  goal_id: "<each active goal>"
  node_ids: '["nd_handoff"]'
```

### Steps (Receiving Agent)

```
Step 1 — Retrieve handoff context
──────────────────────────────────
Tool: retrieve_context
  query: "agent handoff briefing and active work"
  limit: 5
  node_type: "episodic"
  min_score: 0.3

→ Read the handoff briefing node
```

```
Step 2 — Follow Workflow B (Warm Resume)
────────────────────────────────────────
List active goals, survey attention, orient.
```

```
Step 3 — Continue from the sending agent's last state
─────────────────────────────────────────────────────
The graph IS the handoff. The receiving agent now has:
  - Full goal state (from manage_goal list_goals)
  - Knowledge built by the prior agent (from retrieve_context)
  - Outcome history (confidence levels reflect successes/failures)
  - Explicit handoff briefing (from the episodic handoff node)

Proceed with whatever workflow matches the current objective.
```

---

## Workflow L — Trace Evidence for Decision Explainability

> **When:** Before high-stakes actions, after deliberation, when the user asks
> "why did you conclude X?", or when auditing reasoning chains.
>
> **Tools used:** `retrieve_context`, `trace_evidence_path`, `query_graph`, `store_node`

```
# 1. Identify the two endpoints to trace between
retrieve_context(query: "the decision or conclusion in question")
→ Find the conclusion node ID and the source evidence node ID

# 2. Trace the evidence path
trace_evidence_path(from: "<source_id>", to: "<conclusion_id>", k: 3)
→ Returns K lowest-cost paths with per-edge cost breakdown

# 3. Interpret the results
For each path:
  - total_cost < 1.0 → strong, direct evidence chain ✓
  - total_cost > 3.0 → weak or indirect — investigate
  - any "contradicts" edge → the chain passes through a known conflict ⚠
  - multiple diverse paths → conclusion has robust multi-source support ✓

# 4. If a contradicts edge appears in the path:
query_graph(operation: "get_node", node_id: "<node_before_contradiction>")
query_graph(operation: "get_node", node_id: "<node_after_contradiction>")
→ Inspect both sides of the contradiction

# 5. Report the chain to the user in natural language
"Node A → B → C → D, cost 0.42: A -[causal, conf 0.9]→ B -[supports, conf 0.8]→ C -[causal, conf 0.7]→ D"

# 6. Optionally store the audit as episodic knowledge
store_node(
  content: "Evidence trace from <source> to <conclusion>: 3 hops, total cost 0.42, no contradictions",
  node_type: "episodic",
  confidence: 0.8,
  source: "trace_evidence_path audit"
)
```

### Variations

**Post-deliberation verification:**
```
deliberate(query: "...", write_back: true)
→ Get conclusion node ID from response
trace_evidence_path(from: "<original_evidence>", to: "<conclusion_id>")
→ Verify the crystallized conclusion connects back to source
topology_analyze(query: "...")
→ Confirm κ dropped after crystallization
```

**Bidirectional vs directed tracing:**
```
# Default: bidirectional (follows edges in both directions)
trace_evidence_path(from: "<a>", to: "<b>")

# Strict causal direction only (A caused B, not B caused A)
trace_evidence_path(from: "<a>", to: "<b>", bidirectional: false)
```

**Recency-weighted tracing:**
```
# Strongly prefer recent evidence (24h half-life)
trace_evidence_path(from: "<a>", to: "<b>", half_life_hours: 24.0)
```

---

## Workflow Composition — Combining Recipes

These workflows are designed to compose. Here are common compositions:

### Project Onboarding (Full)

```
1. Workflow A (Cold Start)
2. Workflow D (Explore and Map a Codebase)
3. Workflow J (Teach Domain Knowledge — user fills in what code can't show)
4. Workflow H (Maintenance — consolidate after heavy seeding)
5. Workflow I (End-of-Session Cleanup)
```

### Daily Continuation Session

```
1. Workflow B (Warm Resume)
2. Workflow E (Ralph Loop — iterate on active goals)
3. Workflow I (End-of-Session Cleanup)
```

### Bug Fix Session

```
1. Workflow B (Warm Resume)
2. Workflow F (Debug with persistent memory)
3. Workflow G (Resolve Contradictions — if debugging reveals conflicting knowledge)
4. Workflow I (End-of-Session Cleanup)
```

### Knowledge Curation Session

```
1. Workflow B (Warm Resume)
2. Workflow H (Maintenance — audit and clean)
3. Workflow G (Resolve Contradictions — address any found during audit)
4. Workflow J (Teach Domain Knowledge — user adds missing information)
5. Workflow I (End-of-Session Cleanup)
```

### Agent Relay (Multi-Agent Pipeline)

```
Agent 1:
  1. Workflow A or B (Start)
  2. Workflow E (Ralph Loop — iteration 1-5)
  3. Workflow K (Handoff — sending)

Agent 2:
  1. Workflow K (Handoff — receiving)
  2. Workflow E (Ralph Loop — iteration 6-10)
  3. Workflow K or I (Handoff or Cleanup)
```

---

## Workflow Selection Guide

Use this decision tree to pick the right workflow:

```
Is this a new session?
├── Yes → Is the graph empty?
│   ├── Yes → Workflow A (Cold Start)
│   └── No  → Workflow B (Warm Resume)
│
├── User asking a question? → Workflow C (Answer from Memory)
│
├── User wants codebase exploration? → Workflow D (Explore Codebase)
│
├── Autonomous goal-driven work? → Workflow E (Ralph Loop)
│
├── Debugging a problem? → Workflow F (Debug with Memory)
│
├── Found contradictions? → Workflow G (Resolve Contradictions)
│
├── Graph needs housekeeping? → Workflow H (Maintenance)
│
├── Session ending? → Workflow I (End-of-Session Cleanup)
│
├── User teaching new domain? → Workflow J (Teach Domain)
│
└── Handing off to another agent? → Workflow K (Multi-Agent Handoff)
```

---

## Tool Call Frequency Guide

How often to call each tool during a typical productive session:

| Tool | Frequency | When |
|------|-----------|------|
| `retrieve_context` | **Every few turns** | Before answering questions, before acting on goals |
| `store_node` | **Frequently** | After every significant discovery or user-provided fact |
| `store_edge` | **After node batches** | After storing 2+ related nodes |
| `learn_from_outcome` | **After every consequential action** | When you have causal_context and an outcome |
| `query_graph` | **As needed** | When inspecting specific nodes/edges or checking for duplicates |
| `manage_goal` | **Per project-level action** | Create/transition/progress at natural milestones |
| `review_goal` | **At decision points** | Before high-stakes actions, after learning phases |
| `topology_analyze` | **On suspicion** | When retrieval shows deliberate routing or contradictions |
| `trace_evidence_path` | **Before high-stakes actions / on demand** | When auditing reasoning chains, after deliberation, or for explainability |
| `deliberate` | **Rarely** | Only when κ > 0 and stakes are high |
| `run_consolidation` | **End of session / every ~5 iterations** | Periodic maintenance |
| `attention_survey` | **Session start / periodically** | To check what needs focus |
| `attention_run_cycle` | **When running autonomously** | To let the attention engine direct priorities |

---

## Summary

Every workflow follows the same fundamental rhythm:

```
  ORIENT   → What do I already know? (retrieve_context, list_goals)
  PLAN     → What should I do next? (review_goal, attention_survey)
  ACT      → Do the thing (bounded, specific actions)
  RECORD   → Store what I learned (store_node, store_edge, link_nodes)
  REFLECT  → Did it work? (learn_from_outcome, set_progress)
  MAINTAIN → Keep the graph healthy (run_consolidation)
```

The power of Graphonomous is in the **accumulation**. A single session's worth
of knowledge is useful. Hundreds of sessions' worth — with confidence scores
refined by outcomes, contradictions resolved by deliberation, and weak knowledge
pruned by consolidation — is transformative. Every workflow contributes to that
accumulation.