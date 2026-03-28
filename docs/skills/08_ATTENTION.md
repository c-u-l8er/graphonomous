# Skill 08 — Attention

> **Tools covered:** `attention_survey`, `attention_run_cycle`
> **Purpose:** Autonomous focus management — survey what needs attention, rank
> priorities across goals, and optionally dispatch actions based on an autonomy level.
> **Depends on:** [04_GOAL_MANAGEMENT.md](04_GOAL_MANAGEMENT.md) (goals feed the attention system),
> [05_COVERAGE_AND_REVIEW.md](05_COVERAGE_AND_REVIEW.md) (coverage scores feed priority ranking),
> [06_TOPOLOGY_AND_DELIBERATION.md](06_TOPOLOGY_AND_DELIBERATION.md) (κ-aware routing informs dispatch)

---

## Why This Matters

When you have multiple active goals, the question isn't just "what should I
do?" — it's "what should I do **first**?" The attention system answers this by
continuously ranking goals based on:

- **Urgency** — how time-sensitive is this goal?
- **Knowledge gaps** — how much is unknown vs. known?
- **Coverage decision** — does the graph say `act`, `learn`, or `escalate`?
- **Topology** — are there unresolved cycles (κ > 0) blocking progress?

The result is a **prioritized attention map** that tells you which goals need
focus right now, what kind of focus they need, and — at higher autonomy levels —
takes action on your behalf.

Think of it as a project manager that watches your goal board and says: "This
goal is urgent, has adequate knowledge, and the topology is clean — act on it
now. That goal over there has gaps and circular reasoning — it needs learning
and deliberation before you touch it."

---

## Two Tools, Two Purposes

| Tool | Purpose | Modifies State? |
|------|---------|----------------|
| `attention_survey` | **Read-only.** Returns the current ranked attention map. | No |
| `attention_run_cycle` | **Active.** Runs a full survey → triage → dispatch cycle. | Potentially, depending on autonomy level |

Use `attention_survey` when you want to *see* what needs attention.
Use `attention_run_cycle` when you want to *act* on what needs attention.

---

## Autonomy Levels

The attention system operates at one of three autonomy levels that control how
much it does on its own:

| Level | Behavior | When to Use |
|-------|----------|-------------|
| **`observe`** | Survey and rank only. No actions taken. | Default. Safe for inspection. Use when you want to decide what to do yourself. |
| **`advise`** | Survey, rank, and suggest actions. Does not execute them. | When you want recommendations but retain control over execution. |
| **`act`** | Survey, rank, and dispatch actions autonomously. | When you trust the system to take action on high-priority items without confirmation. |

The autonomy level is typically configured at the system level, but
`attention_run_cycle` lets you override it per-call for experimentation or
escalation.

---

## Tool Reference: `attention_survey`

### Purpose

Returns the current ranked attention map — a prioritized list of goals that
need focus, annotated with coverage scores, topology routing, and dispatch
recommendations.

This is **read-only**. It does not change any goal state, execute any actions,
or trigger any side effects. Call it as often as you like.

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `include_idle` | no | boolean | `false` | Include goals that don't currently need action (`dispatch_mode: idle`). By default, only actionable items are returned. |

### Examples

**See what needs attention (actionable items only):**

```json
{
}
```

Or equivalently:

```json
{
  "include_idle": false
}
```

**See everything, including idle goals:**

```json
{
  "include_idle": true
}
```

### Response Shape

