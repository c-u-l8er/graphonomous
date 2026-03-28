# Operations & Maintenance

This page is the operational runbook for running, validating, and maintaining **Graphonomous** in development and production-like environments.

---

## 1) Operational Model

Graphonomous runs as an Elixir/OTP application with supervised runtime services and an MCP server interface over stdio. Core operational concerns are:

- **Process health** (runtime services are up)
- **Data durability** (SQLite-backed state)
- **Retrieval quality** (memory remains relevant)
- **Learning integrity** (outcomes update confidence correctly)
- **Memory hygiene** (consolidation decay/pruning cycles)
- **Transport stability** (MCP client/server connectivity)

---

## 2) Daily Operator Checklist

Use this checklist for routine operation:

1. Start Graphonomous with an explicit DB path.
2. Verify runtime health snapshot.
3. Verify goals snapshot (if goal-driven workflows are active).
4. Confirm retrieval works on a known query.
5. Confirm writes (`store_node`) and updates (`learn_from_outcome`) succeed.
6. Run/inspect consolidation state.
7. Review logs for transport disconnects or repeated timeouts.

---

## 3) Startup Procedures

## 3.1 Local development startup

Run Graphonomous with a dedicated local DB:

- Ensure your DB directory exists.
- Start using fallback embedder when troubleshooting or on constrained devices.

Recommended startup characteristics:

- Explicit `--db` path
- Stable log level (`info` or `debug`)
- Request timeout tuned for your client/editor

## 3.2 MCP client startup validation

After startup, validate in this order:

1. Tool discovery returns expected Graphonomous tools.
2. Resource reads succeed:
   - `graphonomous://runtime/health`
   - `graphonomous://goals/snapshot`
3. A test retrieval query returns `status: ok`.
4. A test node write succeeds.

---

## 4) Health Monitoring

## 4.1 Runtime health resource

Use `graphonomous://runtime/health` to verify:

- Process-level service status (`up`/`down`)
- High-level object counts (nodes/goals)
- Timestamp of snapshot generation

If any core service is down, restart runtime and verify DB accessibility.

## 4.2 Goal snapshot resource

Use `graphonomous://goals/snapshot` to verify:

- Total number of goals
- Status distribution (`proposed`, `active`, `blocked`, `completed`, etc.)
- Serialized goal records for debugging orchestration state

---

## 5) Data & Storage Operations

## 5.1 Persistence strategy

Graphonomous uses SQLite as durable storage and ETS as hot in-memory cache.

Operational implications:

- SQLite file is the recovery source of truth.
- ETS is rebuilt/warmed from DB state.
- Always keep DB path explicit and stable per environment.

## 5.2 Backup strategy

Recommended backup practice:

- Schedule periodic copies/snapshots of the SQLite DB file.
- Perform backups during low-write periods when possible.
- Keep at least:
  - daily rolling backups (7 days),
  - weekly backups (4 weeks),
  - monthly backups (3–6 months).

## 5.3 Recovery procedure

If runtime state appears inconsistent:

1. Stop Graphonomous.
2. Backup current DB file before changes.
3. Restart runtime and verify health.
4. Re-run retrieval sanity checks.
5. If needed, restore from known-good backup and replay required operational steps.

---

## 6) Learning Loop Operations

## 6.1 Required loop discipline

For consequential actions:

1. Retrieve context first.
2. Perform action.
3. Report outcome with real `causal_node_ids`.

This keeps confidence updates meaningful and avoids drift.

## 6.2 Outcome status semantics

Use outcome status correctly:

- `success`: action achieved intended result
- `partial_success`: mixed outcome
- `failure`: action failed
- `timeout`: no reliable completion signal

Treating timeouts as failures can incorrectly penalize good knowledge.

## 6.3 Confidence hygiene

Operational rule:

- Use evidence-calibrated confidence values.
- Avoid blanket high confidence in both stored nodes and outcomes.
- Favor structured evidence payloads for audits and debugging.

---

## 7) Goal Operations

For multi-step work, always use goals.

## 7.1 Goal lifecycle flow

Typical progression:

`proposed -> active -> completed`  
or  
`proposed/active -> blocked -> active` (when unblocked)

## 7.2 Coverage review gate

Before high-impact actions, run goal coverage review to route execution:

