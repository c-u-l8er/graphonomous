# R8 — Graphonomous MCP memory probe (READ side only)

Probe agent: isolated memory-probe subagent, session `ac8f93a5-7380-4895-ae54-fd98459289cc`.
Date: 2026-09-02. Reason for the probe: the Graphonomous MCP server had hung ~30 min on `act`
calls in recent sessions. Policy followed: each read-side call type tried ONCE, nothing retried,
nothing written (`act`, `learn`, `consolidate run` were NOT called).

## Timing

All four MCP calls were issued in ONE parallel batch (they are independent), together with a
`date` call that stamped the start.

| mark | UTC timestamp |
|---|---|
| batch issued (start stamp, from `date` in the same batch) | 2026-09-02T20:48:01.541Z |
| after-stamp (taken by the next agent turn, after all four results were already in hand) | 2026-09-02T20:49:02.878Z |

Per-call durations are NOT individually measurable in a parallel batch. What is known:
every one of the four calls returned within the window above, and none blocked, timed out, or
errored. The after-stamp is an upper bound inflated by agent turn latency; the actual server
responses arrived well inside it (the harness delivered all four results together with the
`date` output).

## Outcome by call

| # | call | result | notes |
|---|---|---|---|
| 1 | `consolidate {action:"stats"}` | OK, returned | graph reports **0 nodes / 0 edges** |
| 2 | `retrieve {action:"context", query:"Graphonomous G0 WRL-native …"}` | OK, returned | `count: 0`, `topology.routing: "fast"` |
| 3 | `retrieve {action:"context", query:"WRL relation identity profile …"}` | OK, returned | `count: 0`, `topology.routing: "fast"` |
| 4 | `route {action:"attention_survey", include_idle:false}` | OK, returned | 3 goals, all `escalate`; `include_idle` accepted without a validation error (schema does not list it — it may have been ignored) |

No call failed. No error text to quote.

## 1. `consolidate stats` — raw

```json
{"status":"ok","node_count":0,"edge_count":0,"orphan_node_count":0,
 "min_confidence":0.0,"avg_confidence":0.0,"max_confidence":0.0,
 "relationship_distribution":{},"source_distribution":{},
 "timescale_distribution":{},"type_distribution":{}}
```

Health reading: the node/edge store the server is answering from is EMPTY. There is no
health/uptime field in the stats payload; the only health signal is that it answered promptly.

## 2. `retrieve context` — query A

Query: `Graphonomous G0 WRL-native semantic evidence graph over the invariant program; WRL TRVM integration; prior decisions`

```json
{"status":"ok","count":0,"results":[],"causal_context":[],
 "topology":{"routing":"fast","max_kappa":0,"scc_count":0,"sccs":[],"dag_nodes":[]},
 "stats":{"seed_count":0,"expanded_count":0,"returned":0,
          "retrieval_confidence":0,"max_ann_similarity":0,
          "ann_score_stats":{"count":0,"mean":0,"stddev":0},
          "abstention_signal":false,"temporal_intent":"normal","topology_skipped":false}}
```

Top results: NONE (no ids, content, confidence, or source to report). `topology.routing` = `fast`.

## 3. `retrieve context` — query B

Query: `WRL relation identity profile mechanism D6 D8 D9 gaps; TRVM derive protocol; content-addressed evidence`

```json
{"status":"ok","count":0,"results":[],"causal_context":[],
 "topology":{"routing":"fast","max_kappa":0,"scc_count":0,"sccs":[],"dag_nodes":[]},
 "stats":{"seed_count":0,"expanded_count":0,"returned":0,
          "retrieval_confidence":0,"max_ann_similarity":0,
          "ann_score_stats":{"count":0,"mean":0,"stddev":0},
          "abstention_signal":false,"temporal_intent":"normal","topology_skipped":false}}
```

Top results: NONE. `topology.routing` = `fast`.

## 4. `route attention_survey` — raw (trimmed)

