# Skill 04 — Goal Management

> **Tool:** `manage_goal`
> **Purpose:** Create, track, and manage durable goals that persist across sessions,
> restarts, and context switches. Goals are the backbone of autonomous, multi-step work.
> **Depends on:** [01_RETRIEVE_AND_REMEMBER.md](01_RETRIEVE_AND_REMEMBER.md) for storing
> knowledge nodes that get linked to goals.

---

## Why Goals Matter

Without goals, every conversation is a one-shot interaction. The LLM has no
memory of *intent* — what it was trying to accomplish, how far it got, or what
remains. Goals give you:

- **Persistence** — survive restarts, crashes, and session boundaries
- **Decomposition** — break big objectives into trackable sub-tasks
- **Progress tracking** — quantified 0.0–1.0 progress on each goal
- **Knowledge linkage** — connect goals to the graph nodes that support them
- **Lifecycle management** — transition goals through states as work progresses
- **Coverage review** — assess whether the graph has enough knowledge to act (see [05_COVERAGE_AND_REVIEW.md](05_COVERAGE_AND_REVIEW.md))

If you're doing anything that takes more than one turn — mapping a codebase,
building a feature, debugging a system, running an exploration — **create a goal**.

---

## The `manage_goal` Tool

`manage_goal` is a multi-operation tool. The `operation` parameter selects what
you want to do, and other parameters vary by operation.

### Operations at a Glance

| Operation | What It Does | Required Params | Key Optional Params |
|-----------|-------------|-----------------|---------------------|
| `create_goal` | Create a new goal | `payload` (must include `title`) | `payload.priority`, `payload.horizon`, `payload.parent_goal_id` |
| `get_goal` | Fetch a single goal by ID | `goal_id` | — |
| `list_goals` | List goals with optional filters | — | `payload` (filter object) |
| `update_goal` | Update goal fields | `goal_id` | `payload` (fields to update) |
| `delete_goal` | Remove a goal permanently | `goal_id` | — |
| `transition_goal` | Change goal status with metadata | `goal_id`, `status` | `metadata` |
| `set_progress` | Set numeric progress (0.0–1.0) | `goal_id`, `progress` | — |
| `link_nodes` | Link knowledge nodes to a goal | `goal_id`, `node_ids` | — |
| `unlink_nodes` | Remove node links from a goal | `goal_id`, `node_ids` | — |
| `review_goal` | Run epistemic coverage evaluation | `goal_id`, `signal` | `opts` |

> **Note:** The `review_goal` operation within `manage_goal` is a convenience
> entry point. For full coverage evaluation with decision policy application,
> use the dedicated `review_goal` tool instead — see [05_COVERAGE_AND_REVIEW.md](05_COVERAGE_AND_REVIEW.md).

---

## Goal Lifecycle

Goals move through these statuses:

```
                    ┌──────────┐
              ┌────►│ completed │
              │     └──────────┘
              │
┌──────────┐  │     ┌──────────┐     ┌──────────┐
│ proposed  ├──┴────►│  active  ├─────►│  failed  │
└──────────┘        └────┬─────┘     └──────────┘
     ▲                   │
     │                   │           ┌───────────┐
     │ (learn decision)  ├──────────►│ suspended  │
     │                   │           └───────────┘
     │                   │
     │                   │           ┌───────────┐
     └───────────────────┴──────────►│ abandoned  │
           (escalate or              └───────────┘
            manual abandon)
```

| Status | Meaning | Typical Transitions |
|--------|---------|-------------------|
| `proposed` | Goal exists but hasn't been started; may need more knowledge first | → `active`, → `abandoned` |
| `active` | Goal is being actively worked on | → `completed`, → `failed`, → `suspended`, → `abandoned` |
| `blocked` | Goal cannot proceed; awaiting external input or escalation | → `active`, → `abandoned` |
| `completed` | Goal achieved its criteria | Terminal state |
| `failed` | Goal was attempted but could not be achieved | Terminal state (or → retry via new goal) |
| `suspended` | Goal is paused; may resume later | → `active`, → `abandoned` |
| `abandoned` | Goal was dropped intentionally | Terminal state |

When using `review_goal`, the coverage decision maps to status transitions:

| Decision | Target Status | Meaning |
|----------|--------------|---------|
| `act` | `active` | Enough knowledge to proceed |
| `learn` | `proposed` | Need more information first |
| `escalate` | `blocked` | Cannot proceed without external help |

---

## Operation Details

### `create_goal` — Start Tracking Intent

