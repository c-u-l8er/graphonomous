# Graphonomous — CLAUDE Instructions

This file defines how Claude (and Claude-driven agents) must operate in this repository.

## Primary Directive

Use Graphonomous as an **always-on memory + learning loop** in every non-trivial chat.

Adopt this internal policy at session start:

**“Graphonomous-first memory loop is active.”**

---

## 1) Mandatory Skills Pack (Load First)

Before doing meaningful work, load and follow these files in order:

1. `docs/skills/AGENT_BOOTSTRAP_PROMPT.md`
2. `docs/skills/SKILLS.md`
3. `docs/skills/01_RETRIEVE_AND_REMEMBER.md`
4. `docs/skills/02_LEARNING_LOOP.md`
5. `docs/skills/03_GRAPH_INSPECTION.md`
6. `docs/skills/04_GOAL_MANAGEMENT.md`
7. `docs/skills/05_COVERAGE_AND_REVIEW.md`
8. `docs/skills/06_TOPOLOGY_AND_DELIBERATION.md`
9. `docs/skills/07_CONSOLIDATION.md`
10. `docs/skills/08_ATTENTION.md`
11. `docs/skills/09_WORKFLOWS.md`
12. `docs/skills/10_ANTI_PATTERNS.md`

If some files are unavailable, proceed with best effort and explicitly lower certainty.

---

## 2) Always-On Default Loop

For non-trivial user requests, run this loop:

1. **Retrieve first** (`retrieve_context`)
2. **Reason + act**
3. **Store durable knowledge** (`store_node`, optional `store_edge`)
4. **Close outcome loop** (`learn_from_outcome`) when signal exists
5. **Maintain graph quality** (`run_consolidation`) periodically

Do not routinely skip retrieval on domain-heavy tasks.

---

## 3) Session Start Protocol (Every Chat)

At start of chat (or major topic switch):

1. Retrieve context for user topic/history
2. Check goals state (active/proposed/blocked as needed)
3. Optionally survey attention if multiple goals exist
4. Proceed grounded in retrieved memory

---

## 4) Node / Edge Discipline

- Prefer **atomic nodes** (one claim/procedure/event per node).
- Node types:
  - `semantic` = facts/architecture
  - `procedural` = workflows/how-to
  - `episodic` = observed events/outcomes
- Include `source` whenever possible.
- Confidence must reflect evidence quality (no blanket high confidence).
- Create edges only when they improve retrieval/provenance:
  `causal`, `supports`, `contradicts`, `related`, `derived_from`.

---

## 5) Outcome Learning Discipline

When action used retrieved context:

- Preserve retrieval causal IDs.
- Feed only true causal IDs into `learn_from_outcome`.
- Use status exactly: `success`, `partial_success`, `failure`, `timeout`.
- `timeout` is not `failure`.
- Include structured evidence when practical.

No fabricated outcome signals. No fabricated causal attribution.

---

## 6) Goal Discipline (Multi-Step Work)

For tasks spanning multiple turns:

- Create/manage goals
- Link supporting nodes to goals
- Update progress incrementally with evidence
- Review coverage at decision points (`review_goal`)
- Follow decision routing:
  - `act` -> continue execution
  - `learn` -> gather more context
  - `escalate` -> block/escalate appropriately

---

## 7) Topology / Deliberation Discipline

- Read topology signals on retrieval responses.
- If routing is deliberate (κ > 0), use `topology_analyze` / `deliberate` for high-stakes decisions.
- Avoid unnecessary deliberation when routing is fast.

---

## 8) Attention Discipline

When many goals are in flight:

- Use `attention_survey` (and optionally `attention_run_cycle`) to prioritize.
- Respect dispatch mode: `act`, `learn`, `escalate`, `idle`.
- Prefer observe/advise posture unless autonomous action is explicitly desired.

---

## 9) Consolidation Discipline

Trigger consolidation:

- At productive session boundaries
- Periodically during long iterative runs
- After heavy storage/learning bursts

Use status outputs to monitor memory quality trends.

---

## 10) Hard Prohibitions

Never:

- Skip retrieval habitually
- Skip outcome learning on consequential actions
- Inflate confidence indiscriminately
- Store kitchen-sink nodes
- Fabricate coverage signals/causal links
- Ignore repeated `learn` / `escalate` outcomes
- Create edge spaghetti
- Neglect consolidation indefinitely

---

## 11) Prompt Wiring Requirement (For Claude Runtimes)

Any Claude system/developer prompt for this repo should include:

- `docs/skills/AGENT_BOOTSTRAP_PROMPT.md` (required)
- `docs/skills/SKILLS.md` (required)
- Relevant numbered skill files (or all for general-purpose use)

Minimum acceptable wiring: bootstrap prompt + skills index.

---

## 12) End-of-Session Behavior

Before ending a productive session:

1. Store key new facts/procedures/events
2. Report pending outcomes
3. Update goals/progress/state
4. Trigger consolidation (status when practical)

---

## 13) Project Constraints (Keep Intact)

- Source of truth:
  - `../graphonomous.com/project_spec/README.md`
  - `../AmpersandBoxDesign/prompts/GRAPHONOMOUS_PROMPT.md`
- Keep vendored MCP dependency approach in `vendor/anubis_mcp`
- Do **not** add EXLA
- Keep raw SQL + parameterized writes model
- Keep version synchronization across:
  - `mix.exs`
  - `npm/package.json`
  - git tag `vX.Y.Z`

---

## 14) Build and Run (Reference)

```sh
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix run --no-halt -- --db ~/.graphonomous/knowledge.db --embedder-backend fallback
```

---

## 15) Core MCP Surface (Reference)

Primary tools:
- `store_node`
- `store_edge`
- `retrieve_context`
- `learn_from_outcome`
- `query_graph`
- `manage_goal`
- `review_goal`
- `run_consolidation`
- `topology_analyze`
- `deliberate`
- `attention_survey`
- `attention_run_cycle`

Resources:
- `graphonomous://runtime/health`
- `graphonomous://goals/snapshot`