```json
{
  "status": "ok",
  "attention_items": [
    {
      "goal_id": "goal_auth_001",
      "goal_title": "Map authentication subsystem",
      "attention_score": 0.872,
      "dispatch_mode": "act",
      "coverage_score": 0.78,
      "coverage_decision": "act",
      "decision_confidence": 0.74,
      "max_kappa": 0,
      "routing": "fast",
      "coverage_rationale": [
        "Coverage score 0.78 above act threshold (0.60)",
        "Mean confidence of relevant nodes: 0.81",
        "No contradictions detected"
      ],
      "attention_rationale": "Urgency=0.8, gap=0.22, coverage_decision=act, κ=0, routing=fast."
    },
    {
      "goal_id": "goal_deploy_002",
      "goal_title": "Document deployment pipeline",
      "attention_score": 0.654,
      "dispatch_mode": "learn",
      "coverage_score": 0.42,
      "coverage_decision": "learn",
      "decision_confidence": 0.58,
      "max_kappa": 1,
      "routing": "deliberate",
      "coverage_rationale": [
        "Coverage score 0.42 below act threshold (0.60)",
        "2 knowledge gaps identified",
        "1 contradiction found"
      ],
      "attention_rationale": "Urgency=0.6, gap=0.58, coverage_decision=learn, κ=1, routing=deliberate."
    }
  ],
  "autonomy_level": "observe",
  "next_heartbeat_in_ms": 300000
}
```

### Key Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `attention_items` | array | Ranked list of goals needing attention (highest attention_score first) |
| `attention_items[].goal_id` | string | The goal's ID — use with `manage_goal` and `review_goal` |
| `attention_items[].goal_title` | string | Human-readable goal title |
| `attention_items[].attention_score` | number (0.0–1.0) | Overall priority score. Higher = needs more attention now. |
| `attention_items[].dispatch_mode` | string | Recommended action type: `"act"`, `"learn"`, `"escalate"`, or `"idle"` |
| `attention_items[].coverage_score` | number (0.0–1.0) | How well the graph covers this goal's domain |
| `attention_items[].coverage_decision` | string | The coverage evaluator's recommendation: `"act"`, `"learn"`, or `"escalate"` |
| `attention_items[].decision_confidence` | number (0.0–1.0) | How confident the coverage decision is |
| `attention_items[].max_kappa` | number | Maximum κ value in the goal's knowledge region (0 = acyclic, >0 = cycles) |
| `attention_items[].routing` | string | Topology routing: `"fast"` or `"deliberate"` |
| `attention_items[].coverage_rationale` | array of strings | Human-readable coverage evaluation notes |
| `attention_items[].attention_rationale` | string | Compact summary of why this goal has its attention score |
| `autonomy_level` | string | Current system autonomy level: `"observe"`, `"advise"`, or `"act"` |
| `next_heartbeat_in_ms` | number | Milliseconds until the next automatic attention heartbeat |

### Understanding `dispatch_mode`

The `dispatch_mode` tells you what *kind* of action the goal needs:

| `dispatch_mode` | Meaning | What You Should Do |
|-----------------|---------|-------------------|
| `"act"` | Coverage is sufficient, topology is clean. Execute. | Pick up the goal and do its next action. |
| `"learn"` | Knowledge gaps or low confidence. Gather info first. | `retrieve_context` → explore → `store_node` → re-review |
| `"escalate"` | Graph can't cover this domain. Need external help. | Ask the user, consult external docs, or delegate to another agent. |
| `"idle"` | Goal doesn't need attention right now. | Skip it. Only visible when `include_idle: true`. |

### Understanding `attention_score`

The `attention_score` is a composite 0.0–1.0 value that combines:

- **Urgency** — derived from goal priority, horizon, and staleness
- **Gap** — `1.0 - coverage_score` — how much knowledge is missing
- **Topology complexity** — higher κ adds urgency for deliberation
- **Staleness** — goals that haven't been worked on recently get a boost

Higher attention_score = "focus on me first."

Items are returned sorted by `attention_score` descending, so the first item
in the array is always the highest-priority one.

### Understanding `attention_rationale`

Each item includes a compact rationale string showing the raw dimensions
that feed into the attention score:

```
"Urgency=0.8, gap=0.22, coverage_decision=act, κ=0, routing=fast."
```

This tells you:
- **Urgency=0.8** — high urgency (maybe high priority + short horizon)
- **gap=0.22** — small knowledge gap (1.0 - 0.78 coverage)
- **coverage_decision=act** — the coverage evaluator says proceed
- **κ=0** — no cycles in the knowledge region
- **routing=fast** — normal retrieval is fine (no deliberation needed)