#### When to Use

- Beginning a multi-step task (codebase exploration, feature build, debugging)
- The user describes something they want accomplished over time
- Decomposing a large objective into sub-goals
- You realize mid-conversation that the current work should be tracked

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"create_goal"` |
| `payload` | yes | string (JSON) | Must include `"title"`. Can include `"description"`, `"priority"`, `"horizon"`, `"parent_goal_id"`, `"completion_criteria"`, and any other metadata. |

#### Examples

**Simple goal:**
```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Map the authentication subsystem\", \"priority\": \"high\"}"
}
```

**Goal with horizon and criteria:**
```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Achieve 85% codebase coverage in knowledge graph\", \"priority\": \"high\", \"horizon\": \"medium\", \"completion_criteria\": {\"type\": \"progress_threshold\", \"target\": 0.85}, \"description\": \"Store semantic and procedural nodes covering all major modules, with confidence >= 0.7 on architectural facts.\"}"
}
```

**Sub-goal linked to parent:**
```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Map OTP supervision tree\", \"priority\": \"medium\", \"parent_goal_id\": \"goal_abc123\", \"horizon\": \"short\"}"
}
```

#### Response

```json
{
  "status": "ok",
  "operation": "create_goal",
  "result": {
    "id": "goal_xyz789",
    "title": "Map the authentication subsystem",
    "status": "proposed",
    "progress": 0.0,
    "priority": "high",
    "created_at": "2025-06-15T10:30:00Z",
    ...
  }
}
```

**Save the `id`!** You'll need it for every other goal operation.

#### Payload Field Guide

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | **Required.** Short, descriptive name for the goal. |
| `description` | string | Longer description of what the goal entails. |
| `priority` | string | `"low"`, `"medium"`, `"high"`, `"critical"` — helps attention ranking. |
| `horizon` | string | `"short"` (hours), `"medium"` (days), `"long"` (weeks+). |
| `parent_goal_id` | string | ID of parent goal for decomposition hierarchy. |
| `completion_criteria` | object | Structured criteria for when this goal is "done". |
| `tags` | array | Optional tags for filtering/categorization. |

---

### `get_goal` — Inspect a Single Goal

#### When to Use

- Checking current status and progress of a specific goal
- Reading goal metadata before deciding next steps
- Verifying a goal exists before linking or transitioning

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"get_goal"` |
| `goal_id` | yes | string | The goal's ID |

#### Example

```json
{
  "operation": "get_goal",
  "goal_id": "goal_xyz789"
}
```

---

### `list_goals` — Browse and Filter Goals

#### When to Use

- **Session startup** — see what goals are active from prior sessions
- Reviewing all goals before choosing what to work on next
- Filtering by status, priority, or other fields

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"list_goals"` |
| `payload` | no | string (JSON) | Filter object. Omit for all goals. |

#### Examples

**List all goals:**
```json
{
  "operation": "list_goals"
}
```

**Filter by status:**
```json
{
  "operation": "list_goals",
  "payload": "{\"status\": \"active\"}"
}
```

**Filter by priority:**
```json
{
  "operation": "list_goals",
  "payload": "{\"priority\": \"high\"}"
}
```

---

### `update_goal` — Modify Goal Fields

#### When to Use

- Refining a goal's description or criteria after learning more
- Changing priority as circumstances change
- Adding metadata fields discovered during work

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"update_goal"` |
| `goal_id` | yes | string | The goal's ID |
| `payload` | no | string (JSON) | Fields to update |

#### Example

```json
{
  "operation": "update_goal",
  "goal_id": "goal_xyz789",
  "payload": "{\"description\": \"Updated: focus on JWT and OAuth2 flows specifically\", \"priority\": \"critical\"}"
}
```

> **Note:** To change `status`, use `transition_goal` instead of `update_goal`.
> Status transitions may carry metadata and trigger policies.

---

### `delete_goal` — Permanently Remove a Goal

#### When to Use

- A goal was created in error
- The goal is no longer relevant and you want to declutter

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"delete_goal"` |
| `goal_id` | yes | string | The goal's ID |

#### Example

```json
{
  "operation": "delete_goal",
  "goal_id": "goal_xyz789"
}
```

> **Prefer `transition_goal` to status `"abandoned"` over deleting.** Deletion
> removes all history. Abandoning preserves the record of what was attempted.

---

### `transition_goal` — Change Goal Status

#### When to Use

- Moving a goal from `proposed` → `active` (starting work)
- Completing a goal: `active` → `completed`
- Pausing: `active` → `suspended`
- Recording failure: `active` → `failed`
- Resuming: `suspended` → `active`

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"transition_goal"` |
| `goal_id` | yes | string | The goal's ID |
| `status` | yes | string | Target status: `proposed`, `active`, `blocked`, `completed`, `failed`, `suspended`, `abandoned` |
| `metadata` | no | string (JSON) | Transition context — why the status changed, evidence |

