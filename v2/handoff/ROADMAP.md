# ROADMAP — Graphonomous v2 after D-078

**Written 2026-09-28, the day of D-078: there is no Graphonomous v3, and v2 grows instead.** This file holds
the requirements that survived the closed v3 investigation (`docs/spec/v3/README.md`), each placed under the
part of the stack that actually owns it. Every item here is `PROPOSED` in STATUS's vocabulary: nothing is
built, and nothing skips the lane's order (inventory → ingestion contract → profile obligation → adjudication →
build). `STATUS.md` stays the only place that says what is built or tested.

**The standing invariant, carried from V3-1 (b): prefer missing a relation over asserting a wrong one.**

## 0. Queued before D-078, unchanged by it

- **WRL as the fourth source family** (D-077, authorized next). The R17 inventory is done; the minimal
  `graphonomous.semantic.v3` *profile* obligation awaits adjudication. That id is a profile version and has
  nothing to do with the closed product v3.
- **Linkage** (D-076), then `graphonomous.consistency.rules.v1`, frozen only after re-measurement.
- **Law 4b** (STATUS "Open" 1).

**[TRAVIS] — order.** D-078 does not say whether the two new families come before or after WRL. The
recommendation is register → memory folder, both **after** WRL. WRL is already authorized and inventoried.
The register is pinnable by commit, as every current family is. The memory folder needs a new pin kind (§2).

## 1. Source family — the ruling register

| | |
|---|---|
| Source | `REVISION_REGISTER.md` in `c-u-l8er/ProjectAmp2` |
| Pin | a commit. The file is tracked, so `adapters/git.mjs` (pinned, read-only, never the working tree) works unchanged |
| Visibility | **PRIVATE** (`gh repo view c-u-l8er/ProjectAmp2 --json visibility`) — see §3 |
| Gate | a read-only inventory in the R15/R17 pattern, before any adapter |

**Measured 2026-09-28 at root `c739879`:**
- **100 rows** (`grep -cE '^\| R[0-9]' REVISION_REGISTER.md`).
- **A row's authority varies by row.** It is recorded in the last column: Travis 24 · "Claude, outside review" 20 ·
  measured 16 · "measured, outside review" 14 · re-derived 7 · open 3 · other 2. Two rows are marked
  `UNRULED`. **The inventory has to classify authority per row**, because an unruled or measured row is not
  a ruling.
- **Authored relations to other rows are rare.** About 13 rows use an explicit verb before an R-id:
  "superseded" 7 · "supersedes" 2 · extends · completes · closes · amends, 1 each. 45 rows mention
  another R-id somewhere in their prose.

**What may become a relation:**
- A **mention** is deterministic: the row's text contains `R96`. It may become a reference relation of the
  `CITES` kind.
- A **transition** (`SUPERSEDES`, and anything like refines, amends or retracts) becomes a relation **only**
  from an explicit authored form with a deterministic grammar. The inventory says which forms qualify.
- Prose that merely implies a transition is not parsed into one.

## 2. Source family — the memory folder

| | |
|---|---|
| Source | `~/.claude/projects/-home-travis-ProjectAmp2/memory/*.md`, indexed by `MEMORY.md` |
| Pin | **none exists yet.** The folder is in no repository, so `adapters/git.mjs` cannot pin it. It needs a content-addressed directory snapshot: a sha256 per file plus a manifest hash. V3-1 (a)'s `bench.py` already built one (`corpus_manifest.json`). Whether a new pin kind fits the FROZEN `GRAPHONOMOUS-PROJECTION-v1` (D-075) or needs a new projection contract is **for the inventory to answer, not to assume** |
| Visibility | **PRIVATE** — see §3 |
| Authority class | not settled. The notes are written by sessions, and some are Travis's words relayed. Treat it as an inventory question, never as "authoritative" by default |
| Churn | many parallel sessions edit it continuously, so every projection names its snapshot and every answer is `as_of` it |

**Measured 2026-09-28:**
- **150 notes.** 121 carry a frontmatter `name:`.
- **315 `[[link]]` occurrences, over 130 distinct targets.** 105 of those targets resolve to a note name or
  filename.
- **One note carries a live credential**, found by pattern. The value was not printed.
- Transition words, counted as occurrences, not pairs: WRONG 74 · SUPERSEDED 14 · RETRACTED 13 ·
  CORRECTED 10.

**What may become a relation:**
- **Intake refuses secret-shaped text.** This is v3's F-2, kept, and the credential above makes it a present
  requirement.
- **A resolving `[[link]]`** is a deterministic reference relation.
- **A dangling link is not an edge.** It becomes an unresolved finding, like `LAW_REFERENCE_UNRESOLVED`.
- **Transition words are prose, not grammar.** V3-1 (b) needed Claude's transcription to turn them into pairs,
  so they are not deterministic and are **not emitted**. At most they are candidates for review (§5).
