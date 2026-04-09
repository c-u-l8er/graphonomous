---
name: workflows
description: Use when the user asks "how do I use graphonomous for X?", wants end-to-end recipes, or needs guidance on common multi-step patterns like cold start, codebase exploration, debugging, or autonomous iteration.
argument-hint: [cold-start|warm-resume|question|explore|debug|ralph-loop|contradictions|maintenance|end-session|teach|handoff]
---

# Graphonomous Workflows

End-to-end recipes for common tasks. Pick the workflow that matches your situation.

## Arguments

Workflow type: $ARGUMENTS

## Cold Start (empty graph)
1. `retrieve(action: "context", query: "project overview")` — confirm empty
2. `act(action: "manage_goal", operation: "create_goal", payload: {"title": "Orient on project", "horizon": "short"})`
3. Explore code/docs → `act(action: "store_node", ...)` for each key finding
4. Link nodes with `act(action: "store_edge", ...)` where relationships improve retrieval
5. `act(action: "manage_goal", operation: "set_progress", goal_id: "<id>", progress: 0.5)`
6. `consolidate(action: "run")`

## Warm Resume (existing knowledge)
1. `act(action: "manage_goal", operation: "list_goals", filters: {"status": "active"})`
2. `route(action: "attention_survey", include_idle: false)`
3. Pick top attention item or follow user request
4. `retrieve(action: "context", query: "<current topic>")`
5. Continue working with context, saving `causal_context`

## Answer a Question
1. `retrieve(action: "context", query: "<the question>")` — save `causal_context`
2. Check `topology.routing` — if `"deliberate"`, run `route(action: "deliberate", query: "...")`
3. Optionally `retrieve(action: "coverage", query: "...")` for quick act/learn/escalate pre-check
4. Answer using retrieved knowledge + current conversation
5. `act(action: "store_node", node_type: "semantic", content: "...", source: "conversation")`
6. If user confirms → `learn(action: "from_outcome", status: "success", causal_node_ids: [...])`

## Explore a Codebase
1. Create parent goal: `act(action: "manage_goal", operation: "create_goal", payload: {"title": "Explore <repo>"})`
2. Create sub-goals per module (3–6), each with `parent_goal_id`
3. For each module: explore → `act(action: "store_node", ...)` → `act(action: "store_edge", ...)`
4. Use `consolidate(action: "traverse", start_node_id: "<id>", max_depth: 2)` to walk related knowledge
5. `act(action: "manage_goal", operation: "link_nodes", ...)` — link findings to sub-goals
6. `act(action: "manage_goal", operation: "set_progress", ...)` after each module
7. `route(action: "review_goal", ...)` on parent when all sub-goals done

## Debug a Problem
1. `retrieve(action: "context", query: "prior context on <issue>")` — save `causal_context`
2. Isolate the issue using retrieved context
3. Test fix
4. `act(action: "store_node", node_type: "episodic", content: "...")`
5. `learn(action: "from_outcome", status: "success"|"failure", causal_node_ids: [...])` with real IDs
6. Link to goal if applicable

## Resolve Contradictions
1. Detect: `retrieve` returns nodes with `contradicts` edges, or `routing: "deliberate"`
2. Diagnose: `route(action: "topology", query: "<topic>")` — examine SCCs and fault-line edges
3. Deliberate: `route(action: "deliberate", query: "<the contradiction>", write_back: true)`
4. Verify: `route(action: "topology", ...)` again — confirm κ decreased
5. Store resolution as semantic node if not already written back

## Ralph Loop (autonomous iteration)
1. `route(action: "attention_survey")` → pick top item
2. `retrieve(action: "context", ...)` for that goal — save `causal_context`
3. Act on it
4. `learn(action: "from_outcome", ...)` with real causal IDs
5. `route(action: "review_goal", ...)` → follow act/learn/escalate decision
6. Advance to next attention item
7. Repeat; `consolidate(action: "run")` every 4–5 cycles

## Maintenance
1. `consolidate(action: "stats")` — check overall graph health
2. `consolidate(action: "run")`
3. `act(action: "manage_goal", operation: "list_goals")` — review all goals
4. Re-review any active goals near completion thresholds
5. Transition stale goals to `suspended` or `abandoned` with metadata

## Teach a Domain
1. `act(action: "manage_goal", operation: "create_goal", payload: {"title": "Learn <domain>"})`
2. User provides info → `act(action: "store_node", ...)` for each fact/procedure
3. `act(action: "store_edge", ...)` to connect related concepts
4. `act(action: "manage_goal", operation: "link_nodes", ...)` — link all nodes to goal
5. Build out recursively until coverage review returns `act`

## Multi-Agent Handoff
1. Prepare state snapshot: `act(action: "manage_goal", operation: "list_goals")`
2. For each active goal: `act(action: "manage_goal", operation: "get_goal", goal_id: "<id>")`
3. Include linked nodes, progress, outcomes, and coverage state
4. Recipient resumes with `/graphonomous:bootstrap` to load context

## End of Session
1. Store pending knowledge: `act(action: "store_node", ...)`
2. Report outcomes: `learn(action: "from_outcome", ...)`
3. Update goal progress: `act(action: "manage_goal", operation: "set_progress", ...)`
4. Consolidate: `consolidate(action: "run")`