#### Examples

**Activate a goal:**
```json
{
  "operation": "transition_goal",
  "goal_id": "goal_xyz789",
  "status": "active",
  "metadata": "{\"reason\": \"Coverage review returned act decision\", \"coverage_score\": 0.78}"
}
```

**Complete a goal with evidence:**
```json
{
  "operation": "transition_goal",
  "goal_id": "goal_xyz789",
  "status": "completed",
  "metadata": "{\"reason\": \"All authentication modules mapped\", \"nodes_created\": 14, \"average_confidence\": 0.82, \"completed_by\": \"exploration-session-2025-06-15\"}"
}
```

**Fail a goal:**
```json
{
  "operation": "transition_goal",
  "goal_id": "goal_xyz789",
  "status": "failed",
  "metadata": "{\"reason\": \"Source code not accessible — private repo with no credentials\", \"attempts\": 3}"
}
```

**Suspend a goal:**
```json
{
  "operation": "transition_goal",
  "goal_id": "goal_xyz789",
  "status": "suspended",
  "metadata": "{\"reason\": \"Blocked on external API documentation — waiting for team to share\", \"resume_condition\": \"API docs available\"}"
}
```

#### Best Practice: Always Include Metadata

Transition metadata creates a durable audit trail. Future sessions can read the
goal and understand *why* it's in its current state without needing conversation
history. Include:

- `reason` — human-readable explanation
- Evidence fields — counts, scores, identifiers
- Context — what session or iteration triggered the transition

---

### `set_progress` — Update Numeric Progress

#### When to Use

- Incrementally reporting progress as sub-tasks complete
- After storing new knowledge that advances a goal
- After an `learn_from_outcome` success that moves the needle

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"set_progress"` |
| `goal_id` | yes | string | The goal's ID |
| `progress` | yes | number | Value between 0.0 (not started) and 1.0 (complete) |

#### Examples

```json
{
  "operation": "set_progress",
  "goal_id": "goal_xyz789",
  "progress": 0.35
}
```

#### Progress Guidelines

| Progress | Meaning |
|----------|---------|
| 0.0 | Not started |
| 0.1–0.3 | Early exploration; initial structure understood |
| 0.3–0.5 | Core knowledge captured; key modules identified |
| 0.5–0.7 | Substantial coverage; most areas mapped |
| 0.7–0.85 | Near-complete; filling in gaps and verifying |
| 0.85–1.0 | Done or nearly done; high confidence across the board |

**Tip:** For decomposed goals, calculate parent progress as the weighted average
of sub-goal progress. Update the parent after updating any child.

---

### `link_nodes` — Connect Knowledge to Goals

#### When to Use

- After storing a node that's evidence for or relevant to a goal
- Connecting outcome nodes to the goal they advanced
- Building a knowledge map around a goal so `review_goal` can assess coverage

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"link_nodes"` |
| `goal_id` | yes | string | The goal's ID |
| `node_ids` | yes | string (JSON array) | Array of node IDs to link |

#### Example

```json
{
  "operation": "link_nodes",
  "goal_id": "goal_xyz789",
  "node_ids": "[\"nd_abc123\", \"nd_def456\", \"nd_ghi789\"]"
}
```

#### Why Linking Matters

Linked nodes serve multiple purposes:

1. **Coverage evaluation** — `review_goal` looks at linked nodes to assess whether
   you have enough knowledge to act. More linked, high-confidence nodes = higher coverage.
2. **Context retrieval** — when resuming a goal in a new session, linked nodes
   provide immediate relevant context.
3. **Progress justification** — linked nodes are the *evidence* behind your
   progress claims. "Progress is 0.6" is much more meaningful when 15 nodes
   are linked showing exactly what's been learned.

#### When to Link

Link a node to a goal when:

- The node was created as part of working on that goal
- The node provides evidence toward the goal's completion criteria
- The node represents a discovery that changes the goal's scope or approach
- The node is an outcome from an action taken in service of the goal

---

### `unlink_nodes` — Remove Node Links

#### When to Use

