# V3-1 (b) — relation judgment under asymmetric cost, predeclared

**Written 2026-09-28, committed before the dataset is built, before any system is run, and before any
label is seen.** Stage V3-1 (b) of `docs/spec/v3/README.md` §7. Only `cost_matrix.json` beside this file
stays editable, and only until the first run; `score.py` records the sha256 of the matrix it used.

## The question — deliberately narrow

> Is there a **bounded region** of semantic judgment where a typed decider reduces uncertainty enough, at
> a low enough catastrophic-error cost, to justify placing it **beneath v2's deterministic acceptance
> rules**?

If yes, v2 gains a decider for that region. If no, v2 stays deterministic or manual there. Either result
is useful. "Jev beats Claude" and "Jev wins overall" are **not** the criterion.

**Invariant:** *Graphonomous should prefer missing a relation over asserting a materially wrong relation.*
Failing to discover a relation is recoverable; corrupting the graph's semantic history is not. The cost
matrix encodes this asymmetry: a false `supersedes` costs 10, a missed `supersedes` costs 1 or 2.

**What the benchmark tests:** `candidate pair + supplied scope/context → relation distribution or
abstention`. It does **not** test discovering the pair, extracting spans, finding scope, or explaining —
a typed decider produces no text, and none of that is attributed to it. Pairs are constructed beforehand.

**Starting hypothesis, from the V3-1 (a) result:** there is no new "v3" architecture. v2 survives and
absorbs the useful pieces — the memory folder and the ruling register as sources, BM25 as an external
recall primitive, and a governed relation-proposal stage. This run decides whether that stage gets a
decider.

## Labels

A pair is **(A older, B newer)**; a directed relation reads "B *relation* A".

| label | means |
|---|---|
| `duplicate` | B states the same proposition as A (restated, copied) |
| `refines` | B narrows, qualifies or extends A; A still stands |
| `supersedes` | B replaces A as the current statement; A is withdrawn |
| `contradicts` | A and B cannot both hold, and neither is marked as replacing the other |
| `evidence_for` | B reports a measurement or finding that supports A |
| `evidence_against` | B reports a measurement or finding against A, without stating a replacement claim |
| `scope_disjoint` | similar wording, different subject or scope: they must not be related as the same thing |
| `unrelated` | no meaningful relation |

A system may also **abstain**.

## Two subsets, reported separately

### A — author-grounded transitions (primary; decides the question)

- **Sources:** the Claude Code memory notes (`~/.claude/projects/-home-travis-ProjectAmp2/memory/*.md`,
  snapshotted with a sha256 manifest) and `REVISION_REGISTER.md` at a pinned commit.
- **An item exists only where the author's own text states the transition.** The marker must be explicit
  (for example RETRACTED, SUPERSEDED, WRONG, CORRECTED, FALSIFIED, "restated", "do not conflate",
  "orthogonal", "still true but"), and the text must state both claims.
- **The label follows a fixed mapping from what the author wrote:**

  | the author says | label |
  |---|---|
  | A was wrong, stale or retracted, **and** gives B as the replacement | `supersedes` |
  | a measurement or finding B falsified or weakened A, with no replacement stated | `evidence_against` |
  | a measurement or finding B confirmed or held A | `evidence_for` |
  | B narrows or qualifies A while A stands | `refines` |
  | A and B disagree and it is left open | `contradicts` |
  | B restates A | `duplicate` |
  | A and B must not be conflated | `scope_disjoint` |

  **Claude graders never relabel subset A.**
- **Extraction** (Claude subagents, which only transcribe):
  - A and B are written near-verbatim as standalone claims.
  - **With the transition wording removed.** B is written as a fresh note would state it, not as "A was
    wrong". A regex check rejects any item whose A or B still carries a marker word.
  - A one-line **scope/context** (the subject both claims are about) is supplied, as are dates when stated.
  - **Provenance is kept on every item:** source file and line, plus the verbatim authored quote (≤ 40
    words) that grounds the label, so the gold label can be reconstructed and audited.
  - **At most 5 items per source file**, so no single lane dominates.
  - Transitions whose text does not state both claims are skipped, and the skips are counted.