- `act`: proceed
- `learn`: gather additional context
- `escalate`: block/escalate to human or multi-agent process

## 7.3 Progress and evidence

- Update progress incrementally (avoid “jump to 100%” without evidence).
- Link supporting nodes to goals.
- Keep transition metadata descriptive for auditability.

---

## 8) Consolidation Operations

Consolidation maintains memory quality over time.

## 8.1 When to run

- End of productive sessions
- Periodically during long autonomous runs
- After heavy write/ingestion bursts
- Before critical retrieval/review checkpoints

## 8.2 What to watch

From consolidation status/runtime info monitor:

- cycle count
- last run timestamp
- decay/prune behavior
- signs of overly aggressive pruning

If retrieval quality drops sharply, inspect consolidation settings and confidence distributions.

---

## 9) Incident Response Runbooks

## 9.1 MCP server transport instability

Symptoms:

- client timeouts
- server shutdown messages
- intermittent success/failure across calls

Response:

1. Confirm runtime process is alive.
2. Validate health resource.
3. Restart MCP runtime cleanly.
4. Re-run minimal smoke flow (list tools -> read resources -> retrieve -> store).
5. Inspect logs for transport and timeout patterns.
6. Increase request timeout if workload is heavy.

## 9.2 Write-path failures

Symptoms:

- retrieval works but node/goal writes fail
- partial success in batches

Response:

1. Verify DB path and file permissions.
2. Check available disk space.
3. Restart runtime.
4. Retry writes idempotently.
5. Confirm data via query/list calls after retry.

## 9.3 Retrieval degradation

Symptoms:

- poor relevance
- stale/conflicting recall
- weak support around active goals

Response:

1. Inspect low-confidence node concentration.
2. Run consolidation.
3. Add missing high-quality semantic/procedural nodes.
4. Use coverage review to identify knowledge gaps.
5. Avoid forcing action when routing says `learn` or `escalate`.

---

## 10) Release & Change Management

Before releases:

1. Run format, compile, and tests.
2. Verify MCP tools/resources remain discoverable.
3. Validate key operational workflows:
   - retrieve -> store -> learn -> consolidate
4. Confirm docs and CLI help text are in sync with behavior.
5. Ensure version parity across project metadata and distribution artifacts.

After releases:

- Smoke test install/run path.
- Verify health/resource access from at least one MCP client.
- Confirm no regressions in goal operations and consolidation calls.

---

## 11) Security & Safety Practices

- Never store secrets or credentials in graph content/metadata.
- Use least-privilege file permissions for DB directories.
- Keep logs free of sensitive user data where possible.
- Prefer explicit, auditable metadata over opaque free-text for critical actions.
- Treat externally sourced claims as lower confidence until verified.

---

## 12) Recommended SLO-Style Targets (Starter Set)

These are practical baseline targets you can tune per environment:

- **Runtime availability:** core services up > 99%
- **MCP request success rate:** > 99% for standard calls
- **Median retrieval latency:** < 2s on local workloads
- **Write success rate:** > 99% for node/goal operations
- **Consolidation cadence adherence:** > 95% of expected cycles

---

## 13) Quick Troubleshooting Matrix

| Symptom | Likely Cause | First Action |
|---|---|---|
| Tool calls timeout | Transport/runtime instability | Restart runtime, re-check health |
| Goals not updating | Write-path issue or bad payload | Validate payload shape, retry update |
| Retrieval returns empty repeatedly | Sparse graph or wrong query scope | Seed knowledge, broaden query |
| Coverage always escalates | Insufficient support/confidence | Add evidence nodes, review contradictions |
| Sudden memory loss feel | Aggressive decay/prune settings | Inspect consolidation config/status |

---

## 14) End-of-Session Operator Procedure

Before ending a productive session:

1. Store key new knowledge discovered.
2. Report any pending outcomes.
3. Update goal progress/status.
4. Trigger consolidation and verify status.
5. Capture any unresolved risks in a goal note for next session continuity.

---

## 15) Related Documentation

- `index` — docs entry point
- `architecture` — system design and internals
- `quickstart` — first-run path
- `mcp-tools` — tool/resource interface reference
- `skills/SKILLS` — operational agent behavior loop
- `NPM_PUBLISH` — release/distribution runbook
- `ZED` — editor integration guidance