- A candidate consistency rule for later, from v3's F-3/F-4: **a note that contradicts a current ruling is a
  FINDING, never a relation that outranks the ruling** (D-071: a finding is not a fault).

## 3. Private sources in a public repository — [TRAVIS]

- `c-u-l8er/graphonomous` is **PUBLIC**. Until now v2 has committed its projections into the repository
  (`projections/*`). Those projections already include records derived from sources that are not public
  themselves (the last bullet of this section).
- **Both new families are private.** Their projections, and anything derived from them (the UI payload, the
  site), must not enter this repository.
- Options:
  - **(a)** Projections of private families live at `~/.graphonomous/v2/projections/` (mode 0700), and only
    code enters the repository. This is how V3-1 already works (`~/.graphonomous/v3-bench/`).
  - **(b)** A private companion repository for private projections.
  - **(c)** Only ids and counts are published, like the V3-1 results files.
- **Recommendation: (a),** with (c) as the rule for anything a public document says about them.
- **Also for Travis, and older than this ruling.** `origin/main` already publishes projections derived from
  three sources that have no public origin of their own:
  - `computedriven`, a PRIVATE repository (6 files at `efa8881`);
  - `invariant-r10`, which has no remote at all (23 files at `ba4e625`);
  - the factory ledger `~/.invariant-factory/canonical.git`, which also has no remote (66 files at `d217ee2`).

  All three are read by `snapshots/multi.json`, which is on `origin/main`. None was introduced by the unpushed
  commits. If that publication was intended, it can stand. It is noted here because §3 is the same question.

## 4. Relation governance — what already exists, and what is retained

These are v2 mechanics, unchanged by D-078:
- endpoint-pair refusal at emission and at projection (`lib/lid.mjs`, D-037);
- frozen profiles, where a change goes to a new profile version (D-050);
- linkage refuses an ambiguous target instead of guessing (D-076);
- a FINDING is not a FAULT (D-071).

Emission classes for the new families:

| Class | Example | Rule |
|---|---|---|
| reference | a resolving `[[link]]`; a row mentioning `R96` | emitted: syntax alone establishes it |
| authored transition | a register row's explicit `Supersedes R9` | emitted **only** under a grammar the inventory fixes, with the quote and location as provenance |
| anything else | "this note refines that one", from reading | **not emitted.** Abstain, and at most queue it for review |

**No model is placed in the emission path.** V3-1 (b) is why:
- Governed Jev made 6 false `supersedes`, at confidence up to 0.86, above its correct answers' median of 0.78.
- No threshold separates those errors from its right answers.
- The Claude judge was inconsistent across slices.

## 5. Review and abstention path

- **Abstain is the default.**
- **The review queue is a list of candidate pairs with provenance.** It lives beside the projection, is never
  part of its relations, and is never certified as fact.
- **Proposed shape [TRAVIS]:** a reviewer's verdict becomes a relation only by being written into the **owning
  source** as authored text: an explicit marker in the note or in the register row. The source is then
  re-pinned and re-projected.
  - Graphonomous never stores a verdict as its own truth. That keeps D-071 (no write surface) and the
    definition (*sources it does not own*) intact.
  - The cost is that a review needs an edit in the source. That edit is exactly the authored statement §4
    asks for.

## 6. Boundary — BM25 recall stays outside

- **The tool is `scripts/memory-search.py`** in the root repository (`31fda46`). It is V3-1 (a)'s S3 byte for byte;
  `--check-bench` re-proves it. Its own docstring says it is not part of Graphonomous.
- **Graphonomous does not import it, call it, or store its scores.** A rank is never a relation and never
  evidence (`v2/README.md`: deterministic, content-addressed, replayable transforms only).
- **Both read the same folder, independently.**
- **The only permitted crossing is in §7's research lane**, where a search hit may nominate a candidate pair
  for human review.
- **Re-test recall** (v3 F1's own re-open condition) if the folder grows well past 147 notes, or if questions
  become sentences rather than keyword bags.

## 7. Research lane — non-authoritative, not scheduled

`candidate relation → model suggestion → human review`
- It is **not** in the trusted transition path, and it does not justify a v3.
- If it is tested, the measure is **review-load reduction** against §5's unassisted queue, under a **new**
  predeclaration. It does not reopen V3-1 (b), and it does not tune on that bench's frozen test split.
- Ollaya, or any other decider, enters only through a new predeclared experiment. Ollaya is still not
  installed.
- It needs §5 to exist first, because there is nothing to reduce until there is a queue.

## Not on this roadmap, by D-078

- a Graphonomous-owned memory store;
- a recall daemon;
- a journal justified by the v3 proposal;
- model-mediated recall;
- automatic relation proposals by Jev or any decider;
- renumbering v2 as v3.

The v3 journal's law J-1 (fold equals rebuild) is not rejected on its merits. It lost its reason. If an
append path is ever needed, it arrives with its own justification.