### B — adversarial hard negatives (reported separately; a guard, not the decision)

- **Kinds:**
  - similar wording but a different scope or proposition;
  - the same proposition in different wording;
  - newer but not superseding;
  - negative evidence that is not a contradiction;
  - a derived or copied note versus independent evidence;
  - unrelated controls.
- **Built by** one constructor subagent. **Labeled independently by two blind grader subagents**, who see
  pair + scope only, never the constructor's intended kind.
- **Only items both graders label identically enter B.** The agreement rate is reported.

### Splits

- Each subset is split **40 % tune / 60 % test**, by source file, so near-duplicate items never straddle
  the split. Seed 20260928.
- The dataset (both subsets, both splits) is frozen by a sha256 manifest **before any system sees it**.
- The test split is scored **once**.

## Systems

| id | system |
|---|---|
| `ABS` | always abstain |
| `R-cons` | conservative fixed rules: `duplicate` when normalized token overlap ≥ 0.8, `unrelated` when ≤ 0.1, otherwise abstain |
| `R-recency` | the naive rule the invariant warns against: overlap ≥ 0.3 and B newer ⇒ `supersedes`, otherwise as `R-cons` |
| `J-raw` | Jev (`typesafe/jev-1.13`, OpenRouter) — one `choice` over the 8 labels with their definitions; argmax, never abstains. Options are shuffled with a fixed seed. |
| `J-gov` | the same Jev answers, **governed**: it answers only when the argmax label is in an admitted **region** (a set of labels) **and** its probability ≥ τ; otherwise abstains |
| `C` | a Claude text judge (a subagent that was not an extractor or grader): label or `abstain`, with a one-line reason |

- **`J-gov`'s region and τ are chosen on the tune split only.** The search is over every label subset and
  τ ∈ {0.30, 0.35, …, 0.95}, minimizing mean cost on tune A. Ties go to the higher τ, then the smaller
  region. Both are then **frozen** before the test split is scored.
- **What leaves the machine:** A/B claim text and scope lines go to OpenRouter. The outgoing payload is
  scanned for secret-shaped strings, and the run aborts on a hit.
- **Ollaya** is not installed ([T3]) and is not in this run.

## Metrics — each per subset, each on test (tune also reported)

- **Expected semantic cost** (mean per item, from `cost_matrix.json`).
- **Coverage** (the share of items answered) and **accuracy conditional on answering**.
- **Per-label confusion matrix.**
- **Catastrophic-error count:** false `supersedes`, `contradicts`, `duplicate`.
- **Paired cost differences** against `ABS`, `R-cons`, `R-recency` and `C`, each with a 95 % bootstrap
  interval (10,000 resamples over items, seed 20260928).

## Decision rule

**v2 gains a decider for the frozen region at the frozen τ iff ALL of these hold on test:**

1. **On test A,** mean cost(`J-gov`) − mean cost(`ABS`) < 0, with the 95 % bootstrap interval entirely
   below 0. (This is the question "is its information worth more than refusing to mutate?")
2. **On test A,** `J-gov` asserts **zero** false `supersedes`.
3. **On test B,** mean cost(`J-gov`) ≤ mean cost(`ABS`) (point estimate). The hard negatives must not make
   it worse than refusing.
4. The frozen region is non-empty.

Otherwise: **v2 stays deterministic or manual for relation proposals**, and the decider is not placed.

- **Reported, not decided:** `J-raw` (what an ungoverned decider would do); `C` (the expensive
  comparator); `R-recency` (the price of "newer ⇒ supersedes").

## Known weaknesses, stated before the numbers

- **Extraction is Claude's transcription.** Labels come from the author's words through a fixed mapping,
  but choosing which sentence is "A" and "B" is an extractor's reading. Every item carries its quote for
  audit.
- **Subset B's truth is Claude graders'.** Hence the separate report and the agreement filter.
- **`C` is the same model family as the extractors and graders.** Its agreement with them is not
  independent evidence of quality.
- **One decider, one prompt wording, and small n.** An interval spanning 0 means "not shown".
- **Removing transition wording may make some items harder than real ingestion**, where a new note often
  says "X was wrong" and a rule would catch it. This benchmark deliberately tests the harder case.
