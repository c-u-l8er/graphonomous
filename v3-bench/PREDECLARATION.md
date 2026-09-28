# V3-1 (a) — recall bench, predeclared

**Written 2026-09-28, committed before any system is run, any Jev call is made, or any label exists.**
Stage V3-1 of `docs/spec/v3/README.md` §7; it decides falsifier **F1** and gives a first reading on **F2**.

## The question

Graphonomous v3 would give an agent *recall*: given what it is about to do, surface what it already knows.
Today that job is done by the Claude Code file memory (`MEMORY.md` index + topic files) and by what a
session does with it: read the index, `grep` the folder. **Does a v3-shaped recall — lexical candidates
judged by a calibrated typed decider — answer the questions sessions really asked clearly better than
that?** If not, v3's recall is not worth building on this evidence.

## Population — every real question, not a sample

All distinct retrieve queries sent to the Graphonomous v1 MCP in the Claude Code transcripts under
`~/.claude/projects/-home-travis-ProjectAmp2/` (`extract_queries.py`): **23 distinct queries, 24 calls,
2026-07-25 → 2026-09-22.** Nothing is dropped or added. Query text stays private
(`~/.graphonomous/v3-bench/`, outside this public repository).

## Corpus

A snapshot of `~/.claude/projects/-home-travis-ProjectAmp2/memory/*.md` taken when the bench runs,
recorded with a sha256 manifest. `MEMORY.md` is the index, not a document. The snapshot is later than every
query; the question is whether memory *as it stands* answers them.

## Systems

| id | system | stands for |
|---|---|---|
| S1 `index` | query terms matched against each file's `MEMORY.md` line + frontmatter `description`, idf-weighted | reading the index |
| S2 `grep` | idf-weighted count of distinct query terms present anywhere in the file | grepping the folder |
| S3 `bm25` | BM25 (k1 1.2, b 0.75) over description + body | a ranked search script, no model |
| S4 `bm25+jev` | S3's top 20, reordered by Jev's `choice` probabilities; the rest keep S3 order | **v3's recall: lexical candidates, decider judges** |
| S5 `jev-all` | one Jev `choice` over every file's one-line summary (fits: ≤ 255 options) | a decider with no recall stage |

Jev = `typesafe/jev-1.13` via OpenRouter `/api/v1/systemone`. Options are shuffled with a fixed seed.
Only the query and each candidate's filename + one-line description leave the machine; the outgoing
payload is scanned for secret-shaped strings first and the run aborts on a hit. Ollaya is not installed
(spec [T3]) and is not in this run.

## Labels

For each query, the **pool** is the union of every system's top 10 plus S3's top 20 (everything S4 could
promote). Each pooled file gets a grade: **2** = the file a session asking this should read first / that
answers it; **1** = relevant background; **0** = not relevant. Graders are Claude subagents, **blind to
which system proposed which file** (candidates shuffled, no ranks shown), who may open the files.
Unpooled files count as 0. A query whose pool has no grade ≥ 1 is reported and excluded from means.

## Metrics and the decision rule

- **Primary:** nDCG@5 with graded gains. **Secondary:** MRR@10 of the first grade-2 file; recall@10 of
  grade ≥ 1 files.
- **Baseline B** = whichever of S1, S2 has the higher mean nDCG@5 (the stronger of today's two habits —
  choosing it after the fact only makes v3's bar higher).
- **F1 — v3 recall is worth building** iff the mean paired difference nDCG@5(S4) − nDCG@5(B) is
  **≥ 0.05 and its 95 % bootstrap interval excludes 0** (10,000 resamples over queries, seed 20260928).
  Otherwise **F1 fires**: on this evidence the file memory plus today's lookups suffices.
- **F2, first reading** — the same rule applied to S4 − S3: does the decider add anything over its own
  lexical candidates? S5 − B is reported, not decided.
- Every per-query score is published in the results (as ids and numbers, not query text).

## Known weaknesses, stated before the numbers

- **n = 23.** A real population, but small; an interval that spans 0 is the likely honest outcome for
  small effects, and the rule then says "not shown", not "shown absent".
- **The graders are Claude**, the same family as the agent that would use the memory. Travis can audit
  every label (the label file carries a one-line reason per grade).
- **One decider** (hosted Jev), one prompt wording, no calibration refit.
- The queries were written for a *graph* memory; phrasing favours keyword systems about as much as it
  favours a decider.
