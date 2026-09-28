# V3-1 (a) recall bench — results

**Run 2026-09-28**, under `PREDECLARATION.md` as committed in `0dd0f3ed` before any run. Ids and numbers only:
query text, note names and labels stay in `~/.graphonomous/v3-bench/` (private).

**Verdict: F1 fires — "not shown".** On the 23 real questions, a v3-shaped recall (BM25 candidates judged
by Jev) did not clearly beat grepping the memory folder. **F2's first reading is negative in direction:**
Jev's reordering made its own BM25 candidates slightly worse, losing on 14 of 23 questions. Neither
interval excludes 0, so neither result is "shown absent" either.

## Setup, as run

- **Questions:** all 23 distinct retrieve queries sessions ever sent to Graphonomous v1 (24 calls,
  2026-07-25 → 2026-09-22).
- **Corpus:** 147 memory notes, snapshot `8581aa0111ae982c…` taken 2026-09-28 09:19 −0500.
- **Jev:** `typesafe/jev-1.13` on OpenRouter; 46 calls; total cost **$0.0136**.
  - S4 (20 options per call): median 235 ms.
  - S5 (147 options per call): median 307 ms.
  - The slowest call took 3.3 s.
- **Labels:** 636 blind judgments by four Claude subagents that never saw a ranking. Grades:
  479 × 0, 116 × 1, 41 × 2. Every question had at least one relevant note, so none was excluded.
- **One deviation from a naive reading of the predeclaration, made before any label existed:** S1 and S2
  break ties by BM25 score rather than alphabetically. It can only make those baselines stronger.

## Scores (mean over 23 questions)

| system | nDCG@5 | MRR@10 | recall@10 |
|---|---|---|---|
| S1 `index` | 0.664 | 0.797 | 0.536 |
| S2 `grep` | 0.734 | 0.855 | 0.633 |
| S3 `bm25` | **0.782** | **0.884** | **0.752** |
| S4 `bm25+jev` | 0.762 | 0.831 | 0.733 |
| S5 `jev-all` | 0.739 | 0.824 | 0.731 |

## The predeclared rule — baseline B = S2 `grep`

| comparison | mean Δ nDCG@5 | 95 % bootstrap CI | wins / ties / losses | rule (Δ ≥ 0.05 and CI > 0) |
|---|---|---|---|---|
| **F1**: S4 − B | +0.029 | [−0.054, +0.111] | 11 / 3 / 9 | not met → **F1 fires** |
| **F2**: S4 − S3 | −0.020 | [−0.092, +0.053] | 6 / 3 / 14 | not met |
| S5 − B (reported) | +0.006 | [−0.102, +0.113] | 14 / 1 / 8 | not met |
| S3 − B (reported) | +0.049 | [+0.004, +0.092] | 14 / 3 / 6 | CI excludes 0; Δ = 0.0488, just under the 0.05 margin |
| S5 − S4 (reported) | −0.023 | [−0.088, +0.054] | 8 / 4 / 11 | not met |

## Jev's stated confidence against the labels

| | mean probability of its top pick | top pick graded 2 | top pick graded ≥ 1 |
|---|---|---|---|
| S4 (20 options) | 0.64 | 78 % | 96 % |
| S5 (147 options) | 0.66 | 78 % | 100 % |

Its top pick is right more often than its probability says (**underconfident** here, n = 23). But it is not
right more often than grep's: exploratory, not predeclared, the share of top picks graded 2 is S1 74 % ·
S2 78 % · **S3 83 %** · S4 78 % · S5 78 %.

## Per question, nDCG@5

| qid | S1 | S2 | S3 | S4 | S5 |
|---|---|---|---|---|---|
| q000 | 0.737 | 0.488 | 0.563 | 0.808 | 1.000 |
| q001 | 0.821 | 0.785 | 0.734 | 0.684 | 0.794 |
| q002 | 0.000 | 0.739 | 0.545 | 0.403 | 0.293 |
| q003 | 0.738 | 0.946 | 1.000 | 0.940 | 0.679 |
| q004 | 0.738 | 0.861 | 0.969 | 0.940 | 0.940 |
| q005 | 1.000 | 0.360 | 0.530 | 0.869 | 0.869 |
| q006 | 0.528 | 0.633 | 0.504 | 0.888 | 0.896 |
| q007 | 0.734 | 0.922 | 0.913 | 0.720 | 0.692 |
| q008 | 0.753 | 0.665 | 0.868 | 0.873 | 0.716 |
| q009 | 0.192 | 0.650 | 0.691 | 0.686 | 0.434 |
| q010 | 0.583 | 0.592 | 0.794 | 0.693 | 0.606 |
| q011 | 0.535 | 0.750 | 0.826 | 0.855 | 0.564 |
| q012 | 0.431 | 0.606 | 0.794 | 0.596 | 0.468 |
| q013 | 0.906 | 0.881 | 0.890 | 0.881 | 0.890 |
| q014 | 0.606 | 0.835 | 0.734 | 0.835 | 0.922 |
| q015 | 0.796 | 0.219 | 0.219 | 0.094 | 0.658 |
| q016 | 0.658 | 0.767 | 0.890 | 0.890 | 0.890 |
| q017 | 0.734 | 0.785 | 0.872 | 0.794 | 0.812 |
| q018 | 0.606 | 0.922 | 0.899 | 0.899 | 0.785 |
| q019 | 0.771 | 0.922 | 0.922 | 0.899 | 1.000 |
| q020 | 0.626 | 0.938 | 1.000 | 0.472 | 0.348 |
| q021 | 0.938 | 0.727 | 0.958 | 0.938 | 0.868 |
| q022 | 0.847 | 0.879 | 0.879 | 0.879 | 0.879 |

No system wins every question. The per-question spread between systems is large (for example q002, q005
and q015), so a fusion of rankings might do better than any single one. That is **untested** and is not
claimed here.

## What this shows and what it does not

- **Shown:** for recall over this memory, at this size (147 notes), from these real questions, the cheap
  things already work. Grep finds a first-read note at rank 1 for 78 % of questions, and BM25 over the
  folder does a little better than grep. A decider reordering the candidates did not help.
- **Not shown:** that a decider cannot help recall. There was one prompt wording, one model, n = 23, and
  keyword-bag questions written for a graph memory (a median of 14 words), which suit lexical systems.
- **Not tested at all:** the decider questions that are not about recall — Q-SAME, Q-CONTRA,
  Q-SUPERSEDE, Q-RETIRE (V3-1 (b)). Also Ollaya (not installed), a larger memory, and questions phrased as
  sentences.
- **Graders:** Claude subagents, the same family as the agent that would use the memory. Each label carries
  a one-line reason in the private label files, for audit. The graders saw the same one-line descriptions
  Jev saw, and could also open the notes. If that shared view biased anything, it would have favoured Jev,
  and Jev still did not win.