Compare to a goal in need of deliberation:

```
"Urgency=0.6, gap=0.58, coverage_decision=learn, κ=1, routing=deliberate."
```

This goal has a large gap, needs more knowledge, and its knowledge region
has a cycle requiring deliberation.

---

## Tool Reference: `attention_run_cycle`

### Purpose

Triggers a full attention cycle: **survey → triage → dispatch**. This is the
active counterpart to `attention_survey`. Depending on the autonomy level, it
may take actions on goals (dispatch), not just report on them.

### Parameters

| Param | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `autonomy_override` | no | string | — | Override the system autonomy level for this cycle only. One of: `"observe"`, `"advise"`, `"act"`. If omitted, uses the current system default. |

### Examples

**Run with system default autonomy:**

```json
{
}
```

**Run in observe mode (safe — no side effects):**

```json
{
  "autonomy_override": "observe"
}
```

**Run in advise mode (get recommendations without execution):**

```json
{
  "autonomy_override": "advise"
}
```

**Run in act mode (execute recommended actions):**

```json
{
  "autonomy_override": "act"
}
```

### Response Shape

```json
{
  "status": "ok",
  "autonomy_override": "advise",
  "cycle": {
    "surveyed_count": 5,
    "actionable_count": 3,
    "dispatched_count": 0,
    "items": [
      {
        "goal_id": "goal_auth_001",
        "goal_title": "Map authentication subsystem",
        "attention_score": 0.872,
        "dispatch_mode": "act",
        "dispatched": false,
        "advice": "Coverage is adequate (0.78). Proceed to map remaining auth modules: OAuth2 provider integration, session management."
      },
      {
        "goal_id": "goal_deploy_002",
        "goal_title": "Document deployment pipeline",
        "attention_score": 0.654,
        "dispatch_mode": "learn",
        "dispatched": false,
        "advice": "Coverage gaps detected (0.42). Retrieve context for: CI/CD configuration, container orchestration, environment variable management."
      }
    ],
    "cycle_duration_ms": 342
  },
  "attention_status": {
    "autonomy_level": "observe",
    "next_heartbeat_in_ms": 300000,
    "last_cycle_at": "2025-06-15T14:30:00Z",
    "total_cycles_run": 12
  }
}
```

### Key Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `autonomy_override` | string or null | The override that was applied for this cycle (null if using system default) |
| `cycle.surveyed_count` | number | How many goals were surveyed |
| `cycle.actionable_count` | number | How many goals have `dispatch_mode` ≠ idle |
| `cycle.dispatched_count` | number | How many goals had actions dispatched (only > 0 at `act` autonomy) |
| `cycle.items[]` | array | The prioritized attention items with dispatch info |
| `cycle.items[].dispatched` | boolean | Whether an action was actually dispatched for this item |
| `cycle.items[].advice` | string | Recommendation string (populated at `advise` or `act` levels) |
| `cycle.cycle_duration_ms` | number | How long the cycle took to run |
| `attention_status` | object | Current attention engine state |
| `attention_status.autonomy_level` | string | The system-level autonomy setting |
| `attention_status.next_heartbeat_in_ms` | number | Ms until next automatic heartbeat |
| `attention_status.last_cycle_at` | string (ISO 8601) | When the last cycle ran |
| `attention_status.total_cycles_run` | number | Cumulative cycle count since startup |

### Autonomy Level Behavior During a Cycle

| Level | Survey | Triage | Dispatch |
|-------|--------|--------|----------|
| `observe` | ✅ rank all goals | ✅ assign dispatch_mode | ❌ no execution |
| `advise` | ✅ rank all goals | ✅ assign dispatch_mode | ❌ no execution, but generates `advice` strings |
| `act` | ✅ rank all goals | ✅ assign dispatch_mode | ✅ top-priority items may be dispatched |

