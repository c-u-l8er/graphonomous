# Graphonomous — User Stories

Canonical user-story catalog. Used for Playwright tests (via MCP inspector pattern) + Claude Design input for a future visualization UI (likely hosted on RuneFort).

**Scope:** Continual-learning knowledge-graph engine. MCP-only today; web visualizer planned.
**Unit-test surface covered:** `test/**` (573 tests).

---

## Story 1 · Agent learns from user queries over time

- **Persona:** Device manufacturer embedding LLMs on IoT hardware
- **Goal:** Deploy a 3B-param model on edge that improves over time without retraining
- **Prerequisite:** Model on device; SQLite local; MCP stdio available
- **Steps:**
  1. Initialize Graphonomous: `mix run -- --db ~/.graphonomous/knowledge.db`
  2. Agent receives query: "How do I set the temperature?"
  3. Retriever injects relevant graph context (prior queries, procedures, facts)
  4. LLM generates response (inference external — Graphonomous doesn't run it)
  5. Learner extracts entities/relationships → new nodes, updated edges
  6. System records outcome signal (success? user satisfied?)
- **Success:** After ~100 queries, graph contains domain-specific knowledge; similar questions answered faster
- **Covers:** `retriever.ex`, `learner.ex`, `novelty_detector.ex`, graph CRUD, SQLite storage, outcome ingestion — ~80 unit tests
- **UI status:** mcp-only; Phoenix LiveView dashboard planned for server mode
- **Claude Design hook:** Graph growth timeline (node/edge count over N queries) with topic clusters

## Story 2 · Detect contradictions and update confidence

- **Persona:** Scheduling agent learning meeting coordination
- **Goal:** Catch when learned policies conflict; adjust confidence based on outcomes
- **Prerequisite:** Graph contains contradictory semantic nodes (e.g. "book 9am slots" vs "9am always full")
- **Steps:**
  1. Agent retrieves policy nodes for next booking
  2. Commits action based on retrieved confidences
  3. Runtime reports outcome via `learn.from_outcome`
  4. Graphonomous creates `:outcome` node + updates causal parents
  5. Consolidator flags contradiction via `belief.contradictions`
- **Success:** Conflicting nodes flagged; both decrease confidence; agent requests clarification
- **Covers:** outcome grounding, causal attribution, `learn.from_outcome`, contradiction detector — ~40 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Contradiction report showing conflicting nodes + confidence delta

## Story 3 · Install and replay a learned workflow

- **Persona:** Fleet admin rolling out proven maintenance procedure across machines
- **Goal:** Install a SkillCandidate from FleetPrompt; replay the learned workflow on destination agent
- **Prerequisite:** SkillCandidate stored (via consolidation); agent-browser body available
- **Steps:**
  1. Call `body.browser.replay(Trace)` on destination agent
  2. For each state hash in trace: perceive + verify state match
  3. On mismatch: fail-fast; on match: execute next action
  4. Agent emits SurpriseSignal if forward model prediction diverges
- **Success:** Workflow executes on new machine; state hashes match; skill becomes persistent in destination graph
- **Covers:** trace replay, `state_hash` validation, SurpriseSignal emission, episodic node creation — ~30 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Side-by-side trace diff (Machine A original vs Machine B replay) with hash-match indicators

## Story 4 · Run consolidation to prune low-confidence knowledge

- **Persona:** Backend service operator managing memory footprint
- **Goal:** Decay old knowledge, merge duplicates, promote stable facts
- **Prerequisite:** Graph running; idle period detected (30s+); low-confidence nodes present
- **Steps:**
  1. Consolidator detects idle period
  2. Decay: apply time-based decay to all nodes
  3. Prune: remove nodes/edges below threshold
  4. Merge: nodes with >0.95 embedding similarity merged
  5. Promote: reinforce fast-memory facts to slow-memory
- **Success:** Graph shrinks 10-30%; memory stays stable; most-accessed facts survive
- **Covers:** `consolidator.ex`, decay logic, `pruner.ex`, `merger.ex`, `promoter.ex`, embedder similarity — ~50 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Consolidation timeline with before/after counts + pinned "stable core" facts

## Story 5 · Use coverage scoring to route high-stakes actions

- **Persona:** Governance-aware agent approving contract modifications
- **Goal:** Before destructive action, check if graph has adequate knowledge; escalate if gaps
- **Prerequisite:** Task description available; relevant semantic nodes (may be sparse)
- **Steps:**
  1. Agent calls `coverage_query("approval of contract clause C1")`
  2. Returns: `relevant_nodes`, `coverage_score` (0-1), `knowledge_gaps`, `recommendation`
  3. If coverage ≥ 0.85 + recommendation="act" → proceed
  4. If coverage < 0.85 + recommendation="learn_first" → retrieve more context
  5. If recommendation="escalate" → route to Delegatic or human
- **Success:** High-stakes decisions gated by epistemic readiness; escalations prevent irreversible errors
- **Covers:** `coverage_query`, confidence mean, gap detection — ~15 unit tests
- **UI status:** mcp-only
- **Claude Design hook:** Coverage gauge (0-100%) with gap tooltip listing missing topics

---

**Tests to implement first (MCP-only, no UI required):** Story 1 (inspector-style render of a real query → store → retrieve round-trip). Story 4 is the most visually compelling (graph shrink animation).

**Recommended host for web viz:** RuneFort (`runefort.com`) — specced as the spatial-cognition visualizer for continual-learning agents.
