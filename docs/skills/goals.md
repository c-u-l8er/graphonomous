---
name: goals
description: Use when the user wants to "create a goal", "track progress", "list goals", "update goal", "check goals", "what are my goals", or for any multi-step work spanning multiple turns. Durable intent tracking that survives restarts. Routes through the `act` machine.
argument-hint: [create|list|get|transition|progress|link] [details]
---

# Goal Management

Track durable intent across sessions — create goals, update progress, link knowledge.

## Arguments

Operation and details: $ARGUMENTS

## Operations

### Create a goal
```
act(action: "manage_goal", operation: "create_goal", payload: {
  "title": "Implement auth middleware",
  "description": "Add JWT-based auth to all API routes",
  "priority": "high",
  "horizon": "short",
  "parent_goal_id": "<parent-id>",
  "completion_criteria": ["All routes require valid JWT", "Tests pass"],
  "tags": ["auth", "security"]
})
```

**Payload fields:**
- `title` (required) — concise goal name
- `description` — detailed explanation
- `priority` — `"low"`, `"medium"`, `"high"`, `"critical"`
- `horizon` — `"short"` (hours), `"medium"` (days), `"long"` (weeks+)
- `parent_goal_id` — for sub-goal decomposition (critical for large goals)
- `completion_criteria` — array of success conditions
- `tags` — array of labels for filtering

Save the returned `goal_id`.

### Get a specific goal
```
act(action: "manage_goal", operation: "get_goal", goal_id: "<id>")
```
Returns full goal state: status, progress, linked nodes, metadata, timestamps.

### List goals
```
act(action: "manage_goal", operation: "list_goals", filters: {"status": "active"})
```
Filter by: `status`, `priority`, `tags`. Status values: `proposed`, `active`, `blocked`, `completed`, `failed`, `suspended`, `abandoned`.

### Transition goal status
```
act(action: "manage_goal", operation: "transition_goal", goal_id: "<id>", new_status: "completed", metadata: {
  "reason": "All completion criteria met",
  "evidence": ["test-suite-passed", "coverage-review-act"],
  "context": "session-2026-03-28"
})
```
Always use `transition_goal` (not `update_goal`) for status changes — provides audit trail. Include `reason` and evidence in metadata.

### Set progress
```
act(action: "manage_goal", operation: "set_progress", goal_id: "<id>", progress: 0.6, metadata: {
  "basis": "3 of 5 sub-goals completed"
})
```

**Progress benchmarks (base on evidence, not optimism):**
- 0.0 — not started
- 0.1-0.3 — early exploration, initial nodes stored
- 0.3-0.5 — core knowledge captured, key sub-goals active
- 0.5-0.7 — substantial coverage, most sub-goals done
- 0.7-0.9 — near complete, verifying/testing
- 1.0 — all criteria met

### Link knowledge to goals
```
act(action: "manage_goal", operation: "link_nodes", goal_id: "<id>", node_ids: ["<node1>", "<node2>"])
```
Every node created for a goal should be linked. `route(action: "review_goal")` uses linked nodes to assess coverage — unlinked knowledge is invisible to coverage evaluation.

## Goal lifecycle

```
proposed -> active -> completed
                   -> failed
                   -> suspended -> active (resume)
                   -> abandoned
          -> blocked -> active (unblock)
```

**Key:** `blocked` is for escalation — when coverage review says `escalate` or external help is needed. Use `transition_goal` with metadata explaining the blocker.

## Decomposition

Large goals should be split into 3-6 focused sub-goals using `parent_goal_id`:
```
act(action: "manage_goal", operation: "create_goal", payload: {
  "title": "Implement JWT validation",
  "parent_goal_id": "<parent-auth-goal-id>",
  "priority": "high",
  "horizon": "short"
})
```

## Session startup pattern
1. `act(action: "manage_goal", operation: "list_goals", filters: {"status": "active"})`
2. `act(action: "manage_goal", operation: "get_goal", goal_id: "<top-priority-id>")`
3. Resume work with context from linked nodes

## Anti-patterns to avoid

- Goal monolith — one giant goal instead of 3-6 sub-goals
- Orphan goals — creating goals but never linking nodes or updating progress
- Progress fantasy — setting progress based on optimism, not evidence
- Status shortcuts — using `update_goal` instead of `transition_goal` for status changes
- Ignoring `blocked` — not escalating when coverage is insufficient
