# v3-bench — stage V3-1 of the Graphonomous v3 spec

**Both benches have run, and both are closed.** (a) is in `RESULTS.md`; (b) is in `b/RESULTS.md`. Their
outcome closed the v3 proposal on 2026-09-28: `v2/handoff/DECISION_LOG.md` D-078, and
`docs/spec/v3/README.md` §C.
- Do not re-run either bench hoping for a different verdict.
- A new decider, prompt or review-queue design is a **new** predeclared experiment.
- A new experiment does not tune on (b)'s frozen test split.

Offline measurements that decide whether parts of `docs/spec/v3/README.md` are worth building. **Code only
lives here.** Every input and output — query text, the memory snapshot, rankings, Jev's answers, labels,
results — is written to `~/.graphonomous/v3-bench/` (mode 0700), because this repository is public and those
files are private session memory.

## (a) Recall bench — read `PREDECLARATION.md` first

| Step | Script | Writes (under `~/.graphonomous/v3-bench/`) |
|---|---|---|
| 1 | `extract_queries.py` — every retrieve query sessions sent to Graphonomous v1 | `queries.jsonl` |
| — | `usage.py` — Graphonomous calls vs memory-folder use, counts only | `usage.json` |
| 2 | `bench.py` — snapshot the memory folder, run S1–S5 (S4/S5 ask Jev on OpenRouter; `--no-jev` skips them) | `corpus/`, `corpus_manifest.json`, `rankings.json`, `jev_raw.jsonl` |
| 3 | `pool.py` — blind labeling pools (no system or rank information in a task) | `label_tasks/` |
| — | graders (Claude subagents, blind) | `labels/` |
| 4 | `score.py` — metrics and the predeclared F1 / F2 rule | `results.json` |

`RESULTS.md` beside this file carries the outcome as ids and numbers only.