At `observe` and `advise` levels, `dispatched_count` will always be 0 and
`items[].dispatched` will always be `false`. The key difference between
`observe` and `advise` is that `advise` populates the `advice` field with
concrete recommended next steps for each item.

At `act` level, the system may automatically execute actions like:
- Triggering consolidation for goals with stale knowledge
- Running retrieval for goals in `learn` mode
- Marking goals as blocked for `escalate` items

---

## When to Use Each Tool

### `attention_survey` — Use for:

- **Session startup** — "What should I focus on?" Check the ranked list
  before asking the user or picking up prior work.
- **Mid-session check** — "Has anything changed?" Re-survey to see if
  priorities shifted after new knowledge was stored or outcomes reported.
- **Status reporting** — "What's the state of all our goals?" Show the user
  a prioritized dashboard of what needs attention.
- **Before goal selection** — When you have multiple active goals, survey
  to pick the highest-attention one.

### `attention_run_cycle` — Use for:

- **Autonomous iteration** — In a Ralph Loop or autonomous agent context,
  run a cycle at the start of each iteration to determine focus.
- **Escalation** — When stuck on a goal, run a cycle with `autonomy_override: "advise"`
  to get concrete suggestions about what to do next.
- **Periodic maintenance** — Run a cycle with `autonomy_override: "act"`
  periodically to let the system handle routine goal hygiene (marking
  blocked goals, triggering retrieval for learning goals, etc.).
- **System health check** — The response includes `attention_status` with
  runtime info about the attention engine itself.

---

## Common Patterns

### Pattern 1: Session Startup — "Where Was I?"

At the start of a new session, combine goal listing with attention survey
to regain context and choose focus:

```
Step 1: Survey attention
  attention_survey(include_idle: false)
  → Items ranked by attention_score

Step 2: Pick top item
  The first item has goal_id "goal_xyz" with dispatch_mode "act"

Step 3: Retrieve context for that goal
  retrieve_context(query: "<goal title or topic>")

Step 4: Resume work on the goal
```

This is the **recommended session startup pattern** whenever the Graphonomous
MCP server is connected and goals exist from prior sessions.

### Pattern 2: Autonomous Iteration (Ralph Loop)

In each iteration of an autonomous exploration loop:

```
Step 1: Run attention cycle
  attention_run_cycle(autonomy_override: "advise")
  → Get ranked items with concrete advice

Step 2: Select the top-priority item

Step 3: Follow the dispatch_mode:
  - "act" → execute the goal's next action
  - "learn" → retrieve more context, store knowledge
  - "escalate" → route to user or multi-agent deliberation

Step 4: After acting, report outcome
  learn_from_outcome(...)

Step 5: Update goal progress
  manage_goal(operation: "set_progress", ...)

Step 6: Re-survey or run another cycle
  (Loop back to Step 1)
```

### Pattern 3: Focus Shifting After Outcome

After a failed outcome decreases confidence on causal nodes:

```
Step 1: learn_from_outcome(status: "failure", ...)
  → Causal nodes have reduced confidence

Step 2: attention_survey()
  → The goal that relied on those nodes now has a lower coverage_score
  → Its dispatch_mode may have changed from "act" to "learn"
  → Another goal may now have a higher attention_score

Step 3: Respect the new ranking
  → Switch focus to the new top-priority item
  → Or address the knowledge gap for the original goal
```

### Pattern 4: Periodic Maintenance Cycle

Run a maintenance cycle with `act` autonomy at natural breakpoints (end of
session, after a batch of stores, after consolidation):

```
attention_run_cycle(autonomy_override: "act")
→ The system may:
  - Mark low-coverage goals as needing learning
  - Trigger retrieval for goals with stale knowledge
  - Flag goals for escalation if coverage is critically low
```

### Pattern 5: User Status Report

When the user asks "what's the status of everything?":

