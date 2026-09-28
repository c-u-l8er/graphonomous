# V3-1 (b) — Amendment 1, before any run

**2026-09-28.** Requested by Travis at the checkpoint after the first freeze (`2936de0e`, dataset
`d5c5a974…`). Allowed by the predeclaration because **no system had seen the dataset**: no rule, no Jev
call, no judge. After the first Jev or Claude judgment, the test split is untouchable except for reporting
flaws found in it.

## 1. Bug-fix transitions leave the author-grounded gold

The extractors disagreed on notes that only say an implementation "was broken, now fixed": x3 labelled them
`supersedes`, and x2 skipped them. Rather than disclose that noise, it is removed.

**The criterion:** an A item stays only if the authored text relates two **claims** — something asserted as
true that was withdrawn, replaced, qualified, supported, weakened or distinguished. It leaves if A was simply
how a thing used to be before someone changed it (a fix, a code or config change, a count that moved because
things were added, a rename carried out).

**Two independent screener subagents** judged every A item. They saw the author's quote and could open the
source, and neither saw the other. **An item stays only if both said `keep`.** An `unsure` from either
excludes it. The screeners never relabel.

## 2. Strict leakage audit

- **The gold proof stays out of band.** The system input is `scope + claim A + claim B` only. The author's
  quote and the label never reach a system (`run.py` sends neither).
- **Extraction already stripped transition wording** (the `LEAK` pattern).
- **This amendment adds a stricter pattern** (`STRICT` in `assemble.py`): replace, fix/fixed, broken, bug,
  actually, turned out, in fact, mistake, incorrect, erroneous, obsolete, outdated, withdraw, revert, rolled
  back, anymore, no more, errata, rename, instead, misread, overstate, understate.
  - **In subset A these give the gold away, so the item is dropped.**
  - **In subset B the same words are traps, not leaks** (they tempt a false `supersedes`), so B keeps them
    and they are counted.
- **Reported only, not excluded:** common words that carry no label on their own (not, never, was, now, new,
  revision, closed).

## 3. T4 — cost matrix

**Governing rule:** *cost follows the semantic damage of the false assertion, not the distance between
labels.*

**Changed:**

| true → predicted | was | now | why |
|---|---|---|---|
| `supersedes` → `contradicts` | 2 | **5** | avoids a false supersession, but still asserts a materially false conflict |
| `unrelated` → abstain | 1 | **0** | if no semantic edge exists, refusing to assert one is not a failure |

**Kept:**
- `scope_disjoint` → abstain: 1
- my filled cells: `supersedes`/`contradicts` → `evidence_against` 3; `evidence_against` → `contradicts` 7;
  `unrelated`/`scope_disjoint` → `refines` 5; `unrelated` ↔ `scope_disjoint` 1; `duplicate` → `refines` 3
- evidence-direction reversals (`evidence_for` ↔ `evidence_against`): 6, a serious error

## 4. Evaluation — pooled cost may not decide alone

Subset A is overwhelmingly `supersedes`.

**`score.py` now also reports:**
- **per-label cost**, and **macro cost** (the mean over labels with ≥ 5 items in that split);
- **evidence-direction reversals**, and **support asserted for a rejected claim**;
- alongside everything already listed: coverage, accuracy when answering, the full confusion matrix, false
  `supersedes` / `contradicts` / `duplicate`, and comparisons against `ABS`, the fixed rules and `C`.

**The decision rule gains a fifth condition:**

5. On test A, the macro cost of `J-gov` ≤ the macro cost of `ABS`.

Conditions 1–4 are unchanged. The tuning of `J-gov` (region and τ on tune A, by pooled cost) is unchanged.

## 5. Not changed

The question, the labels, the systems, the split rule (40/60 by source, seed 20260928), the tuning
procedure, and "A decides, B guards" are all unchanged. Both repositories stay unpushed until after the
result.

The re-frozen dataset's hash and counts are in `DATASET_MANIFEST.json`, which names the freeze it replaces.
