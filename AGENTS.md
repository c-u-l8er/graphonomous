# Graphonomous — AGENTS Instructions

This file defines mandatory behavior for any AI agent operating against the Graphonomous MCP server in this repository.

## Scope

These instructions apply to all agent sessions that use Graphonomous memory, goals, and learning tools.

---

## 1) Mandatory Skills Pack (Always Load)

Before doing non-trivial work, the agent must load and follow the Graphonomous skills pack:

- `docs/skills/SKILLS.md`
- `docs/skills/AGENT_BOOTSTRAP_PROMPT.md`
- `docs/skills/01_RETRIEVE_AND_REMEMBER.md`
- `docs/skills/02_LEARNING_LOOP.md`
- `docs/skills/03_GRAPH_INSPECTION.md`
- `docs/skills/04_GOAL_MANAGEMENT.md`
- `docs/skills/05_COVERAGE_AND_REVIEW.md`
- `docs/skills/06_TOPOLOGY_AND_DELIBERATION.md`
- `docs/skills/07_CONSOLIDATION.md`
- `docs/skills/08_ATTENTION.md`
- `docs/skills/09_WORKFLOWS.md`
- `docs/skills/10_ANTI_PATTERNS.md`

If some skills files are unavailable, proceed with best effort using available files and explicitly reduce certainty.

---

## 2) Default Operating Policy (Graphonomous-First)

For non-trivial tasks, follow this loop by default:

1. **Retrieve first** (prior memory/context)
2. **Reason + act**
3. **Store new durable knowledge**
4. **Report outcomes for learning**
5. **Maintain memory quality periodically**

This is the baseline behavior for every session.

---

## 3) Session Start Protocol (Always)

At session start:

1. Retrieve prior context for the user topic.
2. Check goal state (active/proposed/blocked/completed as needed).
3. Optionally survey attention if multiple goals exist.
4. Continue with user request grounded in retrieved context.

Do not start domain-heavy reasoning from scratch when prior memory likely exists.

---

## 4) Knowledge Storage Rules

- Prefer atomic nodes (one claim/procedure/event per node).
- Use correct node type:
  - `semantic` = facts/architecture
  - `procedural` = how-to/workflow
  - `episodic` = observed events/outcomes
- Include `source` whenever possible.
- Set realistic confidence based on evidence quality.
- Add edges only when they improve retrieval quality and provenance.

---

## 5) Outcome Learning Rules

When an action is informed by retrieved context:

- Preserve causal context IDs.
- Use only true causal IDs for outcome feedback.
- Use status precisely: `success | partial_success | failure | timeout`.
- Do not treat `timeout` as `failure`.
- Include structured evidence where possible.

No fabricated outcomes. No fabricated causal provenance.

---

## 6) Goal Discipline

For multi-step work:

- Create and maintain goals.
- Link supporting nodes to goals.
- Update progress incrementally with evidence.
- Run goal coverage review at decision points.
- Respect decision routing:
  - `act` → proceed
  - `learn` → gather more context
  - `escalate` → block/escalate appropriately

---

## 7) Topology + Deliberation Discipline

- Read topology/routing signals from retrieval.
- If cyclic complexity is present (κ > 0 / deliberate routing), use topology analysis/deliberation for high-stakes decisions.
- Avoid unnecessary deliberation when routing is fast.

---

## 8) Attention Discipline

When multiple goals compete:

- Use attention survey/cycle to prioritize.
- Follow dispatch mode (`act | learn | escalate | idle`).
- Prefer observe/advise posture unless autonomous execution is explicitly intended.

---

## 9) Consolidation Discipline

Trigger consolidation:

- At session boundaries after substantial updates
- Periodically during long iterative runs
- After major ingestion/learning batches

Use status checks to monitor graph health and adjust behavior.

---

## 10) Hard Prohibitions (From Anti-Patterns)

Do not:

- Skip retrieval habitually
- Skip outcome learning for consequential actions
- Inflate confidence indiscriminately
- Store kitchen-sink nodes
- Fabricate coverage signals or causal links
- Ignore repeated `learn`/`escalate` decisions
- Create edge spaghetti
- Neglect consolidation indefinitely

---

## 11) Host Prompt Wiring (Required)

When configuring any chat/agent runtime for this repo, include:

1. `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` in system/developer context.
2. `docs/skills/SKILLS.md` as the index.
3. Relevant numbered skill files for the task domain (or all files for general agents).

Minimum acceptable wiring: bootstrap prompt + `SKILLS.md`.

---

## 12) Expected End-of-Session Behavior

Before ending a productive session:

1. Store key new facts/procedures/events.
2. Report pending outcomes.
3. Update goals/progress.
4. Trigger consolidation (with status when practical).

---

## 13) Project-Specific Constraints (Keep)

- Follow source-of-truth spec first:
  - `docs/spec/README.md`
  - `../AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md`
- Keep vendored MCP dependency approach intact.
- Do not reintroduce EXLA dependency.
- Preserve raw SQL + parameterized-write model.
- Keep version sync requirements across Elixir/npm/tagging workflows.

---

## 14) Compliance Marker

Agents should internally adopt this session policy:

**“Graphonomous-first memory loop is active.”**