- A previously linked node turned out to be irrelevant
- Cleaning up after a goal pivot
- Removing contradicted or pruned nodes from goal linkage

#### Parameters

| Param | Required | Type | Description |
|-------|----------|------|-------------|
| `operation` | yes | string | `"unlink_nodes"` |
| `goal_id` | yes | string | The goal's ID |
| `node_ids` | yes | string (JSON array) | Array of node IDs to unlink |

#### Example

```json
{
  "operation": "unlink_nodes",
  "goal_id": "goal_xyz789",
  "node_ids": "[\"nd_outdated_node\"]"
}
```

---

## Goal Decomposition Patterns

### Pattern: Top-Down Decomposition

Start with a high-level goal and break it into sub-goals immediately.

```
1. Create parent goal
   manage_goal(operation: "create_goal",
     payload: '{"title": "Complete codebase comprehension", "priority": "high", "horizon": "medium"}')
   → goal_parent

2. Create sub-goals with parent_goal_id
   manage_goal(operation: "create_goal",
     payload: '{"title": "Map module architecture", "parent_goal_id": "goal_parent", "horizon": "short"}')
   → goal_arch

   manage_goal(operation: "create_goal",
     payload: '{"title": "Document build and test workflows", "parent_goal_id": "goal_parent", "horizon": "short"}')
   → goal_build

   manage_goal(operation: "create_goal",
     payload: '{"title": "Identify integration points and APIs", "parent_goal_id": "goal_parent", "horizon": "short"}')
   → goal_api

   manage_goal(operation: "create_goal",
     payload: '{"title": "Catalog risks and unknowns", "parent_goal_id": "goal_parent", "horizon": "short"}')
   → goal_risk

3. Activate the first sub-goal you want to work on
   manage_goal(operation: "transition_goal", goal_id: "goal_arch", status: "active")
```

### Pattern: Progressive Decomposition

Start with the parent and discover sub-goals as you explore.

```
1. Create parent goal, activate it
2. Begin working
3. When you discover a distinct sub-task:
   create it as a sub-goal with parent_goal_id
4. Link relevant discovered nodes to both parent and sub-goal
5. Repeat as the problem reveals structure
```

### Pattern: Iterative Refinement (Ralph Loop)

For autonomous iteration:

```
For each iteration:
  1. list_goals to find highest-priority active goal
  2. retrieve_context for the goal's topic
  3. Take bounded actions (explore, code, analyze)
  4. store_node for each discovery
  5. link_nodes to goal
  6. learn_from_outcome for the iteration
  7. set_progress based on evidence
  8. review_goal to decide: act / learn / escalate
  9. If act → continue. If learn → gather more. If escalate → switch goals.
```

---

## Session Startup: Resuming Goals

When starting a new session where prior goals may exist:

```
Step 1: List active goals
  manage_goal(operation: "list_goals", payload: '{"status": "active"}')

Step 2: For each active goal, retrieve linked context
  retrieve_context(query: "<goal title or description>")

Step 3: Check progress and decide where to pick up
  manage_goal(operation: "get_goal", goal_id: "<id>")

Step 4: Resume work on the highest-priority active goal
```

This pattern gives you continuity across sessions without requiring the user
to re-explain what they were working on.

---

## Complete Workflow Example

Here's a realistic end-to-end scenario showing multiple goal operations together.

### Scenario: User asks to "understand the payment system"

**1. Create the parent goal:**

```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Understand the payment processing system\", \"priority\": \"high\", \"horizon\": \"medium\", \"description\": \"Map all payment-related modules, flows, error handling, and integrations.\"}"
}
```
→ Returns `goal_id: "goal_pay_001"`

**2. Create sub-goals:**

```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Map payment module structure\", \"parent_goal_id\": \"goal_pay_001\", \"horizon\": \"short\"}"
}
```
→ `goal_id: "goal_pay_s1"`

```json
{
  "operation": "create_goal",
  "payload": "{\"title\": \"Document payment processing flow\", \"parent_goal_id\": \"goal_pay_001\", \"horizon\": \"short\"}"
}
```
→ `goal_id: "goal_pay_s2"`

**3. Activate and start working:**

```json
{
  "operation": "transition_goal",
  "goal_id": "goal_pay_001",
  "status": "active",
  "metadata": "{\"reason\": \"User requested payment system analysis\"}"
}
```

```json
{
  "operation": "transition_goal",
  "goal_id": "goal_pay_s1",
  "status": "active",
  "metadata": "{\"reason\": \"Starting with structural mapping\"}"
}
```