```json
{"status":"ok","autonomy_level":"observe","next_heartbeat_in_ms":null,
 "attention_items":[
  {"goal_id":"goal_1fe506d69ce6499d5937351a2cfcb85c",
   "goal_title":"LongMemEval 88.2% → 95%: Five-fix implementation plan",
   "dispatch_mode":"escalate","coverage_decision":"escalate",
   "attention_score":0.4,"coverage_score":0.4,"decision_confidence":0.65,
   "max_kappa":0,"routing":"fast",
   "attention_rationale":"Urgency=0.5, gap=0.6, coverage_decision=escalate, κ=0, routing=fast.",
   "coverage_rationale":["coverage=0.400 uncertainty=0.650 risk=0.394 decision=escalate",
     "semantic=0.000 consistency=1.000 freshness=0.000 graph_support=0.840 outcomes=0.735",
     "thresholds: act(cov>=0.720, unc<=0.350, risk<=0.450) learn(cov>=0.450, unc<=0.700, risk<=0.750)"]},
  {"goal_id":"goal_af24d0fa48d281d4c99844b8ccc25c79",
   "goal_title":"Entity Resolution + Temporal Entity Graph for Graphonomous",
   "dispatch_mode":"escalate","coverage_decision":"escalate",
   "attention_score":0.38,"coverage_score":0.398,"decision_confidence":0.65,
   "max_kappa":0,"routing":"fast",
   "coverage_rationale":["coverage=0.398 uncertainty=0.650 risk=0.345 decision=escalate",
     "semantic=0.000 consistency=1.000 freshness=0.000 graph_support=0.736 outcomes=0.871",
     "thresholds: act(cov>=0.720, unc<=0.350, risk<=0.450) learn(cov>=0.450, unc<=0.700, risk<=0.750)"]},
  {"goal_id":"goal_933229885bb2373332cafe4c854a1f37",
   "goal_title":"LongMemEval: 86% → 95% QA + <3s latency",
   "dispatch_mode":"escalate","coverage_decision":"escalate",
   "attention_score":0.344,"coverage_score":0.432,"decision_confidence":0.65,
   "max_kappa":0,"routing":"fast",
   "coverage_rationale":["coverage=0.432 uncertainty=0.650 risk=0.320 decision=escalate",
     "semantic=0.000 consistency=1.000 freshness=0.000 graph_support=0.964 outcomes=0.871",
     "thresholds: act(cov>=0.720, unc<=0.350, risk<=0.450) learn(cov>=0.450, unc<=0.700, risk<=0.750)"]}]}
```

Survey summary: 3 active goals, all three dispatched `escalate`; `autonomy_level: observe`;
no heartbeat scheduled. Every goal shows `semantic=0.000` and `freshness=0.000` — consistent
with the empty node store (nothing semantic to retrieve for any goal). All three goals are
Graphonomous's own historical dev goals (LongMemEval, entity resolution), none concern the
WRL / TRVM / invariant program.

## Findings (what the data supports, no more)

1. The READ side is responsive. Four read-side calls, four prompt returns, zero errors. The
   hang seen in other sessions is not reproduced on `consolidate stats`, `retrieve context`,
   or `route attention_survey`. Whether `act` still hangs was deliberately NOT tested here.
2. The graph the server is serving is EMPTY: 0 nodes, 0 edges, empty type/source
   distributions, and both retrievals seed 0 nodes. There is no prior context about the
   invariant program, WRL, TRVM, or G0 retrievable from this server right now.
3. Goals persist while nodes do not. `attention_survey` returns 3 stored goals with non-zero
   `graph_support` and `outcomes` sub-scores, while `stats` says the node/edge store holds
   nothing. Either the goal/outcome records live in a store separate from the node/edge
   tables, or the server has been pointed at (or re-initialised with) a node store that
   differs from the one the goals were created against. This probe cannot tell which; it
   is the question to answer before trusting any "no prior decisions found" reading.
4. `retrieve` reports `abstention_signal: false` with `retrieval_confidence: 0` on an empty
   graph — i.e. it does not flag "I have nothing" as an abstention. A caller that checks only
   `abstention_signal` would treat an empty store as a confident miss.

## Not done (by instruction)

- `act` — not called. `learn` — not called. `consolidate run` — not called. Nothing stored.
- No call was retried.
