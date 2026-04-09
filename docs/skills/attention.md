---
name: attention
description: Use at session startup to regain context, for goal selection and prioritization, when the user asks "what should I focus on?", "what needs attention?", "prioritize goals", "triage", or for periodic status reporting. Routes through the `route` machine.
argument-hint: [survey|cycle] [observe|advise|act]
---

# Attention Engine

Autonomous focus management — rank goals by urgency, knowledge gaps, and topology complexity.

## Arguments

Mode: $ARGUMENTS

## Survey (read-only ranking)

```
route(action: "attention_survey", include_idle: false)
```

Returns ranked `attention_items` sorted by score (0.0-1.0). Each item includes:
- `goal_id`, `goal_title` — which goal
- `attention_score` — composite priority (0.0-1.0)
- `dispatch_mode` — `act`, `learn`, `escalate`, or `idle`
- `coverage_score`, `max_kappa`, `routing` — epistemic state
- `attention_rationale` — compact summary of why this score
- `autonomy_level` — current autonomy setting
- `next_heartbeat_in_ms` — when the next automatic re-evaluation happens

Use `include_idle: true` to also see goals that don't need attention right now.

## Run a Full Cycle (survey -> triage -> dispatch)

```
route(action: "attention_cycle", autonomy_override: "advise")
```

**Autonomy levels:**
- `observe` (default, safe) — survey and rank only, no side effects
- `advise` — rank + suggest next steps, no execution
- `act` — rank + execute high-priority items autonomously

**Response fields:**
- `surveyed_count`, `actionable_count`, `dispatched_count`
- Per-item: `dispatched` boolean, `advice` strings
- `cycle_duration_ms`
- `attention_status`: `autonomy_level`, `next_heartbeat_in_ms`, `last_cycle_at`, `total_cycles_run`

## Dispatch Modes

- **act** — coverage adequate, topology clean — execute the goal's next action
- **learn** — gaps or low confidence — gather more info first
- **escalate** — critically low coverage or high risk — mark blocked, request help
- **idle** — doesn't need attention now

## Attention Score Dimensions

The composite score combines:

| Dimension | What it measures |
|-----------|-----------------|
| **Urgency** | Goal priority and horizon |
| **Knowledge gap** | 1.0 - coverage_score (higher gap = more attention) |
| **Coverage decision severity** | act < learn < escalate |
| **Topology complexity** | Higher kappa = more attention needed |
| **Staleness** | Time since last progress update |

## Topology-Aware Goal Selection

When attention survey shows a goal with `routing: "deliberate"`:
1. Don't immediately act — the knowledge has cycles
2. Run `route(action: "topology", ...)` on that goal's linked nodes
3. `route(action: "deliberate", ...)` if kappa > 0 before proceeding
4. Only dispatch `act` after cycles are resolved or acknowledged

## Session Startup Pattern

1. `route(action: "attention_survey", include_idle: false)`
2. Pick top-ranked item (highest attention_score)
3. Resume that goal or follow user's request

## Background Heartbeat

The attention engine runs automatic re-evaluation cycles in the background. `next_heartbeat_in_ms` tells you when the next automatic survey happens. Manual surveys/cycles supplement this.

## Anti-patterns to avoid

- Running attention cycles too frequently — once at session start + when context shifts is enough
- Ignoring dispatch_mode — if the engine says `learn`, don't skip to `act`
- Over-automating with `act` autonomy when `advise` would be safer