**4. Do work, store knowledge, link to goal:**

After exploring the relevant code, store findings:

```
store_node(content: "Payment processing lives in src/payments/ with 6 modules: charges.ts, refunds.ts, subscriptions.ts, webhooks.ts, stripe_client.ts, and types.ts", ...)
→ node_id: "nd_pay_001"

store_node(content: "stripe_client.ts wraps the Stripe SDK with retry logic (3 attempts, exponential backoff starting at 200ms)", ...)
→ node_id: "nd_pay_002"
```

Link nodes to the sub-goal:

```json
{
  "operation": "link_nodes",
  "goal_id": "goal_pay_s1",
  "node_ids": "[\"nd_pay_001\", \"nd_pay_002\"]"
}
```

**5. Update progress:**

```json
{
  "operation": "set_progress",
  "goal_id": "goal_pay_s1",
  "progress": 0.4
}
```

**6. After sub-goal complete, transition it:**

```json
{
  "operation": "transition_goal",
  "goal_id": "goal_pay_s1",
  "status": "completed",
  "metadata": "{\"nodes_linked\": 8, \"modules_mapped\": 6, \"average_confidence\": 0.85}"
}
```

**7. Update parent progress:**

```json
{
  "operation": "set_progress",
  "goal_id": "goal_pay_001",
  "progress": 0.5
}
```

**8. Move to next sub-goal, repeat.**

---

## Common Mistakes

| Mistake | Why It's Bad | Fix |
|---------|-------------|-----|
| Not creating goals for multi-step work | Progress is lost between sessions | Create a goal whenever work spans multiple turns |
| Creating goals without titles | The `create_goal` call will fail | Always include `"title"` in the payload |
| Using `update_goal` to change status | Loses transition metadata / audit trail | Use `transition_goal` for status changes |
| Deleting goals instead of abandoning | Loses historical record | Transition to `abandoned` with a reason |
| Setting progress without linking nodes | Progress claim has no evidence | Link supporting nodes before bumping progress |
| Never listing goals at session start | Lose continuity, duplicate work | Always `list_goals` at the start of project sessions |
| Creating one giant monolithic goal | Hard to track, hard to review coverage | Decompose into focused sub-goals with a parent |
| Not including transition metadata | Future sessions can't understand why goal is in current state | Always provide `reason` and evidence in metadata |
| Forgetting to update parent progress | Parent goal shows 0% while sub-goals at 80% | Update parent after each sub-goal progress change |

---

## Goals + Other Tools — Integration Map

| After This... | Do This... | Why |
|---------------|-----------|-----|
| `store_node` (relevant to goal) | `manage_goal` → `link_nodes` | Connect evidence to intent |
| `learn_from_outcome` (success) | `manage_goal` → `set_progress` | Advance progress based on verified outcome |
| `review_goal` → `act` | `manage_goal` → `transition_goal` → `active` | Coverage is sufficient, proceed |
| `review_goal` → `learn` | `retrieve_context` → explore → `store_node` | Need more knowledge before acting |
| `review_goal` → `escalate` | `manage_goal` → `transition_goal` → `blocked` | Can't proceed, need external help |
| `attention_survey` shows high-urgency goal | `manage_goal` → `get_goal`, then resume work | Attention engine is directing focus |
| All sub-goals `completed` | `manage_goal` → `transition_goal` parent → `completed` | Roll up completion |
| Session ending | `manage_goal` → `set_progress` for any active goals | Preserve latest progress snapshot |

---

## Tips

1. **Name goals like you'd name a task in a project tracker.** Clear, specific,
   action-oriented: "Map the OTP supervision tree" not "look at code".

2. **Use horizons to communicate urgency.** `short` = should finish this session.
   `medium` = across a few sessions. `long` = ongoing effort.

3. **Link aggressively.** Every node you create while working on a goal should be
   linked to that goal. This is what makes `review_goal` and coverage scoring
   accurate.

4. **Review goals before acting.** Use `review_goal` (see Skill 05) to check
   whether you have adequate knowledge before taking high-stakes actions.

5. **Use `list_goals` as your "where was I?"** At the start of any continuation
   session, listing active goals is the fastest way to regain context.

6. **Don't over-decompose.** 3–6 sub-goals per parent is usually right. If you
   have 20 sub-goals, some should be grouped under intermediate goals.

7. **Transition metadata is your session log.** Record significant decisions,
   evidence, and reasoning in transition metadata. It's the most durable
   record of *why* a goal ended up in its current state.