```
Step 1: attention_survey(include_idle: true)
  → Get ALL goals with attention info

Step 2: Format a report:
  🔴 High priority (attention > 0.7):
    - "Map auth subsystem" — ready to act (coverage 0.78)
    - "Fix deployment pipeline" — needs learning (coverage 0.42, κ=1)

  🟡 Medium priority (attention 0.4–0.7):
    - "Document API endpoints" — ready to act (coverage 0.65)

  🟢 Low priority / idle:
    - "Archive old logs" — idle
    - "Update README" — idle
```

### Pattern 6: Topology-Aware Goal Selection

When the attention survey shows a goal with `routing: "deliberate"`:

```
Step 1: attention_survey()
  → Item: goal_xyz, dispatch_mode: "learn", max_kappa: 2, routing: "deliberate"

Step 2: Before working on this goal, resolve the topology issue
  deliberate(
    query: "Resolve circular dependencies in knowledge about <goal topic>",
    write_back: true
  )

Step 3: Re-survey
  attention_survey()
  → Item: goal_xyz should now have lower or zero κ
  → dispatch_mode may have changed to "act" if deliberation improved coverage
```

---

## Attention Score Components

The `attention_score` is not a black box. It combines several dimensions,
each of which you can see in the response:

| Dimension | Source | High Value Means |
|-----------|--------|-----------------|
| **Urgency** | Goal priority, horizon, staleness | Goal is time-sensitive or overdue |
| **Gap** | `1.0 - coverage_score` | Large knowledge deficit — needs learning |
| **Coverage decision severity** | `escalate` > `learn` > `act` > `idle` | More severe decisions get more attention |
| **Topology complexity** | `max_kappa` | Unresolved cycles need resolution |
| **Staleness** | Time since last progress update | Neglected goals bubble up |

The `attention_rationale` string shows these raw dimensions for transparency:

```
"Urgency=0.8, gap=0.22, coverage_decision=act, κ=0, routing=fast."
```

---

## Attention + Coverage + Topology — How They Interact

The attention system synthesizes signals from coverage review and topology
analysis for each goal. Here's the flow:

```
For each active goal:
  1. Retrieve relevant knowledge → retrieval results
  2. Evaluate coverage against retrieval → coverage_score, decision
  3. Analyze topology of retrieved nodes → κ, routing
  4. Compute attention_score from coverage + topology + urgency
  5. Assign dispatch_mode based on coverage decision + topology routing
```

The combined signal creates nuanced dispatch modes:

| Coverage Decision | Topology Routing | dispatch_mode | Interpretation |
|------------------|-----------------|---------------|----------------|
| `act` | `fast` | `act` | Everything is clean — execute now |
| `act` | `deliberate` | `learn` (or `act` with caution) | Coverage is adequate but knowledge has cycles — may need deliberation first |
| `learn` | `fast` | `learn` | Missing knowledge, but what exists is structurally sound |
| `learn` | `deliberate` | `learn` | Missing knowledge AND structural issues — learn + deliberate |
| `escalate` | any | `escalate` | Coverage is critically low — need external help regardless of topology |

---

## Heartbeat and Automatic Cycles

The attention engine runs periodic **heartbeat cycles** at a configurable
interval (visible as `next_heartbeat_in_ms` in the response). These automatic
cycles re-evaluate attention ranking in the background so that the survey
is always fresh when you call it.

You don't need to manage the heartbeat — it runs automatically. The
`next_heartbeat_in_ms` field is informational, letting you know when the
next automatic re-evaluation will happen.

Manual calls to `attention_run_cycle` are **on-demand** and don't reset
or interfere with the heartbeat schedule. You can call them as often as
you like.

---

## Integration Map

| After This... | Use Attention For... |
|---------------|---------------------|
| Session start | `attention_survey()` → pick top-priority goal |
| `store_node` (batch of new knowledge) | `attention_survey()` → check if priorities shifted |
| `learn_from_outcome` (failure) | `attention_survey()` → see if the failed goal dropped in priority |
| `review_goal` → decision changed | `attention_survey()` → see updated dispatch_mode in ranked context |
| `run_consolidation` | `attention_run_cycle(autonomy_override: "advise")` → post-consolidation freshness |
| `deliberate` (resolved a cycle) | `attention_survey()` → goal's max_kappa should have decreased |
| Ralph Loop iteration boundary | `attention_run_cycle(autonomy_override: "advise")` → structured next-step guidance |
| User asks "what should we work on?" | `attention_survey()` → formatted priority report |

