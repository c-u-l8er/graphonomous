# V3-1 (b) — relation judgment under asymmetric cost — results

**Run and scored once, 2026-09-28**, under `PREDECLARATION.md` (`0c193468`) as amended before any run by
`AMENDMENT_1.md` (`9527e639`).

- **Inputs:** dataset `eb8887054bc4…`; cost matrix `b1455f5403f2…` (sha256 prefixes, recorded by `score.py`).
- **Privacy:** ids and numbers only. The claims, quotes and labels stay in `~/.graphonomous/v3-bench/b/`.

## Verdict — v2 does not gain a decider

| condition (test split) | result |
|---|---|
| 1. mean cost(`J-gov`) − cost(`ABS`) < 0 with the CI below 0, on A | **fails**: −0.192, CI [−0.384, +0.036] |
| 2. zero false `supersedes` on A | **fails**: 6 |
| 3. cost(`J-gov`) ≤ cost(`ABS`) on B | passes: 0.800 vs 0.860 |
| 4. region non-empty | passes: {`supersedes`, `evidence_against`, `scope_disjoint`} at τ 0.65 |
| 5. macro cost(`J-gov`) ≤ macro cost(`ABS`) on A (Amendment 1) | **fails**: 1.609 vs 1.000 |

**By the predeclared rule, relation proposals in v2 stay deterministic or manual.** No typed decider is
placed beneath v2's acceptance rules.

## Setup, as run

- **Subset A** (author-grounded; decides): 334 items, split 110 tune / 224 test. Test A holds
  `supersedes` 158, `scope_disjoint` 24, `evidence_against` 21, `evidence_for` 11, `refines` 9,
  `duplicate` 1.
- **Subset B** (hard negatives; guards): 81 items, split 31 / 50. It has no true `supersedes` or
  `contradicts`.
- **Jev** (`typesafe/jev-1.13`, OpenRouter): 415 calls, **$0.0103**, median 223 ms.
- **Claude text judge (`C`):** four blind subagent slices, 415 items.
- **`J-gov`:** region and τ were chosen on tune A only (tune cost 0.618 against abstain's 1.000), then frozen.

## Test A (n = 224) — the decision

| system | cost | macro cost | coverage | accuracy when answering | false sup / con / dup | evidence reversals |
|---|---|---|---|---|---|---|
| `ABS` always abstain | 1.000 | 1.000 | 0 % | — | 0 / 0 / 0 | 0 |
| `R-cons` fixed rules | 1.147 | 1.214 | 20 % | 2 % | 0 / 0 / 0 | 0 |
| `R-recency` "newer ⇒ supersedes" | 1.384 | 2.416 | 45 % | 47 % | **11** / 0 / 0 | 0 |
| `J-raw` Jev, ungoverned | 1.629 | 2.660 | 100 % | 74 % | **15 / 23** / 0 | 0 |
| `C` Claude text judge | 1.129 | **0.789** | 66 % | 68 % | 1 / 7 / 0 | 0 |
| `J-gov` Jev, governed | **0.808** | 1.609 | 46 % | **94 %** | **6** / 0 / 0 | 0 |

Paired differences for `J-gov` against each system, with 95 % bootstrap intervals:
ABS −0.192 [−0.384, +0.036] · R-cons −0.339 [−0.531, −0.112] · R-recency −0.576 [−0.902, −0.272] ·
J-raw −0.821 [−1.147, −0.513] · C −0.321 [−0.580, −0.049].

### Per-label cost, test A

| true label (n) | ABS | R-cons | J-raw | C | J-gov |
|---|---|---|---|---|---|
| `supersedes` (158) | 1.00 | 1.12 | 1.06 | 1.39 | **0.48** |
| `scope_disjoint` (24) | 1.00 | 1.00 | 2.71 | **0.25** | 1.04 |
| `evidence_against` (21) | 1.00 | 1.48 | 3.76 | **0.48** | 1.52 |
| `evidence_for` (11) | 1.00 | 1.36 | 0.55 | **0.27** | 1.00 |
| `refines` (9) | 1.00 | 1.11 | 5.22 | 1.56 | **4.00** |
| `duplicate` (1) | 1.00 | 0.00 | 0.00 | 0.00 | 1.00 |

## Where `J-gov` fails — and why no threshold fixes it

- **Its whole gain is `supersedes`.** It asserts 82 of the 158 true supersessions correctly and abstains
  on 76.
- **Its six false `supersedes` all fall on minority labels:**
  - 3 × `refines`, at probability **0.86, 0.86 and 0.70**;
  - 2 × `evidence_against`, at 0.67 and 0.65;
  - 1 × `scope_disjoint`, at 0.65.
- **Its correctly asserted supersessions have a median probability of 0.78.** Jev is *more* confident that
  a refinement is a supersession than it typically is about a real supersession. So the errors sit inside
  the confidence range of the right answers, and no τ separates them. That is exactly the case "refinement
  is not supersession" was meant to catch.
- **The tune split could not see this coming.** Tune A had 4 `refines` items, and `J-gov` made 0 false
  `supersedes` there (tune cost 0.618). On test the gain halved and the interval crossed 0. The
  author-grounded corpus is thin outside `supersedes`, so a region learned on it does not transfer.

## Test B (n = 50) — the guard

| system | cost | macro cost | coverage | accuracy when answering | false sup / con / dup |
|---|---|---|---|---|---|
| `ABS` | 0.860 | 0.800 | 0 % | — | 0 / 0 / 0 |
| `R-cons` | 1.120 | 0.987 | 54 % | 30 % | 0 / 0 / 0 |
| `R-recency` | 1.680 | 1.453 | 58 % | 24 % | 3 / 0 / 0 |
| `J-raw` | 1.720 | 1.517 | 100 % | 68 % | 4 / 1 / 0 |
| `C` | **0.420** | **0.300** | 96 % | **88 %** | 0 / 0 / 0 |
| `J-gov` | 0.800 | 0.722 | 10 % | 80 % | 0 / 0 / 0 |

- `J-gov` passes the guard mostly by staying quiet: it answers 5 of 50.
- **The Claude judge is the strongest system on hard negatives by a wide margin.**

## What else the run shows

- **Ungoverned deciders are unsafe.** `J-raw` asserts 15 false `supersedes` and 23 false `contradicts`
  on test A.
- **Governance is what makes Jev tolerable**, and even governed it is not safe enough.
- **"Newer ⇒ supersedes" has a price:** `R-recency` makes 11 false supersessions on A and 3 on B.
- **The Claude judge is the mirror image of Jev.**
  - Strong: evidence, scope, hard negatives.
  - Weak: it under-asserts `supersedes`, which makes its pooled cost worse than abstaining.
  - It is **not consistent across its four slices:** asserted `supersedes` counts were 0, 25, 8 and 36 for
    slices of about 104 items.
  - It is also far more expensive than Jev (about 535k subagent tokens against $0.01).

## Limits

- **One decider** (hosted Jev), **one prompt wording**, no calibration refit. Ollaya is not installed ([T3]).
- **Subset A is thin outside `supersedes`** (9 `refines`, 11 `evidence_for`, 1 `duplicate`, 0
  `contradicts` in test). The failing cells rest on few items. Six catastrophic errors is still six, and
  condition 2 asks for zero.
- **The same model family did most of the human-like work:** extraction, screening, B grading and the `C`
  judge were all Claude. Subset A's labels come from the author's words, but choosing the sentences did
  not.
- **The cost model treats every answer as an assertion.** A setup where Jev's `supersedes` at ≥ 0.65 only
  *queues* a relation for human review (94 % of those answers were right) is a different question about
  review burden. **This run does not test it.**