---

## Common Mistakes

| Mistake | Why It's Bad | Fix |
|---------|-------------|-----|
| Never checking attention at session start | You miss priority changes from prior sessions or background consolidation | Always `attention_survey()` when starting a goal-oriented session |
| Running `attention_run_cycle` with `act` autonomy without understanding what it does | May dispatch actions you don't expect | Start with `observe` or `advise`; only use `act` when you trust the system |
| Ignoring `dispatch_mode: "learn"` and trying to execute anyway | Acting on insufficient knowledge leads to failures and confidence drops | Respect the dispatch mode — gather knowledge first when told to learn |
| Ignoring `routing: "deliberate"` in attention items | Cyclic knowledge can lead to unreliable conclusions | Use `deliberate` tool to resolve cycles before acting on affected goals |
| Surveying too frequently (every message) | Adds latency without new information | Survey at natural breakpoints: session start, after outcomes, after storing batches |
| Not including idle items when doing a full status report | User doesn't see the complete picture | Use `include_idle: true` for comprehensive reports |
| Treating `attention_score` as an absolute measure | Scores are relative — they rank goals against each other, not against an absolute standard | Compare items to each other, don't fixate on absolute values |
| Using `attention_run_cycle` when you have no goals | The cycle will find nothing to survey | Create goals first via `manage_goal` before using attention |

---

## Tips

1. **Start every goal-oriented session with `attention_survey()`.** It's the
   fastest way to regain context and choose focus after a session boundary.

2. **The top item wins.** When in doubt, work on whatever `attention_survey`
   ranks first. The scoring system already accounts for urgency, coverage,
   and topology — trust it or tune the underlying goal priorities.

3. **Use `advise` mode liberally.** Running `attention_run_cycle` with
   `autonomy_override: "advise"` gives you actionable recommendations
   without any side effects. It's the sweet spot between passive observation
   and full autonomy.

4. **Watch `coverage_decision` + `routing` together.** These two fields give
   you the richest signal about what a goal needs. A goal with
   `coverage_decision: "act"` and `routing: "fast"` is ready to go. A goal
   with `coverage_decision: "learn"` and `routing: "deliberate"` needs both
   more knowledge *and* cycle resolution.

5. **Use `include_idle: false` for focus, `include_idle: true` for reporting.**
   During active work, you only care about actionable items. When the user
   asks for a status overview, show everything.

6. **Let attention scores drive goal switching.** If you're stuck on a goal and
   re-survey shows another goal with a higher attention score, it's often more
   productive to switch than to grind. The second goal may be "cheaper" to
   advance, and progress there may unlock the first one.

7. **Pair with consolidation.** After a long session with many stored nodes,
   run consolidation first, then run an attention cycle. Consolidation may
   merge or prune nodes, which changes coverage scores, which changes
   attention ranking. Fresh consolidation → fresh attention → better focus.

---

## Summary

| Principle | Practice |
|-----------|----------|
| Attention tells you what to focus on | Use `attention_survey` to see ranked priorities |
| Active cycles do more than observe | Use `attention_run_cycle` for survey + triage + dispatch |
| Autonomy levels control risk | Start with `observe`/`advise`, graduate to `act` when confident |
| `dispatch_mode` guides your next action | `act` → execute, `learn` → gather, `escalate` → ask for help |
| Coverage + topology = dispatch intelligence | Both signals feed into attention scoring and dispatch mode |
| Survey at transition points | Session start, after outcomes, after consolidation, before goal selection |
| Trust the ranking or tune the inputs | If attention_score rankings feel wrong, adjust goal priority/horizon rather than ignoring the scores |